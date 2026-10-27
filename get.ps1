# dev-setup: download this repo to ~/.dev-setup and run setup.ps1 (for `irm ... | iex`).
#   $env:DEV_SETUP_REPO = 'owner/repo'; irm https://raw.githubusercontent.com/DaiKi-Ito-110/dev-setup/main/get.ps1 | iex
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor 3072
$root = Join-Path $HOME '.dev-setup'
$tool = Join-Path $root 'dev-setup-main'
$zip = Join-Path $env:TEMP 'dev-setup.zip'
New-Item -ItemType Directory -Force $root | Out-Null
Invoke-WebRequest 'https://github.com/DaiKi-Ito-110/dev-setup/archive/refs/heads/main.zip' -OutFile $zip -UseBasicParsing
if (Test-Path $tool) { Remove-Item $tool -Recurse -Force }
Expand-Archive $zip $root -Force
Remove-Item $zip
Write-Host "dev-setup -> $tool (cleanup.bat is here when you return the PC)"
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $tool 'setup.ps1')
