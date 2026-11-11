# EMQX Cloud 连接配置（2026-11-08）

## 已从用户的部署概览确认的公共参数

- 部署名：`deployment-f8f1e9df`
- 状态：运行中（来自用户提供的截图）
- MQTT Host：`f8f1e9df.ala.cn-shenzhen.emqxsl.cn`
- TLS/SSL MQTT 端口：`8883`
- WebSocket TLS 端口：`8084`（当前架构未直接使用）
- CA：`certs/emqxsl-ca.crt`（用户上传的公开根证书，非私钥）
- Railway 项目：`SmartStir-Lab`，服务：`smartstir-api`

### 已完成

- Railway 的 `smartstir-api` 服务草稿中**已暂存** `MQTT_HOST`、`MQTT_PORT`、`DEVICE_ID`；尚未提交部署，服务尚未运行。
- `backend/.env.example` 和 `firmware/SmartStir/secrets.h.example` 已填好 Host、端口与公开 CA 证书。

### 仍需用户在 EMQX 网页中完成

1. 进入「访问控制 → 客户端认证」。
2. 创建两个 MQTT 客户端用户（各自设置强密码）：
   - `stirrer-001`：ESP32 设备用；
   - `smartstir-backend`：Railway 后端用。
3. 进入「访问控制 → 客户端授权」，按项目 README 配置仅允许访问所属主题。
4. 在本机 `firmware/SmartStir/secrets.h` 填写 Wi-Fi 及设备 MQTT 用户名密码（不可提交 Git）；后端的 `MQTT_PASSWORD` 要在 Railway 变量界面中安全设置，不能写入 APP 或仓库。
5. 创建自己的 APP 登录密码哈希与盐；在 Railway 里设置 `APP_USERNAME`、`APP_PASSWORD_HASH`、`APP_PASSWORD_SALT`。
6. 完成后再考虑正式部署，先在不接电机供电的情况下做只读 MQTT 连接验证。

### App Secret 不是 MQTT 客户端密码

用户在聊天中给出的 App Secret 属于 EMQX 的**部署 HTTP 管理 API**，必须配合其 App ID 使用；本工程使用 MQTT TLS，并不需要部署管理 API Key。出于安全考虑不把这一密钥写入示例代码、工程 ZIP 或 Railway MQTT_PASSWORD。因其已粘贴进聊天，建议到 EMQX 控制台撤销并重新创建 API Key。

### 安全说明

本机可通过 `python tools/mqtt_probe.py` 进行只读测试（需要本地 `backend/.env` 中提供 `MQTT_CA_PATH` 和独立 MQTT 用户密码）；不得使用公共测试 Broker 连接实际电机。本修订不使用 GPIO32 本地运行许可；远程启动前仍必须准备独立实体断电开关。
