/*
  SmartStir Lab V1: ESP32 DevKit V1 + TB6612FNG + EMQX Cloud MQTTS
  IMPORTANT: V1 does not measure actual RPM. PWM percentage is not RPM.
  This variant does NOT use GPIO32 or a local ARM permission switch.
  IMPORTANT: Keep an independent, physical 12V motor-power cutoff; never run unattended.
  Remote START still requires valid MQTT, time window, and a nonzero PWM setting.
  Install Arduino libraries: PubSubClient, ArduinoJson, ESP32 board package.
*/
#include <WiFi.h>
#include <WiFiClientSecure.h>
#include <PubSubClient.h>
#include <ArduinoJson.h>
#include <time.h>
#include "secrets.h"

#define STBY 4
#define AIN1 5
#define AIN2 18
#define PWMA 19
#define PWM_CHANNEL 0

#if __has_include(<esp_arduino_version.h>)
#include <esp_arduino_version.h>
#else
#define ESP_ARDUINO_VERSION_MAJOR 2
#endif

const char* DEVICE_ID = "stirrer-001";
const char* TOPIC_COMMAND = "smartstir/v1/devices/stirrer-001/cmd";
const char* TOPIC_ACK = "smartstir/v1/devices/stirrer-001/ack";
const char* TOPIC_STATE = "smartstir/v1/devices/stirrer-001/state";
const char* TOPIC_PRESENCE = "smartstir/v1/devices/stirrer-001/presence";
const unsigned long MAX_RUN_MS = 180000UL;  // hard maximum: 3 minutes for V1 bench tests
const unsigned long REPORT_INTERVAL_MS = 3000UL;
const unsigned long WIFI_RETRY_INTERVAL_MS = 8000UL;
const unsigned long MQTT_RETRY_INTERVAL_MS = 8000UL;

WiFiClientSecure network;
PubSubClient mqtt(network);
bool motorEnabled = false;
uint8_t pwmPercent = 0;
unsigned long runStartMs = 0;
unsigned long lastReportMs = 0;
unsigned long lastWiFiAttemptMs = 0;
unsigned long lastMqttAttemptMs = 0;
// Protect against repeated QoS1 deliveries. Cache the last 16 non-STOP commands.
String recentCommandIds[16];
uint8_t recentCursor = 0;
bool seenCommand(const String &id) {
  for (const auto &saved : recentCommandIds) if (saved == id) return true;
  return false;
}
void rememberCommand(const String &id) {
  recentCommandIds[recentCursor] = id;
  recentCursor = (recentCursor + 1) % 16;
}

void writePWM(uint8_t duty) {
#if ESP_ARDUINO_VERSION_MAJOR >= 3
  ledcWrite(PWMA, duty);
#else
  ledcWrite(PWM_CHANNEL, duty);
#endif
}

void stopMotor() {
  digitalWrite(STBY, LOW);  // disable bridge before updating PWM
  writePWM(0);
  digitalWrite(AIN1, LOW);
  digitalWrite(AIN2, LOW);
  motorEnabled = false;
}

void startMotor() {
  digitalWrite(AIN1, HIGH);
  digitalWrite(AIN2, LOW);
  writePWM((uint8_t)((uint16_t)pwmPercent * 255 / 100));
  digitalWrite(STBY, HIGH);
  // Never let a repeated START silently extend the hard runtime limit.
  if (!motorEnabled) runStartMs = millis();
  motorEnabled = true;
}

bool clockValid() { return time(nullptr) > 1700000000; }

void publishState() {
  if (!mqtt.connected()) return;
  JsonDocument doc;
  doc["device_id"] = DEVICE_ID;
  doc["motor_enabled"] = motorEnabled;
  doc["pwm_percent"] = pwmPercent;
  // Legacy API compatibility: 'armed' now means 'remote command enabled',
  // NOT that a physical interlock is present or that a human is onsite.
  doc["armed"] = true;
  doc["local_arm_required"] = false;
  doc["actual_rpm"] = nullptr; // no Hall sensor installed in current firmware
  doc["uptime_ms"] = millis();
  doc["fault"] = nullptr;
  char buffer[320];
  serializeJson(doc, buffer, sizeof(buffer));
  mqtt.publish(TOPIC_STATE, buffer, true);
}

void publishAck(const char* commandId, const char* status, const char* errorCode = nullptr) {
  if (!mqtt.connected()) return;
  JsonDocument doc;
  doc["command_id"] = commandId;
  doc["status"] = status;
  doc["applied_pwm_percent"] = pwmPercent;
  doc["motor_enabled"] = motorEnabled;
  if (errorCode) doc["error_code"] = errorCode;
  else doc["error_code"] = nullptr;
  char buffer[320];
  serializeJson(doc, buffer, sizeof(buffer));
  mqtt.publish(TOPIC_ACK, buffer, false);
}

void onMqtt(char* topic, byte* payload, unsigned int length) {
  if (strcmp(topic, TOPIC_COMMAND) != 0 || length > 512) return;
  JsonDocument doc;
  DeserializationError err = deserializeJson(doc, payload, length);
  if (err) return;
  String id = doc["command_id"] | "";
  String command = doc["command"] | "";
  long issued = doc["issued_at"] | 0L;
  long expires = doc["expires_at"] | 0L;
  if (id.length() == 0 || id.length() > 72) return;

  // STOP is always safe to apply, even if a time sync issue occurred.
  if (command == "STOP") {
    stopMotor();
    publishAck(id.c_str(), "APPLIED");
    publishState();
    return;
  }
  time_t now = time(nullptr);
  if (!clockValid() || issued <= 0 || expires <= issued ||
      now < issued - 3 || now > expires || expires - issued > 15) {
    publishAck(id.c_str(), "REJECTED", "INVALID_OR_EXPIRED_TIME");
    return;
  }
  if (seenCommand(id)) {
    publishAck(id.c_str(), "DUPLICATE", "ALREADY_HANDLED");
    return;
  }
  rememberCommand(id);
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
    if (value == 0) stopMotor();
    else if (motorEnabled) writePWM((uint8_t)((uint16_t)value * 255 / 100));
    publishAck(id.c_str(), "APPLIED");
    publishState();
  } else if (command == "START") {
    if (pwmPercent == 0 || !mqtt.connected() || WiFi.status() != WL_CONNECTED) {
      publishAck(id.c_str(), "REJECTED", "PWM_ZERO_OR_NOT_CONNECTED");
      return;
    }
    startMotor();
    publishAck(id.c_str(), "APPLIED");
    publishState();
  } else {
    publishAck(id.c_str(), "REJECTED", "UNKNOWN_COMMAND");
  }
}

void setup() {
  // First action is hardware shutdown, independent of network / cloud.
  pinMode(STBY, OUTPUT);
  digitalWrite(STBY, LOW);
  pinMode(AIN1, OUTPUT);
  pinMode(AIN2, OUTPUT);
  pinMode(PWMA, OUTPUT);
  digitalWrite(AIN1, LOW);
  digitalWrite(AIN2, LOW);
#if ESP_ARDUINO_VERSION_MAJOR >= 3
  ledcAttach(PWMA, 20000, 8);
#else
  ledcSetup(PWM_CHANNEL, 20000, 8);
  ledcAttachPin(PWMA, PWM_CHANNEL);
#endif
  stopMotor();
  Serial.begin(115200);
  delay(250);
  WiFi.mode(WIFI_STA);
  WiFi.begin(WIFI_SSID, WIFI_PASSWORD);
  configTime(0, 0, "pool.ntp.org", "time.google.com");
  network.setCACert(MQTT_CA_PEM);
  mqtt.setServer(MQTT_HOST, MQTT_PORT);
  mqtt.setCallback(onMqtt);
  mqtt.setBufferSize(768);
  mqtt.setKeepAlive(20);
  mqtt.setSocketTimeout(5);
  Serial.println("SmartStir ready: motor OFF; remote control without GPIO32 switch.");
}

void loop() {
  // Safety checks execute even if network is unavailable.
  if (motorEnabled && (WiFi.status() != WL_CONNECTED ||
      !mqtt.connected() || (millis() - runStartMs > MAX_RUN_MS))) {
    stopMotor();
    Serial.println("FAIL-SAFE: motor stopped");
  }

  if (WiFi.status() != WL_CONNECTED) {
    if (millis() - lastWiFiAttemptMs > WIFI_RETRY_INTERVAL_MS) {
      lastWiFiAttemptMs = millis();
      WiFi.reconnect();
    }
    delay(5);
    return;
  }
  if (!clockValid()) {
    delay(10);
    return;
  }
  if (!mqtt.connected()) {
    if (millis() - lastMqttAttemptMs > MQTT_RETRY_INTERVAL_MS) {
      lastMqttAttemptMs = millis();
      Serial.println("Connecting secure MQTT...");
      // The Broker's hostname (not an IP) is necessary for SNI.
      bool ok = mqtt.connect(DEVICE_ID, MQTT_USER, MQTT_PASSWORD,
                             TOPIC_PRESENCE, 1, true, "offline", true);
      if (ok) {
        mqtt.subscribe(TOPIC_COMMAND, 1);
        mqtt.publish(TOPIC_PRESENCE, "online", true);
        publishState();
        Serial.println("MQTT online");
      } else {
        Serial.print("MQTT failed state="); Serial.println(mqtt.state());
      }
    }
    delay(5);
    return;
  }
  mqtt.loop();
  if (millis() - lastReportMs > REPORT_INTERVAL_MS) {
    lastReportMs = millis();
    publishState();
  }
  delay(5);
}
