# Android APP 内「检查 GitHub 更新」功能

## 现在已有

- 登录页面与设置页新增「检查 GitHub 更新」入口，不要求先登录云端。
- 通过 HTTPS GET `https://api.github.com/repos/xxx-hhhhhh/SmartStir-Lab/releases/latest` 查询**公开、非草稿、非预发布**版本。
- 读取 `tag_name`（例如 `v1.2.1`），与 APP `pubspec.yaml` 中的版本 `1.2.0+3` 比较。
- 版本更新时只接受此仓库 `https://github.com/xxx-hhhhhh/SmartStir-Lab/releases/download/<tag>/*.apk` 的 APK 附件链接。
- 用户点击「下载并更新」后，使用浏览器下载 APK。**必须由 Android 系统提示安装，APP 不会静默安装。** 如果 Android 阻止“从此来源安装未知应用”，用户需要自己检查来源并决定是否允许。
- 如果仓库不存在、是私有仓库、没有正式 Release 或 Release 里没有 APK，将显示对应提示。

## 关键前置条件

1. `xxx-hhhhhh/SmartStir-Lab` 已创建，**现在是 PUBLIC 公开仓库**。匿名 GitHub Releases API 不可读，未解决发布可访问性之前，APP 内检查更新不会正常发现版本。
2. 不要向公开仓库提交 Wi-Fi、MQTT 密码、`secrets.h`、`.env`、APP 登录凭据、密钥文件。上传前必须检查 git diff。
3. 匿名的手机 APP **无法读取私有 GitHub Releases**。如果源码需要私有，就另开公开的发行版仓库，并同步修改 `lib/core/github_update_service.dart` 中的 owner/repository；不要把 GitHub Token 嵌入 APK。
4. Android 要求 APK **包名相同且签名证书相同**才能直接覆盖更新。你们之前 Windows 生成的 `com.smartstir.smartstir_lab` Debug APK，与新构建 APK 只有使用相同 debug.keystore 才可能直接升级。不同签名只能先卸载旧 APP（可能丢失本机数据），然后安装新版。正式发布前应建立并妥善备份稳定的 release.keystore。
5. 每次发布时先递增 `pubspec.yaml` 的 `version`（名称和 build number），例如从 `1.2.0+3` 变为 `1.2.1+4`；Release Tag 必须是 `v1.2.1`；附件必须是 `.apk` 文件。

## Windows 一次性发布第一版（需要用户 GitHub CLI 权限）

在解压的 SmartStir-Lab 根目录运行：

```powershell
# 提前安装 Git、GitHub CLI、Flutter 和 Android SDK
# 一次性授权 gh：
gh auth login
# 仓库不存在时，会创建公开仓库（仅在显式传入 -CreatePublicRepo 时）：
.\tools\publish_first_release.ps1 -CreatePublicRepo
```

脚本会：检查并排除密钥文件、创建或更新 GitHub 仓库、运行 Flutter 测试、**在当前 Windows 电脑上**编译 DEBUG APK、上传到公开 Release `v1.2.0`，并打印手机可打开的 GitHub 发布页面。你在手机浏览器打开即可下载并确认安装。

**注意：这一版是 debug 签名试用版，不是正式的安全发布链。** 以后建议迁移到私钥受控的 release 签名流程；签名迁移不能直接覆盖旧 debug 安装。

## API 说明

功能独立于 Railway / EMQX，检查更新时不发送任何电机控制指令。不会自动下载后台 APK、不会自动安装或请求系统级安装权限。手机 APP 登录与 MQTT 密码无需提交到 GitHub。

## 现阶段验证状态

已完成源码变更和静态检查；**当前执行环境没有 Flutter/Android SDK，尚未编译新 APK，也没有创建 GitHub Release**。必须在 Windows 或受信任的 Android CI 环境里实际编译签名后才能提供手机安装包。
