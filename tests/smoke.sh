#!/usr/bin/env bash
#
# git-multi-config — smoke tests
#
# 在临时 HOME 中跑完整流程，不触碰真实配置。
# Runs the whole flow inside a throwaway HOME, never touching real config.
#
# 用法 / usage:
#   bash tests/smoke.sh
#   GMC_TEST_BASH=/bin/bash bash tests/smoke.sh   # 用系统 bash 3.2 验证兼容性
#
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$ROOT/git-multi-config.sh"
TOOL_BASH="${GMC_TEST_BASH:-bash}"

PASS=0
FAIL=0
FAILED_LABELS=""

pass() { PASS=$((PASS + 1)); printf '  \033[1;32m✓\033[0m %s\n' "$1"; }
fail() {
  FAIL=$((FAIL + 1))
  FAILED_LABELS="${FAILED_LABELS}${1}"$'\n'
  printf '  \033[1;31m✗\033[0m %s\n' "$1"
}

# ---------------------------------------------------------------------------
# CI 可观测性：把诊断顶到 GitHub Actions run 页面的 Annotations 里，
# 这样即使拿不到 job log 也能一眼看到失败原因。
# ---------------------------------------------------------------------------
esc_lines() { awk 'BEGIN { ORS = "" } { gsub(/%/, "%25"); if (NR > 1) printf "%s", "%0A"; print }'; }

annotate() { # $1=title $2=body
  [ -n "${CI:-}" ] || return 0
  printf '::error title=%s::%s\n' "${1:-smoke}" "$(printf '%s' "${2:-}" | esc_lines)"
}

show_log() { # $1=annotate title $2=log file
  local label="$1" log="$2" body=""
  printf '\033[2m--- %s ---\033[0m\n' "$log"
  if [ -f "$log" ]; then
    sed 's/^/    /' "$log"
    body="$(cat "$log" 2>/dev/null || true)"
  else
    printf '    (log file missing)\n'
  fi
  annotate "$label" "$body"
}

assert_eq() { # $1=actual $2=expected $3=label
  if [ "$1" = "$2" ]; then pass "$3"; else fail "$3 (got '$1', want '$2')"; fi
}

assert_contains() { # $1=file $2=needle $3=label
  if grep -qF -- "$2" "$1" 2>/dev/null; then pass "$3"; else fail "$3 (missing '$2' in $1)"; fi
}

assert_missing() { # $1=file $2=needle $3=label
  if grep -qF -- "$2" "$1" 2>/dev/null; then fail "$3 (unexpected '$2')"; else pass "$3"; fi
}

assert_exists() { # $1=path $2=label
  if [ -e "$1" ]; then pass "$2"; else fail "$2 ($1 not found)"; fi
}

assert_not_exists() { # $1=path $2=label
  if [ ! -e "$1" ]; then pass "$2"; else fail "$2 ($1 still exists)"; fi
}

count() { grep -c -- "$2" "$1" 2>/dev/null || echo 0; }

section() { printf '\n\033[1;34m== %s ==\033[0m\n' "$1"; }

# ---------------------------------------------------------------------------
# 隔离：临时 HOME + 清空所有会让配置落到别处的环境变量
#
# CONFIG_DIR 取自 ${GMC_HOME:-${XDG_CONFIG_HOME:-$HOME/.config}/git-multi-config}，
# 所以只覆盖 HOME 是不够的 —— runner 上一旦预设了 XDG_CONFIG_HOME，
# 配置就会写到临时 HOME 之外，各条断言随之全线崩塌。
# ---------------------------------------------------------------------------
setup_isolation() {
  WORK="$(mktemp -d)"
  HOME="$WORK/home"
  unset XDG_CONFIG_HOME XDG_DATA_HOME XDG_CACHE_HOME XDG_STATE_HOME \
        GMC_HOME GMC_SSH_CONFIG GMC_GITCONFIG GMC_LANG NO_COLOR \
        GIT_DIR GIT_WORK_TREE GIT_CONFIG_GLOBAL GIT_CONFIG_SYSTEM \
        GIT_CONFIG_COUNT GIT_CONFIG_KEY_0 GIT_CONFIG_VALUE_0 2>/dev/null || true
  export HOME
  CFG="$HOME/.config/git-multi-config"
  mkdir -p "$HOME/.ssh"
  touch "$HOME/.ssh/id_ed25519_company" "$HOME/.ssh/id_ed25519"
  chmod 600 "$HOME/.ssh/id_ed25519_company" "$HOME/.ssh/id_ed25519"
}

# ---------------------------------------------------------------------------
section "environment"

printf '  bash  : %s\n' "$("$TOOL_BASH" --version 2>&1 | head -n 1)"
printf '  git   : %s\n' "$(git --version)"
printf '  os    : %s\n' "$(uname -s)"
printf '  TMPDIR=%s  XDG_CONFIG_HOME=%s  CI=%s\n' \
  "${TMPDIR:-<unset>}" "${XDG_CONFIG_HOME:-<unset>}" "${CI:-<unset>}"

# ---------------------------------------------------------------------------
# scenario A: 公司私服 (git.corp.example.com) + 个人 GitHub，安装钩子
# ---------------------------------------------------------------------------
section "scenario A — private server + GitHub, with commit guard"

setup_isolation
mkdir -p "$HOME/work" "$HOME/personal"

cat > "$WORK/answers.conf" <<'EOF'
COMPANY_HOST=git.corp.example.com
COMPANY_KEY=~/.ssh/id_ed25519_company
COMPANY_NAME=Corp User
COMPANY_EMAIL=dev@corp.example.com
COMPANY_GPG=
COMPANY_DIRS=~/work
PERSONAL_HOST=github.com
PERSONAL_KEY=~/.ssh/id_ed25519
PERSONAL_NAME=Personal User
PERSONAL_EMAIL=you@example.com
PERSONAL_GPG=
PERSONAL_DIRS=~/personal
DEFAULT_ID=personal
INSTALL_HOOKS=1
EOF

"$TOOL_BASH" "$SCRIPT" init --from-file "$WORK/answers.conf" --yes --lang en > "$WORK/init.log" 2>&1 \
  && pass "init exits 0" || { fail "init exits 0"; show_log "scenario A init failed" "$WORK/init.log"; }

# 隔离自检：配置必须落在临时 HOME 之内（否则后面的失败全是假象）
assert_exists "$CFG/includeif.conf" "config dir isolated under temp HOME"

assert_contains "$HOME/.ssh/config" "Host git.corp.example.com" "ssh alias written"
assert_contains "$HOME/.ssh/config" "IdentitiesOnly yes" "IdentitiesOnly enforced"
assert_contains "$HOME/.gitconfig" ">>> git-multi-config >>>" "gitconfig include block present"
assert_exists "$HOME/.gitconfig-company" "company profile config created"
assert_exists "$HOME/.gitconfig-personal" "personal profile config created"
assert_contains "$CFG/includeif.conf" "gitdir:$HOME/work/" "dir rule for company dir"
REAL_WORK="$(cd "$HOME/work" && pwd -P)"
assert_contains "$CFG/includeif.conf" "gitdir:$REAL_WORK/" "physical path rule written"

# hasconfig 规则需要 git 2.36+，老版本应自动跳过
GIT_MAJ="$(git --version | sed -n 's/[^0-9]*\([0-9][0-9]*\)\..*/\1/p')"
GIT_MIN="$(git --version | sed -n 's/[^0-9]*[0-9][0-9]*\.\([0-9][0-9]*\).*/\1/p')"
if [ "${GIT_MAJ:-0}" -gt 2 ] || { [ "${GIT_MAJ:-0}" -eq 2 ] && [ "${GIT_MIN:-0}" -ge 36 ]; }; then
  assert_contains "$CFG/includeif.conf" "hasconfig:remote.*.url:git@git.corp.example.com:**" "remote-url rule for company host"
else
  assert_missing "$CFG/includeif.conf" "hasconfig:remote" "remote-url rule skipped on git $GIT_MAJ.$GIT_MIN"
fi
assert_contains "$HOME/.gitconfig-company" "sshCommand = ssh -i \"$HOME/.ssh/id_ed25519_company\"" "per-profile sshCommand"
assert_eq "$(git config --global core.hooksPath 2>/dev/null || echo none)" "$CFG/hooks" "hooksPath installed"

# 身份自动切换
git -C "$HOME/work" init -q repo-a
git -C "$HOME/personal" init -q repo-b
assert_eq "$(git -C "$HOME/work/repo-a" config user.email)" "dev@corp.example.com" "company dir → company email"
assert_eq "$(git -C "$HOME/personal/repo-b" config user.email)" "you@example.com" "personal dir → personal email"

# 提交前拦截钩子
git -C "$HOME/work/repo-a" config --local user.email "wrong@personal.example.com"
echo hi > "$HOME/work/repo-a/f.txt"
git -C "$HOME/work/repo-a" add f.txt
if git -C "$HOME/work/repo-a" commit -q -m "should be blocked" 2>"$WORK/hook.log"; then
  fail "commit guard blocks wrong email"
else
  pass "commit guard blocks wrong email"
fi
assert_contains "$WORK/hook.log" "Refusing to commit" "guard message shown"

# audit 检测 + 修复
if "$TOOL_BASH" "$SCRIPT" audit --lang en > "$WORK/audit1.log" 2>&1; then
  fail "audit reports the planted mismatch"
else
  pass "audit reports the planted mismatch"
fi
"$TOOL_BASH" "$SCRIPT" audit --fix --yes --lang en > "$WORK/audit2.log" 2>&1 \
  && pass "audit --fix exits 0" || { fail "audit --fix exits 0"; show_log "audit --fix failed" "$WORK/audit2.log"; }
assert_eq "$(git -C "$HOME/work/repo-a" config user.email)" "dev@corp.example.com" "audit --fix restores correct identity"
if "$TOOL_BASH" "$SCRIPT" audit --lang en > "$WORK/audit3.log" 2>&1; then
  pass "audit clean after fix"
else
  fail "audit clean after fix"; show_log "audit not clean after fix" "$WORK/audit3.log"
fi

# doctor / list
if "$TOOL_BASH" "$SCRIPT" doctor --lang en > "$WORK/doctor.log" 2>&1; then
  pass "doctor exits 0"
else
  fail "doctor exits 0"; show_log "doctor failed" "$WORK/doctor.log"
fi
assert_contains "$WORK/doctor.log" "state.conf" "doctor reports state"
"$TOOL_BASH" "$SCRIPT" list --lang en > "$WORK/list.log" 2>&1 && pass "list exits 0" || fail "list exits 0"
assert_contains "$WORK/list.log" "dev@corp.example.com" "list shows company identity"

# 幂等：重复 init 不应产生重复块
RULES_BEFORE="$(count "$CFG/includeif.conf" includeIf)"
[ "$RULES_BEFORE" -ge 2 ] || fail "include rules written on first run (got $RULES_BEFORE)"
"$TOOL_BASH" "$SCRIPT" init --from-file "$WORK/answers.conf" --yes --lang en > "$WORK/init2.log" 2>&1 \
  || show_log "second init failed" "$WORK/init2.log"
assert_eq "$(count "$HOME/.ssh/config" '>>> git-multi-config >>>')" "1" "ssh managed block not duplicated"
assert_eq "$(count "$HOME/.gitconfig" '>>> git-multi-config >>>')" "1" "gitconfig managed block not duplicated"
assert_eq "$(count "$CFG/includeif.conf" includeIf)" "$RULES_BEFORE" "include rules not duplicated"

# 卸载
"$TOOL_BASH" "$SCRIPT" uninstall --yes --lang en > "$WORK/uninstall.log" 2>&1 \
  && pass "uninstall exits 0" || { fail "uninstall exits 0"; show_log "uninstall failed" "$WORK/uninstall.log"; }
assert_missing "$HOME/.ssh/config" "git.corp.example.com" "ssh block removed"
assert_missing "$HOME/.gitconfig" ">>> git-multi-config >>>" "gitconfig block removed"
assert_not_exists "$CFG/includeif.conf" "includeif.conf removed"
assert_eq "$(git config --global --get core.hooksPath 2>/dev/null || echo none)" "none" "hooksPath restored"
rm -rf "$WORK"

# ---------------------------------------------------------------------------
# scenario B: 公司也用 github.com → 需要独立别名 + remote 改写
# ---------------------------------------------------------------------------
section "scenario B — both accounts on github.com"

setup_isolation
mkdir -p "$HOME/work" "$HOME/personal"

cat > "$WORK/answers.conf" <<'EOF'
COMPANY_HOST=github.com
COMPANY_KEY=~/.ssh/id_ed25519_company
COMPANY_NAME=Corp User
COMPANY_EMAIL=dev@corp.example.com
COMPANY_DIRS=~/work
PERSONAL_HOST=github.com
PERSONAL_KEY=~/.ssh/id_ed25519
PERSONAL_NAME=Personal User
PERSONAL_EMAIL=you@example.com
PERSONAL_DIRS=~/personal
DEFAULT_ID=personal
INSTALL_HOOKS=0
EOF

"$TOOL_BASH" "$SCRIPT" init --from-file "$WORK/answers.conf" --yes --lang en > "$WORK/init.log" 2>&1 \
  && pass "init exits 0" || { fail "init exits 0"; show_log "scenario B init failed" "$WORK/init.log"; }
assert_contains "$HOME/.ssh/config" "Host github.com-work" "company alias created"
assert_contains "$HOME/.ssh/config" "Host github.com-personal" "personal alias created"
assert_eq "$(git config --global core.hooksPath 2>/dev/null || echo none)" "none" "no hook installed when not requested"

# 身份仍然按目录切换（同域名场景由 core.sshCommand 保证密钥正确）
git -C "$HOME/work" init -q repo-c
assert_eq "$(git -C "$HOME/work/repo-c" config user.email)" "dev@corp.example.com" "company dir → company email (same host)"
assert_contains "$HOME/.gitconfig-company" "id_ed25519_company" "company key forced via sshCommand"

# remote 未使用别名时 audit 应报告并可修复
git -C "$HOME/work/repo-c" remote add origin git@github.com:corp/repo-c.git
if "$TOOL_BASH" "$SCRIPT" audit --lang en > "$WORK/audit.log" 2>&1; then
  fail "audit flags alias-less remote"
else
  pass "audit flags alias-less remote"
fi
"$TOOL_BASH" "$SCRIPT" audit --fix --yes --lang en > /dev/null 2>&1 \
  || annotate "scenario B audit --fix failed" "see step log"
assert_eq "$(git -C "$HOME/work/repo-c" config --get remote.origin.url)" "git@github.com-work:corp/repo-c.git" "audit --fix rewrites remote to alias"
rm -rf "$WORK"

# ---------------------------------------------------------------------------
# scenario C: 多目录 + 路径含空格
# ---------------------------------------------------------------------------
section "scenario C — multiple dirs, path with spaces"

setup_isolation
mkdir -p "$HOME/work/main" "$HOME/work with space" "$HOME/personal"

cat > "$WORK/answers.conf" <<'EOF'
COMPANY_HOST=git.corp.example.com
COMPANY_KEY=~/.ssh/id_ed25519_company
COMPANY_NAME=Corp User
COMPANY_EMAIL=dev@corp.example.com
COMPANY_DIRS=~/work/main,~/work with space
PERSONAL_KEY=~/.ssh/id_ed25519
PERSONAL_NAME=Personal User
PERSONAL_EMAIL=you@example.com
PERSONAL_DIRS=~/personal
DEFAULT_ID=company
INSTALL_HOOKS=0
EOF

"$TOOL_BASH" "$SCRIPT" init --from-file "$WORK/answers.conf" --yes --lang en > "$WORK/init.log" 2>&1 \
  && pass "init exits 0" || { fail "init exits 0"; show_log "scenario C init failed" "$WORK/init.log"; }

assert_contains "$CFG/includeif.conf" "gitdir:$HOME/work/main/" "first company dir rule"
assert_contains "$CFG/includeif.conf" "gitdir:$HOME/work with space/" "dir with space kept intact"
assert_eq "$(git config --global user.email 2>/dev/null || echo none)" "dev@corp.example.com" "default identity = company"

git -C "$HOME/work with space" init -q repo-d
git -C "$HOME/personal" init -q repo-e
assert_eq "$(git -C "$HOME/work with space/repo-d" config user.email)" "dev@corp.example.com" "space dir → company email"
assert_eq "$(git -C "$HOME/personal/repo-e" config user.email)" "you@example.com" "personal dir → personal email (default company)"

if "$TOOL_BASH" "$SCRIPT" audit --lang en > "$WORK/audit.log" 2>&1; then
  pass "audit clean with multiple dirs"
else
  fail "audit clean with multiple dirs"; show_log "scenario C audit failed" "$WORK/audit.log"
fi
assert_contains "$WORK/audit.log" "Repositories scanned: 2" "both dirs scanned"
rm -rf "$WORK"

# ---------------------------------------------------------------------------
section "summary"
printf '  passed: %s\n  failed: %s\n\n' "$PASS" "$FAIL"
if [ "$FAIL" -gt 0 ]; then
  annotate "smoke suite failed" "passed=$PASS failed=$FAIL
failed assertions:
${FAILED_LABELS}"
  exit 1
fi
