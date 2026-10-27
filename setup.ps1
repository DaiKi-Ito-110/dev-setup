# dev-setup / setup.ps1 — まっさらな Windows に、GitHub のプロジェクトを動かす環境を 1 回で用意する。
#   Git(+LFS) と GitHub CLI を winget で入れ、GitHub にブラウザでログインし、プロジェクトを clone して、
#   setup.json（無ければ package.json）に書かれた Node / パッケージマネージャを入れて依存を入れる。
#   何度流しても安全（入っているもの・済んでいるものは飛ばす）。返却時は cleanup.ps1。
#
#   setup.bat owner/repo            … ダブルクリック or コマンドで
#   setup.ps1 -Repo owner/repo -Dir D:\work -DryRun   … -DryRun は実行せずに何をするかだけ出す
param(
  [string]$Repo = $env:DEV_SETUP_REPO,
  [string]$Dir = $(if ($env:DEV_SETUP_DIR) { $env:DEV_SETUP_DIR } else { Join-Path $HOME 'dev' }),
  [switch]$DryRun
)
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'   # Invoke-WebRequest の進捗表示は遅いので出さない
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor 3072  # TLS 1.2

$StateDir = Join-Path $HOME '.dev-setup'   # 入れたもの・clone したものの記録（cleanup が読む）。Node もここに置く

function Say($m) { Write-Host "==> $m" -ForegroundColor Cyan }
function Skip($m) { Write-Host "    $m" -ForegroundColor DarkGray }
function Warn($m) { Write-Host "!!  $m" -ForegroundColor Yellow }
function Have($cmd) { [bool](Get-Command $cmd -ErrorAction SilentlyContinue) }

# 外部コマンドを実行し、失敗したら止める。-DryRun では表示だけ
function Run([string]$Exe, [string[]]$ArgList) {
  if ($DryRun) { Skip "(dry-run) $Exe $($ArgList -join ' ')"; return }
  & $Exe @ArgList
  if ($LASTEXITCODE -ne 0) { throw "失敗しました: $Exe $($ArgList -join ' ')" }
}
# 外部コマンドの成否だけを見る（stderr をつぶしても止まらないよう ErrorAction を緩める）
function Test-Native([string]$Exe, [string[]]$ArgList) {
  $ErrorActionPreference = 'Continue'
  & $Exe @ArgList *> $null
  $LASTEXITCODE -eq 0
}
function Get-Native([string]$Exe, [string[]]$ArgList) {
  $ErrorActionPreference = 'Continue'
  $out = & $Exe @ArgList 2> $null
  if ($LASTEXITCODE -eq 0) { ($out | Out-String).Trim() } else { '' }
}

# 記録はテキストファイル 1 行 1 件（installed.txt = winget ID、clones.txt = clone したフォルダ、paths.txt = ユーザー PATH に足したもの）
function Add-Record([string]$File, [string]$Line) {
  if ($DryRun) { return }
  New-Item -ItemType Directory -Force $StateDir | Out-Null
  $p = Join-Path $StateDir $File
  if (-not ((Test-Path $p) -and ((Get-Content $p) -contains $Line))) { Add-Content $p $Line -Encoding UTF8 }
}

# winget で入れた直後も同じウィンドウで使えるよう、PATH をレジストリから読み直す（このセッションで足した分は残す）
$script:SessionPath = @()
function Update-Path {
  $env:Path = (@($script:SessionPath) + [Environment]::GetEnvironmentVariable('Path', 'Machine') + [Environment]::GetEnvironmentVariable('Path', 'User')) -join ';'
}
function Add-Path([string]$p) {
  $script:SessionPath = @($p) + $script:SessionPath
  $env:Path = "$p;$env:Path"
  if ($DryRun) { return }
  $user = [Environment]::GetEnvironmentVariable('Path', 'User')
  if ((($user -split ';') -notcontains $p)) {
    [Environment]::SetEnvironmentVariable('Path', (@($p) + ($user -split ';' | Where-Object { $_ })) -join ';', 'User')
    Add-Record 'paths.txt' $p
  }
}

function Install-Winget([string]$Id, [string]$Cmd) {
  if (Have $Cmd) { Skip "$Cmd は入っている"; return }
  if (-not (Have winget)) { throw 'winget がありません。Microsoft Store で「アプリ インストーラー」を入れてから、もう一度実行してください。' }
  Say "$Id を入れる"
  Run winget @('install', '--id', $Id, '-e', '--source', 'winget', '--silent', '--accept-package-agreements', '--accept-source-agreements')
  Add-Record 'installed.txt' $Id
  Update-Path
  if (-not $DryRun -and -not (Have $Cmd)) { throw "$Cmd が見つかりません。このウィンドウを閉じて開き直し、もう一度実行してください。" }
}

# owner/repo・https の URL・git@ の URL のどれでも owner/repo にそろえる
function ConvertTo-Slug([string]$r) {
  $r = $r.Trim()
  if ($r -match 'github\.com[:/]+([^/]+)/([^/]+?)(\.git)?/?$') { return "$($Matches[1])/$($Matches[2])" }
  if ($r -match '^[\w.-]+/[\w.-]+$') { return $r }
  throw "リポジトリの指定が読めません: $r（owner/repo の形で）"
}

function Copy-Repo([string]$Slug, [string]$Path) {
  if (Test-Path (Join-Path $Path '.git')) {
    Say "$Path は clone 済み → 最新にする"
    if (-not $DryRun -and -not (Test-Native git @('-C', $Path, 'pull', '--ff-only'))) { Warn "git pull できませんでした（手元に変更がある？）。そのまま続けます" }
  } else {
    Say "$Slug を $Path に clone"
    Run gh @('repo', 'clone', $Slug, $Path)
  }
  Add-Record 'clones.txt' $Path
}

# Node は nodejs.org の公式 zip を ~/.dev-setup/node に展開する（メジャーを指定でき、管理者権限が要らず、消すのも簡単）
function Install-Node([string]$Want) {
  $cur = Get-Native node @('-v')
  $index = $null
  if ($Want -eq 'lts') {
    $index = Invoke-RestMethod 'https://nodejs.org/dist/index.json'
    $Want = (($index | Where-Object { $_.lts } | Select-Object -First 1).version -replace '^v(\d+).*', '$1')
  }
  if ($cur -match "^v$Want\.") { Skip "Node $cur が入っている"; return }
  if (-not $index) { $index = Invoke-RestMethod 'https://nodejs.org/dist/index.json' }
  $ver = ($index | Where-Object { $_.version -like "v$Want.*" } | Select-Object -First 1).version
  if (-not $ver) { throw "Node $Want が nodejs.org に見つかりません" }
  $arch = if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64') { 'arm64' } else { 'x64' }
  $name = "node-$ver-win-$arch"
  $root = Join-Path $StateDir 'node'
  $dest = Join-Path $root $name
  Say "Node $ver を $dest に入れる$(if ($cur) { "（今入っているのは $cur）" })"
  if (-not $DryRun -and -not (Test-Path $dest)) {
    New-Item -ItemType Directory -Force $root | Out-Null
    $zip = Join-Path $env:TEMP "$name.zip"
    Invoke-WebRequest "https://nodejs.org/dist/$ver/$name.zip" -OutFile $zip -UseBasicParsing
    if (Have tar) { tar -xf $zip -C $root } else { Expand-Archive $zip $root -Force }
    Remove-Item $zip
  }
  Add-Path $dest
  if (-not $DryRun) {
    # npm -g の置き場（zip 版は %APPDATA%\npm）も PATH に。pnpm などはここに入る
    $prefix = Get-Native npm @('prefix', '-g')
    if ($prefix -and $prefix -ne $dest) { New-Item -ItemType Directory -Force $prefix | Out-Null; Add-Path $prefix }
    $src = (Get-Command node).Source
    if (-not $src.StartsWith($dest)) { Warn "別の Node（$src）が先に見つかります。アンインストールするか PATH の順番を直してください" }
  }
}

function Install-PackageManager([string]$Pm, [string]$Ver) {
  if ($Pm -eq 'npm') { return }
  if ($Pm -notin @('pnpm', 'yarn')) { Warn "$Pm は自動で入れられません。手で入れてください"; return }
  $cur = Get-Native $Pm @('--version')
  if ($cur -and (-not $Ver -or $cur -eq $Ver)) { Skip "$Pm $cur が入っている"; return }
  $spec = if ($Ver) { "$Pm@$Ver" } else { $Pm }
  Say "$spec を入れる"
  Run npm @('install', '-g', $spec)
}

try {
  # ---- 1. 基本ツール ---------------------------------------------------------
  Install-Winget 'Git.Git' 'git'
  if (-not (Test-Native git @('lfs', 'version'))) { Install-Winget 'GitHub.GitLFS' 'git-lfs' }
  Install-Winget 'GitHub.cli' 'gh'
  if (-not $DryRun) { Test-Native git @('lfs', 'install') | Out-Null }

  # ---- 2. GitHub にログイン（ブラウザ。SSH 鍵は置かない） ---------------------
  if (Have gh) {
    if (Test-Native gh @('auth', 'status', '--hostname', 'github.com')) { Skip 'GitHub にはログイン済み' }
    else {
      Say 'GitHub にログイン（表示されるコードをブラウザに入れてください）'
      Run gh @('auth', 'login', '--web', '--hostname', 'github.com', '--git-protocol', 'https')
    }
    Run gh @('auth', 'setup-git')
  }
  if (-not (Get-Native git @('config', '--global', 'user.name'))) {
    $u = if ($DryRun) { $null } else { Get-Native gh @('api', 'user') | ConvertFrom-Json }
    $defName = if ($u.name) { $u.name } else { $u.login }
    $defMail = if ($u) { "$($u.id)+$($u.login)@users.noreply.github.com" } else { '' }
    $n = Read-Host "git のコミットに使う名前 [$defName]"; if (-not $n) { $n = $defName }
    $m = Read-Host "git のコミットに使うメール [$defMail]"; if (-not $m) { $m = $defMail }
    Run git @('config', '--global', 'user.name', $n)
    Run git @('config', '--global', 'user.email', $m)
    if (-not $DryRun) { New-Item -ItemType File -Force (Join-Path $StateDir 'git-identity') | Out-Null }  # cleanup で消してよい印
  }

  # ---- 3. プロジェクトを clone ----------------------------------------------
  if (-not $Repo) { $Repo = Read-Host 'セットアップするリポジトリ（例: DaiKi-Ito-110/tsuchino_himitsu）' }
  $slug = ConvertTo-Slug $Repo
  $path = Join-Path $Dir ($slug -split '/')[1]
  if (-not $DryRun) { New-Item -ItemType Directory -Force $Dir | Out-Null }
  Copy-Repo $slug $path

  $cfgPath = Join-Path $path 'setup.json'
  $pkgPath = Join-Path $path 'package.json'
  $cfg = if (Test-Path $cfgPath) { Get-Content $cfgPath -Raw -Encoding UTF8 | ConvertFrom-Json } else { [pscustomobject]@{} }
  $pkg = if (Test-Path $pkgPath) { Get-Content $pkgPath -Raw -Encoding UTF8 | ConvertFrom-Json } else { $null }
  if (-not (Test-Path $cfgPath)) { Skip 'setup.json は無いので package.json から判断する' }

  # ---- 4. Node とパッケージマネージャ ---------------------------------------
  $nodeWant = $cfg.node
  if (-not $nodeWant) {
    foreach ($f in '.nvmrc', '.node-version') {
      $p = Join-Path $path $f
      if (Test-Path $p) { $nodeWant = ((Get-Content $p -TotalCount 1) -replace '^v?(\d+).*', '$1'); break }
    }
  }
  if (-not $nodeWant -and $pkg.engines.node -match '(\d+)') { $nodeWant = $Matches[1] }
  if (-not $nodeWant -and $pkg) { $nodeWant = 'lts' }
  if ($nodeWant) { Install-Node "$nodeWant" }

  if ($pkg) {
    $pm = 'npm'; $pmVer = ''
    if ($pkg.packageManager) { $pm, $pmVer = $pkg.packageManager -split '@', 2; $pmVer = $pmVer -replace '\+.*', '' }
    elseif (Test-Path (Join-Path $path 'pnpm-lock.yaml')) { $pm = 'pnpm' }
    elseif (Test-Path (Join-Path $path 'yarn.lock')) { $pm = 'yarn' }
    Install-PackageManager $pm $pmVer
  }

  # ---- 5. 追加のリポジトリ（setup.json の repos） ---------------------------
  foreach ($r in @($cfg.repos | Where-Object { $_ })) {
    $rp = [IO.Path]::GetFullPath((Join-Path $path $r.dir))
    if ($r.optional -and -not (Test-Path (Join-Path $rp '.git'))) {
      $a = Read-Host "$($r.repo) も clone しますか？（$($r.why)） [y/N]"
      if ($a -notmatch '^[yY]') { continue }
    }
    Copy-Repo (ConvertTo-Slug $r.repo) $rp
    if ($r.lfs) { Run git @('-C', $rp, 'lfs', 'pull') }
  }

  # ---- 6. 依存を入れる ------------------------------------------------------
  $cmds = @()
  if ($cfg.install) { $cmds += $cfg.install }
  elseif ($pkg -and $pm -eq 'npm' -and (Test-Path (Join-Path $path 'package-lock.json'))) { $cmds += 'npm ci' }
  elseif ($pkg) { $cmds += "$pm install" }
  $cmds += @($cfg.postInstall | Where-Object { $_ })
  foreach ($c in $cmds) {
    Say "$c（$path）"
    Push-Location $path
    try { Run cmd.exe @('/c', $c) } finally { Pop-Location }
  }

  # ---- 7. 次にやること ------------------------------------------------------
  Write-Host ''
  Say "できあがり: $path"
  foreach ($n in @($cfg.notes | Where-Object { $_ })) { Write-Host "  - $n" }
  if (-not $cfg.notes -and (Test-Path (Join-Path $path 'start.bat'))) { Write-Host '  - start.bat をダブルクリックで起動' }
  Write-Host "  - 返却するときは cleanup.bat（ログイン情報・clone したフォルダ・入れたツールを消す）"
  if (-not $DryRun) { Invoke-Item $path }
} catch {
  Write-Host ''
  Write-Host "失敗しました: $($_.Exception.Message)" -ForegroundColor Red
  Write-Host 'もう一度実行すると、済んだところは飛ばして続きからやり直します。'
  exit 1
}
