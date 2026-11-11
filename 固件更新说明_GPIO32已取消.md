# SmartStir Lab V1.1 — 移除 GPIO32 许可开关

本次修改：`firmware/SmartStir/SmartStir.ino` 取消 GPIO32 开关输入；`mobile/lib/screens/workspace_page.dart` 取消「现场许可」展示和按钮限制；保持原 TB6612 接线。

## 硬件接线

| ESP32 | TB6612 |
|---|---|
| GPIO4 | STBY |
| GPIO5 | AIN1 |
| GPIO18 | AIN2 |
| GPIO19 | PWMA |
| 3V3 | VCC |
| GND | GND；与 12V 负极共地 |
| 电机独立 12V 电源正极 | VM |
| 电机两线 | AO1 与 AO2 |

**GPIO32 不用接任何线；不要把 12V 接入 ESP32 GPIO。**

## 操作顺序

1. 先断开电机 12V，确保磁铁/转动部件不会突然运动。
2. `secrets.h`（如果已存在）不要覆盖，仅替换同一目录中的 `SmartStir.ino`。未生成 `secrets.h` 时运行 `python tools/configure_firmware.py` 填写本地 Wi-Fi 与设备账号凭据。
3. Arduino IDE 选 ESP32 Dev Module，安装 PubSubClient、ArduinoJson 7.x、ESP32 开发板包，编译并烧录。先通过串口确认 Wi-Fi/MQTT 连接。
4. 更新 Android APP：`mobile/lib/screens/workspace_page.dart` 已移除本地许可的界面文案与判断，需要重新编译 APK：在项目根目录运行 `.\tools\build_android.ps1`。不重新编译的旧 APK 仍会显示「现场许可开启」（它是兼容字段，不代表实物开关）。
5. 现场人员确认独立断电手段有效后，先低 PWM 空载测试，逐步验证 SET_PWM → START → STOP、网络断开和 180 秒停止。**不允许无人值守启动。**

## 保留的保护

- 上电默认电机关闭，STBY=LOW
- 需要有效 MQTT TLS、服务器时间范围和非 0 PWM
- Wi-Fi 或 MQTT 掉线即软件停机
- 连续运行最长 180 秒
- QoS1 指令去重，避免重复 START 重置超时计时
- 使用独立实体开关切断电机 12V 供电（这不属于 GPIO32）

未经实机验证，不能据此声称电机已可安全远程启动。
