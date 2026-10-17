#!/usr/bin/env bash
#
# git-multi-config — 一台机器上管理「公司 Git 私服 + 个人 GitHub」多账号环境
# Manage company / personal multi-account Git setups on one machine.
#
# version: 2.0.1   license: MIT
# requires: bash 3.2+, git 2.13+ (2.36+ enables remote-URL based rules)
# tested on: macOS (system bash 3.2) / Linux / WSL
#
set -euo pipefail

VERSION="2.0.1"
PROG="git-multi-config"

# ---------------------------------------------------------------------------
# paths
# ---------------------------------------------------------------------------
CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
CONFIG_DIR="${GMC_HOME:-$CONFIG_HOME/git-multi-config}"
STATE_FILE="$CONFIG_DIR/state.conf"
INCLUDEIF_FILE="$CONFIG_DIR/includeif.conf"
HOOKS_DIR="$CONFIG_DIR/hooks"
SSH_CONFIG="${GMC_SSH_CONFIG:-$HOME/.ssh/config}"
GITCONFIG="${GMC_GITCONFIG:-$HOME/.gitconfig}"
COMPANY_CFG="$HOME/.gitconfig-company"
PERSONAL_CFG="$HOME/.gitconfig-personal"

MARK_BEGIN="# >>> git-multi-config >>>"
MARK_END="# <<< git-multi-config <<<"

SCAN_DEPTH=4
NONINTERACTIVE=0
ASSUME_YES=0
PREFILL_FILE=""
TEST_SSH=0

# ---------------------------------------------------------------------------
# colors
# ---------------------------------------------------------------------------
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
  BLUE='\033[1;34m'; GREEN='\033[1;32m'; YELLOW='\033[1;33m'; RED='\033[1;31m'; DIM='\033[2m'; NC='\033[0m'
else
  BLUE=''; GREEN=''; YELLOW=''; RED=''; DIM=''; NC=''
fi

# ---------------------------------------------------------------------------
# i18n — 默认中文，--lang en 切英文（消息内不可出现 "|"）
# ---------------------------------------------------------------------------
LANG_CODE="${GMC_LANG:-zh}"
case "$LANG_CODE" in
  zh) LANG_CODE="zh" ;;
  en) LANG_CODE="en" ;;
  *)  LANG_CODE="zh" ;;
esac

m() {
  case "$1" in
    desc)                  printf '%s' "Manage company / personal multi-account Git setups|管理公司私服与个人 GitHub 多账号环境";;
    usage)                 printf '%s' "Usage: git-multi-config [command] [options]|用法: git-multi-config [命令] [选项]";;
    cmd_init)              printf '%s' "Interactive setup wizard (default)|交互式配置向导（默认命令）";;
    cmd_audit)             printf '%s' "Audit repos for identity mismatches|审计仓库身份是否错配";;
    cmd_list)              printf '%s' "Show current configuration|查看当前配置";;
    cmd_doctor)            printf '%s' "Diagnose environment problems|诊断环境问题";;
    cmd_uninstall)         printf '%s' "Remove everything this tool installed|卸载本工具写入的全部配置";;
    cmd_help)              printf '%s' "Show this help|显示帮助";;
    opt_from)              printf '%s' "Load answers from file, no prompts|从文件读取答案，不再交互";;
    opt_yes)               printf '%s' "Skip confirmation prompts|跳过确认提示";;
    opt_lang)              printf '%s' "UI language: zh or en|界面语言: zh 或 en";;
    opt_fix)               printf '%s' "Repair issues instead of only reporting|自动修复问题（而非仅报告）";;
    opt_depth)             printf '%s' "Max repo scan depth, default 4|仓库扫描最大深度，默认 4";;
    opt_ssh)               printf '%s' "Also test SSH connectivity|同时测试 SSH 连通性";;
    opt_with_hooks)        printf '%s' "Install the pre-commit identity guard|安装提交前身份拦截钩子";;
    opt_restore)           printf '%s' "Restore newest backups on uninstall|卸载时恢复最近备份";;

    step1)                 printf '%s' "[1/4] Company Git server|【1/4】公司 Git 信息";;
    step2)                 printf '%s' "[2/4] Personal account|【2/4】个人账号信息";;
    step3)                 printf '%s' "[3/4] Default identity and guards|【3/4】默认身份与保护措施";;
    step4)                 printf '%s' "[4/4] Apply|【4/4】写入配置";;

    p_company_host)        printf '%s' "Company Git host, e.g. git.corp.com|公司 Git 服务器域名，如 git.corp.com";;
    p_company_key)         printf '%s' "Company SSH private key|公司账号 SSH 私钥路径";;
    p_company_name)        printf '%s' "Company commit user.name|公司提交用的 user.name";;
    p_company_email)       printf '%s' "Company commit user.email|公司提交用的 user.email";;
    p_company_gpg)         printf '%s' "Company GPG signing key, Enter to skip|公司 GPG 签名密钥，回车跳过";;
    p_company_dirs)        printf '%s' "Company dirs, comma separated, spaces allowed in paths|公司项目目录，多个用逗号分隔，路径可含空格";;
    p_personal_host)       printf '%s' "Personal Git host|个人 Git 服务域名";;
    p_personal_key)        printf '%s' "Personal SSH private key|个人账号 SSH 私钥路径";;
    p_personal_name)       printf '%s' "Personal commit user.name|个人提交用的 user.name";;
    p_personal_email)      printf '%s' "Personal commit user.email|个人提交用的 user.email";;
    p_personal_gpg)        printf '%s' "Personal GPG signing key, Enter to skip|个人 GPG 签名密钥，回车跳过";;
    p_personal_dirs)       printf '%s' "Personal dirs, comma separated, spaces allowed in paths|个人项目目录，多个用逗号分隔，路径可含空格";;
    p_default_id)          printf '%s' "Default identity outside managed dirs: 1 personal, 2 company|目录之外的默认身份: 1 个人, 2 公司";;
    p_hooks)               printf '%s' "Install pre-commit identity guard (sets global core.hooksPath)|安装提交前身份拦截钩子（会设置全局 core.hooksPath）";;

    lbl_company_host)      printf '%s' "Company server";;
    lbl_company_id)        printf '%s' "Company identity";;
    lbl_company_dirs)      printf '%s' "Company dirs";;
    lbl_personal_host)     printf '%s' "Personal server";;
    lbl_personal_id)       printf '%s' "Personal identity";;
    lbl_personal_dirs)     printf '%s' "Personal dirs";;
    lbl_default)           printf '%s' "Default identity";;
    lbl_hooks)             printf '%s' "Commit guard";;
    lbl_files)             printf '%s' "Files";;
    lbl_state)             printf '%s' "State";;
    val_yes)               printf '%s' "yes";;
    val_no)                printf '%s' "no";;
    val_personal)          printf '%s' "personal";;
    val_company)           printf '%s' "company";;

    confirm_write)         printf '%s' "Write these settings|写入以上配置";;
    confirm_uninstall)     printf '%s' "Remove all config written by git-multi-config|移除本工具写入的全部配置";;
    cancelled)             printf '%s' "Cancelled, nothing changed.|已取消，未做任何修改";;

    info_backup)           printf '%s' "Backup|备份";;
    info_write_ssh)        printf '%s' "Writing SSH config|写入 SSH 配置";;
    info_write_id)         printf '%s' "Writing per-profile git configs|写入各身份配置";;
    info_write_inc)        printf '%s' "Writing conditional include rules|写入按目录自动切换规则";;
    info_write_hooks)      printf '%s' "Installing pre-commit guard|安装提交前拦截钩子";;
    ok_ssh)                printf '%s' "SSH config updated|SSH 配置已更新";;
    ok_id)                 printf '%s' "Profile configs written|身份配置文件已写入";;
    ok_inc)                printf '%s' "Auto-switch rules active|自动切换规则已生效";;
    ok_hooks)              printf '%s' "Commit guard installed|提交拦截钩子已安装";;
    ok_default)            printf '%s' "Global default identity set|全局默认身份已设置";;
    ok_done)               printf '%s' "Setup complete|配置完成";;
    ok_removed)            printf '%s' "removed|已移除";;

    warn_key_missing)      printf '%s' "SSH key not found|SSH 密钥不存在";;
    warn_keygen_hint)      printf '%s' "Create it later: ssh-keygen -t ed25519 -f|稍后可用此命令生成: ssh-keygen -t ed25519 -f";;
    warn_dir_missing)      printf '%s' "directory missing, config applies once created|目录不存在，建好后规则即生效";;
    warn_host_conflict)    printf '%s' "an existing Host entry for this host appears BEFORE the managed block in SSH config; SSH key selection is still forced per directory via core.sshCommand|SSH 配置中该 Host 已有更靠前的条目，密钥选择仍由目录级的 core.sshCommand 强制保证";;
    warn_hooks_conflict)   printf '%s' "core.hooksPath already points elsewhere, guard skipped|core.hooksPath 已指向别处，已跳过钩子安装";;
    warn_no_repos)         printf '%s' "No git repositories found under managed dirs|受管目录下未找到 git 仓库";;
    warn_scan)             printf '%s' "cannot read, skipped|无法读取，已跳过";;
    warn_no_hasconfig)     printf '%s' "git is older than 2.36, remote-URL rules are skipped|git 低于 2.36，按 remote 地址判定的规则已跳过";;
    warn_no_hasconfig_hint) printf '%s' "repos outside managed dirs will not switch identity by remote URL|受管目录之外的仓库不会按 remote 地址自动切换身份";;

    err_need_tty)          printf '%s' "Not an interactive terminal, use --from-file|非交互环境，请使用 --from-file";;
    err_required)          printf '%s' "required value|必填";;
    err_email)             printf '%s' "not a valid email|不是合法邮箱";;
    err_no_state)          printf '%s' "No configuration yet, run init first|尚未配置，请先执行 init";;
    err_unknown_opt)       printf '%s' "Unknown option|未知选项";;
    err_from_file)         printf '%s' "Answer file not found|答案文件不存在";;
    err_git_old)           printf '%s' "git too old for includeIf, need 2.13+|git 版本过低，includeIf 需要 2.13+";;
    err_depth)             printf '%s' "positive integer required|需要正整数";;
    err_dirs_empty)        printf '%s' "no valid directory given, only separators?|未提供有效目录，是否只填了分隔符？";;

    next_title)            printf '%s' "Next steps|下一步";;
    next_1)                printf '%s' "Check auto-switch inside a repo under|在以下目录里的仓库验证自动切换";;
    next_2)                printf '%s' "Expect|预期";;
    next_3)                printf '%s' "Audit and repair existing repos|审计并修复存量仓库";;
    next_4)                printf '%s' "Diagnose problems|诊断问题";;

    audit_title)           printf '%s' "Audit|审计";;
    audit_scanned)         printf '%s' "Repositories scanned|已扫描仓库";;
    audit_ok)              printf '%s' "All repositories use the expected identity|所有仓库身份均正确";;
    audit_issues)          printf '%s' "Issues found|发现问题";;
    audit_issue_local)     printf '%s' "local user.email overrides the switch rule|本地 user.email 覆盖了自动切换规则";;
    audit_issue_effective) printf '%s' "effective identity differs from expectation|生效身份与预期不一致";;
    audit_issue_remote)    printf '%s' "remote URL bypasses the dedicated SSH alias|remote 地址未使用公司专用 SSH 别名";;
    audit_expect)          printf '%s' "expect|预期";;
    audit_fixed)           printf '%s' "fixed|已修复";;
    audit_use_fix)         printf '%s' "run with --fix to repair|加 --fix 可自动修复";;

    doc_title)             printf '%s' "Diagnosis|环境诊断";;
    doc_git)               printf '%s' "git version|git 版本";;
    doc_git_hasconfig)     printf '%s' "hasconfig remote rules supported (2.36+)|支持按 remote 地址判定（2.36+）";;
    doc_git_no_hasconfig)  printf '%s' "no hasconfig support, directory rules only|不支持 hasconfig，仅使用目录规则";;
    doc_state)             printf '%s' "State file|状态文件";;
    doc_include)           printf '%s' "Include rules|包含规则文件";;
    doc_ssh_block)         printf '%s' "Managed block in|管理块";;
    doc_perms)             printf '%s' "permissions should be 600|权限应为 600";;
    doc_hooks)             printf '%s' "Commit guard|提交拦截钩子";;
    doc_ssh_test)          printf '%s' "SSH connectivity|SSH 连通性";;
    doc_pass)              printf '%s' "No problems detected|未发现问题";;
    doc_problems)          printf '%s' "problem(s) found|个问题";;

    list_title)            printf '%s' "Current configuration|当前配置";;
    list_none)             printf '%s' "Nothing configured yet|尚未配置";;

    un_ssh)                printf '%s' "SSH config|SSH 配置";;
    un_git)                printf '%s' "global gitconfig|全局 gitconfig";;
    un_inc)                printf '%s' "include rules|包含规则";;
    un_hooks)              printf '%s' "commit guard|提交拦截钩子";;
    un_restore)            printf '%s' "Restored|已恢复";;
    un_done)               printf '%s' "Uninstall complete|卸载完成";;
    un_nothing)            printf '%s' "Nothing to remove|无需卸载";;
    *)                     printf '%s' "$1";;
  esac
}

t() {
  local pair
  pair="$(m "$1")"
  case "$LANG_CODE" in
    en) printf '%s' "${pair%%|*}" ;;
    *)  printf '%s' "${pair#*|}" ;;
  esac
}

# ---------------------------------------------------------------------------
# logging
# ---------------------------------------------------------------------------
info() { printf "${BLUE}[info]${NC} %s\n" "$*"; }
ok()   { printf "${GREEN}[ ok ]${NC} %s\n" "$*"; }
warn() { printf "${YELLOW}[warn]${NC} %s\n" "$*" >&2; }
err()  { printf "${RED}[fail]${NC} %s\n" "$*" >&2; }
die()  { err "$*"; exit 1; }
dim()  { printf "${DIM}%s${NC}\n" "$*"; }
hr()   { printf '%s\n' "------------------------------------------------------------"; }

# ---------------------------------------------------------------------------
# utils
# ---------------------------------------------------------------------------
expand_path() {
  local p="$1"
  case "$p" in
    \~)   p="$HOME" ;;
    \~/*) p="$HOME${p#\~}" ;;
  esac
  printf '%s' "$p"
}

shell_quote() { printf '%q' "$1"; }

# shell_quote 的逆运算：解码 printf '%q' 的输出。
# load_state 以前直接用 . 执行 state.conf，等于把状态文件当代码跑（见 SEC-1）；
# 改成逐行解析 + 解码之后，文件里即使写了 $(...) 也只会变成普通字符串。
# 用纯 bash 逐字符解码，不用 sed：BSD sed 的 BRE 会把 \\( 当成字面括号，
# 同样的写法在 GNU sed 下能用、在 macOS 上却静默失效。
unquote_q() {
  local s="$1" out="" c digits
  case "$s" in
    "''") printf '%s' ""; return 0 ;;
  esac
  # $'...' 形式（原值含控制字符时 %q 会这样输出）：先脱壳，再按转义解码
  if [ "${#s}" -ge 3 ] && [ "${s:0:2}" = "\$'" ] && [ "${s:$((${#s} - 1)):1}" = "'" ]; then
    s="${s:2}"
    s="${s:0:$((${#s} - 1))}"
    while [ -n "$s" ]; do
      c="${s:0:1}"; s="${s:1}"
      if [ "$c" = "\\" ] && [ -n "$s" ]; then
        c="${s:0:1}"; s="${s:1}"
        case "$c" in
          n) out="$out
" ;;
          t) out="$out	" ;;
          r) out="$out$(printf '\r')" ;;
          a) out="$out$(printf '\a')" ;;
          b) out="$out$(printf '\b')" ;;
          f) out="$out$(printf '\f')" ;;
          v) out="$out$(printf '\v')" ;;
          [0-7])
            digits="$c"
            while [ "${#digits}" -lt 3 ]; do
              c="${s:0:1}"
              case "$c" in
                [0-7]) digits="$digits$c"; s="${s:1}" ;;
                *) break ;;
              esac
            done
            out="$out$(printf "\\$digits")"
            ;;
          *) out="$out$c" ;;
        esac
      else
        out="$out$c"
      fi
    done
  else
    # 反斜杠转义形式：\X -> X（反斜杠自身写作 \\）
    while [ -n "$s" ]; do
      c="${s:0:1}"; s="${s:1}"
      if [ "$c" = "\\" ] && [ -n "$s" ]; then
        c="${s:0:1}"; s="${s:1}"
      fi
      out="$out$c"
    done
  fi
  printf '%s' "$out"
}

# 解析符号链接后的物理路径（目录不存在时原样返回）
# git 的 gitdir 匹配基于物理路径，macOS 上 /var、/tmp 等均为软链，故需两种形式都写入
real_path() {
  local p="$1"
  if [ -d "$p" ]; then
    (cd "$p" 2>/dev/null && pwd -P) 2>/dev/null || printf '%s' "$p"
  else
    printf '%s' "$p"
  fi
}

# 仓库是否位于某受管目录之下（同时比较逻辑路径与物理路径）
path_matches() { # $1=repo $2=managed dir
  case "$1" in
    "$2"|"$2"/*) return 0 ;;
  esac
  local r p
  r="$(real_path "$1")"
  p="$(real_path "$2")"
  case "$r" in
    "$p"|"$p"/*) return 0 ;;
  esac
  return 1
}

# 目录分隔符：逗号 / 分号 / 冒号；不把空格视为分隔符，以便支持含空格的路径
norm_dirs() {
  printf '%s' "$1" | tr ',;' '::' | tr -s ':' | sed 's/^://;s/:$//'
}

dirs_lines() { printf '%s\n' "$1" | tr ':' '\n' | sed '/^$/d'; }

each_company_dir() {
  dirs_lines "${COMPANY_DIRS:-}" | while IFS= read -r d; do
    if [ -n "$d" ]; then printf '%s\n' "$(expand_path "$d")"; fi
  done
}

each_personal_dir() {
  dirs_lines "${PERSONAL_DIRS:-}" | while IFS= read -r d; do
    if [ -n "$d" ]; then printf '%s\n' "$(expand_path "$d")"; fi
  done
}

# 最长前缀匹配，决定某仓库应使用的邮箱
expected_email_for() {
  local repo="$1" best="" best_email="" d ed
  while IFS= read -r d; do
    if [ -z "$d" ]; then continue; fi
    ed="$(expand_path "$d")"
    if path_matches "$repo" "$ed"; then
      if [ "${#ed}" -gt "${#best}" ]; then best="$ed"; best_email="${COMPANY_EMAIL:-}"; fi
    fi
  done <<EOF
$(dirs_lines "${COMPANY_DIRS:-}")
EOF
  while IFS= read -r d; do
    if [ -z "$d" ]; then continue; fi
    ed="$(expand_path "$d")"
    if path_matches "$repo" "$ed"; then
      if [ "${#ed}" -gt "${#best}" ]; then best="$ed"; best_email="${PERSONAL_EMAIL:-}"; fi
    fi
  done <<EOF
$(dirs_lines "${PERSONAL_DIRS:-}")
EOF
  printf '%s' "$best_email"
}

backup_file() {
  local f="$1" bak
  [ -f "$f" ] || return 0
  bak="$f.bak.$(date +%Y%m%d_%H%M%S)"
  cp "$f" "$bak"
  info "$(t info_backup): $f -> $bak"
}

latest_backup() { ls -1t "$1".bak.* 2>/dev/null | head -n 1; }

remove_managed_block() {
  local f="$1" b="$2" e="$3"
  [ -f "$f" ] || return 0
  grep -qF "$b" "$f" 2>/dev/null || return 0
  awk -v b="$b" -v e="$e" '
    $0 == b { skip = 1; next }
    $0 == e { skip = 0; next }
    skip != 1 { print }
  ' "$f" > "$f.gmc.tmp" && mv "$f.gmc.tmp" "$f"
}

append_managed_block() {
  local f="$1" body="$2"
  mkdir -p "$(dirname "$f")"
  touch "$f"
  {
    printf '\n%s\n' "$MARK_BEGIN"
    printf '%s\n' "$body"
    printf '%s\n' "$MARK_END"
  } >> "$f"
}

has_managed_block() {
  if [ -f "$1" ] && grep -qF "$MARK_BEGIN" "$1" 2>/dev/null; then return 0; fi
  return 1
}

# 管理块之外是否已存在同 Host 条目（SSH 中先出现者生效）
host_outside_block() {
  local f="$1" host="$2"
  [ -f "$f" ] || return 1
  awk -v host="$host" -v b="$MARK_BEGIN" -v e="$MARK_END" '
    $0 == b { inblock = 1 }
    $0 == e { inblock = 0; next }
    inblock == 1 { next }
    /^[Hh]ost[[:space:]]/ {
      n = split($0, a, /[[:space:]]+/)
      for (i = 2; i <= n; i++) if (a[i] == host) found = 1
    }
    END { exit(found ? 0 : 1) }
  ' "$f"
}

git_mmp() { git --version 2>/dev/null | sed -n 's/[^0-9]*\([0-9][0-9]*\)\.\([0-9][0-9]*\).*/\1 \2/p'; }

version_ge() { # $1.$2 >= $3.$4
  if [ "$1" -gt "$3" ] 2>/dev/null; then return 0; fi
  if [ "$1" -eq "$3" ] 2>/dev/null && [ "$2" -ge "$4" ] 2>/dev/null; then return 0; fi
  return 1
}

supports_includeif() {
  local v; v="$(git_mmp)"
  [ -n "$v" ] || return 1
  # shellcheck disable=SC2086  # 有意让 "2 13" 拆成两个参数
  version_ge $v 2 13
}

supports_hasconfig() {
  local v; v="$(git_mmp)"
  [ -n "$v" ] || return 1
  # shellcheck disable=SC2086
  version_ge $v 2 36
}

# ---------------------------------------------------------------------------
# prompts
# ---------------------------------------------------------------------------
prefill_get() {
  [ -n "$PREFILL_FILE" ] && [ -f "$PREFILL_FILE" ] || return 0
  sed -n "s/^[[:space:]]*$1=//p" "$PREFILL_FILE" | tail -n 1 \
    | sed "s/^['\"]//;s/['\"][[:space:]]*$//" | sed 's/[[:space:]]*$//'
}

ask() { # $1=state key, $2=prompt key, $3=default
  local pre val
  pre="$(prefill_get "$1")"
  if [ -n "$pre" ]; then printf '%s' "$pre"; return 0; fi
  if [ "$NONINTERACTIVE" = "1" ]; then printf '%s' "${3:-}"; return 0; fi
  if [ -n "${3:-}" ]; then
    read -r -p "$(t "$2") [$3]: " val || true
    printf '%s' "${val:-$3}"
  else
    read -r -p "$(t "$2"): " val || true
    printf '%s' "$val"
  fi
}

ask_yn() { # $1=state key, $2=prompt key, $3=default y|n
  local pre val
  pre="$(prefill_get "$1")"
  if [ -n "$pre" ]; then
    case "$pre" in 1|y|Y|yes|YES|true) printf 'y' ;; *) printf 'n' ;; esac
    return 0
  fi
  if [ "$NONINTERACTIVE" = "1" ] || [ "$ASSUME_YES" = "1" ]; then printf '%s' "${3:-n}"; return 0; fi
  read -r -p "$(t "$2")? [y/N]: " val || true
  case "$val" in y|Y|yes|YES) printf 'y' ;; *) printf 'n' ;; esac
}

confirm() { # $1=prompt key
  local a
  if [ "$ASSUME_YES" = "1" ]; then return 0; fi
  read -r -p "$(t "$1") [y/N]: " a || true
  case "$a" in y|Y|yes|YES) return 0 ;; *) return 1 ;; esac
}

check_ssh_key() { # $1=key path, $2=label
  local p
  if [ -f "$1" ]; then
    p="$(stat -f '%Lp' "$1" 2>/dev/null || stat -c '%a' "$1" 2>/dev/null || echo '')"
    if [ -n "$p" ] && [ "$p" != "600" ]; then
      warn "$2: $1 ($(t doc_perms)), now $p"
    else
      ok "$2: $1"
    fi
  else
    warn "$2: $(t warn_key_missing): $1"
    dim "      $(t warn_keygen_hint) $1"
  fi
}

require_email() {
  case "$1" in
    *@*.*) return 0 ;;
    *) err "$2: $(t err_email) ($1)"; return 1 ;;
  esac
}

# 只接受 >=1 的十进制整数。--depth 的值会直接进 find -maxdepth，
# 传 abc / 2.5 会被 find 拒绝并使调用方静默中止；0 与负数会被 BSD find 静默接受
# 却扫不到东西（见 BUG-4）
require_positive_int() { # $1=value $2=label
  case "${1:-}" in
    ''|*[!0-9]*) err "$2: $(t err_depth) (${1:-})"; return 1 ;;
  esac
  if [ "$1" -lt 1 ]; then err "$2: $(t err_depth) ($1)"; return 1; fi
  return 0
}

# ---------------------------------------------------------------------------
# state
# ---------------------------------------------------------------------------
load_state() {
  COMPANY_HOST=""; COMPANY_ALIAS=""; COMPANY_KEY=""; COMPANY_NAME=""; COMPANY_EMAIL=""
  COMPANY_GPG=""; COMPANY_DIRS=""
  PERSONAL_HOST="github.com"; PERSONAL_ALIAS="github.com"; PERSONAL_KEY=""; PERSONAL_NAME=""
  PERSONAL_EMAIL=""; PERSONAL_GPG=""; PERSONAL_DIRS=""
  DEFAULT_ID="personal"; HOOKS_INSTALLED="0"; HOOKS_PREV_PATH=""
  [ -f "$STATE_FILE" ] || return 0
  # 逐行解析，不再 source：状态文件是数据，不是代码（见 SEC-1）。
  # 未知键直接忽略 —— 以前它们会被 shell 当成命令执行。
  local line key val
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
      ''|'#'*) continue ;;
      *=*) ;;
      *) continue ;;
    esac
    key="${line%%=*}"
    val="$(unquote_q "${line#*=}")"
    case "$key" in
      COMPANY_HOST)    COMPANY_HOST="$val" ;;
      COMPANY_ALIAS)   COMPANY_ALIAS="$val" ;;
      COMPANY_KEY)     COMPANY_KEY="$val" ;;
      COMPANY_NAME)    COMPANY_NAME="$val" ;;
      COMPANY_EMAIL)   COMPANY_EMAIL="$val" ;;
      COMPANY_GPG)     COMPANY_GPG="$val" ;;
      COMPANY_DIRS)    COMPANY_DIRS="$val" ;;
      PERSONAL_HOST)   PERSONAL_HOST="$val" ;;
      PERSONAL_ALIAS)  PERSONAL_ALIAS="$val" ;;
      PERSONAL_KEY)    PERSONAL_KEY="$val" ;;
      PERSONAL_NAME)   PERSONAL_NAME="$val" ;;
      PERSONAL_EMAIL)  PERSONAL_EMAIL="$val" ;;
      PERSONAL_GPG)    PERSONAL_GPG="$val" ;;
      PERSONAL_DIRS)   PERSONAL_DIRS="$val" ;;
      DEFAULT_ID)      DEFAULT_ID="$val" ;;
      HOOKS_INSTALLED) HOOKS_INSTALLED="$val" ;;
      HOOKS_PREV_PATH) HOOKS_PREV_PATH="$val" ;;
      *) : ;;
    esac
  done < "$STATE_FILE"
}

save_state() {
  mkdir -p "$CONFIG_DIR"
  {
    printf '# generated by %s v%s — do not edit by hand\n' "$PROG" "$VERSION"
    printf '# 由 git-multi-config 自动生成，请勿手工编辑\n'
    printf 'GMC_STATE_VERSION=%s\n' "2"
    printf 'COMPANY_HOST=%s\n'   "$(shell_quote "${COMPANY_HOST:-}")"
    printf 'COMPANY_ALIAS=%s\n'  "$(shell_quote "${COMPANY_ALIAS:-}")"
    printf 'COMPANY_KEY=%s\n'    "$(shell_quote "${COMPANY_KEY:-}")"
    printf 'COMPANY_NAME=%s\n'   "$(shell_quote "${COMPANY_NAME:-}")"
    printf 'COMPANY_EMAIL=%s\n'  "$(shell_quote "${COMPANY_EMAIL:-}")"
    printf 'COMPANY_GPG=%s\n'    "$(shell_quote "${COMPANY_GPG:-}")"
    printf 'COMPANY_DIRS=%s\n'   "$(shell_quote "${COMPANY_DIRS:-}")"
    printf 'PERSONAL_HOST=%s\n'  "$(shell_quote "${PERSONAL_HOST:-}")"
    printf 'PERSONAL_ALIAS=%s\n' "$(shell_quote "${PERSONAL_ALIAS:-}")"
    printf 'PERSONAL_KEY=%s\n'   "$(shell_quote "${PERSONAL_KEY:-}")"
    printf 'PERSONAL_NAME=%s\n'  "$(shell_quote "${PERSONAL_NAME:-}")"
    printf 'PERSONAL_EMAIL=%s\n' "$(shell_quote "${PERSONAL_EMAIL:-}")"
    printf 'PERSONAL_GPG=%s\n'   "$(shell_quote "${PERSONAL_GPG:-}")"
    printf 'PERSONAL_DIRS=%s\n'  "$(shell_quote "${PERSONAL_DIRS:-}")"
    printf 'DEFAULT_ID=%s\n'     "$(shell_quote "${DEFAULT_ID:-personal}")"
    printf 'HOOKS_INSTALLED=%s\n' "$(shell_quote "${HOOKS_INSTALLED:-0}")"
    printf 'HOOKS_PREV_PATH=%s\n' "$(shell_quote "${HOOKS_PREV_PATH:-}")"
  } > "$STATE_FILE"
  chmod 600 "$STATE_FILE" 2>/dev/null || true
}

state_exists() { [ -f "$STATE_FILE" ]; }

# ---------------------------------------------------------------------------
# writers
# ---------------------------------------------------------------------------
write_ssh_config() {
  local dir body
  dir="$(dirname "$SSH_CONFIG")"
  mkdir -p "$dir"
  chmod 700 "$dir" 2>/dev/null || true
  remove_managed_block "$SSH_CONFIG" "$MARK_BEGIN" "$MARK_END"

  # IdentityFile 的路径必须加引号：含空格的密钥路径会让 sshd_config 解析器直接
  # 报 "keyword identityfile extra arguments at end of line" 并放弃整份 config，
  # 连用户已有的其他 Host 一起失效（见 BUG-1）
  body="$(printf '# company git server\nHost %s\n    HostName %s\n    User git\n    IdentityFile "%s"\n    IdentitiesOnly yes\n\n# personal git host\nHost %s\n    HostName %s\n    User git\n    IdentityFile "%s"\n    IdentitiesOnly yes' \
    "$COMPANY_ALIAS" "$COMPANY_HOST" "$COMPANY_KEY" \
    "$PERSONAL_ALIAS" "$PERSONAL_HOST" "$PERSONAL_KEY")"

  if [ "$COMPANY_HOST" = "$PERSONAL_HOST" ]; then
    body="$body

# personal alias, lets you force the personal key in any directory
Host ${PERSONAL_HOST}-personal
    HostName $PERSONAL_HOST
    User git
    IdentityFile "$PERSONAL_KEY"
    IdentitiesOnly yes"
  fi

  append_managed_block "$SSH_CONFIG" "$body"
  chmod 600 "$SSH_CONFIG" 2>/dev/null || true
  ok "$(t ok_ssh)"

  if [ "$COMPANY_ALIAS" != "$COMPANY_HOST" ] && host_outside_block "$SSH_CONFIG" "$COMPANY_HOST"; then
    warn "$COMPANY_HOST: $(t warn_host_conflict)"
  fi
}

write_id_config() { # $1=file $2=name $3=email $4=gpg $5=key $6=label
  {
    printf '# generated by %s v%s — %s\n' "$PROG" "$VERSION" "$6"
    printf '[user]\n'
    printf '\tname = %s\n' "$2"
    printf '\temail = %s\n' "$3"
    if [ -n "$4" ]; then printf '\tsigningkey = %s\n' "$4"; fi
    printf '[commit]\n'
    if [ -n "$4" ]; then printf '\tgpgsign = true\n'; else printf '\tgpgsign = false\n'; fi
    printf '[core]\n'
    printf '\tsshCommand = ssh -i "%s" -o IdentitiesOnly=yes\n' "$5"
  } > "$1"
  chmod 600 "$1" 2>/dev/null || true
}

write_includeif() {
  local d r
  mkdir -p "$CONFIG_DIR"
  {
    printf '# generated by %s v%s — do not edit by hand\n' "$PROG" "$VERSION"
    printf '# 由 git-multi-config 生成，请勿手工编辑\n'
    # 每个目录写两条规则：逻辑路径 + 物理路径（软链场景下 git 按物理路径匹配）
    each_company_dir | while IFS= read -r d; do
      printf '\n[includeIf "gitdir:%s/"]\n\tpath = %s\n' "$d" "$COMPANY_CFG"
      r="$(real_path "$d")"
      if [ "$r" != "$d" ]; then
        printf '\n[includeIf "gitdir:%s/"]\n\tpath = %s\n' "$r" "$COMPANY_CFG"
      fi
    done
    each_personal_dir | while IFS= read -r d; do
      printf '\n[includeIf "gitdir:%s/"]\n\tpath = %s\n' "$d" "$PERSONAL_CFG"
      r="$(real_path "$d")"
      if [ "$r" != "$d" ]; then
        printf '\n[includeIf "gitdir:%s/"]\n\tpath = %s\n' "$r" "$PERSONAL_CFG"
      fi
    done
    if [ "$COMPANY_HOST" != "$PERSONAL_HOST" ] && supports_hasconfig; then
      printf '\n[includeIf "hasconfig:remote.*.url:git@%s:**"]\n\tpath = %s\n' "$COMPANY_HOST" "$COMPANY_CFG"
      printf '\n[includeIf "hasconfig:remote.*.url:git@%s:**"]\n\tpath = %s\n' "$COMPANY_ALIAS" "$COMPANY_CFG"
      printf '\n[includeIf "hasconfig:remote.*.url:https://%s/**"]\n\tpath = %s\n' "$COMPANY_HOST" "$COMPANY_CFG"
      printf '\n[includeIf "hasconfig:remote.*.url:https://%s/**"]\n\tpath = %s\n' "$PERSONAL_HOST" "$PERSONAL_CFG"
    fi
  } > "$INCLUDEIF_FILE"
  chmod 600 "$INCLUDEIF_FILE" 2>/dev/null || true

  # 全局 gitconfig 只挂一个 include；块追加在文件末尾，保证条件规则优先于全局默认身份
  remove_managed_block "$GITCONFIG" "$MARK_BEGIN" "$MARK_END"
  touch "$GITCONFIG"
  append_managed_block "$GITCONFIG" "$(printf '[include]\n\tpath = %s' "$INCLUDEIF_FILE")"
}

# ---------------------------------------------------------------------------
# pre-commit guard
# ---------------------------------------------------------------------------
install_hooks() {
  local prev
  prev="$(git config --global --get core.hooksPath 2>/dev/null || true)"
  if [ -n "$prev" ] && [ "$prev" != "$HOOKS_DIR" ]; then
    warn "$(t warn_hooks_conflict): $prev"
    HOOKS_INSTALLED="0"
    return 0
  fi
  mkdir -p "$HOOKS_DIR"
  cat > "$HOOKS_DIR/pre-commit" <<'HOOK'
#!/bin/sh
# git-multi-config — pre-commit identity guard
# 临时跳过 / bypass: GMC_ALLOW_ANY=1 git commit ...
if [ "${GMC_ALLOW_ANY:-0}" = "1" ]; then exit 0; fi

# 登记邮箱向 git 索取，而不是解析 state.conf。
# state.conf 的值经 printf '%q' 转义（如 o\'brien@example.com、a\!b@example.com），
# 用 sed 剥引号却不反转义会把邮箱解析成 o\ / a\!b@... ，于是合法提交被误拦（见 BUG-2）。
# git config --file 走 ini 解析器，不存在 shell 引号与转义问题。
email="$(git config user.email 2>/dev/null || true)"
if [ -z "$email" ]; then exit 0; fi

registered=""
for f in "$HOME/.gitconfig-company" "$HOME/.gitconfig-personal"; do
  [ -f "$f" ] || continue
  cand="$(git config --file "$f" user.email 2>/dev/null || true)"
  [ -n "$cand" ] || continue
  if [ "$email" = "$cand" ]; then exit 0; fi
  registered="$registered $cand"
done

# 一个登记邮箱都没读到（尚未 init，或配置文件被清掉）时放行，避免误拦
if [ -z "$registered" ]; then exit 0; fi

printf '\n' >&2
printf '[git-multi-config] Refusing to commit with %s\n' "$email" >&2
printf '[git-multi-config] 拒绝提交：当前身份邮箱 %s 不在登记列表中\n' "$email" >&2
printf '[git-multi-config] Registered / 已登记:%s\n' "$registered" >&2
printf '[git-multi-config] Fix: git config --local --unset user.email\n' >&2
printf '[git-multi-config] Bypass: GMC_ALLOW_ANY=1 git commit ...\n' >&2
exit 1
HOOK
  chmod 755 "$HOOKS_DIR/pre-commit"
  # 仅当此前没有别处配置时才记录，避免重复 init 把自身路径记成“原值”
  if [ "$prev" != "$HOOKS_DIR" ]; then
    HOOKS_PREV_PATH="$prev"
  fi
  git config --global core.hooksPath "$HOOKS_DIR"
  HOOKS_INSTALLED="1"
  ok "$(t ok_hooks)"
}

uninstall_hooks() {
  local cur
  cur="$(git config --global --get core.hooksPath 2>/dev/null || true)"
  if [ "$cur" = "$HOOKS_DIR" ]; then
    if [ -n "${HOOKS_PREV_PATH:-}" ]; then
      git config --global core.hooksPath "$HOOKS_PREV_PATH"
    else
      git config --global --unset core.hooksPath 2>/dev/null || true
    fi
    ok "$(t un_hooks): $(t ok_removed)"
  fi
  rm -f "$HOOKS_DIR/pre-commit" 2>/dev/null || true
}

# ---------------------------------------------------------------------------
# init
# ---------------------------------------------------------------------------
cmd_init() {
  if [ ! -t 0 ] && [ -z "$PREFILL_FILE" ] && [ "$NONINTERACTIVE" != "1" ]; then
    die "$(t err_need_tty)"
  fi

  info "$(t step1)"
  COMPANY_HOST="$(ask COMPANY_HOST p_company_host "${COMPANY_HOST:-}")"
  [ -n "$COMPANY_HOST" ] || die "$(t p_company_host): $(t err_required)"
  COMPANY_KEY="$(expand_path "$(ask COMPANY_KEY p_company_key "${COMPANY_KEY:-$HOME/.ssh/id_ed25519_company}")")"
  COMPANY_NAME="$(ask COMPANY_NAME p_company_name "${COMPANY_NAME:-}")"
  [ -n "$COMPANY_NAME" ] || die "$(t p_company_name): $(t err_required)"
  COMPANY_EMAIL="$(ask COMPANY_EMAIL p_company_email "${COMPANY_EMAIL:-}")"
  require_email "$COMPANY_EMAIL" "$(t p_company_email)" || exit 1
  COMPANY_GPG="$(ask COMPANY_GPG p_company_gpg "${COMPANY_GPG:-}")"
  COMPANY_DIRS="$(norm_dirs "$(ask COMPANY_DIRS p_company_dirs "${COMPANY_DIRS:-$HOME/work}")")"
  [ -n "$COMPANY_DIRS" ] || die "$(t p_company_dirs): $(t err_dirs_empty)"

  echo
  info "$(t step2)"
  PERSONAL_HOST="$(ask PERSONAL_HOST p_personal_host "${PERSONAL_HOST:-github.com}")"
  PERSONAL_KEY="$(expand_path "$(ask PERSONAL_KEY p_personal_key "${PERSONAL_KEY:-$HOME/.ssh/id_ed25519}")")"
  PERSONAL_NAME="$(ask PERSONAL_NAME p_personal_name "${PERSONAL_NAME:-}")"
  [ -n "$PERSONAL_NAME" ] || die "$(t p_personal_name): $(t err_required)"
  PERSONAL_EMAIL="$(ask PERSONAL_EMAIL p_personal_email "${PERSONAL_EMAIL:-}")"
  require_email "$PERSONAL_EMAIL" "$(t p_personal_email)" || exit 1
  PERSONAL_GPG="$(ask PERSONAL_GPG p_personal_gpg "${PERSONAL_GPG:-}")"
  PERSONAL_DIRS="$(norm_dirs "$(ask PERSONAL_DIRS p_personal_dirs "${PERSONAL_DIRS:-$HOME/personal}")")"
  # 仅含分隔符（: :: ,, ;）的取值会被 norm_dirs 归一成空串，此时默认值兜底已经
  # 走过去了步骤，若不拦住就会写出 0 条 personal 规则却仍报「已生效」（见 BUG-3）
  [ -n "$PERSONAL_DIRS" ] || die "$(t p_personal_dirs): $(t err_dirs_empty)"

  echo
  info "$(t step3)"
  local def hooks_ans
  def="$(ask DEFAULT_ID p_default_id "$([ "${DEFAULT_ID:-personal}" = "company" ] && echo 2 || echo 1)")"
  case "$def" in
    2|company|work) DEFAULT_ID="company" ;;
    *)              DEFAULT_ID="personal" ;;
  esac
  hooks_ans="$(ask_yn INSTALL_HOOKS p_hooks "${INSTALL_HOOKS_DEFAULT:-n}")"

  if [ "$COMPANY_HOST" = "$PERSONAL_HOST" ]; then
    COMPANY_ALIAS="${COMPANY_HOST}-work"
  else
    COMPANY_ALIAS="$COMPANY_HOST"
  fi
  PERSONAL_ALIAS="$PERSONAL_HOST"

  echo
  hr
  printf '  %-16s %s\n' "$(t lbl_company_host)"  "$COMPANY_HOST  (alias: $COMPANY_ALIAS)"
  printf '  %-16s %s\n' "$(t lbl_company_id)"    "$COMPANY_NAME <$COMPANY_EMAIL>${COMPANY_GPG:+ [gpg]}"
  printf '  %-16s %s\n' "$(t lbl_company_dirs)"  "$(each_company_dir | tr '\n' ' ')"
  printf '  %-16s %s\n' "$(t lbl_personal_host)" "$PERSONAL_HOST"
  printf '  %-16s %s\n' "$(t lbl_personal_id)"   "$PERSONAL_NAME <$PERSONAL_EMAIL>${PERSONAL_GPG:+ [gpg]}"
  printf '  %-16s %s\n' "$(t lbl_personal_dirs)" "$(each_personal_dir | tr '\n' ' ')"
  printf '  %-16s %s\n' "$(t lbl_default)"       "$([ "$DEFAULT_ID" = "company" ] && t val_company || t val_personal)"
  printf '  %-16s %s\n' "$(t lbl_hooks)"         "$([ "$hooks_ans" = "y" ] && t val_yes || t val_no)"
  hr
  confirm confirm_write || { info "$(t cancelled)"; return 0; }

  echo
  info "$(t step4)"
  supports_includeif || die "$(t err_git_old): $(git_mmp)"

  backup_file "$SSH_CONFIG"
  backup_file "$GITCONFIG"

  mkdir -p "$CONFIG_DIR"
  each_company_dir > "$CONFIG_DIR/.tmp.dirs"
  each_personal_dir >> "$CONFIG_DIR/.tmp.dirs"
  while IFS= read -r d; do
    if [ -n "$d" ] && [ ! -d "$d" ]; then warn "$d: $(t warn_dir_missing)"; fi
  done < "$CONFIG_DIR/.tmp.dirs"
  rm -f "$CONFIG_DIR/.tmp.dirs"

  info "$(t info_write_ssh)"
  write_ssh_config
  check_ssh_key "$COMPANY_KEY" "company"
  check_ssh_key "$PERSONAL_KEY" "personal"

  info "$(t info_write_id)"
  write_id_config "$COMPANY_CFG"  "$COMPANY_NAME"  "$COMPANY_EMAIL"  "$COMPANY_GPG"  "$COMPANY_KEY"  "company"
  write_id_config "$PERSONAL_CFG" "$PERSONAL_NAME" "$PERSONAL_EMAIL" "$PERSONAL_GPG" "$PERSONAL_KEY" "personal"
  ok "$(t ok_id)"

  # 先落全局默认身份（让 [user] / [commit] 段落先就位），再追加 include 块使其位于文件末尾
  if [ "$DEFAULT_ID" = "company" ]; then
    git config --global user.name "$COMPANY_NAME"
    git config --global user.email "$COMPANY_EMAIL"
    if [ -n "$COMPANY_GPG" ]; then
      git config --global user.signingkey "$COMPANY_GPG"
      git config --global commit.gpgsign true
    else
      git config --global commit.gpgsign false
    fi
  else
    git config --global user.name "$PERSONAL_NAME"
    git config --global user.email "$PERSONAL_EMAIL"
    if [ -n "$PERSONAL_GPG" ]; then
      git config --global user.signingkey "$PERSONAL_GPG"
      git config --global commit.gpgsign true
    else
      git config --global commit.gpgsign false
    fi
  fi
  ok "$(t ok_default)"

  info "$(t info_write_inc)"
  write_includeif
  ok "$(t ok_inc)"

  # git < 2.36 时 hasconfig 规则被静默跳过，仅在 doctor 里才看得到；init 结束是
  # 用户最可能读到输出的时刻，就在这里提示（见 UX-2）
  if ! supports_hasconfig; then
    warn "$(t warn_no_hasconfig): $(git --version 2>/dev/null | sed 's/git version //')"
    dim "      $(t warn_no_hasconfig_hint)"
  fi

  if [ "$hooks_ans" = "y" ]; then
    info "$(t info_write_hooks)"
    install_hooks
  fi

  save_state

  if [ "$TEST_SSH" = "1" ]; then test_ssh_connectivity; fi

  echo
  hr
  ok "$(t ok_done)"
  printf '  %-16s %s\n' "$(t lbl_files)" "$SSH_CONFIG, $GITCONFIG, $INCLUDEIF_FILE"
  printf '  %-16s %s\n' "$(t lbl_state)" "$STATE_FILE"
  echo
  printf '%s:\n' "$(t next_title)"
  printf '  1) %s %s\n     cd <repo> && git config user.email   # %s %s\n' \
    "$(t next_1)" "$(each_company_dir | head -n 1)" "$(t next_2)" "$COMPANY_EMAIL"
  printf '  2) %s: %s audit --fix\n' "$(t next_3)" "$PROG"
  printf '  3) %s: %s doctor --ssh\n' "$(t next_4)" "$PROG"
  hr
}

# ---------------------------------------------------------------------------
# audit
# ---------------------------------------------------------------------------
# 扫出受管目录下的仓库路径。
# find 的 stderr 不再丢弃：遇到不可读路径时 find 会非零退出，叠加 pipefail 会让
# 整个 audit 在打印任何一行之前就中止，表现为「0 字节输出 + 退出码 1」，用户无从
# 得知发生了什么（见 BUG-5）。现在改为逐条 warn 出来，并保证扫描本身不中断。
scan_repos() {
  local d errf="$CONFIG_DIR/.audit.scanerr" line
  mkdir -p "$CONFIG_DIR"
  {
    each_company_dir
    each_personal_dir
  } | while IFS= read -r d; do
    if [ -d "$d" ]; then
      : > "$errf"
      find "$d" -maxdepth "$SCAN_DEPTH" -name .git -prune 2>"$errf" | sed 's#/\.git$##' || true
      if [ -s "$errf" ]; then
        # find 的报错可能没有结尾换行，read 此时返回非零但已赋值，
        # 故必须带 || [ -n "$line" ]，否则循环体一次都不会执行
        while IFS= read -r line || [ -n "$line" ]; do
          warn "$(t warn_scan): $line"
        done < "$errf"
      fi
    fi
  done || true
  rm -f "$errf" 2>/dev/null || true
}

cmd_audit() {
  state_exists || die "$(t err_no_state)"
  load_state

  local fix="${1:-0}" list="$CONFIG_DIR/.audit.repos"
  local total=0 issues=0 repo="" expected="" local_email="" eff_email="" remote="" newurl=""
  mkdir -p "$CONFIG_DIR"
  scan_repos | sort -u > "$list"

  if [ ! -s "$list" ]; then
    warn "$(t warn_no_repos)"
    rm -f "$list"
    return 0
  fi

  info "$(t audit_title)"
  while IFS= read -r repo; do
    [ -n "$repo" ] || continue
    total=$((total + 1))
    expected="$(expected_email_for "$repo")"
    [ -n "$expected" ] || continue

    local_email="$(git -C "$repo" config --local user.email 2>/dev/null || true)"
    eff_email="$(git -C "$repo" config user.email 2>/dev/null || true)"
    remote="$(git -C "$repo" config --get remote.origin.url 2>/dev/null || true)"

    if [ -n "$local_email" ] && [ "$local_email" != "$expected" ]; then
      issues=$((issues + 1))
      printf '%s %s\n    %s: %s (%s: %s)\n' "${YELLOW}!${NC}" "$repo" "$(t audit_issue_local)" "$local_email" "$(t audit_expect)" "$expected"
      if [ "$fix" = "1" ]; then
        git -C "$repo" config --local --unset user.email 2>/dev/null || true
        git -C "$repo" config --local --unset user.name 2>/dev/null || true
        ok "    $(t audit_fixed)"
      fi
    fi

    if [ "$COMPANY_HOST" = "$PERSONAL_HOST" ] && [ "$COMPANY_ALIAS" != "$COMPANY_HOST" ]; then
      if [ "$expected" = "$COMPANY_EMAIL" ]; then
        case "$remote" in
          "git@$COMPANY_HOST:"*)
            issues=$((issues + 1))
            printf '%s %s\n    %s: %s\n' "${YELLOW}!${NC}" "$repo" "$(t audit_issue_remote)" "$remote"
            if [ "$fix" = "1" ]; then
              newurl="$(printf '%s' "$remote" | sed "s#^git@$COMPANY_HOST:#git@$COMPANY_ALIAS:#")"
              git -C "$repo" remote set-url origin "$newurl"
              ok "    $(t audit_fixed): $newurl"
            fi ;;
        esac
      fi
    fi

    if [ -z "$local_email" ] && [ -n "$eff_email" ] && [ "$eff_email" != "$expected" ]; then
      issues=$((issues + 1))
      printf '%s %s\n    %s: %s (%s: %s)\n' "${YELLOW}!${NC}" "$repo" "$(t audit_issue_effective)" "$eff_email" "$(t audit_expect)" "$expected"
    fi
  done < "$list"
  rm -f "$list"

  info "$(t audit_scanned): $total"
  if [ "$issues" -eq 0 ]; then
    ok "$(t audit_ok)"
    return 0
  fi
  if [ "$fix" = "1" ]; then
    ok "$(t audit_issues): $issues"
    return 0
  fi
  warn "$(t audit_issues): $issues"
  dim "$(t audit_use_fix)"
  return 1
}

# ---------------------------------------------------------------------------
# doctor
# ---------------------------------------------------------------------------
test_ssh_connectivity() {
  info "$(t doc_ssh_test)"
  local h out
  for h in "$COMPANY_ALIAS" "$PERSONAL_ALIAS"; do
    out="$(ssh -o BatchMode=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=accept-new -T "git@$h" 2>&1 || true)"
    case "$out" in
      *"successfully authenticated"*|*"Hi "*|*"Welcome"*|*"shell"*) ok "  $h" ;;
      *) warn "  $h: $(printf '%s' "$out" | head -n 1)" ;;
    esac
  done
}

cmd_doctor() {
  local problems=0 v
  info "$(t doc_title)"
  v="$(git_mmp)"
  if [ -z "$v" ]; then
    err "$(t doc_git): not found"
    problems=$((problems + 1))
  else
    if supports_includeif; then
      ok "$(t doc_git): $(git --version | sed 's/git version //')"
    else
      err "$(t err_git_old): $v"
      problems=$((problems + 1))
    fi
    if supports_hasconfig; then
      ok "$(t doc_git_hasconfig)"
    else
      warn "$(t doc_git_no_hasconfig)"
    fi
  fi

  if ! state_exists; then
    warn "$(t err_no_state)"
    return 0
  fi
  load_state
  ok "$(t doc_state): $STATE_FILE"

  if [ -f "$INCLUDEIF_FILE" ]; then
    ok "$(t doc_include): $INCLUDEIF_FILE ($(grep -c 'includeIf' "$INCLUDEIF_FILE" 2>/dev/null || echo 0) rules)"
  else
    err "$(t doc_include): missing"
    problems=$((problems + 1))
  fi

  if has_managed_block "$GITCONFIG"; then
    ok "$(t doc_ssh_block) gitconfig: $GITCONFIG"
  else
    err "$GITCONFIG: $(t doc_ssh_block) missing"
    problems=$((problems + 1))
  fi

  if has_managed_block "$SSH_CONFIG"; then
    ok "$(t doc_ssh_block) ssh: $SSH_CONFIG"
  else
    err "$SSH_CONFIG: $(t doc_ssh_block) missing"
    problems=$((problems + 1))
  fi

  check_ssh_key "$COMPANY_KEY" "company"
  check_ssh_key "$PERSONAL_KEY" "personal"
  if [ ! -f "$COMPANY_KEY" ]; then problems=$((problems + 1)); fi
  if [ ! -f "$PERSONAL_KEY" ]; then problems=$((problems + 1)); fi

  if [ "${HOOKS_INSTALLED:-0}" = "1" ]; then
    local cur
    cur="$(git config --global --get core.hooksPath 2>/dev/null || true)"
    if [ "$cur" = "$HOOKS_DIR" ]; then
      ok "$(t doc_hooks): $HOOKS_DIR"
    else
      err "$(t doc_hooks): expected $HOOKS_DIR, found ${cur:-none}"
      problems=$((problems + 1))
    fi
  fi

  if [ "$TEST_SSH" = "1" ]; then test_ssh_connectivity; fi

  echo
  if [ "$problems" -gt 0 ]; then
    err "$problems $(t doc_problems)"
    exit 1
  fi
  ok "$(t doc_pass)"
}

# ---------------------------------------------------------------------------
# list
# ---------------------------------------------------------------------------
cmd_list() {
  if ! state_exists; then info "$(t list_none)"; return 0; fi
  load_state
  hr
  printf '%s\n' "$(t list_title)"
  hr
  printf '  %-16s %s\n' "$(t lbl_company_host)"  "$COMPANY_HOST  (alias: $COMPANY_ALIAS)"
  printf '  %-16s %s\n' "$(t lbl_company_id)"    "$COMPANY_NAME <$COMPANY_EMAIL>${COMPANY_GPG:+ [gpg: $COMPANY_GPG]}"
  printf '  %-16s %s\n' "$(t lbl_company_dirs)"  "$(each_company_dir | tr '\n' ' ')"
  printf '  %-16s %s\n' "$(t lbl_personal_host)" "$PERSONAL_HOST"
  printf '  %-16s %s\n' "$(t lbl_personal_id)"   "$PERSONAL_NAME <$PERSONAL_EMAIL>${PERSONAL_GPG:+ [gpg: $PERSONAL_GPG]}"
  printf '  %-16s %s\n' "$(t lbl_personal_dirs)" "$(each_personal_dir | tr '\n' ' ')"
  printf '  %-16s %s\n' "$(t lbl_default)"       "$DEFAULT_ID"
  printf '  %-16s %s\n' "$(t lbl_hooks)"         "$([ "${HOOKS_INSTALLED:-0}" = "1" ] && t val_yes || t val_no)"
  printf '  %-16s %s\n' "$(t lbl_state)"         "$STATE_FILE"
  hr
}

# ---------------------------------------------------------------------------
# uninstall
# ---------------------------------------------------------------------------
cmd_uninstall() {
  if ! state_exists; then info "$(t un_nothing)"; return 0; fi
  load_state
  confirm confirm_uninstall || { info "$(t cancelled)"; return 0; }

  if has_managed_block "$SSH_CONFIG"; then
    backup_file "$SSH_CONFIG"
    remove_managed_block "$SSH_CONFIG" "$MARK_BEGIN" "$MARK_END"
    ok "$(t un_ssh): $(t ok_removed)"
  fi
  if has_managed_block "$GITCONFIG"; then
    backup_file "$GITCONFIG"
    remove_managed_block "$GITCONFIG" "$MARK_BEGIN" "$MARK_END"
    ok "$(t un_git): $(t ok_removed)"
  fi
  if [ -f "$INCLUDEIF_FILE" ]; then
    rm -f "$INCLUDEIF_FILE"
    ok "$(t un_inc): $(t ok_removed)"
  fi
  local f b
  for f in "$COMPANY_CFG" "$PERSONAL_CFG"; do
    if [ -f "$f" ]; then
      backup_file "$f"
      rm -f "$f"
      ok "$(printf '%s' "$f"): $(t ok_removed)"
    fi
  done
  uninstall_hooks

  if [ "$RESTORE_BACKUP" = "1" ]; then
    for f in "$SSH_CONFIG" "$GITCONFIG"; do
      b="$(latest_backup "$f")"
      if [ -n "$b" ]; then
        cp "$b" "$f"
        ok "$(t un_restore) $b -> $f"
      fi
    done
  fi

  rm -f "$STATE_FILE"
  rmdir "$HOOKS_DIR" 2>/dev/null || true
  rmdir "$CONFIG_DIR" 2>/dev/null || true
  ok "$(t un_done)"
}

# ---------------------------------------------------------------------------
# help
# ---------------------------------------------------------------------------
cmd_help() {
  printf '%s v%s — %s\n\n' "$PROG" "$VERSION" "$(t desc)"
  printf '%s\n\n' "$(t usage)"
  printf '  init                     %s\n' "$(t cmd_init)"
  printf '  audit [--fix]            %s\n' "$(t cmd_audit)"
  printf '  list                     %s\n' "$(t cmd_list)"
  printf '  doctor [--ssh]           %s\n' "$(t cmd_doctor)"
  printf '  uninstall [--restore]    %s\n' "$(t cmd_uninstall)"
  printf '  help                     %s\n\n' "$(t cmd_help)"
  printf '  --from-file <file>       %s\n' "$(t opt_from)"
  printf '  -y, --yes                %s\n' "$(t opt_yes)"
  printf '  --lang <zh|en>           %s\n' "$(t opt_lang)"
  printf '  --fix                    %s\n' "$(t opt_fix)"
  printf '  --depth <n>              %s\n' "$(t opt_depth)"
  printf '  --ssh                    %s\n' "$(t opt_ssh)"
  printf '  --with-hooks             %s\n' "$(t opt_with_hooks)"
  printf '  --restore                %s\n\n' "$(t opt_restore)"
  dim "  COMPANY_HOST= COMPANY_KEY= COMPANY_NAME= COMPANY_EMAIL= COMPANY_GPG= COMPANY_DIRS="
  dim "  PERSONAL_HOST= PERSONAL_KEY= PERSONAL_NAME= PERSONAL_EMAIL= PERSONAL_GPG= PERSONAL_DIRS="
  dim "  DEFAULT_ID=personal|company   INSTALL_HOOKS=0|1"
}

# ---------------------------------------------------------------------------
# entry point
# ---------------------------------------------------------------------------
main() {
  local cmd="" AUDIT_FIX=0 INSTALL_HOOKS_DEFAULT="n"
  RESTORE_BACKUP=0

  # 预扫 --lang：用户习惯把 --lang 写在后面（如 `audit --depth abc --lang en`），
  # 但参数解析阶段的报错可能在它之前就产生，先扫一遍才能保证提示语是用户要的语言
  local pi=1 pv
  while [ "$pi" -le "$#" ]; do
    pv="${!pi}"
    case "$pv" in
      --lang=*) LANG_CODE="${pv#*=}" ;;
      --lang)
        pi=$((pi + 1))
        if [ "$pi" -le "$#" ]; then LANG_CODE="${!pi}"; fi
        ;;
    esac
    pi=$((pi + 1))
  done
  case "$LANG_CODE" in
    en|zh) ;;
    *) LANG_CODE="zh" ;;
  esac

  while [ $# -gt 0 ]; do
    case "$1" in
      init|setup)      cmd="init" ;;
      audit)           cmd="audit" ;;
      list|status)     cmd="list" ;;
      doctor|check)    cmd="doctor" ;;
      uninstall|remove) cmd="uninstall" ;;
      help|--help|-h)  cmd="help" ;;
      --version|-V)    cmd="version" ;;
      --from-file)     shift; PREFILL_FILE="${1:-}"; NONINTERACTIVE=1 ;;
      --from-file=*)   PREFILL_FILE="${1#*=}"; NONINTERACTIVE=1 ;;
      --yes|-y)        ASSUME_YES=1 ;;
      --non-interactive) NONINTERACTIVE=1 ;;
      --lang)          shift; LANG_CODE="${1:-zh}" ;;
      --lang=*)        LANG_CODE="${1#*=}" ;;
      --fix)           AUDIT_FIX=1 ;;
      --depth)
        shift
        require_positive_int "${1:-}" "$(t opt_depth)" || exit 1
        SCAN_DEPTH="$1"
        ;;
      --depth=*)
        require_positive_int "${1#*=}" "$(t opt_depth)" || exit 1
        SCAN_DEPTH="${1#*=}"
        ;;
      --ssh)           TEST_SSH=1 ;;
      --with-hooks)    INSTALL_HOOKS_DEFAULT="y" ;;
      --restore)       RESTORE_BACKUP=1 ;;
      *)               die "$(t err_unknown_opt): $1" ;;
    esac
    shift
  done

  case "$LANG_CODE" in
    en|zh) ;;
    *) LANG_CODE="zh" ;;
  esac

  if [ -n "$PREFILL_FILE" ] && [ ! -f "$PREFILL_FILE" ]; then
    die "$(t err_from_file): $PREFILL_FILE"
  fi

  if [ -z "$PREFILL_FILE" ]; then load_state; fi

  case "$cmd" in
    ""|init)   cmd_init ;;
    audit)     cmd_audit "$AUDIT_FIX" ;;
    list)      cmd_list ;;
    doctor)    cmd_doctor ;;
    uninstall) cmd_uninstall ;;
    help)      cmd_help ;;
    version)   printf '%s %s\n' "$PROG" "$VERSION" ;;
  esac
}

main "$@"
