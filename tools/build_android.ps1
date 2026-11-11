# SmartStir Lab: Windows / PowerShell Android debug APK build.
# Requires Flutter SDK, Android SDK and a configured Android toolchain.
$ErrorActionPreference = 'Stop'
$project = Split-Path -Parent $PSScriptRoot
$mobile = Join-Path $project 'mobile'
if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
  throw '未找到 flutter。请先安装 Flutter SDK 并将 bin 加入 PATH： https://docs.flutter.dev/install'
}
Push-Location $mobile
try {
  flutter doctor -v
  # A missing Windows desktop toolchain need not block Android builds.
  if (-not (Test-Path 'android')) {
    flutter create --org com.smartstir --project-name smartstir_lab --platforms=android .
    if ($LASTEXITCODE -ne 0) { throw 'Flutter Android 工程生成失败' }
  }
  $manifest = 'android/app/src/main/AndroidManifest.xml'
  $raw = [System.IO.File]::ReadAllText((Join-Path (Get-Location) $manifest))
  if ($raw -notmatch 'android\.permission\.INTERNET') {
    $needle = '<application'
    if (-not $raw.Contains($needle)) { throw '未找到 AndroidManifest.xml 中的 application 标签' }
    $permission = '    <uses-permission android:name="android.permission.INTERNET" />' + [Environment]::NewLine
    $raw = $raw.Replace($needle, $permission + '    <application')
    [System.IO.File]::WriteAllText((Join-Path (Get-Location) $manifest), $raw)
  }
  flutter pub get
  if ($LASTEXITCODE -ne 0) { throw '依赖安装失败' }
  flutter analyze
  if ($LASTEXITCODE -ne 0) { throw 'Flutter 静态分析失败' }
  flutter test
  if ($LASTEXITCODE -ne 0) { throw 'Flutter 测试失败' }
  flutter build apk --debug
  if ($LASTEXITCODE -ne 0) { throw 'APK 编译失败' }
  Write-Host 'APK: mobile/build/app/outputs/flutter-apk/app-debug.apk'
} finally { Pop-Location }
