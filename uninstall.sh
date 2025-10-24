#!/bin/bash

#================================================================
# Xray-Core 一键卸载脚本
#================================================================

# 不使用 set -e，改用显式错误处理
# set -e 会导致交互式输入失败时立即退出
# set -u 在某些条件判断中可能导致问题，暂不启用
set -o pipefail

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

DEPS=(curl wget unzip jq python3 git)
declare -a SUMMARY=()
OS_FAMILY="unknown"

add_summary() {
    local message="$1"
    SUMMARY+=("$message")
}

detect_system() {
    if [[ -f /etc/os-release ]]; then
        # shellcheck disable=SC1091
        . /etc/os-release
        OS_FAMILY=${ID:-unknown}
    fi
    [[ -z "$OS_FAMILY" ]] && OS_FAMILY="unknown"
}

remove_scripts() {
    local operated=false

    if [[ -d /opt/s-xray ]]; then
        print_info "删除管理脚本目录 /opt/s-xray..."
        rm -rf /opt/s-xray
        operated=true
    fi

    for cmd in /usr/local/bin/s-xray /usr/local/bin/xray-manager; do
        if [[ -f "$cmd" || -L "$cmd" ]]; then
            print_info "删除全局命令: $cmd"
            rm -f "$cmd"
            operated=true
        fi
    done

    if [[ "$operated" == true ]]; then
        print_success "管理脚本程序已卸载"
        add_summary "管理脚本程序已卸载"
    else
        print_info "未检测到可卸载的管理脚本"
    fi
}

remove_xray_runtime() {
    local operated=false

    if systemctl is-active --quiet xray 2>/dev/null; then
        print_info "停止 Xray 服务..."
        systemctl stop xray 2>/dev/null || true
        print_success "Xray 服务已停止"
        operated=true
    fi

    if systemctl is-enabled --quiet xray 2>/dev/null; then
        print_info "禁用 Xray 服务..."
        systemctl disable xray 2>/dev/null || true
        operated=true
    fi

    if [[ -f /etc/systemd/system/xray.service ]]; then
        print_info "删除 Xray systemd 单元..."
        rm -f /etc/systemd/system/xray.service
        systemctl daemon-reload 2>/dev/null || true
        operated=true
    fi

    print_info "停止订阅服务..."
    pkill -f "subscription_server.py" 2>/dev/null || true
    pkill -f "python.*subscription_server.py" 2>/dev/null || true
    pkill -f "python.*8080" 2>/dev/null || true

    if [[ -d /usr/local/xray/data ]]; then
        print_info "删除 Xray 数据目录..."
        rm -rf /usr/local/xray/data
        operated=true
    fi

    if [[ -f /usr/local/xray/config.json ]]; then
        print_info "删除 Xray 主配置..."
        rm -f /usr/local/xray/config.json
        operated=true
    fi

    if [[ -d /usr/local/xray ]]; then
        print_info "删除 Xray 核心目录..."
        rm -rf /usr/local/xray
        operated=true
    fi

    if [[ "$operated" == true ]]; then
        print_success "Xray 核心与配置已卸载"
        add_summary "Xray 核心与配置已卸载"
    else
        print_info "未检测到 Xray 核心或配置文件"
    fi
}

remove_dependencies() {
    local remove_list=()
    for dep in "${DEPS[@]}"; do
        if command -v "$dep" >/dev/null 2>&1; then
            remove_list+=("$dep")
        fi
    done

    if [[ ${#remove_list[@]} -eq 0 ]]; then
        print_info "未检测到需要卸载的依赖包"
        return 0
    fi

    print_info "准备卸载依赖包: ${remove_list[*]}"

    case $OS_FAMILY in
        ubuntu|debian)
            apt-get remove -y --purge "${remove_list[@]}" >/dev/null 2>&1 || apt-get remove -y --purge "${remove_list[@]}" || true
            apt-get autoremove -y >/dev/null 2>&1 || true
            apt-get autoclean -y >/dev/null 2>&1 || true
            ;;
        centos|rhel|fedora)
            local pkg_tool=""
            if command -v dnf >/dev/null 2>&1; then
                pkg_tool="dnf"
            elif command -v yum >/dev/null 2>&1; then
                pkg_tool="yum"
            fi

            if [[ -n "$pkg_tool" ]]; then
                $pkg_tool remove -y "${remove_list[@]}" >/dev/null 2>&1 || true
                if [[ "$pkg_tool" == "dnf" ]]; then
                    dnf autoremove -y >/dev/null 2>&1 || true
                elif [[ "$pkg_tool" == "yum" ]]; then
                    yum autoremove -y >/dev/null 2>&1 || true
                fi
            else
                print_warning "未检测到可用的包管理器，跳过依赖卸载"
                return 0
            fi
            ;;
        *)
            print_warning "当前系统未识别，跳过依赖卸载"
            return 0
            ;;
    esac

    print_success "依赖包已卸载"
    add_summary "依赖包已卸载 (${remove_list[*]})"
}

detect_system

# 确保stdin可用
if [[ ! -t 0 ]]; then
    print_warning "检测到stdin不可用，尝试重新打开..."
    if [[ -e /dev/tty ]]; then
        exec < /dev/tty || {
            print_error "无法重新打开 /dev/tty，请在交互式终端中运行此脚本"
            exit 1
        }
    else
        print_error "/dev/tty 不可用，请在交互式终端中运行此脚本"
        exit 1
    fi
fi

clear
echo -e "${CYAN}"
cat << "EOF"
 _   _       _           _        _ _
| | | |_ __ (_)_ __  ___| |_ __ _| | |
| | | | '_ \| | '_ \/ __| __/ _` | | |
| |_| | | | | | | | \__ \ || (_| | | |
 \___/|_| |_|_|_| |_|___/\__\__,_|_|_|
EOF
echo -e "${NC}"
echo -e "${CYAN}=====================================${NC}"
echo -e "${CYAN}    Xray-Core 管理脚本卸载程序${NC}"
echo -e "${CYAN}=====================================${NC}"
echo ""

print_info "卸载程序已启动"
echo ""

# 卸载级别选择菜单
echo -e "${YELLOW}请选择卸载级别：${NC}"
echo ""
echo -e "${CYAN}1.${NC} 仅卸载管理脚本"
echo -e "   - 删除 xray-manager 脚本与 modules"
echo -e "   - ${GREEN}保留${NC} Xray 核心"
echo -e "   - ${GREEN}保留${NC} 配置与数据"
echo ""
echo -e "${CYAN}2.${NC} 仅卸载 Xray 核心与配置文件"
echo -e "   - 停止并删除 Xray 服务"
echo -e "   - 删除 /usr/local/xray 及数据"
echo -e "   - ${GREEN}保留${NC} 管理脚本"
echo ""
echo -e "${CYAN}3.${NC} 完全卸载"
echo -e "   - 删除管理脚本、Xray 核心与配置"
echo -e "   - 清理 systemd 服务与订阅进程"
echo -e "   - 卸载随脚本安装的依赖包"
echo ""
echo -e "${CYAN}0.${NC} 取消卸载"
echo ""

read -r -p "请选择 [0-3]: " uninstall_level || {
    print_error "读取输入失败"
    exit 1
}

case $uninstall_level in
    0)
        print_info "卸载已取消"
        exit 0
        ;;
    1)
        UNINSTALL_LEVEL="script"
        print_info "将执行：仅卸载管理脚本"
        ;;
    2)
        UNINSTALL_LEVEL="xray_only"
        print_info "将执行：仅卸载 Xray 核心与配置文件"
        ;;
    3)
        UNINSTALL_LEVEL="full"
        print_info "将执行：完全卸载"
        ;;
    *)
        print_error "无效选择"
        exit 1
        ;;
esac

echo ""
read -p "确定要继续吗? [y/N]: " confirm || {
    echo ""
    print_info "卸载已取消"
    exit 0
}

if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
    print_info "卸载已取消"
    exit 0
fi

echo ""
print_info "开始卸载..."

case "$UNINSTALL_LEVEL" in
    script)
        remove_scripts
        ;;
    xray_only)
        remove_xray_runtime
        ;;
    full)
        remove_xray_runtime
        remove_scripts
        remove_dependencies
        ;;
esac

if [[ "$UNINSTALL_LEVEL" == "xray_only" || "$UNINSTALL_LEVEL" == "full" ]]; then
    echo ""
    print_warning "是否额外清理防火墙规则?"
    echo -e "  ${YELLOW}提示：${NC}将移除脚本曾开放的端口，请谨慎操作"
    read -p "清理防火墙规则? [y/N]: " clean_firewall || clean_firewall="n"

    if [[ "$clean_firewall" == "y" || "$clean_firewall" == "Y" ]]; then
        print_info "检查常见防火墙工具..."
        if command -v ufw >/dev/null 2>&1 && ufw status | grep -q "Status: active"; then
            print_info "检测到 UFW，可手动执行: ufw status numbered"
        elif command -v firewall-cmd >/dev/null 2>&1; then
            print_info "检测到 firewalld，可手动执行: firewall-cmd --list-all"
        else
            print_info "未检测到活动防火墙，无需额外清理"
        fi
        add_summary "防火墙规则已检查"
    fi
fi

echo ""
echo -e "${GREEN}=====================================${NC}"
echo -e "${GREEN}         卸载完成！${NC}"
echo -e "${GREEN}=====================================${NC}"
echo ""
echo -e "${CYAN}卸载摘要：${NC}"
if [[ ${#SUMMARY[@]} -eq 0 ]]; then
    echo -e "  ${YELLOW}•${NC} 未执行任何资源删除操作"
else
    for item in "${SUMMARY[@]}"; do
        echo -e "  ${GREEN}•${NC} $item"
    done
fi

echo ""
case "$UNINSTALL_LEVEL" in
    script)
        print_info "Xray 核心与配置已保留，可随时重新部署管理脚本。"
        ;;
    xray_only)
        print_info "管理脚本已保留，如需重新部署 Xray，请重新运行安装流程。"
        ;;
    full)
        print_info "已完成彻底卸载，如需再次使用请重新执行安装脚本。"
        ;;
esac

echo ""
echo -e "${CYAN}感谢使用 s-xray 管理脚本！${NC}"
echo ""
