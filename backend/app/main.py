"""SmartStir V1 API. Single-user DEVELOPMENT MVP; not a validated audit system.

APP -> HTTPS API -> MQTT TLS -> ESP32. Broker credentials remain ONLY on server.
Run behind HTTPS reverse proxy for any off-network use.
"""
import hashlib
import hmac
import json
import os
import secrets
import sqlite3
import ssl
import threading
import time
import uuid
from contextlib import asynccontextmanager
from pathlib import Path
from typing import Literal

import paho.mqtt.client as mqtt
from dotenv import load_dotenv
from fastapi import Depends, FastAPI, Header, HTTPException
from pydantic import BaseModel, Field

load_dotenv()
DEVICE_ID = os.getenv("DEVICE_ID", "stirrer-001")
TOPIC = f"smartstir/v1/devices/{DEVICE_ID}"
DB_FILE = os.getenv("DB_PATH", "local.db")
CONFIG_KEYS = ["MQTT_HOST", "MQTT_USER", "MQTT_PASSWORD", "APP_USERNAME", "APP_PASSWORD_SALT", "APP_PASSWORD_HASH"]
missing = [k for k in CONFIG_KEYS if not os.getenv(k)]
if missing:
    raise RuntimeError("Missing environment settings: " + ", ".join(missing))

LOCK = threading.RLock()
DEVICE_STATE = {"device_id": DEVICE_ID, "online": False, "last_seen": None, "last_state_at": None, "motor_enabled": False,
                "pwm_percent": 0, "actual_rpm": None, "armed": False}
SESSIONS: dict[str, float] = {}
FAILED_LOGINS: list[float] = []
CONNECTION_READY = False


def db_connect():
    conn = sqlite3.connect(DB_FILE, check_same_thread=False, timeout=5)
    conn.row_factory = sqlite3.Row
    return conn


def init_db():
    with db_connect() as con:
        con.execute("""CREATE TABLE IF NOT EXISTS commands (
            command_id TEXT PRIMARY KEY, command TEXT NOT NULL,
            value INTEGER, created_at INTEGER NOT NULL, status TEXT NOT NULL,
            ack_json TEXT)""")
        con.execute("""CREATE TABLE IF NOT EXISTS events (
            event_id INTEGER PRIMARY KEY AUTOINCREMENT, created_at INTEGER NOT NULL,
            kind TEXT NOT NULL, data_json TEXT NOT NULL)""")


def insert_event(kind, obj):
    with LOCK, db_connect() as con:
        con.execute("INSERT INTO events(created_at,kind,data_json) VALUES(?,?,?)",
                    (int(time.time()), kind, json.dumps(obj, ensure_ascii=False)))


def on_connect(client, userdata, flags, reason_code, properties):
    global CONNECTION_READY
    CONNECTION_READY = not reason_code.is_failure
    if CONNECTION_READY:
        for suffix in ["ack", "state", "presence", "event"]:
            client.subscribe(f"{TOPIC}/{suffix}", qos=1)


def on_disconnect(client, userdata, disconnect_flags, reason_code, properties):
    global CONNECTION_READY
    CONNECTION_READY = False
    with LOCK:
        DEVICE_STATE["online"] = False


def on_message(client, userdata, msg):
    suffix = msg.topic.split("/")[-1]
    if suffix == "presence":
        online = msg.payload.decode("utf-8", errors="replace") == "online"
        with LOCK:
            DEVICE_STATE["online"] = online
            DEVICE_STATE["last_seen"] = int(time.time())
        insert_event("presence", {"online": online})
        return
    try:
        obj = json.loads(msg.payload.decode("utf-8"))
        if not isinstance(obj, dict):
            return
    except (UnicodeDecodeError, json.JSONDecodeError):
        return
    now = int(time.time())
    if suffix == "state":
        with LOCK:
            # A state message is not proof of actual motor rotation.
            for key in ["motor_enabled", "pwm_percent", "actual_rpm", "armed", "uptime_ms", "fault"]:
                if key in obj:
                    DEVICE_STATE[key] = obj[key]
            DEVICE_STATE["last_seen"] = now
            DEVICE_STATE["last_state_at"] = now
    elif suffix == "ack":
        command_id = str(obj.get("command_id", ""))
        if not command_id:
            return
        accepted = {"APPLIED", "REJECTED", "DUPLICATE", "FAILED"}
        result = obj.get("status", "")
        if result not in accepted:
            return
        with LOCK, db_connect() as con:
            cur = con.execute("UPDATE commands SET status=?,ack_json=? WHERE command_id=? AND status IN ('PENDING','TIMEOUT')",
                              (result, json.dumps(obj), command_id))
            changed = cur.rowcount > 0
        if changed:
            insert_event("command_ack", obj)
    elif suffix == "event":
        insert_event("device_event", obj)


mqtt_client = mqtt.Client(callback_api_version=mqtt.CallbackAPIVersion.VERSION2,
                          client_id="smartstir-backend-v1", protocol=mqtt.MQTTv311)
mqtt_client.username_pw_set(os.environ["MQTT_USER"], os.environ["MQTT_PASSWORD"])
mqtt_client.tls_set(ca_certs=os.getenv("MQTT_CA_PATH") or None, cert_reqs=ssl.CERT_REQUIRED,
                    tls_version=ssl.PROTOCOL_TLS_CLIENT)
mqtt_client.tls_insecure_set(False)
mqtt_client.on_connect = on_connect
mqtt_client.on_disconnect = on_disconnect
mqtt_client.on_message = on_message
mqtt_client.reconnect_delay_set(min_delay=2, max_delay=30)


@asynccontextmanager
async def lifespan(app: FastAPI):
    init_db()
    mqtt_client.connect_async(os.environ["MQTT_HOST"], int(os.getenv("MQTT_PORT", "8883")), keepalive=25)
    mqtt_client.loop_start()
    yield
    mqtt_client.loop_stop()
    mqtt_client.disconnect()


app = FastAPI(title="SmartStir Lab Prototype API", version="0.1.0", lifespan=lifespan)


class LoginRequest(BaseModel):
    username: str
    password: str


class CommandRequest(BaseModel):
    command: Literal["START", "STOP", "SET_PWM"]
    value: int | None = Field(default=None, ge=0, le=100)


def scrypt_hash(password: str, salt_hex: str) -> str:
    return hashlib.scrypt(password.encode("utf-8"), salt=bytes.fromhex(salt_hex),
                          n=2**14, r=8, p=1, dklen=32).hex()


def require_auth(authorization: str | None = Header(default=None)):
    if not authorization or not authorization.startswith("Bearer "):
        raise HTTPException(status_code=401, detail="Login required")
    token = authorization[7:]
    with LOCK:
        expiry = SESSIONS.get(token)
    if not expiry or expiry < time.monotonic():
        raise HTTPException(status_code=401, detail="Session expired")
    return True


@app.post("/api/v1/login")
def login(body: LoginRequest):
    # Single-admin V1: global login throttle, deliberately conservative for a test device.
    with LOCK:
        now = time.monotonic()
        FAILED_LOGINS[:] = [t for t in FAILED_LOGINS if now - t < 300]
        if len(FAILED_LOGINS) >= 5:
            raise HTTPException(status_code=429, detail="Too many attempts; retry in 5 minutes")
    ok_user = hmac.compare_digest(body.username.encode(), os.environ["APP_USERNAME"].encode())
    actual = scrypt_hash(body.password, os.environ["APP_PASSWORD_SALT"])
    ok_password = hmac.compare_digest(actual, os.environ["APP_PASSWORD_HASH"])
    if not (ok_user and ok_password):
        with LOCK:
            FAILED_LOGINS.append(time.monotonic())
        raise HTTPException(status_code=401, detail="Invalid credentials")
    token = secrets.token_urlsafe(32)
    with LOCK:
        FAILED_LOGINS.clear()
        SESSIONS.update({k: t for k, t in SESSIONS.items() if t > time.monotonic()})
        SESSIONS[token] = time.monotonic() + 3600
        # In-memory MVP sessions; restart invalidates them.
    return {"access_token": token, "expires_in": 3600, "token_type": "bearer"}


@app.post("/api/v1/logout")
def logout(authorization: str | None = Header(default=None), auth=Depends(require_auth)):
    token = authorization[7:]
    with LOCK:
        SESSIONS.pop(token, None)
    return {"ok": True}


@app.get("/health")
def health():
    return {"api": "ok", "mqtt_connected": CONNECTION_READY}


@app.get("/api/v1/devices")
def devices(auth=Depends(require_auth)):
    with LOCK:
        item = dict(DEVICE_STATE)
    item["online"] = bool(item["online"] and item["last_seen"] and
                          int(time.time()) - int(item["last_seen"]) <= 12 and
                          item["last_state_at"] and int(time.time()) - int(item["last_state_at"]) <= 12)
    return [item]


@app.get("/api/v1/devices/{device_id}")
def device_status(device_id: str, auth=Depends(require_auth)):
    if device_id != DEVICE_ID:
        raise HTTPException(status_code=404, detail="Unknown device")
    with LOCK:
        item = dict(DEVICE_STATE)
    # Last Will and heartbeat together protect against stale retained state.
    item["online"] = bool(item["online"] and item["last_seen"] and
                          int(time.time()) - int(item["last_seen"]) <= 12 and
                          item["last_state_at"] and int(time.time()) - int(item["last_state_at"]) <= 12)
    if not item["online"]:
        item["motor_enabled"] = None  # unknown, not necessarily off
    return item


@app.post("/api/v1/devices/{device_id}/commands", status_code=202)
def send_command(device_id: str, body: CommandRequest, auth=Depends(require_auth)):
    if device_id != DEVICE_ID:
        raise HTTPException(status_code=404, detail="Unknown device")
    if body.command == "SET_PWM" and body.value is None:
        raise HTTPException(status_code=422, detail="PWM value is required")
    if body.command != "SET_PWM" and body.value is not None:
        raise HTTPException(status_code=422, detail="Unexpected value")
    if not CONNECTION_READY:
        raise HTTPException(status_code=503, detail="MQTT service offline")
    # STOP should be attempted even if stale. START must be gated by live device status.
    state = device_status(device_id, True)
    if body.command != "STOP" and not state["online"]:
        raise HTTPException(status_code=409, detail="Device offline")
    if body.command == "START" and not state["armed"]:
        raise HTTPException(status_code=409, detail="Local safety switch not armed")
    now = int(time.time())
    command_id = str(uuid.uuid4())
    packet = {"version": 1, "command_id": command_id, "command": body.command,
              "issued_at": now, "expires_at": now + 5}
    if body.value is not None:
        packet["value"] = body.value
    with LOCK, db_connect() as con:
        con.execute("INSERT INTO commands VALUES (?,?,?,?,?,?)",
                    (command_id, body.command, body.value, now, "PENDING", None))
    result = mqtt_client.publish(f"{TOPIC}/cmd", json.dumps(packet), qos=1, retain=False)
    if result.rc != mqtt.MQTT_ERR_SUCCESS:
        with LOCK, db_connect() as con:
            con.execute("UPDATE commands SET status='FAILED' WHERE command_id=?", (command_id,))
        raise HTTPException(status_code=503, detail="MQTT publish failed")
    return {"command_id": command_id, "status": "PENDING"}


@app.get("/api/v1/devices/{device_id}/commands/{command_id}")
def command_status(device_id: str, command_id: str, auth=Depends(require_auth)):
    if device_id != DEVICE_ID:
        raise HTTPException(status_code=404, detail="Unknown device")
    with LOCK, db_connect() as con:
        row = con.execute("SELECT * FROM commands WHERE command_id=?", (command_id,)).fetchone()
    if not row:
        raise HTTPException(status_code=404, detail="Command not found")
    item = dict(row)
    if item["status"] == "PENDING" and int(time.time()) - item["created_at"] > 10:
        item["status"] = "TIMEOUT"
        with LOCK, db_connect() as con:
            con.execute("UPDATE commands SET status='TIMEOUT' WHERE command_id=? AND status='PENDING'", (command_id,))
    return item


@app.get("/api/v1/devices/{device_id}/events")
def events(device_id: str, auth=Depends(require_auth)):
    if device_id != DEVICE_ID:
        raise HTTPException(status_code=404, detail="Unknown device")
    with LOCK, db_connect() as con:
        rows = con.execute("SELECT * FROM events ORDER BY event_id DESC LIMIT 100").fetchall()
    return [dict(row) for row in rows]
