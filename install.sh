#!/usr/bin/env bash
set -Eeuo pipefail

INSTALLER_VERSION="v1.0-linux"
NODE_VERSION="v20.18.1"
NODE_VERSION_NUMBER="${NODE_VERSION#v}"
CLAUDE_MODEL="claude-opus-4-6"
CODEX_MODEL="gpt-5.5"
GEMINI_MODEL="gemini-3.1-flash-lite-preview"
NPM_MIRROR="https://registry.npmmirror.com"
NPM_OFFICIAL="https://registry.npmjs.org"
NODE_MIRROR="https://npmmirror.com/mirrors/node"
NODE_OFFICIAL="https://nodejs.org/dist"

MAXAPI_ROOT="${HOME}/.maxapi"
NPM_PREFIX="${MAXAPI_ROOT}/npm-global"
MAXAPI_BIN="${MAXAPI_ROOT}/bin"
MAXAPI_NODE_ROOT="${MAXAPI_ROOT}/node"
MAXAPI_NODE_DIR="${MAXAPI_NODE_ROOT}/${NODE_VERSION}"
MAXAPI_LOG_DIR="${MAXAPI_ROOT}/logs"
LOCK_PATH="${MAXAPI_ROOT}/install.lock"
LOCK_DIR="${LOCK_PATH}.d"

SHELL_BLOCK_START="# >>> MAX API CLI Installer >>>"
SHELL_BLOCK_END="# <<< MAX API CLI Installer <<<"

API_BASE_URL_CANDIDATE_1_NAME="橙云线路"
API_BASE_URL_CANDIDATE_1="https://new.28.al"
API_BASE_URL_CANDIDATE_2_NAME="腾讯云CDN线路"
API_BASE_URL_CANDIDATE_2="https://new.1huanlesap02.top"
API_BASE_URL="$API_BASE_URL_CANDIDATE_1"
API_ROUTE_NAME="$API_BASE_URL_CANDIDATE_1_NAME"

MODE="install"
LOG_FILE=""
LOCK_FD_OPENED=0
LOCK_DIR_CREATED=0
PKG_MANAGER=""
SUDO_CMD=""
ARCH=""
NODE_ARCH=""
IS_WSL=0
IS_CONTAINER=0
IS_ROOT=0
HAS_TTY=0
SELECTED_TOOLS=""
API_KEY=""
ROUTE_SUMMARY=""

CLAUDE_STATUS="未执行"
CLAUDE_VERSION=""
CLAUDE_CONFIG=""
CLAUDE_SMOKE="未执行"
CLAUDE_WARNING=""
CLAUDE_FAILURE=""

CODEX_STATUS="未执行"
CODEX_VERSION=""
CODEX_CONFIG=""
CODEX_SMOKE="未执行"
CODEX_WARNING=""
CODEX_FAILURE=""

GEMINI_STATUS="未执行"
GEMINI_VERSION=""
GEMINI_CONFIG=""
GEMINI_SMOKE="未执行"
GEMINI_WARNING=""
GEMINI_FAILURE=""

usage() {
  cat <<'EOF'
MAX API Linux installer

Usage:
  bash install.sh
  bash install.sh --repair
  bash install.sh --uninstall
  bash install.sh --help

Options:
  --repair     Re-check dependencies, rewrite configuration, and validate tools.
  --uninstall  Remove MAX API managed shell blocks and user-level runtime files.
  --help       Show this help.
EOF
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --repair)
        MODE="repair"
        ;;
      --uninstall)
        MODE="uninstall"
        ;;
      --help|-h)
        usage
        exit 0
        ;;
      *)
        printf '未知参数: %s\n' "$1" >&2
        usage >&2
        exit 2
        ;;
    esac
    shift
  done
}

ensure_bash_version() {
  if [[ -z "${BASH_VERSION:-}" || "${BASH_VERSINFO[0]}" -lt 4 ]]; then
    printf '该脚本需要 Bash 4 或更高版本。\n' >&2
    exit 1
  fi
}

setup_paths_and_logging() {
  mkdir -p "$MAXAPI_ROOT" "$MAXAPI_LOG_DIR" "$MAXAPI_BIN" "$NPM_PREFIX"
  LOG_FILE="${MAXAPI_LOG_DIR}/install-$(date +%Y%m%d-%H%M%S).log"
  touch "$LOG_FILE"
  exec > >(tee -a "$LOG_FILE") 2>&1
}

cleanup() {
  local exit_code=$?
  if [[ "$LOCK_DIR_CREATED" -eq 1 ]]; then
    rmdir "$LOCK_DIR" 2>/dev/null || true
  fi
  exit "$exit_code"
}

redact_text() {
  local text="${1:-}"
  if [[ -n "${API_KEY:-}" ]]; then
    text="${text//${API_KEY}/****}"
  fi
  printf '%s' "$text" | sed -E 's/(api[_-]?key|auth[_-]?token|bearer|token|secret|password)([[:space:]]*[=:][[:space:]]*)[^[:space:]]+/\1\2****/Ig'
}

log() {
  local level="$1"
  local message="$2"
  printf '  [%s] %s\n' "$level" "$(redact_text "$message")"
}

info() { log "信息" "$1"; }
success() { log "成功" "$1"; }
warn() { log "警告" "$1"; }
err() { log "错误" "$1"; }

step() {
  printf '\n'
  printf '==> %s\n' "$1"
  printf '%s\n' '------------------------------------------------------------'
}

die() {
  err "$1"
  exit 1
}

banner() {
  cat <<EOF

  ███╗   ███╗ █████╗ ██╗  ██╗     █████╗ ██████╗ ██╗
  ████╗ ████║██╔══██╗╚██╗██╔╝    ██╔══██╗██╔══██╗██║
  ██╔████╔██║███████║ ╚███╔╝     ███████║██████╔╝██║
  ██║╚██╔╝██║██╔══██║ ██╔██╗     ██╔══██║██╔═══╝ ██║
  ██║ ╚═╝ ██║██║  ██║██╔╝ ██╗    ██║  ██║██║     ██║
  ╚═╝     ╚═╝╚═╝  ╚═╝╚═╝  ╚═╝    ╚═╝  ╚═╝╚═╝     ╚═╝

  MAX API Linux 一键安装工具 ${INSTALLER_VERSION}
  支持: Claude Code · Codex CLI · Gemini CLI
  服务: MAX API 自动测速选线

EOF
}

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

run_cmd() {
  local description="$1"
  shift
  info "$description"
  "$@"
}

capture_cmd() {
  local output
  set +e
  output="$("$@" 2>&1)"
  local code=$?
  set -e
  printf '%s' "$output"
  return "$code"
}

acquire_lock() {
  if command_exists flock; then
    exec 9>"$LOCK_PATH"
    LOCK_FD_OPENED=1
    if ! flock -n 9; then
      die "检测到另一个 MAX API 安装进程正在运行，请稍后重试。锁文件: $LOCK_PATH"
    fi
    info "已获取安装锁: $LOCK_PATH"
    return
  fi

  if mkdir "$LOCK_DIR" 2>/dev/null; then
    LOCK_DIR_CREATED=1
    info "已获取安装锁: $LOCK_DIR"
    return
  fi

  die "检测到另一个 MAX API 安装进程正在运行，请稍后重试。锁目录: $LOCK_DIR"
}

detect_arch() {
  local machine
  machine="$(uname -m)"
  case "$machine" in
    x86_64|amd64)
      ARCH="x86_64"
      NODE_ARCH="x64"
      ;;
    aarch64|arm64)
      ARCH="arm64"
      NODE_ARCH="arm64"
      ;;
    *)
      die "不支持的 CPU 架构: $machine。当前仅支持 x86_64 与 arm64/aarch64。"
      ;;
  esac
}

detect_package_manager() {
  if command_exists apt-get; then
    PKG_MANAGER="apt"
  elif command_exists dnf; then
    PKG_MANAGER="dnf"
  elif command_exists yum; then
    PKG_MANAGER="yum"
  elif command_exists pacman; then
    PKG_MANAGER="pacman"
  else
    PKG_MANAGER=""
  fi
}

detect_environment_flags() {
  [[ "$EUID" -eq 0 ]] && IS_ROOT=1 || IS_ROOT=0
  [[ -r /dev/tty && -w /dev/tty ]] && HAS_TTY=1 || HAS_TTY=0

  if grep -qiE 'microsoft|wsl' /proc/version /proc/sys/kernel/osrelease 2>/dev/null; then
    IS_WSL=1
  fi

  if [[ -f /.dockerenv || -f /run/.containerenv ]] || grep -qaE 'docker|containerd|kubepods|podman|lxc' /proc/1/cgroup 2>/dev/null; then
    IS_CONTAINER=1
  fi

  if [[ "$IS_ROOT" -eq 1 ]]; then
    SUDO_CMD=""
  elif command_exists sudo; then
    SUDO_CMD="sudo"
  else
    SUDO_CMD=""
  fi
}

run_as_root() {
  if [[ "$IS_ROOT" -eq 1 ]]; then
    "$@"
    return
  fi

  if [[ -z "$SUDO_CMD" ]]; then
    return 127
  fi

  "$SUDO_CMD" "$@"
}

preflight() {
  step "安装前环境检查"

  if [[ "$(uname -s)" != "Linux" ]]; then
    die "该安装器仅支持 Linux。"
  fi
  success "操作系统: Linux"

  detect_arch
  success "系统架构: $ARCH"

  detect_package_manager
  if [[ -z "$PKG_MANAGER" ]]; then
    die "未检测到受支持的包管理器。当前支持 apt、dnf、yum、pacman。"
  fi
  success "包管理器: $PKG_MANAGER"

  detect_environment_flags
  [[ "$IS_ROOT" -eq 1 ]] && info "当前用户: root" || info "当前用户: $(id -un)"
  [[ "$IS_WSL" -eq 1 ]] && info "环境: WSL" || true
  [[ "$IS_CONTAINER" -eq 1 ]] && info "环境: 容器或轻量运行时" || true

  if [[ "$MODE" != "uninstall" && "$HAS_TTY" -ne 1 ]]; then
    die "当前没有可交互 TTY，无法安全输入 API Key。请使用 bash <(curl -fsSL URL) 或下载后执行。"
  fi
  success "交互终端: 可用"

  if [[ ! -d "$HOME" || ! -w "$HOME" ]]; then
    die "HOME 目录不可写: $HOME"
  fi
  success "HOME 可写: $HOME"

  local available_kb
  available_kb="$(df -Pk "$HOME" | awk 'NR==2 {print $4}')"
  if [[ -n "$available_kb" && "$available_kb" -lt 512000 ]]; then
    die "HOME 所在磁盘可用空间不足 500MB。"
  fi
  success "磁盘空间: 满足至少 500MB"

  local year
  year="$(date +%Y 2>/dev/null || echo 1970)"
  if [[ "$year" -lt 2024 ]]; then
    warn "系统时间看起来异常，HTTPS 证书校验可能失败。当前年份: $year"
  else
    success "系统时间: $year"
  fi

  if command_exists curl; then
    if curl -fsSIL --max-time 8 "$NPM_OFFICIAL" >/dev/null 2>&1 || curl -fsSIL --max-time 8 "$NPM_MIRROR" >/dev/null 2>&1; then
      success "DNS/TLS: npm 源可连通"
    else
      warn "DNS/TLS 预检未能连通 npm 源，后续会继续尝试并输出诊断。"
    fi
  elif command_exists getent; then
    if getent hosts registry.npmjs.org >/dev/null 2>&1 || getent hosts registry.npmmirror.com >/dev/null 2>&1; then
      success "DNS: npm 域名可解析"
    else
      warn "DNS 预检未能解析 npm 域名。"
    fi
  else
    warn "缺少 curl/getent，跳过 DNS/TLS 预检。"
  fi
}

process_holds_path() {
  local path="$1"
  if command_exists fuser; then
    fuser "$path" >/dev/null 2>&1
    return $?
  fi
  return 1
}

process_list_for_names() {
  if command_exists ps; then
    ps -eo pid=,comm=,args= 2>/dev/null | awk '
      $2 ~ /^(apt|apt-get|dpkg|unattended-upgr|unattended-upgrades|dnf|yum|rpm|pacman)$/ {
        print "PID " $1 " | " $0
      }
    ' | sed 's/[[:space:]]\+/ /g' | head -n 10
  fi
}

lock_holder_details() {
  local path="$1"
  [[ -e "$path" ]] || return 0

  if command_exists fuser; then
    local pids
    pids="$(fuser "$path" 2>/dev/null | tr ' ' '\n' | awk 'NF' | xargs 2>/dev/null || true)"
    if [[ -n "$pids" ]]; then
      local pid
      for pid in $pids; do
        if [[ -r "/proc/${pid}/cmdline" ]]; then
          printf '锁文件 %s 被 PID %s 占用: %s\n' "$path" "$pid" "$(tr '\0' ' ' < "/proc/${pid}/cmdline" | sed 's/[[:space:]]*$//')"
        else
          printf '锁文件 %s 被 PID %s 占用\n' "$path" "$pid"
        fi
      done
    fi
  fi
}

package_manager_process_pids() {
  local names=""
  case "$PKG_MANAGER" in
    apt)
      names="apt apt-get dpkg unattended-upgr unattended-upgrades"
      ;;
    dnf|yum)
      names="dnf yum rpm"
      ;;
    pacman)
      names="pacman"
      ;;
  esac

  {
    local name
    for name in $names; do
      pgrep -x "$name" 2>/dev/null || true
    done

    if command_exists fuser; then
      case "$PKG_MANAGER" in
        apt)
          fuser /var/lib/dpkg/lock-frontend /var/lib/dpkg/lock /var/cache/apt/archives/lock 2>/dev/null || true
          ;;
        dnf|yum)
          fuser /var/lib/rpm/.rpm.lock 2>/dev/null || true
          ;;
        pacman)
          fuser /var/lib/pacman/db.lck 2>/dev/null || true
          ;;
      esac
    fi
  } | tr ' ' '\n' | awk -v self="$$" -v parent="$PPID" '/^[0-9]+$/ && $1 != self && $1 != parent { seen[$1]=1 } END { for (pid in seen) print pid }' | sort -n
}

pid_cmdline() {
  local pid="$1"
  if [[ -r "/proc/${pid}/cmdline" ]]; then
    tr '\0' ' ' < "/proc/${pid}/cmdline" | sed 's/[[:space:]]*$//'
  else
    ps -p "$pid" -o args= 2>/dev/null || true
  fi
}

send_signal_to_pid() {
  local signal="$1"
  local pid="$2"

  if kill "-$signal" "$pid" 2>/dev/null; then
    return 0
  fi

  if [[ "$IS_ROOT" -ne 1 && -n "$SUDO_CMD" ]]; then
    "$SUDO_CMD" kill "-$signal" "$pid" 2>/dev/null
    return $?
  fi

  return 1
}

terminate_package_manager_processes() {
  local pids
  pids="$(package_manager_process_pids)"
  if [[ -z "$pids" ]]; then
    warn "没有找到可终止的包管理器进程。"
    return
  fi

  warn "即将向占用包管理器的进程发送 SIGTERM。后果：正在进行的系统更新或安装会被中断，可能需要后续修复 dpkg/rpm/pacman 状态。"
  local pid
  for pid in $pids; do
    warn "SIGTERM PID $pid: $(pid_cmdline "$pid")"
    if ! send_signal_to_pid TERM "$pid"; then
      warn "无法终止 PID $pid，可能权限不足或进程已退出。"
    fi
  done

  sleep 5
  if ! package_manager_busy; then
    success "包管理器占用已释放。"
    return
  fi

  warn "发送 SIGTERM 后包管理器仍被占用。"
  if [[ "$HAS_TTY" -ne 1 ]]; then
    warn "无交互终端，不会发送 SIGKILL。"
    return
  fi

  local confirm
  confirm="$(prompt_line "  是否强制发送 SIGKILL？这可能破坏正在写入的包数据库。输入 KILL 确认，直接回车跳过: ")"
  if [[ "$confirm" != "KILL" ]]; then
    warn "已跳过 SIGKILL，继续等待或稍后退出。"
    return
  fi

  pids="$(package_manager_process_pids)"
  for pid in $pids; do
    warn "SIGKILL PID $pid: $(pid_cmdline "$pid")"
    if ! send_signal_to_pid KILL "$pid"; then
      warn "无法强制终止 PID $pid，可能权限不足或进程已退出。"
    fi
  done

  sleep 2
  if package_manager_busy; then
    warn "SIGKILL 后包管理器仍被占用，请手动检查进程和锁文件。"
  else
    success "包管理器占用已释放。"
  fi
}

package_manager_busy_details() {
  local details=""
  local processes
  processes="$(process_list_for_names || true)"
  if [[ -n "$processes" ]]; then
    details="${details}相关进程:\n${processes}\n"
  fi

  case "$PKG_MANAGER" in
    apt)
      local lock_details=""
      lock_details="$(
        lock_holder_details /var/lib/dpkg/lock-frontend
        lock_holder_details /var/lib/dpkg/lock
        lock_holder_details /var/cache/apt/archives/lock
      )"
      ;;
    dnf|yum)
      local lock_details=""
      lock_details="$(lock_holder_details /var/lib/rpm/.rpm.lock)"
      ;;
    pacman)
      local lock_details=""
      lock_details="$(lock_holder_details /var/lib/pacman/db.lck)"
      ;;
    *)
      local lock_details=""
      ;;
  esac

  if [[ -n "${lock_details:-}" ]]; then
    details="${details}锁文件占用:\n${lock_details}\n"
  fi

  if [[ -z "$details" ]]; then
    details="未能读取到具体占用进程；可能是包管理器短暂运行、权限限制或锁刚刚释放。"
  fi

  printf '%b' "$details"
}

print_package_manager_repair_options() {
  warn "修复选项:"
  warn "1. 继续等待系统更新结束。这是最安全的方式，后果是安装会晚几分钟完成。"
  warn "2. 另开终端查看占用: ps -ef | grep -E 'apt|dpkg|unattended|dnf|yum|rpm|pacman'。后果是只观察，不改变系统状态。"
  warn "3. 如果确认是 unattended-upgrades，可等待它结束；不建议强杀。强杀后果是可能留下 dpkg 半配置状态，需要运行 dpkg --configure -a 修复。"
  warn "4. 只有确认没有 apt/dpkg 进程时，才考虑清理陈旧锁。误删活锁的后果是破坏包数据库。"
}

prompt_package_manager_kill_option() {
  if [[ "$HAS_TTY" -ne 1 ]]; then
    warn "当前没有交互终端，不提供终止进程选项。"
    return
  fi

  warn "可选操作: [W]继续等待 / [T]终止占用进程(SIGTERM) / [Q]退出安装。默认 W。"
  local choice
  choice="$(prompt_line "  请选择 W/T/Q: ")"
  choice="$(printf '%s' "$choice" | tr '[:upper:]' '[:lower:]' | xargs 2>/dev/null || true)"

  case "$choice" in
    t|term|kill)
      terminate_package_manager_processes
      ;;
    q|quit|exit)
      die "用户选择退出安装。"
      ;;
    *)
      info "继续等待包管理器释放锁。"
      ;;
  esac
}

package_manager_busy() {
  case "$PKG_MANAGER" in
    apt)
      if pgrep -x apt >/dev/null 2>&1 || pgrep -x apt-get >/dev/null 2>&1 || pgrep -x dpkg >/dev/null 2>&1 || pgrep -x unattended-upgr >/dev/null 2>&1; then
        return 0
      fi
      process_holds_path /var/lib/dpkg/lock-frontend && return 0
      process_holds_path /var/lib/dpkg/lock && return 0
      ;;
    dnf|yum)
      if pgrep -x dnf >/dev/null 2>&1 || pgrep -x yum >/dev/null 2>&1 || pgrep -x rpm >/dev/null 2>&1; then
        return 0
      fi
      process_holds_path /var/lib/rpm/.rpm.lock && return 0
      ;;
    pacman)
      if pgrep -x pacman >/dev/null 2>&1; then
        return 0
      fi
      [[ -f /var/lib/pacman/db.lck ]] && process_holds_path /var/lib/pacman/db.lck && return 0
      ;;
  esac
  return 1
}

wait_for_package_manager_locks() {
  local waited=0
  local max_wait=120
  while package_manager_busy; do
    if [[ "$waited" -ge "$max_wait" ]]; then
      package_manager_busy_details | while IFS= read -r line; do
        [[ -n "$line" ]] && warn "$line"
      done
      print_package_manager_repair_options
      die "包管理器锁等待超过 ${max_wait} 秒。请关闭系统更新或其他安装进程后重试。"
    fi
    warn "包管理器正在被占用，等待 5 秒后重试...（已等待 ${waited}/${max_wait} 秒）"
    if [[ "$waited" -eq 0 || $((waited % 30)) -eq 0 ]]; then
      package_manager_busy_details | while IFS= read -r line; do
        [[ -n "$line" ]] && warn "$line"
      done
      prompt_package_manager_kill_option
    fi
    sleep 5
    waited=$((waited + 5))
  done
}

install_packages() {
  local packages=("$@")
  if [[ "${#packages[@]}" -eq 0 ]]; then
    return
  fi

  if [[ "$IS_ROOT" -ne 1 && -z "$SUDO_CMD" ]]; then
    die "缺少 sudo，无法安装系统依赖: ${packages[*]}。请先安装 sudo 或以 root 运行。"
  fi

  wait_for_package_manager_locks
  case "$PKG_MANAGER" in
    apt)
      run_as_root env DEBIAN_FRONTEND=noninteractive apt-get update
      run_as_root env DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends "${packages[@]}"
      ;;
    dnf)
      run_as_root dnf install -y "${packages[@]}"
      ;;
    yum)
      run_as_root yum install -y "${packages[@]}"
      ;;
    pacman)
      run_as_root pacman -Sy --needed --noconfirm "${packages[@]}"
      ;;
    *)
      die "不支持的包管理器: $PKG_MANAGER"
      ;;
  esac
}

ensure_base_dependencies() {
  step "安装基础依赖"

  case "$PKG_MANAGER" in
    apt)
      install_packages git curl wget ca-certificates tar gzip xz-utils sudo gnupg lsb-release iputils-ping
      ;;
    dnf|yum)
      install_packages git curl wget ca-certificates tar gzip xz sudo iputils
      ;;
    pacman)
      install_packages git curl wget ca-certificates tar gzip xz sudo iputils
      ;;
  esac

  local missing=()
  for cmd in git curl wget tar gzip; do
    command_exists "$cmd" || missing+=("$cmd")
  done
  if [[ "${#missing[@]}" -gt 0 ]]; then
    die "基础依赖安装后仍缺少命令: ${missing[*]}"
  fi
  success "基础依赖已就绪。"
}

node_major_version() {
  if ! command_exists node; then
    echo 0
    return
  fi
  local major
  major="$(node --version 2>/dev/null | sed -E 's/^v([0-9]+).*/\1/' | head -n 1)"
  if [[ "$major" =~ ^[0-9]+$ ]]; then
    echo "$major"
  else
    echo 0
  fi
}

npm_available() {
  command_exists npm
}

node_is_package_managed() {
  local node_path
  node_path="$(command -v node 2>/dev/null || true)"
  [[ -n "$node_path" ]] || return 1
  case "$PKG_MANAGER" in
    apt)
      dpkg -S "$node_path" >/dev/null 2>&1 || dpkg-query -W nodejs >/dev/null 2>&1
      ;;
    dnf|yum)
      rpm -qf "$node_path" >/dev/null 2>&1
      ;;
    pacman)
      pacman -Qo "$node_path" >/dev/null 2>&1
      ;;
    *)
      return 1
      ;;
  esac
}

apt_node_removal_is_safe() {
  local simulation
  simulation="$(LC_ALL=C apt-get -s remove nodejs npm 2>/dev/null || true)"
  local removals
  removals="$(printf '%s\n' "$simulation" | awk '/^Remv / {print $2}')"
  if [[ -z "$removals" ]]; then
    return 1
  fi

  local count=0
  local package
  while IFS= read -r package; do
    [[ -z "$package" ]] && continue
    count=$((count + 1))
    if [[ ! "$package" =~ ^(nodejs|npm|libnode[0-9]*|nodejs-doc|node-abbrev|node-acorn|node-agent-base|node-ajv|node-ansi|node-archy|node-are-we-there-yet|node-asap|node-balanced-match|node-brace-expansion|node-builtins|node-cacache|node-chalk|node-cli-table|node-clone|node-color|node-columnify|node-console-control-strings|node-copy-concurrently|node-core-util-is|node-debug|node-defaults|node-delayed-stream|node-delegates|node-depd|node-encoding|node-events|node-fs-write-stream-atomic|node-glob|node-graceful-fs|node-gyp|node-hosted-git-info|node-iferr|node-imurmurhash|node-inflight|node-inherits|node-ini|node-ip|node-ip-regex|node-json-parse-better-errors|node-jsonparse|node-lru-cache|node-minimatch|node-minipass|node-mkdirp|node-move-concurrently|node-ms|node-mute-stream|node-negotiator|node-nopt|node-normalize-package-data|node-npm-bundled|node-npm-package-arg|node-npmlog|node-once|node-opener|node-osenv|node-p-map|node-path-is-absolute|node-process-nextick-args|node-promise-inflight|node-promise-retry|node-promzard|node-read|node-read-package-json|node-readable-stream|node-resolve|node-retry|node-rimraf|node-safe-buffer|node-semver|node-set-blocking|node-signal-exit|node-slash|node-slice-ansi|node-source-map|node-spdx|node-ssri|node-string-decoder|node-strip-ansi|node-tar|node-text-table|node-unique-filename|node-util-deprecate|node-validate-npm-package-name|node-which|node-wide-align|node-wrappy|node-yallist)$ ]]; then
      warn "Node 卸载模拟包含非 Node/npm 直接相关包: $package"
      return 1
    fi
  done <<< "$removals"

  [[ "$count" -le 80 ]]
}

try_remove_package_managed_node() {
  step "处理低版本 Node.js"

  if ! node_is_package_managed; then
    warn "当前 Node.js 来源不是系统包管理器，保持原环境不变，改用用户级 Node.js ${NODE_VERSION}。"
    return 1
  fi

  case "$PKG_MANAGER" in
    apt)
      if ! apt_node_removal_is_safe; then
        warn "Node.js 卸载影响无法确认安全，跳过卸载，改用用户级 Node.js。"
        return 1
      fi
      wait_for_package_manager_locks
      run_as_root env DEBIAN_FRONTEND=noninteractive apt-get remove -y nodejs npm || return 1
      ;;
    dnf)
      warn "dnf 环境下不自动卸载低版本 Node.js，以避免误删依赖；改用用户级 Node.js。"
      return 1
      ;;
    yum)
      warn "yum 环境下不自动卸载低版本 Node.js，以避免误删依赖；改用用户级 Node.js。"
      return 1
      ;;
    pacman)
      warn "pacman 环境下不自动卸载低版本 Node.js，以避免误删依赖；改用用户级 Node.js。"
      return 1
      ;;
  esac

  success "已移除低版本 Node.js/npm。"
  return 0
}

try_install_node_from_package_manager() {
  step "尝试通过系统包管理器安装 Node.js"
  case "$PKG_MANAGER" in
    apt)
      install_packages nodejs npm
      ;;
    dnf|yum)
      install_packages nodejs npm
      ;;
    pacman)
      install_packages nodejs npm
      ;;
  esac

  local major
  major="$(node_major_version)"
  if [[ "$major" -ge 20 ]] && npm_available; then
    success "系统 Node.js 已满足要求: $(node --version)"
    return 0
  fi

  if [[ "$major" -gt 0 && "$major" -lt 20 ]]; then
    warn "系统包管理器安装的 Node.js 仍低于 20，将尝试受保护卸载后改用用户级 Node.js。"
    try_remove_package_managed_node || true
  fi

  warn "系统包管理器未能提供 Node.js 20+，将安装用户级 Node.js。"
  return 1
}

download_file() {
  local url="$1"
  local output="$2"
  if command_exists curl; then
    curl -fL --connect-timeout 10 --retry 2 --retry-delay 2 -o "$output" "$url"
  elif command_exists wget; then
    wget -O "$output" "$url"
  else
    return 1
  fi
}

install_user_node() {
  step "安装用户级 Node.js ${NODE_VERSION}"

  local tarball="node-${NODE_VERSION}-linux-${NODE_ARCH}.tar.xz"
  local tmp_dir
  tmp_dir="$(mktemp -d)"
  local archive="${tmp_dir}/${tarball}"
  local mirror_url="${NODE_MIRROR}/${NODE_VERSION}/${tarball}"
  local official_url="${NODE_OFFICIAL}/${NODE_VERSION}/${tarball}"

  info "正在下载 Node.js: $mirror_url"
  if ! download_file "$mirror_url" "$archive"; then
    warn "Node.js 镜像下载失败，回退官方地址。"
    download_file "$official_url" "$archive" || die "Node.js 下载失败。"
  fi

  rm -rf "$MAXAPI_NODE_DIR"
  mkdir -p "$MAXAPI_NODE_ROOT" "$MAXAPI_BIN"
  tar -xJf "$archive" -C "$MAXAPI_NODE_ROOT"
  mv "${MAXAPI_NODE_ROOT}/node-${NODE_VERSION}-linux-${NODE_ARCH}" "$MAXAPI_NODE_DIR"
  ln -sf "${MAXAPI_NODE_DIR}/bin/node" "${MAXAPI_BIN}/node"
  ln -sf "${MAXAPI_NODE_DIR}/bin/npm" "${MAXAPI_BIN}/npm"
  ln -sf "${MAXAPI_NODE_DIR}/bin/npx" "${MAXAPI_BIN}/npx"
  rm -rf "$tmp_dir"

  export PATH="${MAXAPI_BIN}:${PATH}"
  success "用户级 Node.js 已安装: $("$MAXAPI_BIN/node" --version)"
}

ensure_node() {
  step "检测 Node.js"
  export PATH="${MAXAPI_BIN}:${NPM_PREFIX}/bin:${PATH}"

  local major
  major="$(node_major_version)"
  if [[ "$major" -ge 20 ]] && npm_available; then
    success "Node.js 已安装: $(node --version)（满足 >=20 要求）"
    return
  fi

  if [[ "$major" -gt 0 ]]; then
    warn "Node.js 版本过低: $(node --version 2>/dev/null || true)。需要 Node.js 20+。"
    try_remove_package_managed_node || true
  else
    info "未检测到 Node.js。"
  fi

  if try_install_node_from_package_manager; then
    return
  fi

  install_user_node

  major="$(node_major_version)"
  if [[ "$major" -lt 20 ]] || ! npm_available; then
    die "Node.js 安装后仍不可用或版本不足。"
  fi
}

configure_user_npm() {
  step "配置用户级 npm"

  mkdir -p "$NPM_PREFIX" "$MAXAPI_BIN"
  export PATH="${MAXAPI_BIN}:${NPM_PREFIX}/bin:${PATH}"

  if ! command_exists npm; then
    die "未检测到 npm。"
  fi

  npm config set prefix "$NPM_PREFIX" --location=user >/dev/null 2>&1 || npm config set prefix "$NPM_PREFIX" >/dev/null
  npm config set registry "$NPM_MIRROR" --location=user >/dev/null 2>&1 || npm config set registry "$NPM_MIRROR" >/dev/null

  local current_prefix
  current_prefix="$(npm config get prefix 2>/dev/null || true)"
  if [[ "$current_prefix" != "$NPM_PREFIX" ]]; then
    warn "npm prefix 未能持久化为 $NPM_PREFIX，当前进程仍会优先使用该目录。"
    export npm_config_prefix="$NPM_PREFIX"
  fi

  success "npm 用户级安装目录: $NPM_PREFIX"
  success "npm registry: $(npm config get registry 2>/dev/null || echo "$NPM_MIRROR")"
}

prompt_line() {
  local prompt="$1"
  local value
  printf '%s' "$prompt" > /dev/tty
  IFS= read -r value < /dev/tty
  printf '%s' "$value"
}

prompt_secret() {
  local prompt="$1"
  local value
  printf '%s' "$prompt" > /dev/tty
  IFS= read -r -s value < /dev/tty
  printf '\n' > /dev/tty
  printf '%s' "$value"
}

show_tool_menu() {
  step "选择要安装的工具"
  cat >/dev/tty <<'EOF'

  [1] Claude Code
  [2] Codex CLI
  [3] Gemini CLI

  [A] 全部安装

EOF

  local choice item selected
  while true; do
    choice="$(prompt_line "  请输入选项（例如：1,3 或 A）: ")"
    choice="$(printf '%s' "$choice" | tr '[:lower:]' '[:upper:]' | xargs)"
    selected=""
    if [[ "$choice" == "A" ]]; then
      SELECTED_TOOLS="claude codex gemini"
      return
    fi

    local valid=1
    for item in $(printf '%s' "$choice" | tr ',，' '  '); do
      case "$item" in
        1) selected="${selected} claude" ;;
        2) selected="${selected} codex" ;;
        3) selected="${selected} gemini" ;;
        *) valid=0 ;;
      esac
    done

    selected="$(printf '%s' "$selected" | xargs -n1 2>/dev/null | awk '!seen[$0]++' | xargs 2>/dev/null || true)"
    if [[ "$valid" -eq 1 && -n "$selected" ]]; then
      SELECTED_TOOLS="$selected"
      return
    fi

    warn "无效选项。请输入 1-3，可用逗号分隔多选，或输入 A 表示全部安装。"
  done
}

read_api_key() {
  step "配置 API Key"
  printf '\n  请输入来自 MAX API 的 API Key\n  输入内容不会显示，这是正常现象。\n\n' > /dev/tty
  while true; do
    API_KEY="$(prompt_secret "  API Key: ")"
    if [[ -z "$API_KEY" ]]; then
      warn "API Key 不能为空。"
      continue
    fi
    if [[ "${#API_KEY}" -lt 8 ]]; then
      warn "API Key 看起来过短，请检查后重新输入。"
      continue
    fi
    return
  done
}

route_host() {
  local url="$1"
  printf '%s' "$url" | sed -E 's#^https?://([^/]+).*#\1#'
}

ping_route_score() {
  local host="$1"
  if ! command_exists ping; then
    echo "100000"
    return
  fi

  local output received avg loss
  output="$(ping -c 3 -W 2 "$host" 2>/dev/null || true)"
  received="$(printf '%s\n' "$output" | awk -F',' '/packets transmitted/ {gsub(/[^0-9]/, "", $2); print $2}')"
  loss="$(printf '%s\n' "$output" | awk -F',' '/packet loss/ {gsub(/[^0-9.]/, "", $3); print int($3)}')"
  avg="$(printf '%s\n' "$output" | awk -F'/' '/rtt|round-trip/ {print int($5)}')"
  [[ -n "$received" ]] || received=0
  [[ -n "$loss" ]] || loss=100
  [[ -n "$avg" ]] || avg=9999
  echo $((loss * 1000 + avg))
}

http_route_score() {
  local url="$1"
  if ! command_exists curl; then
    echo "100000"
    return
  fi

  local metrics code time_ms
  metrics="$(curl -o /dev/null -sS -w '%{http_code} %{time_total}' --max-time 8 "$url" 2>/dev/null || true)"
  code="$(printf '%s' "$metrics" | awk '{print $1}')"
  time_ms="$(printf '%s' "$metrics" | awk '{printf "%d", $2 * 1000}')"
  [[ -n "$time_ms" ]] || time_ms=9999
  if [[ "$code" == "000" || -z "$code" ]]; then
    echo "100000"
  else
    echo "$time_ms"
  fi
}

select_maxapi_route() {
  step "检测 MAX API 线路"

  local host1 host2 ping1 ping2 http1 http2 total1 total2
  host1="$(route_host "$API_BASE_URL_CANDIDATE_1")"
  host2="$(route_host "$API_BASE_URL_CANDIDATE_2")"

  info "正在检测 $API_BASE_URL_CANDIDATE_1_NAME: $host1"
  ping1="$(ping_route_score "$host1")"
  http1="$(http_route_score "$API_BASE_URL_CANDIDATE_1")"
  total1=$((ping1 + http1))
  info "$API_BASE_URL_CANDIDATE_1_NAME 分数: ping=$ping1 http=$http1 total=$total1"

  info "正在检测 $API_BASE_URL_CANDIDATE_2_NAME: $host2"
  ping2="$(ping_route_score "$host2")"
  http2="$(http_route_score "$API_BASE_URL_CANDIDATE_2")"
  total2=$((ping2 + http2))
  info "$API_BASE_URL_CANDIDATE_2_NAME 分数: ping=$ping2 http=$http2 total=$total2"

  if [[ "$total2" -lt "$total1" ]]; then
    API_BASE_URL="$API_BASE_URL_CANDIDATE_2"
    API_ROUTE_NAME="$API_BASE_URL_CANDIDATE_2_NAME"
  else
    API_BASE_URL="$API_BASE_URL_CANDIDATE_1"
    API_ROUTE_NAME="$API_BASE_URL_CANDIDATE_1_NAME"
  fi

  ROUTE_SUMMARY="${API_ROUTE_NAME} (${API_BASE_URL})"
  success "已选择 MAX API 线路: $ROUTE_SUMMARY"
}

json_update_claude() {
  local path="$1"
  mkdir -p "$(dirname "$path")"
  API_KEY_ENV="$API_KEY" API_BASE_URL_ENV="$API_BASE_URL" CLAUDE_MODEL_ENV="$CLAUDE_MODEL" CONFIG_PATH_ENV="$path" node <<'NODE'
const fs = require('fs');
const path = process.env.CONFIG_PATH_ENV;
let data = {};
try {
  if (fs.existsSync(path)) {
    const raw = fs.readFileSync(path, 'utf8').trim();
    if (raw) data = JSON.parse(raw);
  }
} catch (_) {
  data = {};
}
data.env = data.env && typeof data.env === 'object' ? data.env : {};
data.env.ANTHROPIC_MODEL = process.env.CLAUDE_MODEL_ENV;
data.env.ANTHROPIC_API_KEY = process.env.API_KEY_ENV;
data.env.ANTHROPIC_AUTH_TOKEN = process.env.API_KEY_ENV;
data.env.ANTHROPIC_BASE_URL = process.env.API_BASE_URL_ENV;
fs.writeFileSync(path, JSON.stringify(data, null, 2) + '\n');
NODE
}

json_update_gemini() {
  local path="$1"
  mkdir -p "$(dirname "$path")"
  GEMINI_MODEL_ENV="$GEMINI_MODEL" CONFIG_PATH_ENV="$path" node <<'NODE'
const fs = require('fs');
const path = process.env.CONFIG_PATH_ENV;
let data = {};
try {
  if (fs.existsSync(path)) {
    const raw = fs.readFileSync(path, 'utf8').trim();
    if (raw) data = JSON.parse(raw);
  }
} catch (_) {
  data = {};
}
data.model = data.model && typeof data.model === 'object' ? data.model : {};
data.model.name = process.env.GEMINI_MODEL_ENV;
data.security = data.security && typeof data.security === 'object' ? data.security : {};
data.security.auth = data.security.auth && typeof data.security.auth === 'object' ? data.security.auth : {};
data.security.auth.selectedType = 'gemini-api-key';
data.security.auth.enforcedType = 'gemini-api-key';
fs.writeFileSync(path, JSON.stringify(data, null, 2) + '\n');
NODE
}

backup_file_if_exists() {
  local path="$1"
  if [[ -f "$path" ]]; then
    local backup="${path}.bak.$(date +%Y%m%d-%H%M%S)"
    cp "$path" "$backup"
    info "已备份现有文件: $backup"
  fi
}

toml_escape() {
  printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

write_codex_config() {
  local path="$1"
  mkdir -p "$(dirname "$path")"
  local existing=""
  local filtered=""
  if [[ -f "$path" ]]; then
    existing="$(cat "$path")"
    filtered="$(printf '%s\n' "$existing" | awk '
      BEGIN { skip=0; seen_section=0 }
      /^[[:space:]]*\[/ {
        seen_section=1
        section=tolower($0)
        if (section ~ /^[[:space:]]*\[model_providers\.maxapi\][[:space:]]*$/) {
          skip=1
          next
        }
        skip=0
        print
        next
      }
      skip { next }
      !seen_section && /^[[:space:]]*(model|model_provider|openai_base_url)[[:space:]]*=/ { next }
      { print }
    ' | sed '/^[[:space:]]*$/N;/^\n$/D')"
  fi

  local escaped_key escaped_base
  escaped_key="$(toml_escape "$API_KEY")"
  escaped_base="$(toml_escape "${API_BASE_URL}/v1")"

  {
    printf '# Codex CLI 配置 - 由 MAX API Linux 安装器生成\n'
    printf 'model = "%s"\n' "$CODEX_MODEL"
    printf 'model_provider = "maxapi"\n\n'
    if [[ -n "$(printf '%s' "$filtered" | xargs 2>/dev/null || true)" ]]; then
      printf '%s\n\n' "$filtered"
    fi
    printf '[model_providers.maxapi]\n'
    printf 'name = "MAX API"\n'
    printf 'base_url = "%s"\n' "$escaped_base"
    printf 'wire_api = "responses"\n'
    printf 'experimental_bearer_token = "%s"\n' "$escaped_key"
  } > "$path"
}

tool_upper() {
  case "$1" in
    claude) echo "CLAUDE" ;;
    codex) echo "CODEX" ;;
    gemini) echo "GEMINI" ;;
    *) echo "$1" | tr '[:lower:]' '[:upper:]' ;;
  esac
}

set_tool_field() {
  local tool="$1"
  local field="$2"
  local value="$3"
  local upper
  upper="$(tool_upper "$tool")"
  printf -v "${upper}_${field}" '%s' "$value"
}

append_tool_warning() {
  local tool="$1"
  local message="$2"
  local upper existing
  upper="$(tool_upper "$tool")"
  eval "existing=\"\${${upper}_WARNING}\""
  if [[ -n "$existing" ]]; then
    message="${existing}; ${message}"
  fi
  set_tool_field "$tool" "WARNING" "$message"
  warn "$message"
}

tool_display_name() {
  case "$1" in
    claude) echo "Claude Code" ;;
    codex) echo "Codex CLI" ;;
    gemini) echo "Gemini CLI" ;;
    *) echo "$1" ;;
  esac
}

tool_command_name() {
  case "$1" in
    claude) echo "claude" ;;
    codex) echo "codex" ;;
    gemini) echo "gemini" ;;
  esac
}

install_npm_package_with_fallback() {
  local display="$1"
  local package="$2"
  local primary_registry="$3"
  local fallback_registry="$4"

  info "正在安装 $display: $package"
  if npm install -g "$package" --registry="$primary_registry"; then
    return 0
  fi

  warn "$display 使用首选 npm 源安装失败，正在切换备用源。"
  npm install -g "$package" --registry="$fallback_registry"
}

validate_tool_version() {
  local command_name="$1"
  local version
  if ! command_exists "$command_name"; then
    return 1
  fi
  version="$("$command_name" --version 2>&1 | head -n 1 || true)"
  [[ -n "$version" ]] || return 1
  printf '%s' "$version"
}

output_snippet() {
  local text
  text="$(printf '%s' "${1:-}" | tr '\n' ' ' | sed 's/[[:space:]]\+/ /g; s/^[[:space:]]//; s/[[:space:]]$//')"
  if [[ -z "$text" ]]; then
    return
  fi

  if [[ "${#text}" -le 360 ]]; then
    printf '%s' "$text"
    return
  fi

  printf '%s ... %s' "${text:0:180}" "${text: -180}"
}

install_tool() {
  local tool="$1"
  local display package command_name primary fallback config_path version
  display="$(tool_display_name "$tool")"
  command_name="$(tool_command_name "$tool")"

  case "$tool" in
    claude)
      package="@anthropic-ai/claude-code"
      primary="$NPM_OFFICIAL"
      fallback="$NPM_MIRROR"
      config_path="${HOME}/.claude/settings.json"
      ;;
    codex)
      package="@openai/codex"
      primary="$NPM_MIRROR"
      fallback="$NPM_OFFICIAL"
      config_path="${HOME}/.codex/config.toml"
      ;;
    gemini)
      package="@google/gemini-cli"
      primary="$NPM_MIRROR"
      fallback="$NPM_OFFICIAL"
      config_path="${HOME}/.gemini/settings.json"
      ;;
    *)
      return 1
      ;;
  esac

  step "安装 $display"
  if version="$(validate_tool_version "$command_name")"; then
    info "$display 已安装: $version，将刷新到最新版本。"
  fi

  if ! install_npm_package_with_fallback "$display" "$package" "$primary" "$fallback"; then
    set_tool_field "$tool" "STATUS" "失败"
    set_tool_field "$tool" "FAILURE" "$display 的 npm 安装失败。"
    err "$display 的 npm 安装失败。"
    return
  fi

  hash -r
  version="$(validate_tool_version "$command_name" || true)"
  if [[ -z "$version" ]]; then
    set_tool_field "$tool" "STATUS" "部分成功"
    set_tool_field "$tool" "FAILURE" "$display 已安装，但 --version 验证失败。"
    err "$display 已安装，但 --version 验证失败。"
    return
  fi

  set_tool_field "$tool" "VERSION" "$version"
  success "$display 安装完成: $version"

  info "正在写入 $display 配置。"
  backup_file_if_exists "$config_path"
  case "$tool" in
    claude)
      json_update_claude "$config_path"
      ;;
    codex)
      write_codex_config "$config_path"
      ;;
    gemini)
      json_update_gemini "$config_path"
      ;;
  esac

  set_tool_field "$tool" "CONFIG" "$config_path"
  set_tool_field "$tool" "STATUS" "已安装"
  success "$display 配置已写入: $config_path"
}

remove_managed_block_from_file() {
  local file="$1"
  [[ -f "$file" ]] || return 0
  local tmp
  tmp="$(mktemp)"
  awk -v start="$SHELL_BLOCK_START" -v end="$SHELL_BLOCK_END" '
    $0 == start { skip=1; next }
    $0 == end { skip=0; next }
    !skip { print }
  ' "$file" > "$tmp"
  if ! cmp -s "$file" "$tmp"; then
    backup_file_if_exists "$file"
    mv "$tmp" "$file"
    success "已更新 shell 配置: $file"
  else
    rm -f "$tmp"
  fi
}

current_shell_rc_file() {
  local shell_name
  shell_name="$(basename "${SHELL:-}")"
  case "$shell_name" in
    bash) echo "${HOME}/.bashrc" ;;
    zsh) echo "${HOME}/.zshrc" ;;
    fish) echo "${HOME}/.config/fish/config.fish" ;;
    *) echo "" ;;
  esac
}

write_shell_profile_block() {
  step "写入 shell 持久化配置"

  local block
  block="$(cat <<EOF
$SHELL_BLOCK_START
export PATH="\$HOME/.maxapi/bin:\$HOME/.maxapi/npm-global/bin:\$PATH"
export GEMINI_API_KEY="$(printf '%s' "$API_KEY" | sed 's/\\/\\\\/g; s/"/\\"/g')"
export GOOGLE_GEMINI_BASE_URL="$API_BASE_URL"
$SHELL_BLOCK_END
EOF
)"

  local files=("${HOME}/.profile")
  local shell_rc
  shell_rc="$(current_shell_rc_file)"
  if [[ -n "$shell_rc" && "$shell_rc" != "${HOME}/.profile" ]]; then
    if [[ "$(basename "${SHELL:-}")" == "fish" ]]; then
      warn "检测到 fish shell，v1 不自动写入 fish 配置。可手动执行: set -Ux GEMINI_API_KEY '****'; set -Ux GOOGLE_GEMINI_BASE_URL '$API_BASE_URL'"
    else
      files+=("$shell_rc")
    fi
  fi

  local file
  for file in "${files[@]}"; do
    mkdir -p "$(dirname "$file")"
    touch "$file"
    remove_managed_block_from_file "$file"
    {
      printf '\n%s\n' "$block"
    } >> "$file"
    success "已写入 MAX API shell 标记块: $file"
  done

  export PATH="${MAXAPI_BIN}:${NPM_PREFIX}/bin:${PATH}"
  export GEMINI_API_KEY="$API_KEY"
  export GOOGLE_GEMINI_BASE_URL="$API_BASE_URL"
}

remove_shell_blocks() {
  step "清理 shell 持久化配置"
  local files=("${HOME}/.profile" "${HOME}/.bashrc" "${HOME}/.zshrc")
  local file
  for file in "${files[@]}"; do
    remove_managed_block_from_file "$file"
  done
  if [[ -f "${HOME}/.config/fish/config.fish" ]]; then
    remove_managed_block_from_file "${HOME}/.config/fish/config.fish"
  fi
}

smoke_prompt() {
  printf 'This is a post-install connectivity check. Do not use tools. What is 17 multiplied by 19? Reply with only the number.'
}

run_tool_actual_call() {
  local tool="$1"
  local command_name display workspace output_file raw_output code
  command_name="$(tool_command_name "$tool")"
  display="$(tool_display_name "$tool")"
  workspace="$(mktemp -d)"
  output_file=""
  raw_output=""

  if ! command_exists "$command_name"; then
    set_tool_field "$tool" "SMOKE" "失败: 未找到命令"
    append_tool_warning "$tool" "$display 实际调用测试失败: 未找到命令。"
    rm -rf "$workspace"
    return
  fi

  step "实际调用测试: $display"
  set +e
  case "$tool" in
    claude)
      raw_output="$(cd "$workspace" && timeout 120 "$command_name" -p "$(smoke_prompt)" --output-format text --permission-mode plan --tools "" --no-session-persistence 2>&1)"
      code=$?
      ;;
    codex)
      output_file="${workspace}/codex-last-message.txt"
      raw_output="$(cd "$workspace" && timeout 120 "$command_name" exec --skip-git-repo-check --ephemeral --color never -o "$output_file" "$(smoke_prompt)" 2>&1)"
      code=$?
      if [[ -s "$output_file" ]]; then
        raw_output="$(cat "$output_file")"
      fi
      ;;
    gemini)
      raw_output="$(cd "$workspace" && timeout 120 "$command_name" -p "$(smoke_prompt)" --output-format text 2>&1)"
      code=$?
      ;;
    *)
      code=1
      ;;
  esac
  set -e

  raw_output="$(redact_text "$raw_output")"
  rm -rf "$workspace"

  if [[ "$code" -eq 124 ]]; then
    set_tool_field "$tool" "SMOKE" "失败: 超时"
    append_tool_warning "$tool" "$display 实际调用测试 120 秒超时。"
    return
  fi

  if [[ "$code" -ne 0 ]]; then
    set_tool_field "$tool" "SMOKE" "失败"
    append_tool_warning "$tool" "$display 实际调用测试失败，退出码 $code。输出摘要: $(output_snippet "$raw_output")"
    return
  fi

  if [[ "$raw_output" =~ 323 ]]; then
    set_tool_field "$tool" "SMOKE" "成功"
    success "$display 实际调用成功。"
  else
    set_tool_field "$tool" "SMOKE" "失败: 返回不符合预期"
    append_tool_warning "$tool" "$display 实际调用返回内容不包含 323。输出摘要: $(output_snippet "$raw_output")"
  fi
}

run_actual_call_tests() {
  step "最终实际调用测试"
  info "将对每个已选择的工具发起一次极小的真实请求，以验证 API 连通性。"
  local tool
  for tool in $SELECTED_TOOLS; do
    local upper status
    upper="$(tool_upper "$tool")"
    eval "status=\"\${${upper}_STATUS}\""
    if [[ "$status" == "已安装" || "$MODE" == "repair" ]]; then
      run_tool_actual_call "$tool"
    fi
  done
}

print_tool_summary() {
  local tool="$1"
  local display upper status version config smoke warning failure
  display="$(tool_display_name "$tool")"
  upper="$(tool_upper "$tool")"
  eval "status=\"\${${upper}_STATUS}\""
  eval "version=\"\${${upper}_VERSION}\""
  eval "config=\"\${${upper}_CONFIG}\""
  eval "smoke=\"\${${upper}_SMOKE}\""
  eval "warning=\"\${${upper}_WARNING}\""
  eval "failure=\"\${${upper}_FAILURE}\""

  printf '  %s: %s\n' "$display" "$status"
  [[ -n "$version" ]] && printf '    版本: %s\n' "$version"
  [[ -n "$config" ]] && printf '    配置: %s\n' "$config"
  [[ -n "$smoke" ]] && printf '    实际调用: %s\n' "$smoke"
  [[ -n "$warning" ]] && printf '    警告: %s\n' "$(redact_text "$warning")"
  [[ -n "$failure" ]] && printf '    原因: %s\n' "$(redact_text "$failure")"
}

show_summary() {
  step "安装结果汇总"
  printf '  日志文件: %s\n' "$LOG_FILE"
  printf '  安装目录: %s\n' "$MAXAPI_ROOT"
  [[ -n "$ROUTE_SUMMARY" ]] && printf '  MAX API 线路: %s\n' "$ROUTE_SUMMARY"
  printf '\n'

  local tool
  for tool in claude codex gemini; do
    print_tool_summary "$tool"
  done

  printf '\n'
  printf '  使用方法:\n'
  for tool in $SELECTED_TOOLS; do
    printf '    %s\n' "$(tool_command_name "$tool")"
  done
  printf '\n'
  printf '  如果命令未找到，请重新打开终端，或执行: source ~/.profile\n'
}

configure_selected_tools_only() {
  local tool config_path version command_name
  for tool in $SELECTED_TOOLS; do
    command_name="$(tool_command_name "$tool")"
    version="$(validate_tool_version "$command_name" || true)"
    if [[ -n "$version" ]]; then
      set_tool_field "$tool" "VERSION" "$version"
      set_tool_field "$tool" "STATUS" "已安装"
    else
      set_tool_field "$tool" "STATUS" "失败"
      set_tool_field "$tool" "FAILURE" "$(tool_display_name "$tool") 命令不可用。"
      continue
    fi

    case "$tool" in
      claude)
        config_path="${HOME}/.claude/settings.json"
        backup_file_if_exists "$config_path"
        json_update_claude "$config_path"
        ;;
      codex)
        config_path="${HOME}/.codex/config.toml"
        backup_file_if_exists "$config_path"
        write_codex_config "$config_path"
        ;;
      gemini)
        config_path="${HOME}/.gemini/settings.json"
        backup_file_if_exists "$config_path"
        json_update_gemini "$config_path"
        ;;
    esac
    set_tool_field "$tool" "CONFIG" "$config_path"
    success "$(tool_display_name "$tool") 配置已修复: $config_path"
  done
}

run_install_flow() {
  banner
  preflight
  ensure_base_dependencies
  ensure_node
  configure_user_npm
  show_tool_menu
  info "已选择: $SELECTED_TOOLS"
  read_api_key
  select_maxapi_route

  local tool
  for tool in $SELECTED_TOOLS; do
    install_tool "$tool"
  done

  write_shell_profile_block
  run_actual_call_tests
  show_summary
}

run_repair_flow() {
  banner
  preflight
  ensure_base_dependencies
  ensure_node
  configure_user_npm
  show_tool_menu
  info "已选择修复: $SELECTED_TOOLS"
  read_api_key
  select_maxapi_route
  configure_selected_tools_only
  write_shell_profile_block
  run_actual_call_tests
  show_summary
}

run_uninstall_flow() {
  banner
  preflight
  step "卸载 MAX API 管理内容"

  if [[ "$HAS_TTY" -eq 1 ]]; then
    local answer
    answer="$(prompt_line "  将移除 MAX API shell 标记块和 ~/.maxapi 中的 Node/npm 运行时，是否继续？[y/N]: ")"
    case "$(printf '%s' "$answer" | tr '[:upper:]' '[:lower:]')" in
      y|yes) ;;
      *) info "已取消卸载。"; return ;;
    esac
  fi

  export PATH="${MAXAPI_BIN}:${NPM_PREFIX}/bin:${PATH}"
  if command_exists npm; then
    npm uninstall -g @anthropic-ai/claude-code @openai/codex @google/gemini-cli >/dev/null 2>&1 || warn "npm 包卸载未完全成功，继续清理 MAX API 目录。"
  fi

  remove_shell_blocks
  rm -rf "$NPM_PREFIX" "$MAXAPI_NODE_ROOT"
  rm -f "${MAXAPI_BIN}/node" "${MAXAPI_BIN}/npm" "${MAXAPI_BIN}/npx"
  rmdir "$MAXAPI_BIN" 2>/dev/null || true
  success "已清理 MAX API 管理的 Node/npm 运行时。日志目录保留在: $MAXAPI_LOG_DIR"
}

main() {
  parse_args "$@"
  ensure_bash_version
  setup_paths_and_logging
  trap cleanup EXIT
  acquire_lock

  case "$MODE" in
    install) run_install_flow ;;
    repair) run_repair_flow ;;
    uninstall) run_uninstall_flow ;;
    *) die "未知运行模式: $MODE" ;;
  esac
}

main "$@"
