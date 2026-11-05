# ============================================================
# QingNZ 探针 Windows 一键安装脚本 (PowerShell 5+)
#
#   安装目录: C:\qingnz
#   二进制:   C:\qingnz\qingnz.exe
#   配置:     C:\qingnz\config.yml
#   服务名:   qingnz
#
# 用法(先设置环境变量再运行):
#   $env:NZ_SERVER="xxx"; $env:NZ_CLIENT_SECRET="xxx"; ...
#   powershell.exe .\install.ps1
# ============================================================

# Require PS >= 5
if ($PSVersionTable.PSVersion.Major -lt 5) {
    Write-Host "Require PS >= 5, your PSVersion:" $PSVersionTable.PSVersion.Major -BackgroundColor DarkGreen -ForegroundColor White
    exit 1
}

$agentrepo = "qingdeng888/nzagent"
$nzDir = "C:\qingnz"
$nzBin = "$nzDir\qingnz.exe"

# TLS
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# x86 / x64 / arm64
if ([System.Environment]::Is64BitOperatingSystem) {
    if ($env:PROCESSOR_ARCHITECTURE -eq "ARM64") {
        $file = "qingnz_windows_arm64.zip"
    } else {
        $file = "qingnz_windows_amd64.zip"
    }
} else {
    $file = "qingnz_windows_386.zip"
}

$download = "https://github.com/$agentrepo/releases/latest/download/$file"

# 可选: 设置 $env:NZ_GH_PROXY 为 GitHub 加速前缀
if (-not [string]::IsNullOrWhiteSpace($env:NZ_GH_PROXY)) {
    $download = "$env:NZ_GH_PROXY$download"
}

# 已安装则先卸载重装
if (Test-Path $nzBin) {
    Write-Host "QingNZ agent already exists, delete and reinstall" -BackgroundColor DarkGreen -ForegroundColor White
    & $nzBin service uninstall
    Remove-Item $nzDir -Recurse -Force
}

if ([string]::IsNullOrWhiteSpace($env:NZ_SERVER)) {
    Write-Host "NZ_SERVER should not be empty" -BackgroundColor DarkRed -ForegroundColor Green
    exit 1
}
if ([string]::IsNullOrWhiteSpace($env:NZ_CLIENT_SECRET)) {
    Write-Host "NZ_CLIENT_SECRET should not be empty" -BackgroundColor DarkRed -ForegroundColor Green
    exit 1
}

Write-Host "Downloading: $download" -BackgroundColor DarkGreen -ForegroundColor White
Invoke-WebRequest $download -OutFile "$env:TEMP\qingnz.zip"

# 解压
Expand-Archive "$env:TEMP\qingnz.zip" -DestinationPath "$env:TEMP\qingnz" -Force
if (!(Test-Path $nzDir)) { New-Item -Path $nzDir -type directory | Out-Null }

# 整理文件
Move-Item -Path "$env:TEMP\qingnz\qingnz.exe" -Destination $nzBin -Force

# 清理临时文件
Remove-Item "$env:TEMP\qingnz.zip" -Force
Remove-Item "$env:TEMP\qingnz" -Recurse -Force

# 注册 Windows 服务 (服务名自动取二进制文件名 -> qingnz)
& $nzBin service install
if ($LASTEXITCODE -ne 0) {
    Write-Host "Install qingnz service failed" -BackgroundColor DarkRed -ForegroundColor Green
    exit 1
}

# 立即启动
& $nzBin service start
if ($LASTEXITCODE -ne 0) {
    Write-Host "Start qingnz service failed, check: Get-Service qingnz" -BackgroundColor DarkRed -ForegroundColor Green
    exit 1
}

Write-Host "QingNZ agent installed: $nzBin  Service: qingnz" -BackgroundColor DarkGreen -ForegroundColor White
Write-Host "Enjoy It!" -BackgroundColor DarkGreen -ForegroundColor Red
