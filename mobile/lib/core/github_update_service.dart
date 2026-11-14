import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'app_preferences.dart';

/// GitHub Releases only. The repo must be PUBLIC to allow anonymous checking.
/// A private source repository needs a separate public release repository.
class SmartStirUpdateService {
  static const owner = 'xxx-hhhhhh';
  static const repository = 'SmartStir-Lab';
  static const _api =
      'https://api.github.com/repos/$owner/$repository/releases/latest';
  static const _releases = 'https://github.com/$owner/$repository/releases';

  static Future<AppUpdate?> check({http.Client? client}) async {
    final package = await PackageInfo.fromPlatform();
    final version = package.version;
    final ownClient = client == null;
    final httpClient = client ?? http.Client();
    try {
      final response = await httpClient.get(
        Uri.parse(_api),
        headers: const {
          'Accept': 'application/vnd.github+json',
          'X-GitHub-Api-Version': '2022-11-28',
        },
      ).timeout(const Duration(seconds: 12));

      if (response.statusCode == 404) {
        throw const FormatException('更新仓库尚未公开或尚未发布 Release');
      }
      if (response.statusCode != 200) {
        throw Exception('GitHub 请求失败（HTTP ${response.statusCode}）');
      }
      final root = jsonDecode(utf8.decode(response.bodyBytes));
      if (root is! Map<String, dynamic>) {
        throw const FormatException('GitHub 返回了无效数据');
      }
      final tag = root['tag_name'];
      if (tag is! String || !isNewerVersion(tag, version)) return null;
      if (root['draft'] == true || root['prerelease'] == true) return null;

      // Only a release APK in OUR repository is allowed as an update target.
      final assets = root['assets'];
      String? apkUrl;
      if (assets is List) {
        for (final item in assets) {
          if (item is! Map) continue;
          final name = item['name'];
          final url = item['browser_download_url'];
          if (name is String && url is String &&
              name.toLowerCase().endsWith('.apk') &&
              isTrustedAssetUrl(url, owner, repository)) {
            apkUrl = url;
            break;
          }
        }
      }
      if (apkUrl == null) {
        throw const FormatException('已发现新版本，但发布页没有可下载的 Android APK');
      }
      final notes = root['body'];
      return AppUpdate(
        tag: tag,
        currentVersion: version,
        releaseNotes: notes is String ? notes : '',
        apkUrl: apkUrl,
      );
    } finally {
      if (ownClient) httpClient.close();
    }
  }

  /// Semantic version triplets; a release version's build number may differ.
  /// Ignore -alpha/-rc versions for stable update checks.
  static bool isNewerVersion(String release, String current) {
    final remote = _parseStableVersion(release);
    final local = _parseStableVersion(current);
    if (remote == null || local == null) return false;
    for (var i = 0; i < 3; i++) {
      if (remote[i] > local[i]) return true;
      if (remote[i] < local[i]) return false;
    }
    return false;
  }

  static List<int>? _parseStableVersion(String value) {
    final matched = RegExp(r'^v?(\d+)\.(\d+)\.(\d+)(?:\+\d+)?$')
        .firstMatch(value.trim());
    if (matched == null) return null;
    return List.generate(3, (i) => int.parse(matched.group(i + 1)!));
  }

  static bool isTrustedAssetUrl(String url, String owner, String repo) {
    final uri = Uri.tryParse(url);
    if (uri == null || uri.scheme != 'https' || uri.host != 'github.com' ||
        uri.userInfo.isNotEmpty || uri.hasFragment) {
      return false;
    }
    final seg = uri.pathSegments;
    return seg.length == 6 && seg[0] == owner && seg[1] == repo &&
        seg[2] == 'releases' && seg[3] == 'download' &&
        seg.last.toLowerCase().endsWith('.apk');
  }

  static Future<void> showUpdateDialog(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(SnackBar(content: Text(L.t('checking_updates')),
      duration: Duration(seconds: 2)));
    try {
      final pkg = await PackageInfo.fromPlatform();
      final update = await check();
      if (!context.mounted) return;
      if (update == null) {
        await showDialog<void>(context: context, builder: (ctx) => AlertDialog(
          title: Text(L.t('latest_version')),
          content: Text('${L.t('current_version')}: ${pkg.version}\n${L.t('no_new_version')}'),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx),
            child: Text(L.t('submit')))],
        ));
        return;
      }
      await showDialog<void>(context: context, builder: (ctx) => AlertDialog(
        title: Text(L.t('new_version')),
        content: SingleChildScrollView(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('${L.t('current_version')} ${update.currentVersion}  →  ${update.tag}',
              style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 12),
            Text(update.releaseNotes.isEmpty ? L.t('release_notes_missing')
              : update.releaseNotes, maxLines: 18,
              overflow: TextOverflow.ellipsis),
            const SizedBox(height: 14),
            Text(L.t('update_security'),
              style: TextStyle(fontSize: 12)),
          ],
        )),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx),
            child: Text(L.t('later'))),
          FilledButton.icon(
            onPressed: () async {
              Navigator.pop(ctx);
              final url = Uri.parse(update.apkUrl);
              final opened = await launchUrl(url,
                mode: LaunchMode.externalApplication);
              if (!opened && context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(L.t('browser_error'))));
              }
            },
            icon: const Icon(Icons.open_in_browser),
            label: Text(L.t('download_update')),
          ),
        ],
      ));
    } catch (error) {
      if (!context.mounted) return;
      messenger.showSnackBar(SnackBar(
        content: Text('${L.t('update_error')}: $error'),
        duration: const Duration(seconds: 6),
      ));
    }
  }

  static Uri get releasePage => Uri.parse(_releases);
}

class AppUpdate {
  const AppUpdate({
    required this.tag,
    required this.currentVersion,
    required this.releaseNotes,
    required this.apkUrl,
  });
  final String tag;
  final String currentVersion;
  final String releaseNotes;
  final String apkUrl;
}
