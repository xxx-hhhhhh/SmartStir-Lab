"""Interactive local configuration; never prints or transmits secrets."""
from __future__ import annotations
import getpass
import hashlib
import secrets
from pathlib import Path

root = Path(__file__).resolve().parents[1]
out = root / 'backend' / '.env'
if out.exists():
    raise SystemExit('backend/.env 已存在；为防止覆盖密钥，脚本已取消执行。')

print('SmartStir Lab 后端本地配置。输入内容只会保存在 backend/.env 中。')
print('建议先在 EMQX 侧更换此前截图中暴露的密码。')
host = input('EMQX Host [f8f1e9df.ala.cn-shenzhen.emqxsl.cn]: ').strip() or 'f8f1e9df.ala.cn-shenzhen.emqxsl.cn'
if '/' in host or ':' in host:
    raise SystemExit('Host 应为域名，不含 https://、冒号或路径')
mqtt_password = getpass.getpass('smartstir-backend 的 MQTT 密码（不显示输入）: ')
if len(mqtt_password) < 16:
    raise SystemExit('后端 MQTT 密码应至少 16 位；请先在 EMQX 设置强密码。')
app_user = input('APP 管理员用户名 [admin]: ').strip() or 'admin'
app_pass = getpass.getpass('自研 APP 登录密码（至少 16 位，不显示）: ')
app_pass2 = getpass.getpass('再次输入 APP 登录密码: ')
if len(app_pass) < 16 or app_pass != app_pass2:
    raise SystemExit('APP 密码过短或两次输入不一致。')
salt = secrets.token_bytes(16)
digest = hashlib.scrypt(app_pass.encode('utf-8'), salt=salt,
                        n=2**14, r=8, p=1, dklen=32)
# The user's MQTT password is stored only in this local .env file.
vals = {
    'DEVICE_ID': 'stirrer-001',
    'MQTT_HOST': host,
    'MQTT_PORT': '8883',
    'MQTT_USER': 'smartstir-backend',
    'MQTT_PASSWORD': mqtt_password,
    'APP_USERNAME': app_user,
    'APP_PASSWORD_SALT': salt.hex(),
    'APP_PASSWORD_HASH': digest.hex(),
    'DB_PATH': './local.db',
}
if any('\n' in v or '\r' in v or '#' in v for v in vals.values()):
    raise SystemExit('输入含不可直接写入 .env 的特殊符号（# 或换行），请使用其他密码字符。')
out.write_text(''.join(f'{k}={v}\n' for k, v in vals.items()), encoding='utf-8')
try:
    out.chmod(0o600)
except OSError:
    pass
print('已创建 backend/.env。请勿将其提交 GitHub 或通过聊天发送。')
