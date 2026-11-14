"""Integration smoke tests for SmartStir V1.3 accounts and lab ACL (test DB only)."""
import json
import os
import urllib.error
import urllib.request

BASE = os.environ.get("TEST_BASE_URL", "http://127.0.0.1:3000")

def req(path, method="GET", data=None, token=None):
    headers = {"Content-Type": "application/json"}
    if token:
        headers["Authorization"] = "Bearer " + token
    body = None if data is None else json.dumps(data).encode()
    request = urllib.request.Request(BASE + path, data=body, headers=headers, method=method)
    try:
        with urllib.request.urlopen(request, timeout=10) as response:
            return response.status, json.loads(response.read())
    except urllib.error.HTTPError as exc:
        return exc.code, json.loads(exc.read())

def check(expected, result):
    assert result[0] == expected, f"Expected {expected}, got {result}"

assert req("/health")[0] == 200
status, a = req("/api/v1/register", "POST",
                {"username": "alice_test", "password": "TestPassword123"})
check(201, (status, a))
alice = a["access_token"]
status, b = req("/api/v1/register", "POST",
                {"username": "bob_test", "password": "TestPassword456"})
check(201, (status, b))
bob = b["access_token"]
check(401, req("/api/v1/labs"))
check(200, req("/api/v1/labs", token=bob))
check(201, req("/api/v1/labs", "POST", {"name":"Chemistry Lab"}, token=alice))
status, labs = req("/api/v1/labs", token=alice)
lab_id = labs[0]["id"]
status, other = req("/api/v1/labs", token=bob)
assert not other, other
check(404, req(f"/api/v1/labs/{lab_id}/invitations", "POST",
               {"username":"alice_test"}, token=bob))
check(201, req(f"/api/v1/labs/{lab_id}/invitations", "POST",
               {"username":"bob_test"}, token=alice))
status, invites = req("/api/v1/invitations", token=bob)
check(200, (status, invites))
assert len(invites) == 1, invites
check(200, req(f"/api/v1/invitations/{invites[0]['id']}/accept", "POST", {}, token=bob))
status, joined = req("/api/v1/labs", token=bob)
assert joined[0]["id"] == lab_id and joined[0]["role"] == "member", joined
check(403, req(f"/api/v1/labs/{lab_id}/devices", "POST", {
    "device_id":"stirrer-002","pairing_code":"1234567890123456","label":"ESP32 B"}, token=bob))
check(409, req(f"/api/v1/labs/{lab_id}/devices", "POST", {
    "device_id":"stirrer-002","pairing_code":"1234567890123456","label":"ESP32 B"}, token=alice))
status, members = req(f"/api/v1/labs/{lab_id}/members",token=alice)
assert len(members) == 2, members
check(200, req("/api/v1/logout", "POST", {}, token=alice))
check(401, req("/api/v1/labs",token=alice))
print("PASS: registration, login, lab creation, invite acceptance, access control, pairing authorization, logout")
