"""Static tests for control protocol and safety settings; no network connection needed."""
import pathlib

root = pathlib.Path(__file__).resolve().parents[2]
firmware = (root / "firmware/SmartStir/SmartStir.ino").read_text()
api = (root / "backend/app/main.py").read_text()


def test_fixed_verified_pins():
    for pin in ("#define STBY 4", "#define AIN1 5", "#define AIN2 18", "#define PWMA 19"):
        assert pin in firmware


def test_safe_shutdown_without_gpio32_switch():
    assert "digitalWrite(STBY, LOW)" in firmware
    assert "#define ARM_PIN" not in firmware
    assert "pinMode(32" not in firmware
    assert "armed()" not in firmware
    assert 'doc["armed"] = true' in firmware  # legacy API compatibility
    assert 'doc["local_arm_required"] = false' in firmware
    assert "MAX_RUN_MS" in firmware
    assert "WiFi.status() != WL_CONNECTED" in firmware
    assert "!mqtt.connected()" in firmware


def test_protocol_uses_expiry_and_no_retained_start():
    assert "expires_at" in firmware and "expires_at" in api
    assert "qos=1, retain=False" in api
    assert 'doc["actual_rpm"] = nullptr' in firmware


def test_start_cannot_reset_hard_timeout():
    assert "if (!motorEnabled) runStartMs = millis();" in firmware
    assert "seenCommand(id)" in firmware
    assert "recentCommandIds[16]" in firmware


def test_app_no_broker_password_in_source():
    mobile = root / 'mobile/lib'
    dart = '\n'.join(path.read_text() for path in mobile.rglob('*.dart'))
    assert 'MQTT_PASSWORD' not in dart
    assert '12345678' not in dart
    assert 'api/v1/login' in dart
