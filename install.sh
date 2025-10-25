#!/bin/bash

#================================================================
# Xray-Core 一键安装脚本
# 快速安装入口
#================================================================

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# 打印函数
print_info() { echo -e "${CYAN}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }

# 检查 root 权限
if [[ $EUID -ne 0 ]]; then
    print_error "此脚本必须以 root 权限运行"
    exit 1
fi

clear
echo -e "${CYAN}"
cat << "EOF"
 __  __                  __  __
 \ \/ /_ __ __ _ _   _  |  \/  | __ _ _ __   __ _  __ _  ___ _ __
  \  /| '__/ _` | | | | | |\/| |/ _` | '_ \ / _` |/ _` |/ _ \ '__|
  /  \| | | (_| | |_| | | |  | | (_| | | | | (_| | (_| |  __/ |
 /_/\_\_|  \__,_|\__, | |_|  |_|\__,_|_| |_|\__,_|\__, |\___|_|
                 |___/                            |___/
EOF
echo -e "${NC}"
echo -e "${CYAN}=====================================${NC}"
echo -e "${CYAN}    Xray-Core 一键管理脚本安装程序${NC}"
echo -e "${CYAN}=====================================${NC}"
echo ""

# 检查系统
print_info "检测系统信息..."

if [[ -f /etc/os-release ]]; then
    . /etc/os-release
    OS=$ID
    VER=$VERSION_ID
    print_success "系统: $PRETTY_NAME"
else
    print_error "无法检测系统类型"
    exit 1
fi

# 检查架构
ARCH=$(uname -m)
print_info "系统架构: $ARCH"

case $ARCH in
    x86_64)
        print_success "支持的架构"
        ;;
    aarch64|armv7l)
        print_success "支持的架构"
        ;;
    *)
        print_error "不支持的架构: $ARCH"
        exit 1
        ;;
esac

# 安装依赖
print_info "安装必要依赖..."

case $OS in
    ubuntu|debian)
        print_info "更新软件包列表..."
        apt-get update -qq 2>&1 | grep -E "^(Get:|Fetched|Reading)" || true

        DEPS="curl wget unzip jq python3 git"
        for dep in $DEPS; do
            if ! command -v $dep >/dev/null 2>&1; then
                print_info "正在安装: $dep"
                apt-get install -y $dep 2>&1 | grep -E "^(Setting up|Unpacking)" || true
            else
                print_info "已安装: $dep ✓"
            fi
        done
        ;;
    centos|rhel|fedora)
        DEPS="curl wget unzip jq python3 git"
        for dep in $DEPS; do
            if ! command -v $dep >/dev/null 2>&1; then
                print_info "正在安装: $dep"
                yum install -y $dep 2>&1 | grep -E "^(Installing|Complete)" || true
            else
                print_info "已安装: $dep ✓"
            fi
        done
        ;;
    *)
        print_warning "未知系统，跳过依赖安装"
        ;;
esac

print_success "依赖安装完成"

# 检查脚本文件
print_info "检查脚本文件..."

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 检测是否为在线安装（通过 curl | bash 方式）
if [[ ! -f "${SCRIPT_DIR}/xray-manager.sh" ]] || [[ ! -d "${SCRIPT_DIR}/modules" ]]; then
    print_info "检测到在线安装，正在下载完整项目..."

    # 设置安装目录
    INSTALL_DIR="/opt/s-xray"

    # 如果目录已存在，更新而不是删除
    if [[ -d "$INSTALL_DIR" ]]; then
        print_info "检测到已安装，将更新到最新版本..."

        # 备份用户数据（如果存在）
        if [[ -d "$INSTALL_DIR/data" ]]; then
            print_info "备份用户数据..."
            BACKUP_DIR="/tmp/s-xray-backup-$(date +%Y%m%d%H%M%S)"
            mkdir -p "$BACKUP_DIR"
            cp -r "$INSTALL_DIR/data" "$BACKUP_DIR/" 2>/dev/null || true
            print_success "用户数据已备份到: $BACKUP_DIR"
        fi

        # 删除旧的脚本文件，但保留数据目录
        print_info "清理旧版本文件..."
        rm -rf "$INSTALL_DIR"/*.sh "$INSTALL_DIR"/modules 2>/dev/null || true
    fi

    # 创建临时目录
    TEMP_DIR=$(mktemp -d)
    cd "$TEMP_DIR"

    # 下载项目文件
    print_info "下载项目文件..."
    DOWNLOAD_SUCCESS=false

    if command -v git >/dev/null 2>&1; then
        # 优先使用 git clone
        git clone --depth=1 https://github.com/sindricn/s-xray.git s-xray >/dev/null 2>&1
        if [[ $? -eq 0 ]]; then
            # 创建或更新安装目录
            mkdir -p "$INSTALL_DIR"
            # 复制文件到安装目录（保留数据目录）
            cp -r s-xray/* "$INSTALL_DIR/" 2>/dev/null || true
            DOWNLOAD_SUCCESS=true
        fi
    fi

    if [[ "$DOWNLOAD_SUCCESS" == "false" ]]; then
        # 使用 wget 或 curl 下载 zip
        if command -v wget >/dev/null 2>&1; then
            wget -q https://github.com/sindricn/s-xray/archive/refs/heads/main.zip -O s-xray.zip
        elif command -v curl >/dev/null 2>&1; then
            curl -sL https://github.com/sindricn/s-xray/archive/refs/heads/main.zip -o s-xray.zip
        else
            print_error "未找到 wget 或 curl 命令"
            rm -rf "$TEMP_DIR"
            exit 1
        fi

        # 解压文件
        if unzip -q s-xray.zip 2>/dev/null; then
            # 创建或更新安装目录
            mkdir -p "$INSTALL_DIR"
            # 复制文件到安装目录（保留数据目录）
            cp -r s-xray-main/* "$INSTALL_DIR/" 2>/dev/null || true
            DOWNLOAD_SUCCESS=true
        fi
    fi

    # 检查下载是否成功
    if [[ "$DOWNLOAD_SUCCESS" == "false" ]]; then
        print_error "项目文件下载失败"
        rm -rf "$TEMP_DIR"
        exit 1
    fi

    # 恢复用户数据（如果有备份）
    if [[ -n "$BACKUP_DIR" && -d "$BACKUP_DIR/data" ]]; then
        print_info "恢复用户数据..."
        cp -r "$BACKUP_DIR/data" "$INSTALL_DIR/" 2>/dev/null || true
        print_success "用户数据已恢复"
    fi

    # 清理临时文件
    rm -rf "$TEMP_DIR"

    # 更新 SCRIPT_DIR
    SCRIPT_DIR="$INSTALL_DIR"
    cd "$SCRIPT_DIR"

    print_success "项目文件下载完成"
fi

# 验证文件
if [[ ! -f "${SCRIPT_DIR}/xray-manager.sh" ]]; then
    print_error "未找到主脚本文件: ${SCRIPT_DIR}/xray-manager.sh"
    exit 1
fi

if [[ ! -d "${SCRIPT_DIR}/modules" ]]; then
    print_error "未找到模块目录: ${SCRIPT_DIR}/modules"
    exit 1
fi

print_success "脚本文件检查完成"

# 设置权限
print_info "设置执行权限..."
chmod +x "${SCRIPT_DIR}/xray-manager.sh"
chmod +x "${SCRIPT_DIR}/modules/"*.sh 2>/dev/null || true
chmod +x "${SCRIPT_DIR}/install.sh" 2>/dev/null || true
chmod +x "${SCRIPT_DIR}/uninstall.sh" 2>/dev/null || true

print_success "权限设置完成"

# 创建软链接
print_info "创建命令软链接..."
ln -sf "${SCRIPT_DIR}/xray-manager.sh" /usr/local/bin/xray-manager 2>/dev/null || true
ln -sf "${SCRIPT_DIR}/xray-manager.sh" /usr/local/bin/s-xray 2>/dev/null || true

if [[ -f /usr/local/bin/s-xray ]]; then
    print_success "可以使用 's-xray' 或 'xray-manager' 命令启动脚本"
fi

echo ""
echo -e "${GREEN}=====================================${NC}"
echo -e "${GREEN}         安装完成！${NC}"
echo -e "${GREEN}=====================================${NC}"
echo ""
echo -e "${CYAN}安装信息：${NC}"
echo -e "  安装目录: ${YELLOW}${SCRIPT_DIR}${NC}"
echo -e "  全局命令: ${YELLOW}s-xray${NC} / ${YELLOW}xray-manager${NC}"
echo ""
echo -e "${CYAN}快速开始：${NC}"
echo ""
echo -e "  1. 启动管理脚本："
echo -e "     ${YELLOW}s-xray${NC}  ${GREEN}(推荐)${NC}"
echo -e "     或"
echo -e "     ${YELLOW}xray-manager${NC}"
echo -e "     或"
echo -e "     ${YELLOW}${SCRIPT_DIR}/xray-manager.sh${NC}"
echo ""
echo -e "  2. 首次使用建议："
echo -e "     - 安装 Xray 内核"
echo -e "     - 添加节点"
echo -e "     - 添加用户"
echo -e "     - 生成订阅"
echo -e "     - 开放防火墙端口"
echo ""
echo -e "${CYAN}卸载方式：${NC}"
echo -e "  ${YELLOW}bash ${SCRIPT_DIR}/uninstall.sh${NC}"
echo ""
echo -e "${CYAN}文档：${NC}"
echo -e "  查看完整文档: ${YELLOW}${SCRIPT_DIR}/README.md${NC}"
echo ""
echo -e "${CYAN}感谢使用 Xray 管理脚本！${NC}"
echo ""

# 询问是否立即启动（仅在交互式终端时询问）
if [[ -t 0 ]]; then
    read -p "是否立即启动管理脚本? [Y/n]: " start_now
    if [[ "$start_now" != "n" && "$start_now" != "N" ]]; then
        exec "${SCRIPT_DIR}/xray-manager.sh"
    fi
else
    # 非交互式终端（通过管道安装）不自动启动
    print_info "非交互模式，安装完成。请手动运行 's-xray' 启动脚本"
fi
