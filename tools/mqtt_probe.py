"""Read-only TLS MQTT probe. NO motor control is ever published by this tool."""
import argparse
import os
import ssl
import time
from pathlib import Path

import paho.mqtt.client as mqtt
from dotenv import load_dotenv

ROOT = Path(__file__).resolve().parents[1]
load_dotenv(ROOT / "backend" / ".env")
p = argparse.ArgumentParser(description="Read-only SmartStir MQTT connectivity test")
p.add_argument('--seconds', type=int, default=15)
args = p.parse_args()

for key in ('MQTT_HOST', 'MQTT_USER', 'MQTT_PASSWORD'):
    if not os.getenv(key):
        raise SystemExit(f'Missing {key} in backend/.env')

client = mqtt.Client(mqtt.CallbackAPIVersion.VERSION2, client_id='smartstir-probe-' + str(os.getpid()),
                     protocol=mqtt.MQTTv311)
client.username_pw_set(os.environ['MQTT_USER'], os.environ['MQTT_PASSWORD'])
client.tls_set(ca_certs=os.getenv('MQTT_CA_PATH') or None, cert_reqs=ssl.CERT_REQUIRED,
               tls_version=ssl.PROTOCOL_TLS_CLIENT)
client.tls_insecure_set(False)

def connected(c, userdata, flags, reason_code, props):
    print('MQTT connect result:', reason_code)
    if not reason_code.is_failure:
        for suffix in ('presence', 'state', 'ack'):
            c.subscribe('smartstir/v1/devices/stirrer-001/' + suffix)

client.on_connect = connected
client.on_message = lambda c, u, m: print(m.topic, m.payload.decode(errors='replace'))
client.connect(os.environ['MQTT_HOST'], int(os.getenv('MQTT_PORT', '8883')))
client.loop_start()
try:
    time.sleep(max(1, min(args.seconds, 90)))
finally:
    client.disconnect()
    client.loop_stop()
