#!/usr/bin/env bash
#
# git-multi-config installer
#
# 用法 / usage:
#   ./install.sh                                  # 从本地仓库安装 / install from this clone
#   curl -fsSL <raw-url>/install.sh | bash        # 远程安装 / install from the network
#   PREFIX=/usr/local/bin ./install.sh            # 指定安装目录 / custom prefix
#   GMC_SHA256=<sha256> ./install.sh              # 校验下载内容后再安装 / verify before install
#
# 完整性 / integrity: 远程安装默认只打印下载内容的 sha256。设置 GMC_SHA256 会在安装前
# 强制校验，不匹配即拒绝。首次运行后把打印出的摘要记下来，之后就能固定校验。
set -euo pipefail

REPO_RAW="${GMC_REPO_RAW:-https://raw.githubusercontent.com/sabereey/git-multi-config/main}"
PREFIX="${PREFIX:-$HOME/.local/bin}"
BIN="$PREFIX/git-multi-config"

sha256_of() {
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" 2>/dev/null | awk '{print $1}'
  elif command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" 2>/dev/null | awk '{print $1}'
  fi
}

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
  # 下载内容的基本合理性检查：正常内容一定以 bash 的 shebang 开头，
  # 这样能拦住「200 但返回 HTML」之类的异常（见 SEC-2）
  if ! head -n 1 "$tmp" 2>/dev/null | grep -q '^#!/.*bash'; then
    err "downloaded file does not look like a shell script: $REPO_RAW"
    rm -f "$tmp"
    exit 1
  fi
  # 完整性校验：GMC_SHA256 未设置时只打印摘要，设置后强制比对
  actual="$(sha256_of "$tmp" || true)"
  if [ -n "${GMC_SHA256:-}" ]; then
    if [ -z "$actual" ]; then
      err "shasum or sha256sum is required to verify GMC_SHA256"
      rm -f "$tmp"
      exit 1
    fi
    if [ "$actual" != "$GMC_SHA256" ]; then
      err "checksum mismatch, refusing to install"
      err "  expected: $GMC_SHA256"
      err "  actual  : $actual"
      rm -f "$tmp"
      exit 1
    fi
    ok "checksum verified"
  elif [ -n "$actual" ]; then
    warn "downloaded content is NOT verified; its sha256 is"
    printf '       %s\n' "$actual"
    printf '       pin it next time: GMC_SHA256=%s ./install.sh\n' "$actual"
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
