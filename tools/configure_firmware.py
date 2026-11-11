"""Safely creates local firmware/secrets.h from the shipped public CA example."""
import getpass
import json
from pathlib import Path

root = Path(__file__).resolve().parents[1]
firmware = root / 'firmware' / 'SmartStir'
target = firmware / 'secrets.h'
if target.exists():
    raise SystemExit('firmware/secrets.h 已存在；脚本不会覆盖当前设备配置。')
source = (firmware / 'secrets.h.example').read_text(encoding='utf-8')
print('SmartStir ESP32 本地配置；密码不会显示，也不会上传。')
print('请先在 EMQX 中更换已经暴露在之前截图里的 MQTT 密码。')
ssid = input('实验室 Wi-Fi SSID: ').strip()
wifi_pw = getpass.getpass('Wi-Fi 密码: ')
mqtt_pw = getpass.getpass('stirrer-001 的 MQTT 密码: ')
if not ssid or not wifi_pw or len(mqtt_pw) < 16:
    raise SystemExit('SSID/密码不能留空；MQTT 密码要求至少 16 位。')
replacements = {
    '"REPLACE_WIFI_SSID"': json.dumps(ssid, ensure_ascii=False),
    '"REPLACE_WIFI_PASSWORD"': json.dumps(wifi_pw, ensure_ascii=False),
    '"REPLACE_WITH_DEVICE_PASSWORD"': json.dumps(mqtt_pw, ensure_ascii=False),
}
for old, new in replacements.items():
    if old not in source:
        raise SystemExit('证书模板内容不符合预期，请不要生成固件')
    source = source.replace(old, new, 1)
target.write_text(source, encoding='utf-8')
try:
    target.chmod(0o600)
except OSError:
    pass
print('已创建 firmware/SmartStir/secrets.h，请使用 Arduino IDE 烧录。')
