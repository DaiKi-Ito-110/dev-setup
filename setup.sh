#!/bin/bash
# dev-setup / setup.sh — まっさらな Mac に、GitHub のプロジェクトを動かす環境を 1 回で用意する（setup.ps1 の Mac 版）。
#   Homebrew で git / git-lfs / gh / jq を入れ、GitHub にブラウザでログインし、プロジェクトを clone して、
#   setup.json（無ければ package.json）に書かれた Node / パッケージマネージャを入れて依存を入れる。
#   何度流しても安全（入っているもの・済んでいるものは飛ばす）。返却時は cleanup.sh。
#
#   bash -c "$(curl -fsSL https://raw.githubusercontent.com/DaiKi-Ito-110/dev-setup/main/setup.sh)" _ owner/repo
#   ./setup.sh owner/repo [--dir ~/work] [--dry-run]
# macOS 標準の bash 3.2 で動くように書く（連想配列・mapfile は使わない）
set -Eeuo pipefail

REPO="${DEV_SETUP_REPO:-}"
DIR="${DEV_SETUP_DIR:-$HOME/dev}"
DRY_RUN=0
while [ $# -gt 0 ]; do
  case "$1" in
    --dir) DIR="$2"; shift 2 ;;
    --dry-run) DRY_RUN=1; shift ;;
    *) REPO="$1"; shift ;;
  esac
done

STATE_DIR="$HOME/.dev-setup"   # 入れたもの・clone したものの記録（cleanup が読む）。Node もここに置く
PROFILE="$HOME/.zprofile"
MARK="# dev-setup"             # cleanup が消す行の印

say() { printf '\033[36m==> %s\033[0m\n' "$*"; }
skip() { printf '\033[90m    %s\033[0m\n' "$*"; }
warn() { printf '\033[33m!!  %s\033[0m\n' "$*"; }
have() { command -v "$1" >/dev/null 2>&1; }
run() {
  if [ "$DRY_RUN" = 1 ]; then skip "(dry-run) $*"; return; fi
  "$@"
}
ask() { local a; read -r -p "$1 [y/N] " a </dev/tty; [[ "$a" =~ ^[yY] ]]; }
prompt() { local a; read -r -p "$1 [$2] " a </dev/tty; echo "${a:-$2}"; }
trap 'printf "\n\033[31m失敗しました。\033[0m もう一度実行すると、済んだところは飛ばして続きからやり直します。\n"' ERR

# 記録はテキストファイル 1 行 1 件（installed.txt = brew で入れたもの、clones.txt = clone したフォルダ）
record() {
  [ "$DRY_RUN" = 1 ] && return
  mkdir -p "$STATE_DIR"
  touch "$STATE_DIR/$1"
  grep -qxF "$2" "$STATE_DIR/$1" || echo "$2" >>"$STATE_DIR/$1"
}
# ~/.zprofile に 1 行足す（新しいターミナルでも PATH が通るように）
profile_add() {
  [ "$DRY_RUN" = 1 ] && { skip "(dry-run) $PROFILE に追記: $1"; return; }
  grep -qxF "$1 $MARK" "$PROFILE" 2>/dev/null || echo "$1 $MARK" >>"$PROFILE"
}

# owner/repo・https の URL・git@ の URL のどれでも owner/repo にそろえる
to_slug() {
  local r="${1%/}"; r="${r%.git}"
  if [[ "$r" =~ github\.com[:/]+([^/]+)/([^/]+)$ ]]; then echo "${BASH_REMATCH[1]}/${BASH_REMATCH[2]}"
  elif [[ "$r" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]]; then echo "$r"
  else echo "リポジトリの指定が読めません: $1（owner/repo の形で）" >&2; return 1; fi
}

clone_repo() { # slug path
  if [ -d "$2/.git" ]; then
    say "$2 は clone 済み → 最新にする"
    [ "$DRY_RUN" = 1 ] || git -C "$2" pull --ff-only || warn "git pull できませんでした（手元に変更がある？）。そのまま続けます"
  else
    say "$1 を $2 に clone"
    run gh repo clone "$1" "$2"
  fi
  record clones.txt "$2"
}

# Node は nodejs.org の公式 tarball を ~/.dev-setup/node に展開する（メジャーを指定でき、sudo が要らず、消すのも簡単）
install_node() {
  local want="$1" cur index ver arch name dest
  cur="$(node -v 2>/dev/null || true)"
  index="$(curl -fsSL https://nodejs.org/dist/index.json)"
  if [ "$want" = lts ]; then want="$(echo "$index" | jq -r '[.[] | select(.lts)][0].version' | sed -E 's/^v([0-9]+).*/\1/')"; fi
  if [[ "$cur" == "v$want."* ]]; then skip "Node $cur が入っている"; return; fi
  ver="$(echo "$index" | jq -r --arg m "v$want." '[.[] | select(.version | startswith($m))][0].version // empty')"
  [ -n "$ver" ] || { echo "Node $want が nodejs.org に見つかりません" >&2; return 1; }
  arch="$( [ "$(uname -m)" = arm64 ] && echo arm64 || echo x64 )"
  name="node-$ver-darwin-$arch"
  dest="$STATE_DIR/node/$name"
  say "Node $ver を $dest に入れる${cur:+（今入っているのは $cur）}"
  if [ "$DRY_RUN" = 0 ] && [ ! -d "$dest" ]; then
    mkdir -p "$STATE_DIR/node"
    curl -fsSL "https://nodejs.org/dist/$ver/$name.tar.gz" | tar -xz -C "$STATE_DIR/node"
  fi
  export PATH="$dest/bin:$PATH"
  profile_add "export PATH=\"$dest/bin:\$PATH\""
}

install_pm() { # pm version
  local cur
  [ "$1" = npm ] && return
  case "$1" in pnpm|yarn) ;; *) warn "$1 は自動で入れられません。手で入れてください"; return ;; esac
  cur="$("$1" --version 2>/dev/null || true)"
  if [ -n "$cur" ] && { [ -z "$2" ] || [ "$cur" = "$2" ]; }; then skip "$1 $cur が入っている"; return; fi
  say "$1${2:+@$2} を入れる"
  run npm install -g "$1${2:+@$2}"   # tarball の Node は npm -g が Node のフォルダに入るので sudo は要らない
}

# ---- 1. 基本ツール -----------------------------------------------------------
if ! have brew; then
  for b in /opt/homebrew/bin/brew /usr/local/bin/brew; do [ -x "$b" ] && eval "$("$b" shellenv)" && break; done
fi
if ! have brew; then
  say 'Homebrew を入れる（Mac のパスワードを聞かれます）'
  run /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  for b in /opt/homebrew/bin/brew /usr/local/bin/brew; do [ -x "$b" ] && eval "$("$b" shellenv)" && break; done
  record installed.txt homebrew
fi
if have brew; then profile_add "eval \"\$($(command -v brew) shellenv)\""; fi
for f in git git-lfs gh jq; do
  if brew list --formula "$f" >/dev/null 2>&1; then skip "$f は入っている"
  else say "$f を入れる"; run brew install "$f"; record installed.txt "$f"; fi
done
[ "$DRY_RUN" = 1 ] || git lfs install >/dev/null

# ---- 2. GitHub にログイン（ブラウザ。SSH 鍵は置かない） -------------------------
if gh auth status --hostname github.com >/dev/null 2>&1; then skip 'GitHub にはログイン済み'
else
  say 'GitHub にログイン（表示されるコードをブラウザに入れてください）'
  run gh auth login --web --hostname github.com --git-protocol https
fi
run gh auth setup-git
if [ -z "$(git config --global user.name || true)" ]; then
  user_json="$( [ "$DRY_RUN" = 1 ] && echo '{}' || gh api user)"
  def_name="$(echo "$user_json" | jq -r '.name // .login // ""')"
  def_mail="$(echo "$user_json" | jq -r 'if .login then "\(.id)+\(.login)@users.noreply.github.com" else "" end')"
  run git config --global user.name "$(prompt 'git のコミットに使う名前' "$def_name")"
  run git config --global user.email "$(prompt 'git のコミットに使うメール' "$def_mail")"
  [ "$DRY_RUN" = 1 ] || { mkdir -p "$STATE_DIR"; touch "$STATE_DIR/git-identity"; }  # cleanup で消してよい印
fi

# ---- 3. プロジェクトを clone ---------------------------------------------------
[ -n "$REPO" ] || read -r -p 'セットアップするリポジトリ（例: DaiKi-Ito-110/tsuchino_himitsu） ' REPO </dev/tty
SLUG="$(to_slug "$REPO")"
P="$DIR/${SLUG#*/}"
[ "$DRY_RUN" = 1 ] || mkdir -p "$DIR"
clone_repo "$SLUG" "$P"

CFG='{}'; PKG='null'
[ -f "$P/setup.json" ] && CFG="$(cat "$P/setup.json")" || skip 'setup.json は無いので package.json から判断する'
[ -f "$P/package.json" ] && PKG="$(cat "$P/package.json")"
cfg() { echo "$CFG" | jq -r "$1 // empty"; }

# ---- 4. Node とパッケージマネージャ --------------------------------------------
NODE_WANT="$(cfg .node)"
for f in .nvmrc .node-version; do
  [ -z "$NODE_WANT" ] && [ -f "$P/$f" ] && NODE_WANT="$(head -n1 "$P/$f" | sed -E 's/^v?([0-9]+).*/\1/')"
done
[ -z "$NODE_WANT" ] && NODE_WANT="$(echo "$PKG" | jq -r '.engines.node // empty' | grep -oE '[0-9]+' | head -n1 || true)"
[ -z "$NODE_WANT" ] && [ "$PKG" != null ] && NODE_WANT=lts
[ -n "$NODE_WANT" ] && install_node "$NODE_WANT"

PM=npm; PM_VER=''
if [ "$PKG" != null ]; then
  spec="$(echo "$PKG" | jq -r '.packageManager // empty')"
  if [ -n "$spec" ]; then PM="${spec%%@*}"; PM_VER="${spec#*@}"; PM_VER="${PM_VER%%+*}"
  elif [ -f "$P/pnpm-lock.yaml" ]; then PM=pnpm
  elif [ -f "$P/yarn.lock" ]; then PM=yarn; fi
  install_pm "$PM" "$PM_VER"
fi

# ---- 5. 追加のリポジトリ（setup.json の repos） ----------------------------------
n="$(echo "$CFG" | jq '.repos // [] | length')"
i=0
while [ "$i" -lt "$n" ]; do
  r="$(echo "$CFG" | jq -c ".repos[$i]")"; i=$((i + 1))
  rrepo="$(echo "$r" | jq -r .repo)"
  rp="$P/$(echo "$r" | jq -r .dir)"   # dir はプロジェクトからの相対
  if [ -d "$(dirname "$rp")" ]; then rp="$(cd "$(dirname "$rp")" && pwd)/$(basename "$rp")"; fi
  if [ "$(echo "$r" | jq -r '.optional // false')" = true ] && [ ! -d "$rp/.git" ]; then
    ask "$rrepo も clone しますか？（$(echo "$r" | jq -r '.why // ""')）" </dev/tty || continue
  fi
  clone_repo "$(to_slug "$rrepo")" "$rp"
  [ "$(echo "$r" | jq -r '.lfs // false')" = true ] && run git -C "$rp" lfs pull
done

# ---- 6. 依存を入れる -----------------------------------------------------------
CMDS=()
if [ -n "$(cfg .install)" ]; then CMDS+=("$(cfg .install)")
elif [ "$PKG" != null ] && [ "$PM" = npm ] && [ -f "$P/package-lock.json" ]; then CMDS+=("npm ci")
elif [ "$PKG" != null ]; then CMDS+=("$PM install"); fi
while IFS= read -r c; do [ -n "$c" ] && CMDS+=("$c"); done < <(echo "$CFG" | jq -r '.postInstall // [] | .[]')
for c in ${CMDS[@]+"${CMDS[@]}"}; do
  say "$c（$P）"
  run bash -c "cd \"$P\" && $c"
done

# ---- 7. 次にやること -----------------------------------------------------------
echo
say "できあがり: $P"
notes="$(echo "$CFG" | jq -r '.notes // [] | .[]')"
if [ -n "$notes" ]; then echo "$notes" | sed 's/^/  - /'
elif [ -f "$P/start.command" ]; then echo '  - start.command をダブルクリックで起動'; fi
echo '  - 返却するときは cleanup.sh（ログイン情報・clone したフォルダ・入れたツールを消す）'
echo '  - 新しいターミナルを開くと node / pnpm にパスが通ります'
[ "$DRY_RUN" = 1 ] || open "$P"
