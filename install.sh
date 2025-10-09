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
        apt-get update -qq
        apt-get install -y curl wget unzip jq python3 >/dev/null 2>&1
        ;;
    centos|rhel|fedora)
        yum install -y curl wget unzip jq python3 >/dev/null 2>&1
        ;;
    *)
        print_warning "未知系统，跳过依赖安装"
        ;;
esac

print_success "依赖安装完成"

# 检查脚本文件
print_info "检查脚本文件..."

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ ! -f "${SCRIPT_DIR}/xray-manager.sh" ]]; then
    print_error "未找到主脚本文件"
    exit 1
fi

if [[ ! -d "${SCRIPT_DIR}/modules" ]]; then
    print_error "未找到模块目录"
    exit 1
fi

print_success "脚本文件检查完成"

# 设置权限
print_info "设置执行权限..."
chmod +x "${SCRIPT_DIR}/xray-manager.sh"
chmod +x "${SCRIPT_DIR}/modules/"*.sh 2>/dev/null || true

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
echo -e "${CYAN}文档：${NC}"
echo -e "  查看完整文档: ${YELLOW}${SCRIPT_DIR}/README.md${NC}"
echo ""
echo -e "${CYAN}感谢使用 Xray 管理脚本！${NC}"
echo ""

# 询问是否立即启动
read -p "是否立即启动管理脚本? [Y/n]: " start_now
if [[ "$start_now" != "n" && "$start_now" != "N" ]]; then
    exec "${SCRIPT_DIR}/xray-manager.sh"
fi
