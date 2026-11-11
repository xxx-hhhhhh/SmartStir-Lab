# Flutter Android APP

This folder includes `lib/main.dart` and `pubspec.yaml`. Android native project files are not bundled because the sandbox does not have Flutter SDK. On Windows:

1. Install Flutter stable, Android Studio (Android SDK) and VS Code Flutter extension.
2. Go to folder `mobile/`.
3. Run `flutter create --platforms=android .` to generate standard Android project files. **Back up `lib/main.dart` and `pubspec.yaml` first if the tool reports overwrite.**
4. Run `flutter pub get`, `flutter doctor -v`.
5. On a debug-enabled Android phone, run `flutter run`.
6. In APP login screen enter your own backend HTTPS base URL and login credentials.
7. To build APK: `flutter build apk --release` (only after system integration and testing).

The app does not embed MQTT broker usernames/passwords. The login session token is held in memory only. This is a V1 prototype, not a production authentication solution.

## v1.2.0: GitHub 更新

登录页和设置页新增「检查 GitHub 更新」。向公开 GitHub 仓库
`xxx-hhhhhh/SmartStir-Lab` 的 Releases API 查询稳定版，检查到新版本后
通过系统浏览器打开 `.apk` 下载链接，用户手动确认安装。
**这个功能不会在后台静默安装。**

请先在手机上安装 `v1.2.0` 或更高版本，旧的 `v1.0.0` APK 本身没有检查更新入口。
仓库创建及初版发布详见 `../docs/APP-UPDATES.md`。
