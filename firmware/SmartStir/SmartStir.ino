/*
 * SmartStir Lab ESP32 firmware v1.3.0
 * Adapted from the user's legacy TB6612 + Blinker + Hall + OLED sketch.
 *
 * Preserved: STBY=4, AIN1=5, AIN2=18, PWMA=19, 20kHz/8-bit PWM;
 *            optional Hall GPIO27 (1 pulse/rev) and OLED I2C SDA21/SCL22 (0x3C).
 * Replaced: Blinker -> secure MQTT via EMQX Cloud (per-device MQTT identity).
 * Not used: GPIO32. No relay required.
 *
 * IMPORTANT: This prototype is not intended for unattended use.
 * Use a physical motor 12V power cut-off; first test with motor power OFF.
 * actual_rpm is null until a real 3.3V-safe Hall input is connected and enabled.
 */
#include <Arduino.h>
#include <WiFi.h>
#include <WiFiClientSecure.h>
#include <PubSubClient.h>
#include <ArduinoJson.h>
#include <time.h>
#include "secrets.h"

// Change to 1 ONLY when the corresponding accessory is actually wired.
// If Hall is absent, the app must NOT display PWM% as measured RPM.
#define SMARTSTIR_USE_HALL 0
#define SMARTSTIR_USE_OLED 0

#if SMARTSTIR_USE_OLED
#include <Wire.h>
#include <Adafruit_GFX.h>
#include <Adafruit_SSD1306.h>
#define OLED_SDA 21
#define OLED_SCL 22
#define OLED_ADDRESS 0x3C
Adafruit_SSD1306 display(128, 64, &Wire, -1);
bool oledAvailable = false;
unsigned long lastOledMs = 0;
#endif

#if SMARTSTIR_USE_HALL
#define HALL_PIN 27
const uint8_t PULSES_PER_REV = 1;   // Legacy sketch: one pulse per rotation
volatile uint32_t hallPulseCount = 0;
volatile uint32_t lastHallPulseUs = 0;
float actualRpm = 0.0f;
bool hallMeasurementReady = false;
unsigned long lastMeasureMs = 0;
void IRAM_ATTR hallSensorISR() {
  const uint32_t now = micros();
  // Reject very short electrical glitches; adjust if the real sensor requires it.
  if ((uint32_t)(now - lastHallPulseUs) >= 1000U) {
    ++hallPulseCount;
    lastHallPulseUs = now;
  }
}
#endif

#define STBY 4
#define AIN1 5
#define AIN2 18
#define PWMA 19
#define PWM_CHANNEL 0
#define PWM_FREQ 20000
#define PWM_RES 8
#define PWM_MAX 255

#if __has_include(<esp_arduino_version.h>)
#include <esp_arduino_version.h>
#else
#define ESP_ARDUINO_VERSION_MAJOR 2
#endif

// Each ESP32 must have its own device ID, MQTT account and private pairing code.
// Existing local secrets.h without these options still compiles as a legacy device.
#ifndef SMARTSTIR_DEVICE_ID
#define SMARTSTIR_DEVICE_ID "stirrer-001"
#endif
#ifndef SMARTSTIR_PAIRING_CODE
#define SMARTSTIR_PAIRING_CODE ""
#endif
const char* DEVICE_ID = SMARTSTIR_DEVICE_ID;
const String TOPIC_PREFIX = String("smartstir/v1/devices/") + DEVICE_ID;
const String TOPIC_COMMAND = TOPIC_PREFIX + "/cmd";
const String TOPIC_ACK = TOPIC_PREFIX + "/ack";
const String TOPIC_STATE = TOPIC_PREFIX + "/state";
const String TOPIC_PRESENCE = TOPIC_PREFIX + "/presence";
const String TOPIC_PAIR = TOPIC_PREFIX + "/pair";

const unsigned long MAX_RUN_MS = 180000UL;
const unsigned long REPORT_INTERVAL_MS = 3000UL;
const unsigned long WIFI_RETRY_INTERVAL_MS = 8000UL;
const unsigned long MQTT_RETRY_INTERVAL_MS = 8000UL;

WiFiClientSecure tlsClient;
PubSubClient mqtt(tlsClient);
bool motorEnabled = false;
uint8_t pwmPercent = 0;            // Safe: preset starts at 0%; old sketch used 50%
unsigned long runStartMs = 0;
unsigned long lastReportMs = 0;
unsigned long lastWiFiAttemptMs = 0;
unsigned long lastMqttAttemptMs = 0;
unsigned long lastPairingMs = 0;

// QoS1 delivery may repeat. Cache recent command IDs, including START.
String commandCache[16];
uint8_t cacheCursor = 0;
bool commandSeen(const String &id) {
  for (const auto &cached : commandCache) {
    if (cached == id) return true;
  }
  return false;
}
void cacheCommand(const String &id) {
  commandCache[cacheCursor] = id;
  cacheCursor = (cacheCursor + 1) % 16;
}

void setPwmRaw(uint8_t duty) {
#if ESP_ARDUINO_VERSION_MAJOR >= 3
  ledcWrite(PWMA, duty);
#else
  ledcWrite(PWM_CHANNEL, duty);
#endif
}

// Software output disable; a physical 12V cut-off remains essential.
void motorStop() {
  digitalWrite(STBY, LOW);
  setPwmRaw(0);
  digitalWrite(AIN1, LOW);
  digitalWrite(AIN2, LOW);
  motorEnabled = false;
}

void motorStart() {
  digitalWrite(AIN1, HIGH);
  digitalWrite(AIN2, LOW);
  setPwmRaw((uint8_t)((uint16_t)pwmPercent * PWM_MAX / 100));
  digitalWrite(STBY, HIGH);
  if (!motorEnabled) runStartMs = millis(); // Repeated START cannot extend timeout.
  motorEnabled = true;
}

#if SMARTSTIR_USE_HALL
void calculateRpm() {
  unsigned long nowMs = millis();
  unsigned long elapsedMs = nowMs - lastMeasureMs;
  if (elapsedMs < 1000UL) return;
  noInterrupts();
  uint32_t pulses = hallPulseCount;
  hallPulseCount = 0;
  interrupts();
  if (!motorEnabled || pwmPercent == 0) {
    actualRpm = 0.0f;
  } else {
    actualRpm = (float)pulses * 60000.0f /
                ((float)PULSES_PER_REV * (float)elapsedMs);
  }
  hallMeasurementReady = true;
  lastMeasureMs = nowMs;
}
#else
void calculateRpm() {}
#endif

#if SMARTSTIR_USE_OLED
void refreshOled() {
  if (!oledAvailable) return;
  unsigned long now = millis();
  if (now - lastOledMs < 250UL) return;
  lastOledMs = now;
  display.clearDisplay();
  display.setTextColor(SSD1306_WHITE);
  display.setTextSize(1);
  display.setCursor(0, 0);
  display.println("SmartStir / EMQX");
  display.drawLine(0, 11, 127, 11, SSD1306_WHITE);
  display.setCursor(0, 17);
  display.print("Motor: ");
  display.println(motorEnabled ? "RUNNING" : "STOPPED");
  display.setCursor(0, 31);
  display.print("PWM: ");
  display.print(pwmPercent);
  display.println("%");
  display.setCursor(0, 45);
  display.print("RPM: ");
#if SMARTSTIR_USE_HALL
  if (hallMeasurementReady) display.println(actualRpm, 1);
  else display.println("measuring...");
#else
  display.println("N/A");
#endif
  display.setCursor(0, 56);
  display.print("Cloud: ");
  display.println(mqtt.connected() ? "ONLINE" : "OFFLINE");
  display.display();
}
#else
void refreshOled() {}
#endif

bool validClock() { return time(nullptr) > 1700000000; }

void publishState() {
  if (!mqtt.connected()) return;
  JsonDocument doc;
  doc["device_id"] = DEVICE_ID;
  doc["motor_enabled"] = motorEnabled;
  doc["pwm_percent"] = pwmPercent;
  // Existing gateway expects armed. This is a LEGACY compatibility flag,
  // not a real safety-interlock switch or on-site permission.
  doc["armed"] = true;
  doc["local_arm_required"] = false;
  doc["hall_sensor_configured"] = (bool)SMARTSTIR_USE_HALL;
  doc["oled_configured"] = (bool)SMARTSTIR_USE_OLED;
#if SMARTSTIR_USE_HALL
  if (hallMeasurementReady) doc["actual_rpm"] = actualRpm;
  else doc["actual_rpm"] = nullptr;
#else
  doc["actual_rpm"] = nullptr;
#endif
  doc["uptime_ms"] = millis();
  doc["fault"] = nullptr;
  char json[420];
  size_t n = serializeJson(doc, json, sizeof(json));
  if (n > 0 && n < sizeof(json) - 1) mqtt.publish(TOPIC_STATE.c_str(), json, true);
}


void publishPairing() {
  if (!mqtt.connected()) return;
  const char* code = SMARTSTIR_PAIRING_CODE;
  size_t n = strlen(code);
  if (n < 16 || n > 64) return; // Legacy devices do not broadcast a claim.
  JsonDocument doc;
  doc["device_id"] = DEVICE_ID;
  doc["pairing_code"] = code;
  char payload[190];
  size_t written = serializeJson(doc, payload, sizeof(payload));
  if (written > 0 && written < sizeof(payload) - 1)
    mqtt.publish(TOPIC_PAIR.c_str(), payload, false);
}

void publishAck(const char *id, const char *status, const char *error = nullptr) {
  if (!mqtt.connected()) return;
  JsonDocument doc;
  doc["command_id"] = id;
  doc["status"] = status;
  doc["applied_pwm_percent"] = pwmPercent;
  doc["motor_enabled"] = motorEnabled;
  if (error) doc["error_code"] = error;
  else doc["error_code"] = nullptr;
  char json[360];
  size_t n = serializeJson(doc, json, sizeof(json));
  if (n > 0 && n < sizeof(json) - 1) mqtt.publish(TOPIC_ACK.c_str(), json, false);
}

void handleMqtt(char* topic, byte* payload, unsigned int length) {
  if (strcmp(topic, TOPIC_COMMAND.c_str()) != 0 || length > 512) return;
  JsonDocument doc;
  if (deserializeJson(doc, payload, length)) return;
  String id = doc["command_id"] | "";
  String command = doc["command"] | "";
  long issued = doc["issued_at"] | 0L;
  long expires = doc["expires_at"] | 0L;
  if (id.isEmpty() || id.length() > 72) return;

  // STOP can always be applied, even before time synchronization.
  if (command == "STOP") {
    motorStop();
    publishAck(id.c_str(), "APPLIED");
    publishState();
    Serial.println("MQTT command: STOP");
    return;
  }

  time_t now = time(nullptr);
  if (!validClock() || issued <= 0 || expires <= issued ||
      now < issued - 3 || now > expires || expires - issued > 15) {
    publishAck(id.c_str(), "REJECTED", "INVALID_OR_EXPIRED_TIME");
    return;
  }
  if (commandSeen(id)) {
    publishAck(id.c_str(), "DUPLICATE", "ALREADY_HANDLED");
    return;
  }
  cacheCommand(id);

  if (command == "SET_PWM") {
    if (!doc["value"].is<int>()) {
      publishAck(id.c_str(), "REJECTED", "INVALID_VALUE");
      return;
    }
    int value = doc["value"].as<int>();
    if (value < 0 || value > 100) {
      publishAck(id.c_str(), "REJECTED", "OUT_OF_RANGE");
      return;
    }
    pwmPercent = (uint8_t)value;
    if (value == 0) motorStop();
    else if (motorEnabled) setPwmRaw((uint8_t)((uint16_t)value * PWM_MAX / 100));
    publishAck(id.c_str(), "APPLIED");
    publishState();
    Serial.printf("MQTT command: SET_PWM %u%%\n", pwmPercent);
  } else if (command == "START") {
    if (pwmPercent == 0 || !mqtt.connected() || WiFi.status() != WL_CONNECTED) {
      publishAck(id.c_str(), "REJECTED", "PWM_ZERO_OR_NOT_CONNECTED");
      return;
    }
    motorStart();
    publishAck(id.c_str(), "APPLIED");
    publishState();
    Serial.printf("MQTT command: START at PWM %u%%\n", pwmPercent);
  } else {
    publishAck(id.c_str(), "REJECTED", "UNKNOWN_COMMAND");
  }
}

void setup() {
  // Disable motor bridge first, BEFORE Wi-Fi or MQTT setup.
  pinMode(STBY, OUTPUT);
  digitalWrite(STBY, LOW);
  pinMode(AIN1, OUTPUT);
  pinMode(AIN2, OUTPUT);
  pinMode(PWMA, OUTPUT);
  digitalWrite(AIN1, LOW);
  digitalWrite(AIN2, LOW);
  Serial.begin(115200);

#if ESP_ARDUINO_VERSION_MAJOR >= 3
  if (!ledcAttach(PWMA, PWM_FREQ, PWM_RES)) {
    Serial.println("ERROR: PWM init failed; motor disabled");
    while (true) { digitalWrite(STBY, LOW); delay(1000); }
  }
#else
  if (ledcSetup(PWM_CHANNEL, PWM_FREQ, PWM_RES) <= 0) {
    Serial.println("ERROR: PWM init failed; motor disabled");
    while (true) { digitalWrite(STBY, LOW); delay(1000); }
  }
  ledcAttachPin(PWMA, PWM_CHANNEL);
#endif
  motorStop();

#if SMARTSTIR_USE_HALL
  pinMode(HALL_PIN, INPUT_PULLUP);
  attachInterrupt(digitalPinToInterrupt(HALL_PIN), hallSensorISR, FALLING);
  lastMeasureMs = millis();
  Serial.println("Hall sensor enabled on GPIO27 (check 3.3V logic level)");
#endif
#if SMARTSTIR_USE_OLED
  Wire.begin(OLED_SDA, OLED_SCL);
  oledAvailable = display.begin(SSD1306_SWITCHCAPVCC, OLED_ADDRESS);
  Serial.println(oledAvailable ? "OLED online" : "OLED not found; continuing");
#endif

  WiFi.mode(WIFI_STA);
  WiFi.begin(WIFI_SSID, WIFI_PASSWORD);
  configTime(0, 0, "pool.ntp.org", "time.google.com");
  tlsClient.setCACert(MQTT_CA_PEM);
  mqtt.setServer(MQTT_HOST, MQTT_PORT);
  mqtt.setCallback(handleMqtt);
  mqtt.setBufferSize(768);
  mqtt.setKeepAlive(20);
  mqtt.setSocketTimeout(5);
  Serial.println("SmartStir EMQX v1.3.0 ready; motor OFF; no GPIO32 switch.");
  Serial.print("Device ID: "); Serial.println(DEVICE_ID);
  if (strlen(SMARTSTIR_PAIRING_CODE) >= 16) {
    Serial.print("Pairing code (keep private): ");
    Serial.println(SMARTSTIR_PAIRING_CODE);
  }
  Serial.println("Wi-Fi connecting (ESP32 needs 2.4 GHz)...");
}

void loop() {
  calculateRpm();
  refreshOled();

  if (motorEnabled && (WiFi.status() != WL_CONNECTED ||
      !mqtt.connected() || (millis() - runStartMs > MAX_RUN_MS))) {
    motorStop();
    Serial.println("FAIL-SAFE: motor stopped due to disconnect/timeout");
  }

  if (WiFi.status() != WL_CONNECTED) {
    if (millis() - lastWiFiAttemptMs > WIFI_RETRY_INTERVAL_MS) {
      lastWiFiAttemptMs = millis();
      WiFi.reconnect();
      Serial.println("Wi-Fi retrying...");
    }
    delay(5);
    return;
  }
  if (!validClock()) {
    delay(10);             // TLS validation needs accurate time.
    return;
  }
  if (!mqtt.connected()) {
    if (millis() - lastMqttAttemptMs > MQTT_RETRY_INTERVAL_MS) {
      lastMqttAttemptMs = millis();
      Serial.println("Connecting EMQX Cloud over TLS:8883...");
      bool ok = mqtt.connect(DEVICE_ID, MQTT_USER, MQTT_PASSWORD,
                             TOPIC_PRESENCE.c_str(), 1, true, "offline", true);
      if (ok) {
        bool subOk = mqtt.subscribe(TOPIC_COMMAND.c_str(), 1);
        mqtt.publish(TOPIC_PRESENCE.c_str(), "online", true);
        publishState();
        publishPairing();
        lastPairingMs = millis();
        Serial.println(subOk ? "MQTT TLS online; subscribe request sent" :
                   "MQTT TLS online; subscribe request failed locally");
      } else {
        Serial.print("MQTT failed state=");
        Serial.println(mqtt.state());
      }
    }
    delay(5);
    return;
  }

  mqtt.loop();
  if (millis() - lastPairingMs > 30000UL) {
    lastPairingMs = millis();
    publishPairing();
  }
  if (millis() - lastReportMs > REPORT_INTERVAL_MS) {
    lastReportMs = millis();
    publishState();
  }
  delay(5);
}