"""Generate a local scrypt salt/hash. Never print or share the plaintext password."""
import getpass
import hashlib
import secrets

pw = getpass.getpass('Choose an APP login password: ')
if len(pw) < 12:
    raise SystemExit('Use at least 12 characters')
salt = secrets.token_bytes(16)
h = hashlib.scrypt(pw.encode(), salt=salt, n=2**14, r=8, p=1, dklen=32)
print('APP_PASSWORD_SALT=' + salt.hex())
print('APP_PASSWORD_HASH=' + h.hex())
