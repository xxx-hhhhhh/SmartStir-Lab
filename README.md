# SmartStir Lab — 自研 Android + ESP32 + EMQX 远程控制 V1.2.0

**当前交付物：完整源码工程，不是已部署云端服务或已编译 APK。** 软件侧单元测试：`15 passed`，但尚未进行 Android SDK 编译、ESP32 硬件编译与真机联网/电机验收。


> **2026-11-11 最新说明**：项目加入 Android APP 内「检查 GitHub 更新」入口，使用 GitHub Releases API 获取稳定版并通过 Android 浏览器下载安装；详见 `docs/APP-UPDATES.md`。原 `backend/` 是 FastAPI 源码，但目前用户实际在线的 Railway 服务是独立的 Bun `smartstir-gateway`，两者不能直接视为相同部署。首次 APK 仍须在 Windows Flutter 环境下编译。GitHub `xxx-hhhhhh/SmartStir-Lab` 仓库已创建，当前为 Private；匿名检查 Release 会失败，需公开一个仅用于发布 APK 的仓库或在完成安全审查后公开源码仓库。

## 软件链路

```text
Android APP (Flutter)
        │ HTTPS / token
        ▼
FastAPI (Railway smartstir-api, 待部署)
        │ MQTT over TLS / 用户 smartstir-backend
        ▼
EMQX Cloud Serverless (用户已经创建并配置 10 allow + 1 deny)
        │ MQTT over TLS / 用户 stirrer-001
        ▼
ESP32 DevKit V1 ── TB6612FNG ── 12V 有刷电机
```

与 Blinker 无关，手机 APP 不保存 MQTT 客户端凭据。第一版为**一台设备、单管理员**研发原型。APP 有三个页签：控制台、运行事件、设置，和独立登录页。具备在线状态、PWM 设定、START/STOP、指令 ID + 执行结果、最近 100 条事件查询。

## 你们已经确认的硬件接线（保持不变）

| TB6612 | ESP32 | 用途 |
|---|---|---|
| `STBY` | `GPIO4` | 驱动器使能 |
| `AIN1` | `GPIO5` | 方向输入 |
| `AIN2` | `GPIO18` | 方向输入 |
| `PWMA` | `GPIO19` | PWM |
| `VCC` | `3V3` | 逻辑电源 |
| `GND` | ESP32 GND + 12V 电源负极共地 | 公共参考地 |
| `VM` | 12V 电源正极 | 电机供电 |
| `AO1/AO2` | 电机两根线 | 电机 |

**本版本不使用 GPIO32 现场许可开关**，不需要接 GPIO32。仍需现场可直接切断电机 12V 供电的实体开关。软件停机无法替代物理急停。测试时必须有人现场监护，卸下旋转磁铁、固定电机，在空载安全状态先联调。

ESP32 默认上电停机；Wi-Fi/MQTT 掉线、连续运行超过 180 秒会由固件请求停机。重要限制：网络库若阻塞，软件停机可能延迟；硬件失效时依赖独立断电。固件不会因收到重复 START 指令而重置计时器。

**V1.0 不测实际 RPM；PWM% 不是 RPM。** A3144 霍尔、DS3231 时钟、MicroSD、PID、加热与温控不在这个版本中。

## 零：当前在线资源状态

- EMQX Cloud 已部署：`f8f1e9df.ala.cn-shenzhen.emqxsl.cn`，端口 `8883`，TLS。
- EMQX 登录用户：`stirrer-001`、`smartstir-backend`。两者授权规则均为 5 条，另有 `#` 的拒绝兜底规则。**需再次人工核对具体 Topic/动作，截图只能确认数量。**
- Railway 项目 `SmartStir-Lab` 已创建，生产网关服务为 `smartstir-gateway`（Bun/TypeScript，非本仓库 Python 后端），公开地址：`https://smartstir-gateway-production.up.railway.app`；它已部署但与 ESP32 MQTT 实机通信仍需联调。
- 此前在截图或聊天中曝光的 MQTT 密码与 API Secret 应先在 EMQX 中更换；禁止把它们放进仓库。

## 一：后端配置（不需要 MQTTX）

Windows PowerShell 在根目录运行：

```powershell
python tools/configure_backend.py
cd backend
python -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install -r requirements.txt
pip install pytest
pytest -q
uvicorn app.main:app --host 127.0.0.1 --port 8000
```

`configure_backend.py` 会交互式询问 `smartstir-backend` 的新密码以及你们自研 APP 的管理员账号密码，自动生成强密码的 scrypt 哈希与 `backend/.env`，**不会将明文密码打印出来**。如果已经有 `backend/.env`，它会拒绝覆盖。

如需检查云端 MQTT 连接（只订阅状态，**不向电机发送任何指令**），另开一个 PowerShell 窗口：

```powershell
cd SmartStir-Lab-v1.0
.\backend\.venv\Scripts\Activate.ps1
python tools/mqtt_probe.py --seconds 20
```

后端环境要求 Python 3.11+，`pip` 安装依赖。`http://127.0.0.1:8000/health` 仅用于本机检查；**不要直接将明文 HTTP 服务暴露到公网**。

## 二：ESP32 固件

在项目根目录运行：

```powershell
python tools/configure_firmware.py
```

脚本会询问实验室 Wi-Fi 和 `stirrer-001` 新 MQTT 密码，生成**不会提交到 Git 的** `firmware/SmartStir/secrets.h`。已在 `secrets.h.example` 中内置你下载的公开根 CA 证书。

Arduino IDE 安装 **ESP32 开发板支持包、ArduinoJson 7.x、PubSubClient**。打开 `firmware/SmartStir/SmartStir.ino`，选择实际 ESP32 DevKit V1 和串口，先**断开电机 12V 电源**编译、烧录、观察串口 `115200` 的联网状态。正式启动前安装独立电机 12V 电源断开措施；不需要 GPIO32 接线。

## 三：Android APP（不需要 MQTTX）

需要 Windows 电脑安装 Flutter 稳定版 + Android Studio/Android SDK，然后在项目根目录执行：

```powershell
.\tools\build_android.ps1
```

脚本会（在 Android SDK 就绪时）生成 Flutter Android 原生工程、添加 INTERNET 权限、下载 Dart 依赖并构建调试 APK，默认输出：

```text
mobile/build/app/outputs/flutter-apk/app-debug.apk
```

上述脚本**未在本执行环境真实编译验证**。也可在 `mobile` 目录运行 `flutter run` 在手机上调试。APP 登录页面已预填 `https://smartstir-gateway-production.up.railway.app`，不是 EMQX 地址；账号密码是 `configure_backend.py` 设置的 APP 账号密码，**不是** MQTT 用户密码。

- APP 只有在设备在线、PWM 非 0 时才启用启动按钮；按启动后还需确认现场准备。
- APP 会显示设备确认的 PWM；“已启用”是驱动输出状态，非真实 RPM。
- STOP 按钮在等待其他指令回执时也可以发起尝试；如果网络不可用，现场必须物理断电。
- 自研 APP 使用 HTTPS 访问后端，不需要另装 MQTTX 客户端。

## 四：Railway 部署（尚未上线）

1. 建立新的私有 GitHub 仓库 `SmartStir-Lab`，上传不含密码的源码。
2. 在 [Railway 项目](https://railway.com/project/0be8e8a9-55e4-4e37-8cd3-8b5891a4f5c0) 的 `smartstir-api` 服务中连接代码来源，并设置根目录 `/backend`、Dockerfile。
3. 在 Railway 服务变量中设置 `MQTT_PASSWORD`（backend 身份专用）、`APP_USERNAME`、`APP_PASSWORD_SALT`、`APP_PASSWORD_HASH`。不需在聊天中提供任何密钥。
4. 服务已经暂存 `MQTT_HOST`、`MQTT_PORT=8883`、`DEVICE_ID=stirrer-001`、`MQTT_USER=smartstir-backend` 等非敏感变量。**仍需确认已正式提交待部署更改**。
5. 为 SQLite 提供挂载在 `/data` 的持久卷，并设置 `DB_PATH=/data/local.db`。否则重启可能丢失运行事件。这个版本仅供研发，不能宣称审计数据防篡改。
6. 观察部署状态为 `SUCCESS` 后生成 HTTPS 公网域名并调用 `/health` 验证 `mqtt_connected: true`。

详见 `docs/RAILWAY-DEPLOY.md`，云端部署和实际运行服务可能产生费用。

## 五：数据与安全约束

该版本后端使用单管理员登录、1 小时内存令牌、SQLite、有限事件历史和 TLS，不具备多租户 IAM、可审计身份链、正式合规认证、RPM 实测或固件 OTA。云端账户持有私钥，手机 APP 不直接连接 Broker。

指令通过 QoS1 传输、5 秒内过期（STOP 例外），不得使用 retained 启动指令；ESP32 返回 `ack`，API 通过 `command_id` 暴露执行状态。`APPLIED` 表示 GPIO/PWM 控制命令执行，**不证明电机真的旋转**。

已运行本地 Python 测试：`15 passed`。未运行 Flutter 分析器、Android APK 构建、Arduino 编译、EMQX TLS 实测或现场电机测试。不能在未做完这些验证前说设备已可安全地公网运行。


## V1.1 修订：取消 GPIO32 现场许可开关

- 固件 `SmartStir.ino` 不再读写 GPIO32；保持 STBY=4、AIN1=5、AIN2=18、PWMA=19。
- `SET_PWM`、`START`、`STOP` 的消息协议保持不变；仍须使用有效身份认证、指令时间戳，且 PWM 大于 0 才能启动。
- 为兼容已部署的网关，设备状态仍报告 `armed=true`，**仅表示软件允许远程指令，不是物理开关状态**；增加 `local_arm_required=false`。旧 APK 会误显示“现场许可开启”，应重新编译本版本 Android APP 消除该错误提示。
- 默认上电停止、Wi-Fi/MQTT 断线停止、最长运行 180 秒、停止命令优先等约束保留。物理继电器卡死或主控故障时软件停机无保障，保留实体 12V 断电开关。
- 这是 V1.1 源码修订，未验证 Arduino 编译、手机与 EMQX 真机联调。

## GitHub 首版测试 APK（公开仓库）

此仓库公开源码，但不包含 Wi-Fi、MQTT、APP 登录口令或签名私钥。

推送到 `main` 将由 `.github/workflows/android-test-release.yml` 在 GitHub Actions 上编译 Android 调试版并发布首个 `v1.2.0` Release（只在 Release 不存在时创建）。

下载地址：`https://github.com/xxx-hhhhhh/SmartStir-Lab/releases/latest`。

**首次 APK 为测试签名**：不同构建机的 debug.keystore 可能不同，未来无法保证原地覆盖安装；正式发布前需采用固定、妥善保管的发布签名。运行真实电机前仍需现场断电手段和有人监护。
