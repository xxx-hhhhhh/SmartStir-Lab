import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// APP-only preferences. No MQTT credentials or authentication tokens are saved here.
class AppPrefs {
  static final language = ValueNotifier<String>('zh');
  static final confirmStart = ValueNotifier<bool>(false);

  static Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final code = prefs.getString('language') ?? 'zh';
    language.value = ['zh', 'en', 'ja'].contains(code) ? code : 'zh';
    confirmStart.value = prefs.getBool('confirm_start') ?? false;
  }

  static Future<void> setLanguage(String value) async {
    if (!['zh', 'en', 'ja'].contains(value)) return;
    language.value = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('language', value);
  }

  static Future<void> setConfirmStart(bool value) async {
    confirmStart.value = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('confirm_start', value);
  }
}

class L {
  static String t(String key) {
    final dict = _words[key];
    if (dict == null) return key;
    return dict[AppPrefs.language.value] ?? dict['zh'] ?? key;
  }

  static const Map<String, Map<String, String>> _words = {
    'app': {'zh':'智研云搅', 'en':'SmartStir Lab', 'ja':'SmartStir Lab'},
    'subtitle': {'zh':'实验室设备管理', 'en':'Laboratory device management', 'ja':'実験室デバイス管理'},
    'login': {'zh':'登录', 'en':'Sign in', 'ja':'ログイン'},
    'register': {'zh':'注册账号', 'en':'Create account', 'ja':'アカウント登録'},
    'switch_login': {'zh':'已有账号？去登录', 'en':'Already registered? Sign in', 'ja':'アカウントをお持ちですか？ログイン'},
    'switch_register': {'zh':'没有账号？立即注册', 'en':'New here? Register', 'ja':'新規登録はこちら'},
    'username': {'zh':'用户名', 'en':'Username', 'ja':'ユーザー名'},
    'password': {'zh':'密码', 'en':'Password', 'ja':'パスワード'},
    'confirm_password': {'zh':'确认密码', 'en':'Confirm password', 'ja':'パスワード（確認）'},
    'password_note': {'zh':'至少 10 位，含字母和数字', 'en':'At least 10 characters, letters and numbers', 'ja':'英数字を含む10文字以上'},
    'password_mismatch': {'zh':'两次输入的密码不一致', 'en':'Passwords do not match', 'ja':'パスワードが一致しません'},
    'server': {'zh':'服务器地址', 'en':'Server URL', 'ja':'サーバーURL'},
    'loading': {'zh':'正在加载…', 'en':'Loading…', 'ja':'読み込み中…'},
    'submit': {'zh':'确认', 'en':'Confirm', 'ja':'確認'},
    'cancel': {'zh':'取消', 'en':'Cancel', 'ja':'キャンセル'},
    'save': {'zh':'保存', 'en':'Save', 'ja':'保存'},
    'update': {'zh':'检查更新', 'en':'Check for updates', 'ja':'更新を確認'},
    'labs': {'zh':'我的实验室', 'en':'My laboratories', 'ja':'マイ実験室'},
    'create_lab': {'zh':'创建实验室', 'en':'Create laboratory', 'ja':'実験室を作成'},
    'lab_name': {'zh':'实验室名称', 'en':'Laboratory name', 'ja':'実験室名'},
    'no_labs': {'zh':'还没有实验室，先创建一个吧', 'en':'Create your first laboratory', 'ja':'まず実験室を作成してください'},
    'legacy_label': {'zh':'旧版', 'en':'Legacy', 'ja':'旧バージョン'},
    'legacy_gateway': {'zh':'当前连接的是 V1.2 网关。仍可控制已有的 stirrer-001；注册、创建实验室和邀请功能需要部署 V1.3 新网关。', 'en':'Connected to the V1.2 gateway. Existing stirrer-001 controls remain available; registration and labs require V1.3 backend.', 'ja':'V1.2ゲートウェイに接続中。既存のstirrer-001は操作できます。登録・実験室機能にはV1.3サーバーが必要です。'},
    'devices': {'zh':'实验设备', 'en':'Devices', 'ja':'デバイス'},
    'add_device': {'zh':'添加 ESP32', 'en':'Add ESP32', 'ja':'ESP32を追加'},
    'device_id': {'zh':'ESP32 设备编号', 'en':'ESP32 device ID', 'ja':'ESP32デバイスID'},
    'device_name': {'zh':'设备名称', 'en':'Device name', 'ja':'デバイス名'},
    'pairing_code': {'zh':'设备配对码', 'en':'Device pairing code', 'ja':'ペアリングコード'},
    'pair_hint': {'zh':'从 ESP32 串口获取配对码；设备需要在线并运行 V1.3 固件', 'en':'Get the code from ESP32 serial output; v1.3 firmware must be online', 'ja':'ESP32シリアルからコードを確認（V1.3ファームウェアが必要）'},
    'no_devices': {'zh':'暂无设备，点击添加 ESP32', 'en':'No devices yet. Add an ESP32.', 'ja':'デバイスがありません。ESP32を追加してください'},
    'invite': {'zh':'邀请用户', 'en':'Invite member', 'ja':'メンバーを招待'},
    'invite_username': {'zh':'输入已注册的用户名', 'en':'Enter registered username', 'ja':'登録済みユーザー名を入力'},
    'invitations': {'zh':'实验室邀请', 'en':'Invitations', 'ja':'招待'},
    'accept': {'zh':'接受', 'en':'Accept', 'ja':'承認'},
    'decline': {'zh':'拒绝', 'en':'Decline', 'ja':'辞退'},
    'members': {'zh':'成员', 'en':'Members', 'ja':'メンバー'},
    'owner': {'zh':'创建者', 'en':'Owner', 'ja':'オーナー'},
    'member': {'zh':'成员', 'en':'Member', 'ja':'メンバー'},
    'settings': {'zh':'设置', 'en':'Settings', 'ja':'設定'},
    'language': {'zh':'界面语言', 'en':'App language', 'ja':'表示言語'},
    'zh': {'zh':'简体中文', 'en':'Simplified Chinese', 'ja':'簡体字中国語'},
    'en': {'zh':'英语', 'en':'English', 'ja':'英語'},
    'ja': {'zh':'日语', 'en':'Japanese', 'ja':'日本語'},
    'confirmation': {'zh':'启动前二次确认', 'en':'Confirm before starting', 'ja':'起動前の確認'},
    'confirmation_desc': {'zh':'开启后启动电机前弹出确认框，关闭后直接发送启动指令', 'en':'Show an extra confirmation dialog before sending START', 'ja':'起動コマンド前に確認ダイアログを表示'},
    'safety_note': {'zh':'此开关仅影响 APP 弹窗，不会关闭 ESP32 断网停机和 180 秒自动停机等固件保护。必须保留现场断电方式。', 'en':'This changes only the app dialog; ESP32 disconnect and 180-second stop safeguards remain. Keep a physical power cutoff.', 'ja':'この設定はアプリの確認表示のみです。ESP32の通信切断・180秒停止保護は有効のままです。物理遮断手段を確保してください。'},
    'logout': {'zh':'退出登录', 'en':'Sign out', 'ja':'ログアウト'},
    'back_labs': {'zh':'返回实验室', 'en':'Back to laboratories', 'ja':'実験室に戻る'},
    'online': {'zh':'在线', 'en':'Online', 'ja':'オンライン'},
    'offline': {'zh':'离线', 'en':'Offline', 'ja':'オフライン'},
    'unknown': {'zh':'未知', 'en':'Unknown', 'ja':'不明'},
    'control': {'zh':'控制台', 'en':'Controls', 'ja':'制御'},
    'events': {'zh':'运行事件', 'en':'Events', 'ja':'イベント'},
    'refresh': {'zh':'刷新', 'en':'Refresh', 'ja':'更新'},
    'motor': {'zh':'电机状态', 'en':'Motor status', 'ja':'モーター状態'},
    'running': {'zh':'运行中', 'en':'Running', 'ja':'運転中'},
    'stopped': {'zh':'已停止', 'en':'Stopped', 'ja':'停止'},
    'pwm': {'zh':'PWM 占空比', 'en':'PWM duty cycle', 'ja':'PWMデューティ比'},
    'rpm': {'zh':'实测转速', 'en':'Measured RPM', 'ja':'実測回転数'},
    'rpm_absent': {'zh':'未安装测速传感器', 'en':'No RPM sensor', 'ja':'回転数センサー未接続'},
    'set_pwm': {'zh':'应用 PWM', 'en':'Apply PWM', 'ja':'PWMを設定'},
    'start': {'zh':'启动电机', 'en':'Start motor', 'ja':'モーター起動'},
    'stop': {'zh':'停止电机', 'en':'Stop motor', 'ja':'モーター停止'},
    'start_confirm_title': {'zh':'确认启动电机', 'en':'Confirm start', 'ja':'起動を確認'},
    'start_confirm_body': {'zh':'请确认现场有人监护、容器及磁铁牢固，并能通过实体开关随时切断电机电源。', 'en':'Make sure someone is on site, the apparatus is secure, and motor power can be physically cut off.', 'ja':'現場監督者、装置の固定、電源を物理的に遮断できることを確認してください。'},
    'command_wait': {'zh':'指令已发送，等待 ESP32 确认', 'en':'Waiting for ESP32 acknowledgement', 'ja':'ESP32の応答待ち'},
    'pending': {'zh':'处理中…', 'en':'Working…', 'ja':'処理中…'},
    'no_events': {'zh':'暂无事件', 'en':'No events yet', 'ja':'イベントなし'},
    'error': {'zh':'操作失败', 'en':'Operation failed', 'ja':'操作に失敗しました'},
    'info': {'zh':'关于项目', 'en':'About', 'ja':'プロジェクト情報'},
    'checking_updates': {'zh':'正在检查新版本…','en':'Checking for updates…','ja':'更新を確認中…'},
    'latest_version': {'zh':'已是最新版本','en':'Up to date','ja':'最新バージョンです'},
    'current_version': {'zh':'当前版本','en':'Current version','ja':'現在のバージョン'},
    'no_new_version': {'zh':'暂未发现新的稳定版 APK。','en':'No newer stable APK found.','ja':'新しい安定版APKはありません。'},
    'new_version': {'zh':'发现新版本','en':'Update available','ja':'新しいバージョンがあります'},
    'release_notes_missing': {'zh':'本次发布暂无更新说明。','en':'No release notes provided.','ja':'リリースノートはありません。'},
    'update_security': {'zh':'将通过系统浏览器打开 GitHub 下载页，安装需要 Android 系统确认。','en':'Opens GitHub in your browser; Android will ask before installation.','ja':'GitHubのダウンロードページを開きます。インストールにはAndroidの確認が必要です。'},
    'later': {'zh':'稍后再说','en':'Later','ja':'後で'},
    'download_update': {'zh':'下载并更新','en':'Download update','ja':'更新をダウンロード'},
    'browser_error': {'zh':'无法打开浏览器，请稍后重试','en':'Unable to open browser. Try again.','ja':'ブラウザを開けません。後ほどお試しください。'},
    'update_error': {'zh':'检查更新失败','en':'Update check failed','ja':'更新の確認に失敗しました'},
    'server_upgrade_required': {'zh':'当前服务器尚未升级到 V1.3，暂不支持注册。','en':'This server has not been upgraded to V1.3; registration is unavailable.','ja':'サーバーはまだV1.3に更新されていないため登録できません。'},
    'username_taken': {'zh':'用户名已被使用','en':'Username is taken','ja':'ユーザー名は使用されています'},
    'bad_credentials': {'zh':'用户名或密码错误','en':'Incorrect username or password','ja':'ユーザー名かパスワードが正しくありません'},
    'owner_only': {'zh':'仅实验室创建者可以执行此操作','en':'Only laboratory owners can do this','ja':'実験室オーナーのみ操作できます'},
    'lab_missing': {'zh':'实验室不存在或无访问权限','en':'Laboratory not found or access denied','ja':'実験室が存在しないか権限がありません'},
    'device_claimed': {'zh':'该 ESP32 已被其他实验室绑定','en':'This ESP32 is already claimed','ja':'このESP32は既に登録済みです'},
    'pairing_failed': {'zh':'没有找到设备的有效配对证明；请先让 ESP32 联网并重试','en':'No current pairing proof. Connect ESP32 to MQTT and retry.','ja':'有効なペアリング情報がありません。ESP32を接続して再試行してください'},
    'device_missing': {'zh':'未找到设备或无访问权限','en':'Device not found or access denied','ja':'デバイスが存在しないか権限がありません'},
    'username_missing': {'zh':'未找到该注册用户','en':'Registered user not found','ja':'登録済みユーザーが見つかりません'},
    'mqtt_unavailable': {'zh':'云端 MQTT 暂时离线','en':'Cloud MQTT is offline','ja':'クラウドMQTTはオフラインです'},
  };
}
