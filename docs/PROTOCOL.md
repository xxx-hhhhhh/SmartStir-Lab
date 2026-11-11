# SmartStir MQTT v1 protocol

Topic prefix: `smartstir/v1/devices/{device_id}`; first device `stirrer-001`.

## Commands
`cmd`: `{"version":1,"command_id":"UUID","command":"SET_PWM","value":60,"issued_at":<unix_seconds>,"expires_at":<unix_seconds>}`
Allowed `command`: `START`, `STOP`, `SET_PWM`.
`SET_PWM` value: 0..100 percent duty; this is not an RPM target.
TTL: 5 seconds for app commands; device rejects if expired or clock is invalid (except STOP).
Command messages: qos1, retain=false. Device must not start on a stale broker message.

## Acknowledgement
`ack`: `{"command_id":"UUID","status":"APPLIED","applied_pwm_percent":60,"motor_enabled":true,"error_code":null}`
`APPLIED` means control circuit command issued, **NOT** verified physical rotation.

## State
`state`: `{"device_id":"stirrer-001","motor_enabled":false,"pwm_percent":0,"armed":false,"actual_rpm":null,"uptime_ms":0,"fault":null}`
`actual_rpm` stays null until Hall-based rotation measurement is implemented.

## Presence
`presence`: retained `online` on successful MQTT connect; MQTT Last Will retained `offline` for disconnect.

## First release limitations
No measured RPM, no closed-loop speed control, no temperature control, no authenticated compliance-grade audit trail, no offline SD logging, and no actual deployment verification.
