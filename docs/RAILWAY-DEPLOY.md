# SmartStir-Lab 在 Railway 的后端部署

## Railway 项目已经准备（但未部署）

- Railway 工作区：`xxx-hhhhhh's Projects`
- 私有项目名称：`SmartStir-Lab`
- Project ID：`0be8e8a9-55e4-4e37-8cd3-8b5891a4f5c0`
- Environment：`production`，ID：`141e9208-0b20-43fb-88e6-a61a792fe30d`
- 服务：`smartstir-api`，ID：`98a822e4-3fb4-4f05-9094-6269bfac4f22`
- 状态：**staged-create（尚未应用，尚未部署）**，没有公网域名、运行容器或连接到 EMQX。

[打开 Railway 项目](https://railway.com/project/0be8e8a9-55e4-4e37-8cd3-8b5891a4f5c0)

## 源代码准备

1. 在你的 GitHub 账户中新建一个**私有**仓库，例如 `SmartStir-Lab`。
2. 下载项目 ZIP，解压整个 `SmartStir-Lab` 目录，然后上传/提交源码。**绝不要上传 `secrets.h`、`.env`、Wi-Fi 密码、MQTT 密码或私钥。**
3. 在 Railway 的 `smartstir-api` 服务上提交待部署的空服务草稿，然后连接这个私有 GitHub 仓库。
4. 设置该服务的根目录为 `/backend`；这个目录已有 `Dockerfile` 和 `requirements.txt`。
5. 使用 Railway 变量面板配置以下变量（**不要发送到聊天窗口**）：
   - `DEVICE_ID=stirrer-001`
   - `MQTT_HOST=<EMQX Serverless 主机域名>`
   - `MQTT_PORT=8883`
   - `MQTT_USER=smartstir-backend`
   - `MQTT_PASSWORD=<后端独立 MQTT 密码>`
   - `APP_USERNAME=admin`
   - `APP_PASSWORD_SALT=<本地工具生成>`
   - `APP_PASSWORD_HASH=<本地工具生成>`
   - `DB_PATH=/data/local.db`（要求持久卷 `/data`，否则 Railway 重启后可能丢失 SQLite 数据）
   - `MQTT_CA_PATH` 可省略（默认使用系统可信 CA）；如果 Broker 使用私有 CA，需要在容器中提供证书文件，并配置路径。
6. 配置持久卷：在 API 服务下新建 Railway Volume，挂载 `/data`，避免 SQLite 在重启后丢失。
7. 提交部署，确认 Railway Deployment 状态 `SUCCESS`；在服务设置中生成 Railway 默认 HTTPS 域名，并确认 `/health` 返回 `mqtt_connected: true`。只有 `true` 才代表后端到 Broker 的认证连接成功。
8. Flutter APP 登录页面使用 Railway 生成的 `https://...up.railway.app` 地址，而**不是** EMQX Broker 地址。

## 安全与限制

当前后端是 **单用户原型**，包含粗粒度登录频率限制、短期内存会话、MQTT TLS、状态检查及指令回执。用于有人监护的实验台架，不是正式产品级 IAM 或合规审计系统。

Railway 项目可能产生费用，需在 Railway Billing 设置中检查计划和消耗限制；创建空服务草稿不等于启动可计费运行实例。

公网控制真实电机之前，已取消 GPIO32 现场许可输入，仍必须落实独立电机断电手段，并验证断线、重启、过期指令不会误启动电机。
