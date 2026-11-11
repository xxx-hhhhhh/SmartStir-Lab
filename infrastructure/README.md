# 公网后端 HTTPS 部署（需要用户自有云主机与域名）

这是一份可供自有 VPS 使用的 Docker Compose / Caddy 配置**模板**，尚未在云端部署或验证。请先完成 EMQX Broker、证书与 ACL 配置。

前提：VPS 安装 Docker Compose；有域名，例如 `api.example.com`，DNS A/AAAA 指向 VPS；TCP 80、443 放行；运营商/平台允许该网络服务。

1. 在 `backend/` 创建 `.env`，填写 MQTT Host/Port/User/Password、管理员用户名及 scrypt 哈希；如果系统根证书不识别 Broker TLS 证书，再把 CA PEM 保存为 `backend/emqx-ca.pem` 并设置 `MQTT_CA_PATH`。
2. 将 `infrastructure/.env.example` 复制成 `infrastructure/.env`，设置 `API_DOMAIN` 为你们拥有的真实域名，**不要用示例域名**。
3. 在 VPS 项目根目录：`cd infrastructure`，运行 `docker compose up -d --build`。
4. 浏览器打开 `https://<your-api-domain>/health`，检查 MQTT 连接是否就绪。
5. Android APP 登录界面输入 `https://<your-api-domain>` 与自建 APP 账号密码。

后端端口 8000 仅在 Docker 内网开放，不直接暴露公网；Caddy 为公网 HTTPS 入口。正式产品需要进一步增加防暴力登录、可撤销用户会话、数据库备份和访问日志保护；当前仍仅用于现场监督的原型测试。
