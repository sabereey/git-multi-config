#!/usr/bin/env bash
#
# git-multi-config installer
#
# 用法 / usage:
#   ./install.sh                                  # 从本地仓库安装 / install from this clone
#   curl -fsSL <raw-url>/install.sh | bash        # 远程安装 / install from the network
#   PREFIX=/usr/local/bin ./install.sh            # 指定安装目录 / custom prefix
#
set -euo pipefail

REPO_RAW="${GMC_REPO_RAW:-https://raw.githubusercontent.com/sabereey/git-multi-config/main}"
PREFIX="${PREFIX:-$HOME/.local/bin}"
BIN="$PREFIX/git-multi-config"

GREEN='\033[1;32m'; YELLOW='\033[1;33m'; RED='\033[1;31m'; NC='\033[0m'
if [ ! -t 1 ] || [ -n "${NO_COLOR:-}" ]; then GREEN=''; YELLOW=''; RED=''; NC=''; fi

ok()   { printf "${GREEN}[ ok ]${NC} %s\n" "$*"; }
warn() { printf "${YELLOW}[warn]${NC} %s\n" "$*"; }
err()  { printf "${RED}[fail]${NC} %s\n" "$*" >&2; }

SRC=""
case "${BASH_SOURCE[0]:-$0}" in
  */*) HERE="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)" ;;
  *)   HERE="" ;;
esac
if [ -n "$HERE" ] && [ -f "$HERE/git-multi-config.sh" ]; then
  SRC="$HERE/git-multi-config.sh"
fi

mkdir -p "$PREFIX"

if [ -n "$SRC" ]; then
  install -m 755 "$SRC" "$BIN"
else
  # 远程安装：优先 curl，其次 wget
  tmp="$(mktemp)"
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL "$REPO_RAW/git-multi-config.sh" -o "$tmp" || { err "download failed: $REPO_RAW"; rm -f "$tmp"; exit 1; }
  elif command -v wget >/dev/null 2>&1; then
    wget -qO "$tmp" "$REPO_RAW/git-multi-config.sh" || { err "download failed: $REPO_RAW"; rm -f "$tmp"; exit 1; }
  else
    err "curl or wget is required for remote install"
    exit 1
  fi
  install -m 755 "$tmp" "$BIN"
  rm -f "$tmp"
fi

ok "installed: $BIN"
"$BIN" --version >/dev/null 2>&1 && ok "runs: $("$BIN" --version)"

case ":$PATH:" in
  *":$PREFIX:"*) ;;
  *) warn "$PREFIX is not in your PATH. Add it:  export PATH=\"$PREFIX:\$PATH\"" ;;
esac

printf '\nNext / 下一步:\n  git-multi-config init\n'
