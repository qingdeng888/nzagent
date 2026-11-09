#!/bin/sh
# ============================================================
# QingNZ 探针 Linux/macOS/FreeBSD 一键安装脚本
#
#   安装目录: /etc/.qingnz
#   二进制:   /etc/.qingnz/qingnz
#   配置:     /etc/.qingnz/config.yml
#   服务名:   qingnz.service (systemd) / qingnz (OpenRC/launchd)
#
# 用法(环境变量在运行前设置):
#   env NZ_SERVER=xxx NZ_CLIENT_SECRET=xxx [NZ_TLS=true] [NZ_UUID=xxx] ./install.sh
#   ./install.sh uninstall   # 卸载
#
# 可选环境变量:
#   NZ_GH_PROXY   GitHub 加速代理前缀 (设置后跳过交互询问), 例: https://raw.xiaoy.de/
#   其余 NZ_* 变量同官方 agent, 见 https://nezha.wiki
# ============================================================

NZ_BASE_PATH="/etc/.qingnz"
NZ_AGENT_PATH="${NZ_BASE_PATH}"
NZ_BIN_NAME="qingnz"
NZ_REPO="qingdeng888/nzagent"
NZ_GH_PROXY_DEFAULT="https://raw.xiaoy.de/"
GH_PROXY=""

red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
plain='\033[0m'

err() {
    printf "${red}%s${plain}\n" "$*" >&2
}

success() {
    printf "${green}%s${plain}\n" "$*"
}

info() {
    printf "${yellow}%s${plain}\n" "$*"
}

# 非 root 时自动借道 sudo
sudo() {
    myEUID=$(id -ru)
    if [ "$myEUID" -ne 0 ]; then
        if command -v sudo > /dev/null 2>&1; then
            command sudo "$@"
        else
            err "ERROR: sudo is not installed on the system, the action cannot be proceeded."
            exit 1
        fi
    else
        "$@"
    fi
}

deps_check() {
    local deps="unzip grep"
    local _err=0
    local missing=""

    for dep in $deps; do
        if ! command -v "$dep" >/dev/null 2>&1; then
            _err=1
            missing="${missing} $dep"
        fi
    done

    if ! command -v curl >/dev/null 2>&1 && ! command -v wget >/dev/null 2>&1; then
        _err=1
        missing="${missing} curl/wget"
    fi

    if [ "$_err" -ne 0 ]; then
        err "Missing dependencies:$missing. Please install them and try again."
        exit 1
    fi
}

env_check() {
    mach=$(uname -m)
    case "$mach" in
        amd64|x86_64)
            os_arch="amd64"
            ;;
        i386|i686)
            os_arch="386"
            ;;
        aarch64|arm64)
            os_arch="arm64"
            ;;
        *arm*)
            os_arch="arm"
            ;;
        s390x)
            os_arch="s390x"
            ;;
        riscv64)
            os_arch="riscv64"
            ;;
        mips)
            os_arch="mips"
            ;;
        mipsel|mipsle)
            os_arch="mipsle"
            ;;
        loongarch64)
            os_arch="loong64"
            ;;
        *)
            err "Unknown architecture: $mach"
            exit 1
            ;;
    esac

    system=$(uname)
    case "$system" in
        *Linux*)
            os="linux"
            ;;
        *Darwin*)
            os="darwin"
            ;;
        *FreeBSD*)
            os="freebsd"
            ;;
        *)
            err "Unknown OS: $system"
            exit 1
            ;;
    esac
}

# 代理前缀: NZ_GH_PROXY 环境变量优先, 否则安装时交互询问 (回车默认不使用)
proxy_setup() {
    if [ -n "$GH_PROXY" ]; then
        return
    fi
    if [ -n "$NZ_GH_PROXY" ]; then
        GH_PROXY="$NZ_GH_PROXY"
        return
    fi
    printf "是否使用 GitHub 加速代理 (${NZ_GH_PROXY_DEFAULT}) ? 回车默认不使用 [y/N]: "
    read -r input
    case $input in
        [yY][eE][sS] | [yY])
            GH_PROXY="${NZ_GH_PROXY_DEFAULT}"
            info "已启用 GitHub 加速代理: ${GH_PROXY}"
            ;;
        *)
            info "不使用加速代理, 直连 GitHub"
            ;;
    esac
}

# 拼接加速代理前缀到 GitHub 下载链接
gh_url() {
    if [ -n "$GH_PROXY" ]; then
        printf "%s%s" "$GH_PROXY" "$1"
    else
        printf "%s" "$1"
    fi
}

download() {
    _url="$(gh_url "$1")"
    _out="$2"

    info "Downloading: $_url"
    if command -v wget >/dev/null 2>&1; then
        _cmd="wget --timeout=60 -O \"$_out\" \"$_url\""
    else
        _cmd="curl --max-time 60 -fsSL \"$_url\" -o \"$_out\""
    fi

    if ! eval "$_cmd"; then
        err "Download qingnz release failed, check your network connectivity (或使用加速代理后重试)"
        exit 1
    fi
}

install() {
    echo "Installing QingNZ agent..."

    # 决定是否走加速代理 (交互询问, NZ_GH_PROXY 可跳过)
    proxy_setup

    if [ -z "$NZ_SERVER" ]; then
        err "NZ_SERVER should not be empty"
        exit 1
    fi

    if [ -z "$NZ_CLIENT_SECRET" ]; then
        err "NZ_CLIENT_SECRET should not be empty"
        exit 1
    fi

    NZ_AGENT_URL="https://github.com/${NZ_REPO}/releases/latest/download/qingnz_${os}_${os_arch}.zip"

    download "$NZ_AGENT_URL" "/tmp/qingnz_${os}_${os_arch}.zip"

    sudo mkdir -p "$NZ_AGENT_PATH"

    sudo unzip -qo "/tmp/qingnz_${os}_${os_arch}.zip" -d "$NZ_AGENT_PATH" &&
        sudo rm -rf "/tmp/qingnz_${os}_${os_arch}.zip"

    if [ ! -f "${NZ_AGENT_PATH}/${NZ_BIN_NAME}" ]; then
        err "Binary ${NZ_AGENT_PATH}/${NZ_BIN_NAME} not found after extraction"
        exit 1
    fi

    path="$NZ_AGENT_PATH/config.yml"
    if [ -f "$path" ]; then
        # 重新安装: 备份旧配置, 保证新传入的环境变量生效
        sudo mv "$path" "${path}.bak"
    fi

    env="NZ_UUID=$NZ_UUID NZ_SERVER=$NZ_SERVER NZ_CLIENT_SECRET=$NZ_CLIENT_SECRET NZ_TLS=$NZ_TLS NZ_TEMPERATURE=$NZ_TEMPERATURE NZ_GPU=$NZ_GPU NZ_DISABLE_AUTO_UPDATE=$NZ_DISABLE_AUTO_UPDATE NZ_DISABLE_FORCE_UPDATE=$NZ_DISABLE_FORCE_UPDATE NZ_DISABLE_COMMAND_EXECUTE=$NZ_DISABLE_COMMAND_EXECUTE NZ_SKIP_CONNECTION_COUNT=$NZ_SKIP_CONNECTION_COUNT"

    # 清理旧服务(若有)
    sudo "${NZ_AGENT_PATH}"/"${NZ_BIN_NAME}" service -c "$path" uninstall >/dev/null 2>&1

    # 服务名自动取二进制文件名 -> qingnz.service
    _cmd="sudo env $env $NZ_AGENT_PATH/${NZ_BIN_NAME} service -c $path install"
    if ! eval "$_cmd"; then
        err "Install qingnz service failed"
        sudo "${NZ_AGENT_PATH}"/"${NZ_BIN_NAME}" service -c "$path" uninstall >/dev/null 2>&1
        exit 1
    fi

    if ! sudo "${NZ_AGENT_PATH}"/"${NZ_BIN_NAME}" service -c "$path" start; then
        err "Start qingnz service failed, check: systemctl status qingnz"
        exit 1
    fi

    success "qingnz successfully installed at ${NZ_AGENT_PATH}/${NZ_BIN_NAME}"
    info "Service: qingnz.service    Config: $path"
}

uninstall() {
    find "$NZ_AGENT_PATH" -type f -name "*config*.yml" | while read -r file; do
        sudo "$NZ_AGENT_PATH/${NZ_BIN_NAME}" service -c "$file" uninstall
        sudo rm -f "$file"
    done
    sudo rm -rf "$NZ_AGENT_PATH"
    success "QingNZ agent uninstalled."
}

if [ "$1" = "uninstall" ]; then
    if [ -d "$NZ_AGENT_PATH" ]; then
        uninstall
    else
        info "$NZ_AGENT_PATH not found, nothing to uninstall."
    fi
    exit
fi

deps_check
env_check
install
