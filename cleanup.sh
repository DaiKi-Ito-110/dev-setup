#!/bin/bash
# dev-setup / cleanup.sh — レンタルの Mac を返す前の後片付け（setup.sh がしたことを戻す。cleanup.ps1 の Mac 版）。
#   GitHub のログインと git の資格情報を消し、clone したフォルダ・パッケージのキャッシュ・入れた Node を消す。
#   brew で入れたツールは聞いてから消す。消す前に必ず一覧を出して確認する。
#
#   bash -c "$(curl -fsSL https://raw.githubusercontent.com/DaiKi-Ito-110/dev-setup/main/cleanup.sh)"
#   ./cleanup.sh [--dry-run]
set -uo pipefail

DRY_RUN=0
[ "${1:-}" = --dry-run ] && DRY_RUN=1
STATE_DIR="$HOME/.dev-setup"
PROFILE="$HOME/.zprofile"
MARK="# dev-setup"

say() { printf '\033[36m==> %s\033[0m\n' "$*"; }
skip() { printf '\033[90m    %s\033[0m\n' "$*"; }
warn() { printf '\033[33m!!  %s\033[0m\n' "$*"; }
have() { command -v "$1" >/dev/null 2>&1; }
run() {
  if [ "$DRY_RUN" = 1 ]; then skip "(dry-run) $*"; return; fi
  "$@" || warn "うまくいきませんでした: $*"
}
ask() { [ "$DRY_RUN" = 1 ] && return 0; local a; read -r -p "$1 [y/N] " a </dev/tty; [[ "$a" =~ ^[yY] ]]; }
records() { [ -f "$STATE_DIR/$1" ] && grep -v '^$' "$STATE_DIR/$1" || true; }
for b in /opt/homebrew/bin/brew /usr/local/bin/brew; do [ -x "$b" ] && eval "$("$b" shellenv)" && break; done

if [ ! -d "$STATE_DIR" ]; then
  warn 'この Mac には setup の記録（~/.dev-setup）がありません。自分の Mac で流すと、普段使っているログイン情報やキャッシュも消えます。'
  ask '続けますか？' || exit 0
fi

# ---- 1. GitHub のログインと git の資格情報 ---------------------------------------
say 'GitHub のログインと git の資格情報を消す'
if have gh && gh auth token --hostname github.com >/dev/null 2>&1; then run gh auth logout --hostname github.com
else skip 'gh はログインしていない'; fi
for h in https://github.com https://gist.github.com; do
  git config --global --get-all "credential.$h.helper" >/dev/null 2>&1 && run git config --global --unset-all "credential.$h.helper"
done
[ "$DRY_RUN" = 1 ] || printf 'protocol=https\nhost=github.com\n\n' | git credential-osxkeychain erase 2>/dev/null
if [ -f "$STATE_DIR/git-identity" ]; then
  run git config --global --unset user.name; run git config --global --unset user.email
elif name="$(git config --global user.name 2>/dev/null)" && [ -n "$name" ]; then
  if ask "git の名前・メール（$name）も消しますか？"; then
    run git config --global --unset user.name; run git config --global --unset user.email
  fi
fi

# ---- 2. clone したフォルダ ------------------------------------------------------
clones="$(records clones.txt | while IFS= read -r c; do [ -d "$c" ] && echo "$c"; done)"
if [ -n "$clones" ]; then
  say 'clone したフォルダ'
  while IFS= read -r c; do
    echo "  $c"
    [ -n "$(git -C "$c" status --porcelain 2>/dev/null)" ] && warn '  コミットしていない変更があります'
    [ -n "$(git -C "$c" log --branches --not --remotes --oneline 2>/dev/null)" ] && warn '  push していないコミットがあります'
  done <<<"$clones"
  if ask 'これらを削除しますか？'; then
    while IFS= read -r c; do run rm -rf "$c"; done <<<"$clones"
  fi
else skip 'clone したフォルダの記録は無い'; fi

# ---- 3. パッケージのキャッシュ ----------------------------------------------------
say 'パッケージのキャッシュを消す'
if have pnpm; then store="$(pnpm store path 2>/dev/null)"; [ -n "$store" ] && run rm -rf "$store"; fi
for p in "$HOME/Library/pnpm" "$HOME/Library/Caches/pnpm" "$HOME/.npm" "$HOME/Library/Caches/Yarn"; do
  [ -e "$p" ] && run rm -rf "$p"
done

# ---- 4. ~/.zprofile に足した行 ----------------------------------------------------
if grep -qF "$MARK" "$PROFILE" 2>/dev/null; then
  say "$PROFILE から setup が足した行を消す"
  if [ "$DRY_RUN" = 1 ]; then grep -F "$MARK" "$PROFILE" | sed 's/^/    (dry-run) /'
  else grep -vF "$MARK" "$PROFILE" >"$PROFILE.tmp"; mv "$PROFILE.tmp" "$PROFILE"; fi
fi

# ---- 5. brew で入れたツール ---------------------------------------------------------
installed="$(records installed.txt | grep -vx homebrew || true)"
if [ -n "$installed" ] && have brew; then
  say "setup で入れたツール: $(echo $installed)"
  if ask 'アンインストールしますか？'; then
    run brew uninstall $installed
    run rm -rf "$HOME/.config/gh"
  fi
fi
if records installed.txt | grep -qx homebrew; then
  warn 'Homebrew も setup で入れました。消すなら: /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/uninstall.sh)"'
fi

# ---- 6. 記録（と Node 本体）を消す ---------------------------------------------------
[ -d "$STATE_DIR" ] && run rm -rf "$STATE_DIR"
echo
say '後片付けが終わりました。ブラウザのログイン（GitHub など）は各自でログアウトしてください。'
