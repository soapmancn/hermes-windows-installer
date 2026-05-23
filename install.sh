#!/bin/bash
# ============================================================================
# Hermes Agent 安装器（中国大陆镜像版）
# ============================================================================
# Installation script for Linux, macOS, and Android/Termux.
# Prefers CNB.cool Git mirror first, then falls back to source archives / upstream.
#
# Usage:
#   curl -fsSL https://res1.hermesagent.org.cn/install.sh | bash
#
# Or with options:
#   curl -fsSL https://res1.hermesagent.org.cn/install.sh | bash -s -- --skip-setup
#   curl -fsSL https://res1.hermesagent.org.cn/install.sh | bash -s -- --with-browser
#
# ============================================================================

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'
BOLD='\033[1m'

# Base configuration
MIRROR_BASE_URL="${HERMES_MIRROR_BASE_URL:-https://res1.hermesagent.org.cn}"
UPSTREAM_REPO_URL="https://github.com/NousResearch/hermes-agent.git"
UPSTREAM_TARBALL_BASE="https://github.com/NousResearch/hermes-agent/archive/refs/heads"
DEFAULT_GIT_MIRROR_URL="https://cnb.cool/hermesagent-cn/hermes-agent-cn-mirror.git"
GIT_MIRROR_URL="${HERMES_GIT_MIRROR_URL:-$DEFAULT_GIT_MIRROR_URL}"

HERMES_HOME="$HOME/.hermes"
INSTALL_DIR="${HERMES_INSTALL_DIR:-$HERMES_HOME/hermes-agent}"
PYTHON_VERSION="3.11"
NODE_VERSION="24"
AGENT_BROWSER_VERSION="${HERMES_AGENT_BROWSER_VERSION:-0.14.0}"

PIP_INDEX_URL_DEFAULT="${HERMES_PIP_INDEX_URL:-https://pypi.tuna.tsinghua.edu.cn/simple}"
PIP_FALLBACK_INDEX_URLS_DEFAULT="${HERMES_PIP_FALLBACK_INDEX_URLS:-https://mirrors.aliyun.com/pypi/simple https://pypi.mirrors.ustc.edu.cn/simple https://pypi.org/simple}"
NPM_REGISTRY_DEFAULT="${HERMES_NPM_REGISTRY:-https://registry.npmmirror.com}"
NODE_DIST_MIRROR_DEFAULT="${HERMES_NODE_DIST_MIRROR:-https://npmmirror.com/mirrors/node}"
UV_INSTALLER_URL_DEFAULT="${HERMES_UV_INSTALLER_URL:-$MIRROR_BASE_URL/third-party/uv/install.sh}"
UV_INSTALLER_GITHUB_BASE_URL_DEFAULT="${HERMES_UV_GITHUB_BASE_URL:-$MIRROR_BASE_URL/third-party/github}"
UV_PYTHON_INSTALL_MIRROR_DEFAULT="${HERMES_UV_PYTHON_MIRROR:-$MIRROR_BASE_URL/third-party/python-build-standalone/releases/download}"
PLAYWRIGHT_DOWNLOAD_HOST_CONFIG="${HERMES_PLAYWRIGHT_DOWNLOAD_HOST:-}"

# Options
USE_VENV=true
RUN_SETUP=true
BRANCH="main"
INSTALL_BROWSER_TOOLS=false
INSTALL_WHATSAPP_BRIDGE=false
INSTALL_NODE_RUNTIME=false
INSTALL_OPTIONAL_EXTRAS=false

# Detect non-interactive mode (e.g. curl | bash)
if [ -t 0 ]; then
    IS_INTERACTIVE=true
else
    IS_INTERACTIVE=false
fi

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --no-venv)
            USE_VENV=false
            shift
            ;;
        --skip-setup)
            RUN_SETUP=false
            shift
            ;;
        --branch)
            BRANCH="$2"
            shift 2
            ;;
        --dir)
            INSTALL_DIR="$2"
            shift 2
            ;;
        --mirror)
            MIRROR_BASE_URL="$2"
            shift 2
            ;;
        --with-node)
            INSTALL_NODE_RUNTIME=true
            shift
            ;;
        --with-browser)
            INSTALL_NODE_RUNTIME=true
            INSTALL_BROWSER_TOOLS=true
            shift
            ;;
        --with-whatsapp)
            INSTALL_NODE_RUNTIME=true
            INSTALL_WHATSAPP_BRIDGE=true
            shift
            ;;
        --with-optional-extras)
            INSTALL_OPTIONAL_EXTRAS=true
            shift
            ;;
        --full)
            INSTALL_NODE_RUNTIME=true
            INSTALL_BROWSER_TOOLS=true
            INSTALL_WHATSAPP_BRIDGE=true
            INSTALL_OPTIONAL_EXTRAS=true
            shift
            ;;
        -h|--help)
            echo "Hermes Agent 安装器（中国大陆镜像版）"
            echo ""
            echo "用法：install.sh [选项]"
            echo ""
            echo "可用选项："
            echo "  --no-venv         不创建虚拟环境"
            echo "  --skip-setup      跳过交互式配置向导"
            echo "  --branch NAME     要安装的 Git 分支（默认：main）"
            echo "  --dir PATH        安装目录（默认：~/.hermes/hermes-agent）"
            echo "  --mirror URL      覆盖镜像基础地址（默认指向 res1.hermesagent.org.cn）"
            echo "  --with-node       仅安装 Node.js 运行时"
            echo "  --with-browser    尽力安装浏览器相关 JS 依赖"
            echo "  --with-whatsapp   显示 WhatsApp 桥接后续安装说明"
            echo "  --with-optional-extras 安装完整 Python 扩展依赖（耗时更长）"
            echo "  --full            等同于 --with-browser --with-whatsapp"
            echo "  -h, --help        显示帮助"
            exit 0
            ;;
        *)
            echo "未知参数：$1"
            exit 1
            ;;
    esac
done

# ==========================================================================
# Helper functions
# ==========================================================================

print_banner() {
    echo ""
    echo -e "${MAGENTA}${BOLD}"
    echo "──────────────────────────────────────────────────────────────────────"
    echo "  ⚕ Hermes Agent 安装器 · 中国大陆镜像"
    echo "──────────────────────────────────────────────────────────────────────"
    echo "  由 Hermes Agent 中文社区提供加速"
    echo "  社区官网：https://hermesagent.org.cn"
    echo "  镜像脚本版本：2026.05.18-b83f7c1"
    echo "  最后更新：2026-05-18 09:07:41 CST"
    echo "──────────────────────────────────────────────────────────────────────"
    echo -e "${NC}"
}

log_info() {
    echo -e "${CYAN}→${NC} $1"
}

log_success() {
    echo -e "${GREEN}✓${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}⚠${NC} $1"
}

log_error() {
    echo -e "${RED}✗${NC} $1"
}

print_step() {
    echo ""
    echo -e "${CYAN}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}${BOLD}$1${NC}"
    echo -e "${CYAN}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

is_termux() {
    [ -n "${TERMUX_VERSION:-}" ] || [[ "${PREFIX:-}" == *"com.termux/files/usr"* ]]
}

get_command_link_dir() {
    if is_termux && [ -n "${PREFIX:-}" ]; then
        echo "$PREFIX/bin"
    else
        echo "$HOME/.local/bin"
    fi
}

get_command_link_display_dir() {
    if is_termux && [ -n "${PREFIX:-}" ]; then
        echo '$PREFIX/bin'
    else
        echo '~/.local/bin'
    fi
}

get_hermes_command_path() {
    local link_dir
    link_dir="$(get_command_link_dir)"
    if [ -x "$link_dir/hermes" ]; then
        echo "$link_dir/hermes"
    else
        echo "hermes"
    fi
}

configure_network_defaults() {
    export PIP_INDEX_URL="${PIP_INDEX_URL:-$PIP_INDEX_URL_DEFAULT}"
    export UV_DEFAULT_INDEX="${UV_DEFAULT_INDEX:-$PIP_INDEX_URL}"
    export NPM_CONFIG_REGISTRY="${NPM_CONFIG_REGISTRY:-$NPM_REGISTRY_DEFAULT}"
    export PIP_DISABLE_PIP_VERSION_CHECK=1
    export PIP_ROOT_USER_ACTION=ignore
}

get_pip_index_candidates() {
    {
        printf '%s\n' "${PIP_INDEX_URL:-$PIP_INDEX_URL_DEFAULT}"
        for mirror in $PIP_FALLBACK_INDEX_URLS_DEFAULT; do
            printf '%s\n' "$mirror"
        done
    } | awk 'NF && !seen[$0]++'
}

pip_install_with_fallback() {
    local pip_python="$1"
    shift

    local pip_log mirror pip_pid progress_pid elapsed
    pip_log="$(mktemp)"

    while IFS= read -r mirror; do
        [ -z "$mirror" ] && continue
        log_info "正在尝试 pip 镜像：$mirror"
        PIP_INDEX_URL="$mirror" "$pip_python" -m pip "$@" >"$pip_log" 2>&1 &
        pip_pid=$!

        (
            elapsed=0
            while kill -0 "$pip_pid" 2>/dev/null; do
                sleep 15
                elapsed=$((elapsed + 15))
                if kill -0 "$pip_pid" 2>/dev/null; then
                    log_info "pip 仍在处理中（已等待 ${elapsed} 秒），请耐心稍候..."
                fi
            done
        ) &
        progress_pid=$!

        wait "$pip_pid"
        local pip_exit=$?
        kill "$progress_pid" 2>/dev/null || true
        wait "$progress_pid" 2>/dev/null || true

        if [ "$pip_exit" -eq 0 ]; then
            export PIP_INDEX_URL="$mirror"
            export UV_DEFAULT_INDEX="$mirror"
            rm -f "$pip_log"
            return 0
        fi

        log_warn "当前镜像安装失败，准备切换下一个镜像..."
        tail -5 "$pip_log" | while IFS= read -r line; do
            [ -n "$line" ] && log_warn "  $line"
        done
    done < <(get_pip_index_candidates)

    log_error "所有 pip 镜像都尝试失败了"
    rm -f "$pip_log"
    return 1
}

get_source_tarball_urls() {
    local custom="${HERMES_SOURCE_TARBALL_URL:-}"
    local urls=()
    local cache_bust_query="?v=2026.05.18-b83f7c1"

    if [ -n "$custom" ]; then
        urls+=("$custom")
    fi

    urls+=(
        "$MIRROR_BASE_URL/hermes-agent-${BRANCH}.tar.gz${cache_bust_query}"
        "$MIRROR_BASE_URL/hermes-agent-main.tar.gz${cache_bust_query}"
        "$UPSTREAM_TARBALL_BASE/${BRANCH}.tar.gz"
    )

    printf '%s\n' "${urls[@]}"
}

download_to_file() {
    local dest="$1"
    shift
    local url
    for url in "$@"; do
        [ -z "$url" ] && continue
        log_info "正在尝试下载：$url"
        if curl --connect-timeout 15 --retry 2 --retry-delay 1 -fL "$url" -o "$dest"; then
            return 0
        fi
    done
    return 1
}

download_to_stdout() {
    local url
    for url in "$@"; do
        [ -z "$url" ] && continue
        log_info "正在尝试下载：$url"
        if curl --connect-timeout 15 --retry 2 --retry-delay 1 -fsSL "$url"; then
            return 0
        fi
    done
    return 1
}

python_meets_requirement() {
    local candidate="$1"
    "$candidate" - <<'PY' >/dev/null 2>&1
import sys
raise SystemExit(0 if sys.version_info >= (3, 11) else 1)
PY
}

get_python_minor_version() {
    "$PYTHON_PATH" - <<'PY' 2>/dev/null
import sys
print(f"{sys.version_info.major}.{sys.version_info.minor}")
PY
}

find_system_python() {
    local candidates=(python3.13 python3.12 python3.11 python3 python)
    local candidate path
    for candidate in "${candidates[@]}"; do
        if command -v "$candidate" >/dev/null 2>&1; then
            path="$(command -v "$candidate")"
            if python_meets_requirement "$path"; then
                PYTHON_PATH="$path"
                PYTHON_FOUND_VERSION="$($PYTHON_PATH --version 2>/dev/null)"
                return 0
            fi
        fi
    done
    return 1
}

ensure_python_venv_package() {
    if [ "$DISTRO" != "ubuntu" ] && [ "$DISTRO" != "debian" ]; then
        return 1
    fi

    local py_minor packages=() pkg
    py_minor="$(get_python_minor_version)"

    if [ -n "$py_minor" ]; then
        packages+=("python${py_minor}-venv")
    fi
    packages+=("python3-venv")

    for pkg in "${packages[@]}"; do
        if dpkg -s "$pkg" >/dev/null 2>&1; then
            return 0
        fi
    done

    log_warn "检测到系统 Python 缺少虚拟环境组件（venv / ensurepip）"
    log_info "正在尝试自动安装：${packages[*]}"
    log_info "这一步可能需要几十秒，请耐心等待。"

    if [ "$(id -u)" -eq 0 ]; then
        log_info "正在以 root 身份刷新软件源..."
        apt-get update -qq || true
        for pkg in "${packages[@]}"; do
            log_info "正在安装 $pkg ..."
            if apt-get install -y -qq "$pkg" >/dev/null 2>&1; then
                log_success "已安装 $pkg"
                return 0
            fi
        done
        return 1
    fi

    if command -v sudo >/dev/null 2>&1 && sudo -n true 2>/dev/null; then
        log_info "检测到免密 sudo，正在自动刷新软件源..."
        sudo apt-get update -qq || true
        for pkg in "${packages[@]}"; do
            log_info "正在通过 sudo 安装 $pkg ..."
            if sudo DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=a apt-get install -y -qq "$pkg" >/dev/null 2>&1; then
                log_success "已安装 $pkg"
                return 0
            fi
        done
        return 1
    fi

    if command -v sudo >/dev/null 2>&1 && [ -e /dev/tty ]; then
        echo ""
        log_info "当前系统 Python 无法创建虚拟环境，需要安装 venv 组件。"
        log_info "Hermes 本体不需要长期 root 权限；这里只会调用一次 apt 安装必要软件包。"
        read -p "现在自动安装 venv 组件吗？[Y/n] " -n 1 -r < /dev/tty
        echo
        if [[ $REPLY =~ ^[Nn]$ ]]; then
            return 1
        fi
        log_info "正在通过 sudo 刷新软件源..."
        sudo apt-get update -qq < /dev/tty || true
        for pkg in "${packages[@]}"; do
            log_info "正在通过 sudo 安装 $pkg ..."
            if sudo DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=a apt-get install -y -qq "$pkg" < /dev/tty >/dev/null 2>&1; then
                log_success "已安装 $pkg"
                return 0
            fi
        done
    fi

    return 1
}

show_manual_install_hint() {
    local pkg="$1"
    log_info "如需手动安装 $pkg："
    case "$OS" in
        linux)
            case "$DISTRO" in
                ubuntu|debian) log_info "  sudo apt install $pkg" ;;
                fedora)        log_info "  sudo dnf install $pkg" ;;
                arch)          log_info "  sudo pacman -S $pkg" ;;
                *)             log_info "  请使用系统包管理器，或访问项目主页手动安装" ;;
            esac
            ;;
        android)
            log_info "  pkg install $pkg"
            ;;
        macos)
            log_info "  brew install $pkg"
            ;;
    esac
}

# ==========================================================================
# System detection
# ==========================================================================

detect_os() {
    case "$(uname -s)" in
        Linux*)
            if is_termux; then
                OS="android"
                DISTRO="termux"
            else
                OS="linux"
                if [ -f /etc/os-release ]; then
                    . /etc/os-release
                    DISTRO="$ID"
                else
                    DISTRO="unknown"
                fi
            fi
            ;;
        Darwin*)
            OS="macos"
            DISTRO="macos"
            ;;
        CYGWIN*|MINGW*|MSYS*)
            OS="windows"
            DISTRO="windows"
            log_error "检测到 Windows，请改用 PowerShell 安装器："
            log_info "  irm https://res1.hermesagent.org.cn/install.ps1 | iex"
            exit 1
            ;;
        *)
            OS="unknown"
            DISTRO="unknown"
            log_warn "无法识别当前操作系统"
            ;;
    esac

    log_success "已识别系统：$OS ($DISTRO)"
}

# ==========================================================================
# Dependency checks
# ==========================================================================

install_uv() {
    if [ "$DISTRO" = "termux" ]; then
        UV_CMD=""
        return 0
    fi

    log_info "正在检查 uv 包管理器..."

    if command -v uv >/dev/null 2>&1; then
        UV_CMD="uv"
        log_success "已找到 uv（$($UV_CMD --version 2>/dev/null)）"
        return 0
    fi

    if [ -x "$HOME/.local/bin/uv" ]; then
        UV_CMD="$HOME/.local/bin/uv"
        log_success "已在 ~/.local/bin 找到 uv（$($UV_CMD --version 2>/dev/null)）"
        return 0
    fi

    if [ -x "$HOME/.cargo/bin/uv" ]; then
        UV_CMD="$HOME/.cargo/bin/uv"
        log_success "已在 ~/.cargo/bin 找到 uv（$($UV_CMD --version 2>/dev/null)）"
        return 0
    fi

    log_info "正在安装 uv（优先镜像，失败后回退上游）..."
    export UV_INSTALLER_GITHUB_BASE_URL="${UV_INSTALLER_GITHUB_BASE_URL:-$UV_INSTALLER_GITHUB_BASE_URL_DEFAULT}"

    local uv_installer_tmp uv_installer_ok=false uv_installer_url
    uv_installer_tmp="$(mktemp)"
    for uv_installer_url in "$UV_INSTALLER_URL_DEFAULT" "https://astral.sh/uv/install.sh"; do
        [ -z "$uv_installer_url" ] && continue
        log_info "正在下载 uv 安装脚本：$uv_installer_url"
        if curl --connect-timeout 15 --retry 2 --retry-delay 1 -fL "$uv_installer_url" -o "$uv_installer_tmp"; then
            uv_installer_ok=true
            break
        fi
    done

    if [ "$uv_installer_ok" = true ] && sh "$uv_installer_tmp" 2>/dev/null; then
        if [ -x "$HOME/.local/bin/uv" ]; then
            UV_CMD="$HOME/.local/bin/uv"
        elif [ -x "$HOME/.cargo/bin/uv" ]; then
            UV_CMD="$HOME/.cargo/bin/uv"
        elif command -v uv >/dev/null 2>&1; then
            UV_CMD="uv"
        else
            log_error "uv 已安装，但当前 PATH 中找不到它"
            log_info "请将 ~/.local/bin 加入 PATH 后重新运行"
            exit 1
        fi
        log_success "uv 安装完成（$($UV_CMD --version 2>/dev/null)）"
    else
        log_error "安装 uv 失败"
        log_info "如需手动安装，请访问：https://docs.astral.sh/uv/getting-started/installation/"
        rm -f "$uv_installer_tmp"
        exit 1
    fi
    rm -f "$uv_installer_tmp"
}

check_python() {
    if [ "$DISTRO" = "termux" ]; then
        log_info "正在检查 Termux Python..."
        if command -v python >/dev/null 2>&1; then
            PYTHON_PATH="$(command -v python)"
            if python_meets_requirement "$PYTHON_PATH"; then
                PYTHON_FOUND_VERSION="$($PYTHON_PATH --version 2>/dev/null)"
                log_success "已找到 Python：$PYTHON_FOUND_VERSION"
                return 0
            fi
        fi

        log_info "正在通过 pkg 安装 Python..."
        pkg install -y python >/dev/null
        PYTHON_PATH="$(command -v python)"
        PYTHON_FOUND_VERSION="$($PYTHON_PATH --version 2>/dev/null)"
        log_success "Python 安装完成：$PYTHON_FOUND_VERSION"
        return 0
    fi

    log_info "正在检查可用的系统 Python（>= 3.11）..."
    if find_system_python; then
        log_success "已找到 Python：$PYTHON_FOUND_VERSION"
        return 0
    fi

    log_warn "未找到可用的系统 Python"
    install_uv
    export UV_PYTHON_INSTALL_MIRROR="${UV_PYTHON_INSTALL_MIRROR:-$UV_PYTHON_INSTALL_MIRROR_DEFAULT}"

    log_info "正在通过 uv 安装 Python $PYTHON_VERSION..."
    if $UV_CMD python install "$PYTHON_VERSION"; then
        PYTHON_PATH="$($UV_CMD python find "$PYTHON_VERSION")"
        PYTHON_FOUND_VERSION="$($PYTHON_PATH --version 2>/dev/null)"
        log_success "Python 安装完成：$PYTHON_FOUND_VERSION"
    else
        log_error "安装 Python $PYTHON_VERSION 失败"
        log_info "如果你有自建 R2 / 对象存储镜像，请上传 python-build-standalone 资产并设置："
        log_info "  export UV_PYTHON_INSTALL_MIRROR=$UV_PYTHON_INSTALL_MIRROR_DEFAULT"
        exit 1
    fi
}

check_git() {
    if command -v git >/dev/null 2>&1; then
        return 0
    fi

    log_error "未找到 Git"
    case "$OS" in
        linux)
            case "$DISTRO" in
                ubuntu|debian) log_info "安装 Git：sudo apt update && sudo apt install git" ;;
                fedora)        log_info "安装 Git：sudo dnf install git" ;;
                arch)          log_info "安装 Git：sudo pacman -S git" ;;
                *)             log_info "请使用系统包管理器安装 Git" ;;
            esac
            ;;
        android)
            log_info "安装 Git：pkg install git"
            ;;
        macos)
            log_info "安装 Git：xcode-select --install"
            log_info "或者：brew install git"
            ;;
    esac
    exit 1
}

ensure_git_remote() {
    local remote_name="$1"
    local remote_url="$2"

    [ -n "$remote_name" ] || return 1
    [ -n "$remote_url" ] || return 0

    if git remote get-url "$remote_name" >/dev/null 2>&1; then
        git remote set-url "$remote_name" "$remote_url" >/dev/null 2>&1 || true
    else
        git remote add "$remote_name" "$remote_url" >/dev/null 2>&1 || true
    fi
}

bootstrap_git_repo_from_remote() {
    if ! command -v git >/dev/null 2>&1; then
        return 1
    fi

    local remote_url
    for remote_url in "$@"; do
        [ -n "$remote_url" ] || continue

        if (
            cd "$INSTALL_DIR" &&
            rm -rf .git &&
            git init >/dev/null 2>&1 &&
            ensure_git_remote origin "$remote_url" &&
            git fetch --depth 1 origin "$BRANCH" >/dev/null 2>&1 &&
            git checkout -B "$BRANCH" "origin/$BRANCH" >/dev/null 2>&1
        ); then
            if [ "$remote_url" != "$UPSTREAM_REPO_URL" ]; then
                (
                    cd "$INSTALL_DIR" &&
                    ensure_git_remote upstream "$UPSTREAM_REPO_URL"
                ) || true
            fi
            return 0
        fi
    done

    return 1
}

check_node() {
    log_info "正在检查 Node.js..."

    if command -v node >/dev/null 2>&1; then
        HAS_NODE=true
        log_success "已找到 Node.js（$(node --version)）"
        return 0
    fi

    if [ -x "$HERMES_HOME/node/bin/node" ]; then
        export PATH="$HERMES_HOME/node/bin:$PATH"
        HAS_NODE=true
        log_success "已找到 Node.js（$("$HERMES_HOME/node/bin/node" --version)，Hermes 托管版）"
        return 0
    fi

    install_node
}

install_node() {
    if [ "$DISTRO" = "termux" ]; then
        log_info "正在通过 pkg 安装 Node.js..."
        if pkg install -y nodejs >/dev/null; then
            HAS_NODE=true
            log_success "Node.js 安装完成（$(node --version 2>/dev/null)）"
        else
            HAS_NODE=false
            log_warn "通过 pkg 安装 Node.js 失败"
        fi
        return 0
    fi

    local arch="$(uname -m)"
    local node_arch
    case "$arch" in
        x86_64)        node_arch="x64" ;;
        aarch64|arm64) node_arch="arm64" ;;
        armv7l)        node_arch="armv7l" ;;
        *)
            HAS_NODE=false
            log_warn "当前架构 ($arch) 不支持自动安装 Node.js"
            log_info "如需手动安装，请访问：https://nodejs.org/en/download/"
            return 0
            ;;
    esac

    local node_os
    case "$OS" in
        linux) node_os="linux" ;;
        macos) node_os="darwin" ;;
        *)
            HAS_NODE=false
            log_warn "当前操作系统不支持自动安装 Node.js"
            return 0
            ;;
    esac

    local node_dist_mirror="${NODE_DIST_MIRROR:-$NODE_DIST_MIRROR_DEFAULT}"
    local index_url="${node_dist_mirror}/latest-v${NODE_VERSION}.x/"
    local tarball_name
    tarball_name=$(curl -fsSL "$index_url" | grep -oE "node-v${NODE_VERSION}\.[0-9]+\.[0-9]+-${node_os}-${node_arch}\.tar\.xz" | head -1 || true)
    if [ -z "$tarball_name" ]; then
        tarball_name=$(curl -fsSL "$index_url" | grep -oE "node-v${NODE_VERSION}\.[0-9]+\.[0-9]+-${node_os}-${node_arch}\.tar\.gz" | head -1 || true)
    fi

    if [ -z "$tarball_name" ]; then
        HAS_NODE=false
        log_warn "找不到适用于 $node_os-$node_arch 的 Node.js $NODE_VERSION 二进制包"
        log_info "如需手动安装，请访问：https://nodejs.org/en/download/"
        return 0
    fi

    local tmp_dir download_url extracted_dir installed_ver
    tmp_dir="$(mktemp -d)"
    download_url="${index_url}${tarball_name}"

    log_info "正在下载 $tarball_name..."
    if ! curl -fsSL "$download_url" -o "$tmp_dir/$tarball_name"; then
        rm -rf "$tmp_dir"
        HAS_NODE=false
        log_warn "Node.js 下载失败"
        return 0
    fi

    if [[ "$tarball_name" == *.tar.xz ]]; then
        tar xf "$tmp_dir/$tarball_name" -C "$tmp_dir"
    else
        tar xzf "$tmp_dir/$tarball_name" -C "$tmp_dir"
    fi

    extracted_dir="$(find "$tmp_dir" -maxdepth 1 -type d -name 'node-v*' | head -1)"
    if [ ! -d "$extracted_dir" ]; then
        rm -rf "$tmp_dir"
        HAS_NODE=false
        log_warn "Node.js 解压失败"
        return 0
    fi

    rm -rf "$HERMES_HOME/node"
    mkdir -p "$HERMES_HOME"
    mv "$extracted_dir" "$HERMES_HOME/node"
    rm -rf "$tmp_dir"

    mkdir -p "$HOME/.local/bin"
    ln -sf "$HERMES_HOME/node/bin/node" "$HOME/.local/bin/node"
    ln -sf "$HERMES_HOME/node/bin/npm"  "$HOME/.local/bin/npm"
    ln -sf "$HERMES_HOME/node/bin/npx"  "$HOME/.local/bin/npx"

    export PATH="$HERMES_HOME/node/bin:$PATH"
    installed_ver="$($HERMES_HOME/node/bin/node --version 2>/dev/null)"
    HAS_NODE=true
    log_success "Node.js $installed_ver 已安装到 ~/.hermes/node/"
}

check_optional_system_packages() {
    HAS_RIPGREP=false
    HAS_FFMPEG=false

    if command -v rg >/dev/null 2>&1; then
        HAS_RIPGREP=true
        log_success "已找到 $(rg --version | head -1)"
    else
        log_warn "未找到 ripgrep，将回退为 grep 搜索"
        show_manual_install_hint "ripgrep"
    fi

    if command -v ffmpeg >/dev/null 2>&1; then
        HAS_FFMPEG=true
        log_success "已找到 ffmpeg $(ffmpeg -version 2>/dev/null | head -1 | awk '{print $3}')"
    else
        log_warn "未找到 ffmpeg，语音 / 媒体功能会受限"
        show_manual_install_hint "ffmpeg"
    fi

    if [ "$DISTRO" = "termux" ]; then
        log_info "正在确保 Termux 构建依赖已安装..."
        pkg install -y clang rust make pkg-config libffi openssl >/dev/null || true
    fi
}

# ==========================================================================
# Installation
# ==========================================================================

prepare_repo() {
    log_info "正在准备 Hermes 源码..."

    local tmp_dir tarball extracted_dir marker_file has_git
    tmp_dir="$(mktemp -d)"
    tarball="$tmp_dir/hermes-agent.tar.gz"
    marker_file="$INSTALL_DIR/.hermes-install-source"
    has_git=false

    if command -v git >/dev/null 2>&1; then
        has_git=true
    fi

    if [ -d "$INSTALL_DIR" ] && [ ! -f "$marker_file" ] && [ ! -d "$INSTALL_DIR/.git" ]; then
        log_error "目录已存在，但不是由当前安装器创建：$INSTALL_DIR"
        log_info "请删除该目录，或通过 --dir 指定其他安装位置"
        rm -rf "$tmp_dir"
        exit 1
    fi

    if [ "$has_git" = true ] && [ -n "$GIT_MIRROR_URL" ]; then
        rm -rf "$INSTALL_DIR"
        mkdir -p "$(dirname "$INSTALL_DIR")"
        log_info "正在尝试通过 CNB.cool / Git 镜像克隆：$GIT_MIRROR_URL"
        if git clone --branch "$BRANCH" "$GIT_MIRROR_URL" "$INSTALL_DIR"; then
            cd "$INSTALL_DIR"
            ensure_git_remote upstream "$UPSTREAM_REPO_URL"
            rm -rf "$tmp_dir"
            log_success "源码已就绪（Git 镜像）"
            return 0
        fi
        rm -rf "$INSTALL_DIR"
        log_warn "Git 镜像克隆失败，正在回退到源码包..."
    fi

    local tarball_urls=()
    while IFS= read -r url; do
        tarball_urls+=("$url")
    done < <(get_source_tarball_urls)

    if download_to_file "$tarball" "${tarball_urls[@]}"; then
        rm -rf "$INSTALL_DIR"
        mkdir -p "$(dirname "$INSTALL_DIR")"
        tar -xzf "$tarball" -C "$tmp_dir"
        extracted_dir="$(find "$tmp_dir" -mindepth 1 -maxdepth 1 -type d | head -1)"
        if [ -z "$extracted_dir" ] || [ ! -d "$extracted_dir" ]; then
            rm -rf "$tmp_dir"
            log_error "解压 Hermes 源码包失败"
            exit 1
        fi
        mv "$extracted_dir" "$INSTALL_DIR"

        # 优先信任源码包自带的 .git：如果 HEAD 能解析说明结构完整，直接用，
        # 避免 bootstrap_git_repo_from_remote 先 rm -rf .git 再 fetch，一旦
        # 网络失败就把原本好的 .git 也抹掉，导致 hermes update 报
        # "not a git repository"。
        if [ "$has_git" = true ] && [ -d "$INSTALL_DIR/.git" ] && \
           git -C "$INSTALL_DIR" rev-parse HEAD >/dev/null 2>&1; then
            printf 'tarball+git\n' > "$marker_file"
            log_success "源码已就绪（源码包自带 Git 元数据，可直接使用 hermes update）"
        elif [ "$has_git" = true ] && bootstrap_git_repo_from_remote "$GIT_MIRROR_URL" "$UPSTREAM_REPO_URL"; then
            printf 'tarball+git\n' > "$marker_file"
            log_success "源码已就绪（源码包安装，已补全 Git 元数据，可直接使用 hermes update）"
        else
            printf 'tarball\n' > "$marker_file"
            if [ "$has_git" = true ]; then
                log_warn "源码已就绪（源码包安装），但 Git 元数据初始化失败；后续 hermes update 可能不可用"
            else
                log_warn "当前系统未安装 Git，本次使用源码包安装；如需后续执行 hermes update，请先安装 Git 后重新运行安装脚本"
            fi
        fi

        rm -rf "$tmp_dir"
        cd "$INSTALL_DIR"
        return 0
    fi

    rm -rf "$tmp_dir"
    log_warn "源码包下载失败，正在回退到 git clone"
    check_git
    rm -rf "$INSTALL_DIR"

    if [ -n "$GIT_MIRROR_URL" ]; then
        log_info "正在尝试 Git 镜像：$GIT_MIRROR_URL"
        if git clone --branch "$BRANCH" "$GIT_MIRROR_URL" "$INSTALL_DIR"; then
            cd "$INSTALL_DIR"
            log_success "源码已就绪（Git 镜像）"
            return 0
        fi
        rm -rf "$INSTALL_DIR"
    fi

    log_info "正在尝试上游 GitHub 仓库..."
    if git clone --branch "$BRANCH" "$UPSTREAM_REPO_URL" "$INSTALL_DIR"; then
        cd "$INSTALL_DIR"
        log_success "源码已就绪（GitHub 克隆）"
        return 0
    fi

    log_error "获取 Hermes 源码失败"
    exit 1
}

patch_hermes_setup_launch_behavior() {
    local setup_py="$INSTALL_DIR/hermes_cli/setup.py"
    [ -f "$setup_py" ] || return 0

    if grep -q "HERMES_SKIP_AUTO_LAUNCH_CHAT" "$setup_py"; then
        return 0
    fi

    "$PYTHON_PATH" - "$setup_py" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
import_block = '''from hermes_cli.cli_output import (  # noqa: E402
    print_error,
    print_info,
    print_success,
    print_warning,
)
'''

translation_block = '''from hermes_cli.cli_output import (  # noqa: E402
    print_error,
    print_info,
    print_success,
    print_warning,
)

_SETUP_TRANSLATIONS = [
    ("Hermes Setup — Non-interactive mode", "Hermes 配置向导 —— 非交互模式"),
    ("The interactive wizard cannot be used here.", "当前环境无法使用交互式配置向导。"),
    ("Configure Hermes using environment variables or config commands:", "你可以通过环境变量或配置命令来设置 Hermes："),
    ("Or set OPENROUTER_API_KEY / OPENAI_API_KEY in your environment.", "或者在环境变量中设置 OPENROUTER_API_KEY / OPENAI_API_KEY。"),
    ("Run 'hermes setup' in an interactive terminal to use the full wizard.", "如需完整向导，请在交互式终端中运行：hermes setup"),
    ("  Skipped (keeping current)", "  已跳过（保留当前设置）"),
    ("  Enter for default", "  直接回车使用默认项"),
    ("Ctrl+C to exit", "Ctrl+C 退出"),
    ("  Select [", "  请选择 ["),
    ("Please enter a number between", "请输入一个数字，范围："),
    ("Please enter a number", "请输入数字"),
    ("Please enter 'y' or 'n'", "请输入 y 或 n"),
    ("Launch hermes chat now?", "现在立即启动 hermes 聊天吗？"),
    ("Connect a messaging platform? (Telegram, Discord, etc.)", "现在连接消息平台吗？（Telegram、Discord 等）"),
    ("Set up messaging now (recommended)", "现在配置消息平台（推荐）"),
    ("Skip — set up later with 'hermes setup gateway'", "先跳过，之后可通过 'hermes setup gateway' 配置"),
]

def _translate_setup_text(text: str) -> str:
    if not isinstance(text, str):
        return text
    translated = text
    for old, new in _SETUP_TRANSLATIONS:
        translated = translated.replace(old, new)
    return translated

_orig_print_error = print_error
_orig_print_info = print_info
_orig_print_success = print_success
_orig_print_warning = print_warning

def print_error(message):
    _orig_print_error(_translate_setup_text(message))

def print_info(message):
    _orig_print_info(_translate_setup_text(message))

def print_success(message):
    _orig_print_success(_translate_setup_text(message))

def print_warning(message):
    _orig_print_warning(_translate_setup_text(message))
'''

if "_translate_setup_text(" not in text and import_block in text:
    text = text.replace(import_block, translation_block, 1)

replacements = [
    (
        '''def print_noninteractive_setup_guidance(reason: str | None = None) -> None:
    """Print guidance for headless/non-interactive setup flows."""
    print()
    print(color("⚕ Hermes Setup — Non-interactive mode", Colors.CYAN, Colors.BOLD))
    print()
    if reason:
        print_info(reason)
    print_info("The interactive wizard cannot be used here.")
    print()
    print_info("Configure Hermes using environment variables or config commands:")
    print_info("  hermes config set model.provider custom")
    print_info("  hermes config set model.base_url http://localhost:8080/v1")
    print_info("  hermes config set model.default your-model-name")
    print()
    print_info("Or set OPENROUTER_API_KEY / OPENAI_API_KEY in your environment.")
    print_info("Run 'hermes setup' in an interactive terminal to use the full wizard.")
    print()
''',
        '''def print_noninteractive_setup_guidance(reason: str | None = None) -> None:
    """Print guidance for headless/non-interactive setup flows."""
    print()
    print(color("⚕ Hermes 配置向导 —— 非交互模式", Colors.CYAN, Colors.BOLD))
    print()
    if reason:
        print_info(reason)
    print_info("当前环境无法使用交互式配置向导。")
    print()
    print_info("你可以通过环境变量或配置命令来设置 Hermes：")
    print_info("  hermes config set model.provider custom")
    print_info("  hermes config set model.base_url http://localhost:8080/v1")
    print_info("  hermes config set model.default your-model-name")
    print()
    print_info("或者在环境变量中设置 OPENROUTER_API_KEY / OPENAI_API_KEY。")
    print_info("如需完整向导，请在交互式终端中运行：hermes setup")
    print()
'''
    ),
    (
        '''def prompt(question: str, default: str = None, password: bool = False) -> str:
    """Prompt for input with optional default."""
    if default:
        display = f"{question} [{default}]: "
    else:
        display = f"{question}: "
''',
        '''def prompt(question: str, default: str = None, password: bool = False) -> str:
    """Prompt for input with optional default."""
    question = _translate_setup_text(question)
    if default:
        display = f"{question} [{default}]: "
    else:
        display = f"{question}: "
'''
    ),
    (
        '''def prompt_choice(question: str, choices: list, default: int = 0) -> int:
    """Prompt for a choice from a list with arrow key navigation.

    Escape keeps the current default (skips the question).
    Ctrl+C exits the wizard.
    """
    idx = _curses_prompt_choice(question, choices, default)
''',
        '''def prompt_choice(question: str, choices: list, default: int = 0) -> int:
    """Prompt for a choice from a list with arrow key navigation.

    Escape keeps the current default (skips the question).
    Ctrl+C exits the wizard.
    """
    question = _translate_setup_text(question)
    choices = [_translate_setup_text(str(choice)) for choice in choices]
    idx = _curses_prompt_choice(question, choices, default)
'''
    ),
    (
        '''def prompt_yes_no(question: str, default: bool = True) -> bool:
    """Prompt for yes/no. Ctrl+C exits, empty input returns default."""
    default_str = "Y/n" if default else "y/N"
''',
        '''def prompt_yes_no(question: str, default: bool = True) -> bool:
    """Prompt for yes/no. Ctrl+C exits, empty input returns default."""
    question = _translate_setup_text(question)
    default_str = "Y/n（回车默认是）" if default else "y/N（回车默认否）"
'''
    ),
    (
        '''        if value in ("y", "yes"):
            return True
        if value in ("n", "no"):
            return False
        print_error("Please enter 'y' or 'n'")
''',
        '''        if value in ("y", "yes", "是"):
            return True
        if value in ("n", "no", "否"):
            return False
        print_error("请输入 y 或 n")
'''
    ),
    (
        '''def _offer_launch_chat():
    """Prompt the user to jump straight into chat after setup."""
    print()
''',
        '''def _offer_launch_chat():
    """Prompt the user to jump straight into chat after setup."""
    if os.environ.get("HERMES_SKIP_AUTO_LAUNCH_CHAT") == "1":
        print_info("镜像安装器将跳过自动启动聊天。准备好后请在新终端中运行：hermes")
        return

    print()
'''
    ),
]

for old, new in replacements:
    if old in text:
        text = text.replace(old, new, 1)

path.write_text(text, encoding="utf-8")
PY

    log_success "已修补 Hermes 配置向导：镜像安装时跳过自动启动聊天"
}

setup_venv() {
    if [ "$USE_VENV" = false ]; then
        log_info "跳过虚拟环境创建（--no-venv）"
        return 0
    fi

    log_info "正在创建虚拟环境..."
    rm -rf "$INSTALL_DIR/venv"

    local venv_log
    venv_log="$(mktemp)"

    if "$PYTHON_PATH" -m venv "$INSTALL_DIR/venv" >"$venv_log" 2>&1; then
        log_success "虚拟环境已就绪（$("$INSTALL_DIR/venv/bin/python" --version 2>/dev/null)）"
        rm -f "$venv_log"
        return 0
    fi

    if ensure_python_venv_package; then
        log_info "已补齐系统 venv 组件，正在重新创建虚拟环境..."
        if "$PYTHON_PATH" -m venv "$INSTALL_DIR/venv" >"$venv_log" 2>&1; then
            log_success "虚拟环境已就绪（$("$INSTALL_DIR/venv/bin/python" --version 2>/dev/null)）"
            rm -f "$venv_log"
            return 0
        fi
        log_warn "系统 venv 组件已安装，但仍无法使用系统 Python 创建虚拟环境"
    fi

    if [ "$DISTRO" != "termux" ]; then
        log_warn "系统 Python 无法创建虚拟环境（Ubuntu / Debian 常见原因是缺少 python3-venv）"
        install_uv
        export UV_PYTHON_INSTALL_MIRROR="${UV_PYTHON_INSTALL_MIRROR:-$UV_PYTHON_INSTALL_MIRROR_DEFAULT}"

        if $UV_CMD venv "$INSTALL_DIR/venv" --python "$PYTHON_PATH" >/tmp/hermes-uv-venv.log 2>&1; then
            log_success "虚拟环境已就绪（$("$INSTALL_DIR/venv/bin/python" --version 2>/dev/null)）"
            return 0
        fi

        log_warn "uv 无法复用系统 Python，正在尝试托管版 Python $PYTHON_VERSION..."
        if $UV_CMD venv "$INSTALL_DIR/venv" --python "$PYTHON_VERSION" >/tmp/hermes-uv-venv.log 2>&1; then
            log_success "虚拟环境已就绪（$("$INSTALL_DIR/venv/bin/python" --version 2>/dev/null)）"
            rm -f "$venv_log"
            return 0
        fi

        if [ -f /tmp/hermes-uv-venv.log ]; then
            log_warn "uv 创建虚拟环境失败，关键输出如下："
            tail -20 /tmp/hermes-uv-venv.log | while IFS= read -r line; do
                log_warn "  $line"
            done
        fi
    fi

    log_error "创建虚拟环境失败"
    if [ -s "$venv_log" ]; then
        log_warn "系统 Python 创建虚拟环境失败，关键输出如下："
        tail -20 "$venv_log" | while IFS= read -r line; do
            log_warn "  $line"
        done
    fi
    rm -f "$venv_log"
    if [ "$DISTRO" = "ubuntu" ] || [ "$DISTRO" = "debian" ]; then
        log_info "你可能需要执行：sudo apt install python3-venv"
        log_info "或者安装对应版本的软件包，例如：sudo apt install python3.12-venv"
    fi
    exit 1
}

install_deps() {
    log_info "正在安装 Python 依赖..."

    local pip_python
    if [ "$USE_VENV" = true ]; then
        pip_python="$INSTALL_DIR/venv/bin/python"
    else
        pip_python="$PYTHON_PATH"
    fi

    if [ "$DISTRO" = "termux" ]; then
        if [ -z "${ANDROID_API_LEVEL:-}" ]; then
            ANDROID_API_LEVEL="$(getprop ro.build.version.sdk 2>/dev/null || true)"
            [ -z "$ANDROID_API_LEVEL" ] && ANDROID_API_LEVEL=24
            export ANDROID_API_LEVEL
            log_info "正在使用 ANDROID_API_LEVEL=$ANDROID_API_LEVEL 构建 Android wheel"
        fi

        if ! pip_install_with_fallback "$pip_python" install --upgrade pip setuptools wheel; then
            log_error "升级 pip / setuptools / wheel 失败"
            exit 1
        fi
        if ! pip_install_with_fallback "$pip_python" install -e '.[termux]' -c constraints-termux.txt; then
            log_warn "Termux 扩展安装（.[termux]）失败，正在回退到基础安装..."
            if ! pip_install_with_fallback "$pip_python" install -e '.' -c constraints-termux.txt; then
                log_error "Termux 环境下安装 Python 包失败"
                log_info "请确认已安装这些依赖：pkg install clang rust make pkg-config libffi openssl"
                exit 1
            fi
        fi
        log_success "Python 依赖安装完成"
        return 0
    fi

    if ! pip_install_with_fallback "$pip_python" install --upgrade pip setuptools wheel; then
        log_warn "升级 pip / setuptools / wheel 失败，继续尝试直接安装 Hermes 依赖"
    fi

    if [ "$DISTRO" = "ubuntu" ] || [ "$DISTRO" = "debian" ]; then
        local need_build_tools=false
        for pkg in gcc python3-dev libffi-dev; do
            if ! dpkg -s "$pkg" >/dev/null 2>&1; then
                need_build_tools=true
                break
            fi
        done
        if [ "$need_build_tools" = true ]; then
            log_warn "部分 Python 包可能需要编译工具（gcc/python3-dev/libffi-dev）"
            log_info "如果安装失败，请执行：sudo apt install build-essential python3-dev libffi-dev"
        fi
    fi

    if [ "$INSTALL_OPTIONAL_EXTRAS" = true ]; then
        log_info "已启用 --with-optional-extras，正在安装完整 Python 扩展依赖（可能需要较长时间）..."
        if ! pip_install_with_fallback "$pip_python" install -e '.[all]'; then
            log_warn "完整安装（.[all]）失败，正在回退到基础安装..."
            if ! pip_install_with_fallback "$pip_python" install -e '.'; then
                log_error "安装 Python 包失败"
                log_info "当前使用的 PyPI 镜像：$PIP_INDEX_URL"
                exit 1
            fi
        fi
    else
        log_info "为提高安装速度与成功率，默认只安装 Hermes 核心依赖。"
        log_info "浏览器、RL 训练等体积较大 / 不常用扩展默认跳过；如有需要可稍后手动补装。"
        if ! pip_install_with_fallback "$pip_python" install -e '.'; then
            log_error "安装 Python 包失败"
            log_info "当前使用的 PyPI 镜像：$PIP_INDEX_URL"
            exit 1
        fi
    fi

    log_success "Python 依赖安装完成"
}

install_agent_browser_binary() {
    local asset_name dest_dir dest
    case "$OS-$(uname -m)" in
        linux-x86_64)        asset_name="agent-browser-linux-x64" ;;
        linux-aarch64|linux-arm64) asset_name="agent-browser-linux-arm64" ;;
        macos-x86_64)        asset_name="agent-browser-darwin-x64" ;;
        macos-arm64)         asset_name="agent-browser-darwin-arm64" ;;
        *)
            log_warn "当前平台 $(uname -s)-$(uname -m) 没有配置镜像版 agent-browser 二进制文件"
            return 1
            ;;
    esac

    dest_dir="$INSTALL_DIR/node_modules/agent-browser/bin"
    dest="$dest_dir/$asset_name"
    mkdir -p "$dest_dir"

    if download_to_file \
        "$dest" \
        "$MIRROR_BASE_URL/third-party/agent-browser/releases/download/v${AGENT_BROWSER_VERSION}/${asset_name}" \
        "https://github.com/vercel-labs/agent-browser/releases/download/v${AGENT_BROWSER_VERSION}/${asset_name}"; then
        chmod +x "$dest" 2>/dev/null || true
        log_success "agent-browser 原生二进制已就绪（$asset_name）"
        return 0
    fi

    log_warn "获取 agent-browser 原生二进制失败"
    return 1
}

install_optional_node_components() {
    if [ "$INSTALL_NODE_RUNTIME" = false ] && [ "$INSTALL_BROWSER_TOOLS" = false ] && [ "$INSTALL_WHATSAPP_BRIDGE" = false ]; then
        log_info "默认跳过可选的 Node.js 组件"
        return 0
    fi

    check_node
    if [ "$HAS_NODE" != true ]; then
        return 0
    fi

    if [ "$INSTALL_BROWSER_TOOLS" = true ]; then
        if [ -f "$INSTALL_DIR/package.json" ]; then
            log_info "正在安装浏览器相关 JS 依赖（尽力而为）..."
            (
                cd "$INSTALL_DIR"
                npm install --silent --ignore-scripts
            ) || log_warn "npm install 失败（浏览器工具未安装）"

            install_agent_browser_binary || true

            if [ -n "$PLAYWRIGHT_DOWNLOAD_HOST_CONFIG" ]; then
                log_info "正在从配置好的镜像安装 Playwright Chromium..."
                (
                    cd "$INSTALL_DIR"
                    PLAYWRIGHT_DOWNLOAD_HOST="$PLAYWRIGHT_DOWNLOAD_HOST_CONFIG" npx playwright install chromium
                ) || log_warn "Playwright Chromium 下载失败"
            else
                log_warn "默认跳过 Playwright 浏览器下载"
                log_info "如果后续需要浏览器工具，请先把 Playwright 资源上传到你的 R2 / 对象存储镜像，然后执行："
                log_info "  cd $INSTALL_DIR && PLAYWRIGHT_DOWNLOAD_HOST=<你的镜像地址> npx playwright install chromium"
            fi
        fi
    fi

    if [ "$INSTALL_WHATSAPP_BRIDGE" = true ]; then
        log_warn "中国大陆镜像版默认跳过 WhatsApp 桥接自动安装"
        log_info "原因：上游依赖固定绑定到了 GitHub git URL"
        log_info "如果你后续把 Baileys / libsignal 镜像到了 Gitee 或你的对象存储镜像，可再到这里手动安装："
        log_info "  $INSTALL_DIR/scripts/whatsapp-bridge"
    fi
}

setup_path() {
    log_info "正在设置 hermes 命令..."

    if [ "$USE_VENV" = true ]; then
        HERMES_BIN="$INSTALL_DIR/venv/bin/hermes"
    else
        HERMES_BIN="$(command -v hermes 2>/dev/null || true)"
        if [ -z "$HERMES_BIN" ]; then
            log_warn "安装后在 PATH 中找不到 hermes"
            return 0
        fi
    fi

    if [ ! -x "$HERMES_BIN" ]; then
        log_warn "在 $HERMES_BIN 找不到 hermes 入口文件"
        return 0
    fi

    local command_link_dir command_link_display_dir
    command_link_dir="$(get_command_link_dir)"
    command_link_display_dir="$(get_command_link_display_dir)"

    mkdir -p "$command_link_dir"
    ln -sf "$HERMES_BIN" "$command_link_dir/hermes"
    log_success "已创建命令链接 hermes → $command_link_display_dir/hermes"

    if [ "$DISTRO" = "termux" ]; then
        export PATH="$command_link_dir:$PATH"
        log_success "hermes 命令已就绪"
        return 0
    fi

    if ! echo "$PATH" | tr ':' '\n' | grep -q "^$command_link_dir$"; then
        local shell_configs=() login_shell path_line shell_config
        login_shell="$(basename "${SHELL:-/bin/bash}")"
        case "$login_shell" in
            zsh)
                [ -f "$HOME/.zshrc" ] && shell_configs+=("$HOME/.zshrc")
                [ -f "$HOME/.zprofile" ] && shell_configs+=("$HOME/.zprofile")
                if [ ${#shell_configs[@]} -eq 0 ]; then
                    touch "$HOME/.zshrc"
                    shell_configs+=("$HOME/.zshrc")
                fi
                ;;
            bash)
                [ -f "$HOME/.bashrc" ] && shell_configs+=("$HOME/.bashrc")
                [ -f "$HOME/.bash_profile" ] && shell_configs+=("$HOME/.bash_profile")
                ;;
            *)
                [ -f "$HOME/.bashrc" ] && shell_configs+=("$HOME/.bashrc")
                [ -f "$HOME/.zshrc" ] && shell_configs+=("$HOME/.zshrc")
                ;;
        esac
        [ -f "$HOME/.profile" ] && shell_configs+=("$HOME/.profile")

        path_line='export PATH="$HOME/.local/bin:$PATH"'
        for shell_config in "${shell_configs[@]}"; do
            if ! grep -v '^[[:space:]]*#' "$shell_config" 2>/dev/null | grep -qE 'PATH=.*\.local/bin'; then
                {
                    echo ""
                    echo "# Hermes Agent —— 确保 ~/.local/bin 在 PATH 中"
                    echo "$path_line"
                } >> "$shell_config"
                log_success "已在 $shell_config 中加入 ~/.local/bin"
            fi
        done

        if [ ${#shell_configs[@]} -eq 0 ]; then
            log_warn "无法自动识别 shell 配置文件来写入 ~/.local/bin"
            log_info "请手动添加：$path_line"
        fi
    else
        log_info "~/.local/bin 已在 PATH 中"
    fi

    export PATH="$command_link_dir:$PATH"
    log_success "hermes 命令已就绪"
}

copy_config_templates() {
    log_info "正在设置配置文件..."

    mkdir -p "$HERMES_HOME"/{cron,sessions,logs,pairing,hooks,image_cache,audio_cache,memories,skills,whatsapp/session}

    if [ ! -f "$HERMES_HOME/.env" ]; then
        if [ -f "$INSTALL_DIR/.env.example" ]; then
            cp "$INSTALL_DIR/.env.example" "$HERMES_HOME/.env"
        else
            touch "$HERMES_HOME/.env"
        fi
        log_success "已创建 ~/.hermes/.env"
    else
        log_info "~/.hermes/.env 已存在，保留现有内容"
    fi

    if [ ! -f "$HERMES_HOME/config.yaml" ] && [ -f "$INSTALL_DIR/cli-config.yaml.example" ]; then
        cp "$INSTALL_DIR/cli-config.yaml.example" "$HERMES_HOME/config.yaml"
        log_success "已根据模板创建 ~/.hermes/config.yaml"
    elif [ -f "$HERMES_HOME/config.yaml" ]; then
        log_info "~/.hermes/config.yaml 已存在，保留现有内容"
    fi

    if [ ! -f "$HERMES_HOME/SOUL.md" ]; then
        cat > "$HERMES_HOME/SOUL.md" << 'SOUL_EOF'
# Hermes Agent Persona

<!--
Edit this file to customize Hermes's personality and tone.
This file is loaded fresh on every message.
-->
SOUL_EOF
        log_success "已创建 ~/.hermes/SOUL.md"
    fi

    local sync_python
    if [ "$USE_VENV" = true ] && [ -x "$INSTALL_DIR/venv/bin/python" ]; then
        sync_python="$INSTALL_DIR/venv/bin/python"
    else
        sync_python="$PYTHON_PATH"
    fi

    if [ -f "$INSTALL_DIR/tools/skills_sync.py" ]; then
        if "$sync_python" "$INSTALL_DIR/tools/skills_sync.py" 2>/dev/null; then
            log_success "已同步技能到 ~/.hermes/skills/"
        elif [ -d "$INSTALL_DIR/skills" ]; then
            cp -r "$INSTALL_DIR/skills/"* "$HERMES_HOME/skills/" 2>/dev/null || true
            log_success "已复制技能到 ~/.hermes/skills/"
        fi
    elif [ -d "$INSTALL_DIR/skills" ]; then
        cp -r "$INSTALL_DIR/skills/"* "$HERMES_HOME/skills/" 2>/dev/null || true
        log_success "已复制技能到 ~/.hermes/skills/"
    fi
}

run_setup_wizard() {
    if [ "$RUN_SETUP" = false ]; then
        log_info "跳过配置向导（--skip-setup）"
        return 0
    fi

    if ! [ -e /dev/tty ]; then
        log_info "没有可用终端，已跳过配置向导。你可以稍后手动运行：hermes setup"
        return 0
    fi

    echo ""
    log_success "Hermes Agent 核心安装已经完成，接下来进入配置 Hermes Agent 环节。"
    log_info "Hermes Agent 中文社区：https://hermesagent.org.cn"
    log_info "下一步的教程（胎教级别）：https://hermesagent.org.cn/docs/getting-started/setup-wizard"
    echo ""
    log_info "正在启动配置向导..."
    echo ""

    local setup_log setup_status
    setup_log="$(mktemp)"

    cd "$INSTALL_DIR"
    if [ "$USE_VENV" = true ]; then
        HERMES_SKIP_AUTO_LAUNCH_CHAT=1 "$INSTALL_DIR/venv/bin/python" -m hermes_cli.main setup < /dev/tty 2>"$setup_log"
        setup_status=$?
    else
        HERMES_SKIP_AUTO_LAUNCH_CHAT=1 "$PYTHON_PATH" -m hermes_cli.main setup < /dev/tty 2>"$setup_log"
        setup_status=$?
    fi

    if [ "$setup_status" -ne 0 ]; then
        if grep -q "prompt_toolkit" "$setup_log" && grep -q "Invalid argument" "$setup_log"; then
            log_warn "检测到已知的 TTY 问题：在 curl | bash 场景下自动启动 Hermes 聊天会失败。"
            log_info "安装和配置其实已经完成。请打开一个新终端后运行：hermes"
            rm -f "$setup_log"
            return 0
        fi

        log_error "配置向导执行失败"
        log_info "你可以稍后重新执行：hermes setup"
        rm -f "$setup_log"
        return 1
    fi

    rm -f "$setup_log"
}

maybe_start_gateway() {
    local env_file="$HERMES_HOME/.env"
    [ -f "$env_file" ] || return 0

    local has_messaging=false
    local var val
    for var in TELEGRAM_BOT_TOKEN DISCORD_BOT_TOKEN SLACK_BOT_TOKEN SLACK_APP_TOKEN WHATSAPP_ENABLED; do
        val="$(grep "^${var}=" "$env_file" 2>/dev/null | cut -d'=' -f2-)"
        if [ -n "$val" ] && [ "$val" != "your-token-here" ]; then
            has_messaging=true
            break
        fi
    done

    [ "$has_messaging" = true ] || return 0
    [ -e /dev/tty ] || return 0

    echo ""
    log_info "检测到消息平台 Token"
    log_info "Hermes 要正常收发消息，需要启动网关进程"
    echo ""

    read -p "安装结束后要立即启动网关吗？[Y/n] " -n 1 -r < /dev/tty
    echo
    if [[ $REPLY =~ ^[Nn]$ ]]; then
        log_info "已跳过。后续可手动运行：hermes gateway"
        return 0
    fi

    local hermes_cmd
    hermes_cmd="$(get_hermes_command_path)"

    if [ "$DISTRO" != "termux" ] && command -v systemctl >/dev/null 2>&1; then
        if $hermes_cmd gateway install 2>/dev/null; then
            if $hermes_cmd gateway start 2>/dev/null; then
                log_success "网关已启动"
            else
                log_warn "网关服务已安装，但启动失败"
            fi
        else
            log_warn "Systemd 安装失败，请手动运行：hermes gateway"
        fi
    else
        nohup $hermes_cmd gateway > "$HERMES_HOME/logs/gateway.log" 2>&1 &
        log_success "网关已启动 in background (logs: ~/.hermes/logs/gateway.log)"
    fi
}

print_success() {
    echo ""
    echo -e "${GREEN}${BOLD}"
    echo "┌─────────────────────────────────────────────────────────┐"
    echo "│              ✓ 安装完成！                   │"
    echo "└─────────────────────────────────────────────────────────┘"
    echo -e "${NC}"
    echo ""

    echo -e "${CYAN}${BOLD}📁 你的文件（都在 ~/.hermes/ 下）：${NC}"
    echo ""
    echo -e "   ${YELLOW}配置：${NC}    ~/.hermes/config.yaml"
    echo -e "   ${YELLOW}密钥：${NC}  ~/.hermes/.env"
    echo -e "   ${YELLOW}数据：${NC}      ~/.hermes/cron/, sessions/, logs/"
    echo -e "   ${YELLOW}代码：${NC}      ~/.hermes/hermes-agent/"
    echo ""

    echo -e "${CYAN}─────────────────────────────────────────────────────────${NC}"
    echo ""
    echo -e "${CYAN}${BOLD}🚀 常用命令：${NC}"
    echo ""
    echo -e "   ${GREEN}hermes${NC}              开始聊天"
    echo -e "   ${GREEN}hermes setup${NC}        配置 API Key 和设置"
    echo -e "   ${GREEN}hermes config${NC}       查看 / 编辑配置"
    echo -e "   ${GREEN}hermes gateway install${NC} 安装网关服务"
    echo -e ""

    if [ "$INSTALL_BROWSER_TOOLS" = false ]; then
        echo -e "${YELLOW}⚡ 中国大陆镜像版默认跳过 Browser / Chromium 工具链。${NC}"
        echo -e "${YELLOW}   如果你后续需要浏览器功能，请使用指令：cd ~/.hermes/hermes-agent && npm install 进行安装${NC}"
        echo -e "${YELLOW}   装完后使用指令检查 hermes doctor${NC}"
        echo -e "${YELLOW}   及 hermes tools list${NC}"
        echo ""
    fi

    if [ "$INSTALL_WHATSAPP_BRIDGE" = false ]; then
        echo -e "${YELLOW}⚡ WhatsApp 桥接未自动安装（上游依赖仍绑定 GitHub git 源）。${NC}"
        echo ""
    fi

    if [ "$INSTALL_OPTIONAL_EXTRAS" = false ]; then
        echo -e "${YELLOW}⚡ 当前默认只安装 Hermes 核心 Python 依赖。${NC}"
        echo -e "${YELLOW}   如需完整扩展依赖，可稍后在仓库目录中执行：${NC}"
        echo "   ./venv/bin/python -m pip install -e '.[all]'"
        echo ""
    fi

    if [ "$DISTRO" = "termux" ]; then
        echo -e "${YELLOW}⚡ 'hermes' 已链接到 $(get_command_link_display_dir)，Termux 下可直接使用。${NC}"
    else
        echo -e "${YELLOW}⚡ 请重新加载 shell 后再使用 'hermes' 命令：${NC}"
        LOGIN_SHELL="$(basename "${SHELL:-/bin/bash}")"
        if [ "$LOGIN_SHELL" = "zsh" ]; then
            echo "   source ~/.zshrc"
        elif [ "$LOGIN_SHELL" = "bash" ]; then
            echo "   source ~/.bashrc"
        else
            echo "   source ~/.bashrc   # 或 ~/.zshrc"
        fi
    fi
    echo ""
}

# ==========================================================================
# Main
# ==========================================================================

main() {
    print_banner
    configure_network_defaults

    print_step "第 1 步 / 7：识别系统环境"
    detect_os

    print_step "第 2 步 / 7：准备 Python 运行环境"
    check_python

    print_step "第 3 步 / 7：检查基础工具"
    check_optional_system_packages

    print_step "第 4 步 / 7：获取 Hermes 代码"
    prepare_repo
    patch_hermes_setup_launch_behavior

    print_step "第 5 步 / 7：创建独立运行环境"
    setup_venv

    print_step "第 6 步 / 7：安装 Hermes 核心依赖"
    install_deps

    print_step "第 7 步 / 7：写入命令与配置文件"
    install_optional_node_components
    setup_path
    copy_config_templates
    run_setup_wizard
    maybe_start_gateway
    print_success
}

main
