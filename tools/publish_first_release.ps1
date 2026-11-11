<#
SmartStir Lab 1.2.0 - publish source and first TEST APK from the developer's
Windows computer. Requires Flutter, Android SDK, Git and GitHub CLI (gh).

Run explicitly with -CreatePublicRepo to permit creating a PUBLIC source repo.
There is no attempt to copy passwords, sign with a production key or change Railway.

IMPORTANT: this is a DEBUG-SIGNED test release. Install-over updates require
future APKs to be signed by the SAME local debug signing certificate.
Production distribution must use a stable, backed-up release signing key.
#>
param([switch]$CreatePublicRepo)
$ErrorActionPreference = 'Stop'
$repo = 'xxx-hhhhhh/SmartStir-Lab'
$version = 'v1.2.0'
$root = Split-Path -Parent $PSScriptRoot

function NeedTool([string]$name) {
    if (-not (Get-Command $name -ErrorAction SilentlyContinue)) {
        throw "缺少工具 $name。请先安装后重新运行。"
    }
}
NeedTool 'git'
NeedTool 'gh'
NeedTool 'flutter'
& gh auth status
if ($LASTEXITCODE -ne 0) { throw 'GitHub CLI 尚未登录。请在终端运行 gh auth login。' }

Push-Location $root
try {
    # We NEVER publish secrets or signing keys, regardless of .gitignore contents.
    $sensitive = @('firmware/SmartStir/secrets.h','backend/.env','mobile/android/key.properties')
    foreach ($file in $sensitive) {
        if (Test-Path $file) {
            & git rev-parse --is-inside-work-tree 2>$null | Out-Null
            if ($LASTEXITCODE -eq 0) {
                $tracked = & git ls-files --error-unmatch -- "$file" 2>$null
                if ($LASTEXITCODE -eq 0) { throw "敏感文件已被 Git 跟踪：$file。请先移除跟踪。" }
            }
        }
    }

    if (-not (Test-Path '.git')) {
        & git init -b main
        if ($LASTEXITCODE -ne 0) { throw 'Git 初始化失败' }
    }
    & git add -A
    if ($LASTEXITCODE -ne 0) { throw 'Git add 失败' }
    $trackedNames = (& git diff --cached --name-only)
    foreach ($name in $trackedNames) {
        if ($name -match '(?i)(^|/)(secrets\.h|\.env|key\.properties)$|\.(jks|keystore|p12|key)$') {
            throw "发现意外跟踪的敏感文件：$name，停止上传。"
        }
    }
    & git diff --cached --quiet
    if ($LASTEXITCODE -ne 0) {
        & git commit -m 'feat: SmartStir Android GitHub update check v1.2.0'
        if ($LASTEXITCODE -ne 0) { throw 'Git commit 失败：请先配置 user.name 和 user.email。' }
    }

    & gh repo view $repo --json name --jq .name 2>$null
    $exists = $LASTEXITCODE -eq 0
    $origin = (& git remote get-url origin 2>$null) -join ''
    if ($origin -and ($origin -notmatch '(^|[:/])xxx-hhhhhh/SmartStir-Lab(\.git)?$')) {
        throw "当前仓库已有其他 origin ($origin)，为避免误上传已停止。"
    }
    if (-not $exists) {
        if (-not $CreatePublicRepo) {
            throw "缺少仓库 $repo。执行本脚本时添加 -CreatePublicRepo 以明确创建 PUBLIC 仓库。"
        }
        # A public repo makes GitHub Releases readable to the phone without a PAT.
        & gh repo create $repo --public --source . --remote origin --push
        if ($LASTEXITCODE -ne 0) { throw 'GitHub 仓库创建/首次 push 失败' }
    } else {
        if (-not $origin) { & git remote add origin "https://github.com/$repo.git" }
        & git push -u origin main
        if ($LASTEXITCODE -ne 0) { throw 'Git push 失败；不执行 force push。' }
    }

    $visibility = (& gh repo view $repo --json visibility --jq .visibility)
    if ($visibility -eq 'PRIVATE') {
        Write-Warning '仓库是 PRIVATE：手机匿名检查 GitHub Releases 会返回 404。当前只用于源码保管和登录 GitHub 的测试 APK 下载。'
        Write-Warning '如需 APP 内检查更新，先建立单独的公开 Releases 仓库并更新 GitHub owner/repository，或经安全检查后由仓库管理员公开源仓库。'
    }

    Push-Location 'mobile' 
    try {
        if (-not (Test-Path 'android')) {
            & flutter create --org com.smartstir --project-name smartstir_lab --platforms=android .
            if ($LASTEXITCODE -ne 0) { throw '无法生成 Android 工程' }
        }
        $manifest = 'android/app/src/main/AndroidManifest.xml'
        $xml = [IO.File]::ReadAllText((Join-Path (Get-Location) $manifest))
        if ($xml -notmatch 'android\.permission\.INTERNET') {
            $xml = $xml.Replace('<application', '    <uses-permission android:name="android.permission.INTERNET" />' + [Environment]::NewLine + '    <application')
            [IO.File]::WriteAllText((Join-Path (Get-Location) $manifest), $xml)
        }
        & flutter pub get
        if ($LASTEXITCODE -ne 0) { throw 'flutter pub get 失败' }
        & flutter analyze
        if ($LASTEXITCODE -ne 0) { throw 'flutter analyze 失败' }
        & flutter test
        if ($LASTEXITCODE -ne 0) { throw 'flutter test 失败' }
        & flutter build apk --debug
        if ($LASTEXITCODE -ne 0) { throw 'APK 编译失败' }
    } finally { Pop-Location }

    $src = Join-Path $root 'mobile/build/app/outputs/flutter-apk/app-debug.apk'
    if (-not (Test-Path $src)) { throw '编译命令成功，但无法找到 APK' }
    $dist = Join-Path $root 'dist'
    New-Item -ItemType Directory -Force -Path $dist | Out-Null
    $apk = Join-Path $dist 'SmartStir-Lab-v1.2.0-debug.apk'
    Copy-Item $src $apk -Force
    & gh release view $version --repo $repo --json url --jq .url 2>$null
    if ($LASTEXITCODE -eq 0) {
        Write-Warning "Release $version 已存在；没有覆盖现有附件。"
    } else {
        & gh release create $version $apk --repo $repo --title 'SmartStir Lab v1.2.0 - Android 测试版' --notes 'Android 调试签名测试版；支持 GitHub 更新检查、远程 PWM 控制、无 GPIO32 许可开关。用户需在 Android 系统确认安装。仅供有人监护的测试，非正式发布。'
        if ($LASTEXITCODE -ne 0) { throw 'GitHub Release 创建失败' }
    }
    Write-Host "GitHub: https://github.com/$repo"
    Write-Host "手机 APK 下载: https://github.com/$repo/releases/tag/$version"
    Write-Host "本机 APK: $apk"
    Write-Warning '仅供开发测试：请保留 Windows 的 debug.keystore。未来发布不同签名的 APK 将无法直接覆盖安装。'
} finally { Pop-Location }
