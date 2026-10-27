# dev-setup / cleanup.ps1 — レンタルPC を返す前の後片付け（setup.ps1 がしたことを戻す）。
#   GitHub のログインと git の資格情報を消し、clone したフォルダ・パッケージのキャッシュ・入れた Node を消す。
#   winget で入れたツール（Git / GitHub CLI）は聞いてから消す。消す前に必ず一覧を出して確認する。
#
#   cleanup.bat            … ダブルクリック or コマンドで
#   cleanup.ps1 -DryRun    … 何を消すかだけ出す
param([switch]$DryRun)
$ErrorActionPreference = 'Stop'

$StateDir = Join-Path $HOME '.dev-setup'

function Say($m) { Write-Host "==> $m" -ForegroundColor Cyan }
function Skip($m) { Write-Host "    $m" -ForegroundColor DarkGray }
function Warn($m) { Write-Host "!!  $m" -ForegroundColor Yellow }
function Have($cmd) { [bool](Get-Command $cmd -ErrorAction SilentlyContinue) }
function Ask($q) { if ($DryRun) { Skip "(dry-run) $q → y とする"; return $true }; (Read-Host "$q [y/N]") -match '^[yY]' }

function Run([string]$Exe, [string[]]$ArgList) {
  if ($DryRun) { Skip "(dry-run) $Exe $($ArgList -join ' ')"; return }
  $ErrorActionPreference = 'Continue'
  & $Exe @ArgList
  if ($LASTEXITCODE -ne 0) { Warn "うまくいきませんでした: $Exe $($ArgList -join ' ')" }
}
function Get-Native([string]$Exe, [string[]]$ArgList) {
  $ErrorActionPreference = 'Continue'
  $out = & $Exe @ArgList 2> $null
  if ($LASTEXITCODE -eq 0) { ($out | Out-String).Trim() } else { '' }
}
function Read-Record([string]$File) {
  $p = Join-Path $StateDir $File
  if (Test-Path $p) { @(Get-Content $p -Encoding UTF8 | Where-Object { $_ }) } else { @() }
}
function Remove-Dir([string]$p) {
  if (-not (Test-Path $p)) { return }
  if ($DryRun) { Skip "(dry-run) 削除 $p"; return }
  # node_modules の junction をたどらずに消すため rmdir を使う
  cmd.exe /c rmdir /s /q "`"$p`""
  if (Test-Path $p) { Warn "消しきれませんでした: $p（使っているアプリを閉じてもう一度）" }
}

$clones = Read-Record 'clones.txt'
$installed = Read-Record 'installed.txt'
$paths = Read-Record 'paths.txt'

if (-not (Test-Path $StateDir)) {
  Warn 'この PC には setup の記録（~/.dev-setup）がありません。自分の PC で流すと、普段使っているログイン情報やキャッシュも消えます。'
  if (-not (Ask '続けますか？')) { exit }
}

# ---- 1. GitHub のログインと git の資格情報 -----------------------------------
Say 'GitHub のログインと git の資格情報を消す'
if ((Have gh) -and (Get-Native gh @('auth', 'token', '--hostname', 'github.com'))) {
  Run gh @('auth', 'logout', '--hostname', 'github.com')
} else { Skip 'gh はログインしていない' }
if (Have git) {
  foreach ($h in 'https://github.com', 'https://gist.github.com') {
    if (Get-Native git @('config', '--global', '--get-all', "credential.$h.helper")) { Run git @('config', '--global', '--unset-all', "credential.$h.helper") }
  }
  if (-not $DryRun) { "protocol=https`nhost=github.com`n" | git credential reject }
}
# Windows の資格情報マネージャーに残った github.com の分（行は「ターゲット: LegacyGeneric:target=git:https://github.com」）
foreach ($line in (cmdkey /list | Select-String 'target=(.*github\.com.*)$')) {
  Run cmdkey @("/delete:$($line.Matches[0].Groups[1].Value.Trim())")
}
if (Test-Path (Join-Path $StateDir 'git-identity')) {
  Run git @('config', '--global', '--unset', 'user.name')
  Run git @('config', '--global', '--unset', 'user.email')
} elseif ((Have git) -and (Get-Native git @('config', '--global', 'user.name'))) {
  if (Ask "git の名前・メール（$(Get-Native git @('config', '--global', 'user.name'))）も消しますか？") {
    Run git @('config', '--global', '--unset', 'user.name')
    Run git @('config', '--global', '--unset', 'user.email')
  }
}

# ---- 2. clone したフォルダ ------------------------------------------------
$clones = @($clones | Where-Object { Test-Path $_ })
if ($clones) {
  Say 'clone したフォルダ'
  foreach ($c in $clones) {
    Write-Host "  $c"
    # push していないものがあれば先に知らせる
    if (Get-Native git @('-C', $c, 'status', '--porcelain')) { Warn '  コミットしていない変更があります' }
    if (Get-Native git @('-C', $c, 'log', '--branches', '--not', '--remotes', '--oneline')) { Warn '  push していないコミットがあります' }
  }
  if (Ask 'これらを削除しますか？') { foreach ($c in $clones) { Remove-Dir $c } }
} else { Skip 'clone したフォルダの記録は無い' }

# ---- 3. パッケージのキャッシュ ----------------------------------------------
Say 'パッケージのキャッシュを消す'
if (Have pnpm) { $store = Get-Native pnpm @('store', 'path'); if ($store) { Remove-Dir $store } }
foreach ($p in "$env:LOCALAPPDATA\pnpm", "$env:LOCALAPPDATA\pnpm-cache", "$env:LOCALAPPDATA\npm-cache", "$env:LOCALAPPDATA\Yarn") { Remove-Dir $p }

# ---- 4. 入れた Node と PATH -----------------------------------------------
Say 'setup で入れた Node と PATH を戻す'
if ($paths) {
  $user = [Environment]::GetEnvironmentVariable('Path', 'User') -split ';' | Where-Object { $_ -and ($paths -notcontains $_) }
  if ($DryRun) { Skip "(dry-run) ユーザー PATH から外す: $($paths -join ', ')" }
  else { [Environment]::SetEnvironmentVariable('Path', ($user -join ';'), 'User') }
  # npm -g の置き場（%APPDATA%\npm）は setup が PATH に足したときだけ消す
  foreach ($p in $paths) { if ($p -like "$env:APPDATA\npm*") { Remove-Dir $p } }
}

# ---- 5. winget で入れたツール ----------------------------------------------
if ($installed) {
  Say "setup で入れたツール: $($installed -join ', ')"
  if (Ask 'アンインストールしますか？') {
    foreach ($id in $installed) { Run winget @('uninstall', '--id', $id, '-e', '--silent') }
    Remove-Dir "$env:APPDATA\GitHub CLI"
  }
}

# ---- 6. 記録（と Node 本体）を消す ------------------------------------------
Remove-Dir $StateDir
Write-Host ''
Say '後片付けが終わりました。ブラウザのログイン（GitHub など）は各自でログアウトしてください。'
