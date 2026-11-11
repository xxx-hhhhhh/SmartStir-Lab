"""Backend protocol tests with a fake MQTT network client (NO real Broker or motor)."""
import hashlib
import importlib.util
import json
import secrets
import sys
import time
import types
from pathlib import Path

import pytest
from fastapi import HTTPException


@pytest.fixture
def api(monkeypatch, tmp_path):
    # Mock unavailable network packages only for testing control/API logic.
    paho = types.ModuleType('paho')
    paho.__path__ = []
    mqtt_pkg = types.ModuleType('paho.mqtt')
    mqtt_pkg.__path__ = []
    mqtt_mod = types.ModuleType('paho.mqtt.client')

    class FakeClient:
        def __init__(self, **kwargs):
            self.published = []
        def username_pw_set(self, *args): pass
        def tls_set(self, **kwargs): pass
        def tls_insecure_set(self, arg): assert not arg
        def reconnect_delay_set(self, **kwargs): pass
        def publish(self, topic, payload, qos, retain):
            self.published.append((topic, json.loads(payload), qos, retain))
            return types.SimpleNamespace(rc=0)

    mqtt_mod.Client = FakeClient
    mqtt_mod.CallbackAPIVersion = types.SimpleNamespace(VERSION2=2)
    mqtt_mod.MQTTv311 = 4
    mqtt_mod.MQTT_ERR_SUCCESS = 0
    mqtt_pkg.client = mqtt_mod
    paho.mqtt = mqtt_pkg
    dotenv = types.ModuleType('dotenv')
    dotenv.load_dotenv = lambda *a, **kw: None
    monkeypatch.setitem(sys.modules, 'paho', paho)
    monkeypatch.setitem(sys.modules, 'paho.mqtt', mqtt_pkg)
    monkeypatch.setitem(sys.modules, 'paho.mqtt.client', mqtt_mod)
    monkeypatch.setitem(sys.modules, 'dotenv', dotenv)
    password = 'password-strong-enough-123'
    salt = secrets.token_bytes(16)
    for k, v in {
        'MQTT_HOST': 'test.example', 'MQTT_USER': 'backend-test',
        'MQTT_PASSWORD': 'not-a-real-password', 'MQTT_CA_PATH': str(tmp_path / 'ca.pem'),
        'APP_USERNAME': 'admin', 'APP_PASSWORD_SALT': salt.hex(),
        'APP_PASSWORD_HASH': hashlib.scrypt(password.encode(), salt=salt, n=2**14,
                                            r=8, p=1, dklen=32).hex(),
        'DB_PATH': str(tmp_path / 'local.db'),
    }.items():
        monkeypatch.setenv(k, v)
    module_path = Path(__file__).parents[1] / 'app/main.py'
    spec = importlib.util.spec_from_file_location('smartstir_api_under_test', module_path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    mod.init_db()
    mod.CONNECTION_READY = True
    return mod, password


def test_login_protected(api):
    mod, pw = api
    with pytest.raises(HTTPException) as ex:
        mod.login(mod.LoginRequest(username='admin', password='wrong'))
    assert ex.value.status_code == 401
    result = mod.login(mod.LoginRequest(username='admin', password=pw))
    assert mod.require_auth('Bearer ' + result['access_token'])


def test_start_denied_without_hardware_arm(api):
    mod, _ = api
    now = int(time.time())
    mod.DEVICE_STATE.update(online=True, last_seen=now, last_state_at=now, armed=False)
    with pytest.raises(HTTPException) as ex:
        mod.send_command('stirrer-001', mod.CommandRequest(command='START'), True)
    assert ex.value.status_code == 409
    assert mod.mqtt_client.published == []


def test_start_non_retained_when_armed(api):
    mod, _ = api
    now = int(time.time())
    mod.DEVICE_STATE.update(online=True, last_seen=now, last_state_at=now, armed=True)
    result = mod.send_command('stirrer-001', mod.CommandRequest(command='START'), True)
    assert result['status'] == 'PENDING'
    topic, packet, qos, retained = mod.mqtt_client.published[0]
    assert topic.endswith('/cmd') and qos == 1 and not retained
    assert packet['expires_at'] - packet['issued_at'] == 5
    assert packet['command_id'] == result['command_id']


def test_command_ack_updates_database(api):
    mod, _ = api
    mod.DEVICE_STATE.update(online=True, last_seen=int(time.time()),
                            last_state_at=int(time.time()), armed=True)
    cmd = mod.send_command('stirrer-001', mod.CommandRequest(command='SET_PWM', value=60), True)
    mod.on_message(None, None, types.SimpleNamespace(
        topic='smartstir/v1/devices/stirrer-001/ack',
        payload=json.dumps({'command_id': cmd['command_id'], 'status':'APPLIED',
                            'applied_pwm_percent': 60}).encode()))
    info = mod.command_status('stirrer-001', cmd['command_id'], True)
    assert info['status'] == 'APPLIED'
    assert len(mod.events('stirrer-001', True)) >= 1


def test_stale_state_is_offline(api):
    mod, _ = api
    now = int(time.time())
    mod.DEVICE_STATE.update(online=True, last_seen=now, last_state_at=now-30, armed=True)
    state = mod.device_status('stirrer-001', True)
    assert state['online'] is False
    assert state['motor_enabled'] is None


def test_logout_invalidates_session(api):
    mod, pw = api
    token = mod.login(mod.LoginRequest(username='admin', password=pw))['access_token']
    assert mod.logout('Bearer ' + token, True)['ok'] is True
    with pytest.raises(HTTPException) as ex:
        mod.require_auth('Bearer ' + token)
    assert ex.value.status_code == 401


def test_stop_attempted_even_if_device_offline(api):
    mod, _ = api
    mod.DEVICE_STATE.update(online=False, last_seen=None, last_state_at=None)
    cmd = mod.send_command('stirrer-001', mod.CommandRequest(command='STOP'), True)
    assert cmd['status'] == 'PENDING'
    assert mod.mqtt_client.published[0][1]['command'] == 'STOP'


def test_unknown_device_is_rejected(api):
    mod, _ = api
    with pytest.raises(HTTPException) as ex:
        mod.device_status('other-motor', True)
    assert ex.value.status_code == 404


def test_invalid_pwm_rejected(api):
    mod, _ = api
    with pytest.raises(Exception):
        mod.CommandRequest(command='SET_PWM', value=120)


def test_applied_ack_cannot_be_overwritten_by_duplicate(api):
    mod, _ = api
    now = int(time.time())
    mod.DEVICE_STATE.update(online=True, last_seen=now, last_state_at=now, armed=True)
    command_id = mod.send_command('stirrer-001', mod.CommandRequest(command='SET_PWM', value=30), True)['command_id']
    for status in ('APPLIED', 'DUPLICATE'):
        mod.on_message(None, None, types.SimpleNamespace(
            topic='smartstir/v1/devices/stirrer-001/ack',
            payload=json.dumps({'command_id': command_id, 'status': status}).encode()))
    assert mod.command_status('stirrer-001', command_id, True)['status'] == 'APPLIED'
