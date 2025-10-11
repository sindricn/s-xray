#!/bin/bash

#================================================================
# Xray-Core 一键卸载脚本
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

# 卸载级别选择菜单
echo -e "${YELLOW}请选择卸载级别：${NC}"
echo ""
echo -e "${CYAN}1.${NC} 仅卸载管理脚本"
echo -e "   - 删除xray-manager.sh及modules目录"
echo -e "   - ${GREEN}保留${NC} Xray核心"
echo -e "   - ${GREEN}保留${NC} 所有配置和数据"
echo ""
echo -e "${CYAN}2.${NC} 卸载脚本和配置文件"
echo -e "   - 删除管理脚本和modules"
echo -e "   - 删除所有配置文件(nodes.json, users.json等)"
echo -e "   - ${GREEN}保留${NC} Xray核心程序"
echo ""
echo -e "${CYAN}3.${NC} 完全卸载"
echo -e "   - 删除管理脚本和配置"
echo -e "   - 停止并删除Xray服务"
echo -e "   - 删除Xray核心程序"
echo -e "   - ${YELLOW}可选${NC}删除依赖包"
echo ""
echo -e "${CYAN}0.${NC} 取消卸载"
echo ""

read -p "请选择 [0-3]: " uninstall_level

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
        UNINSTALL_LEVEL="script_config"
        print_info "将执行：卸载脚本和配置文件"
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
read -p "确定要继续吗? [y/N]: " confirm

if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
    print_info "卸载已取消"
    exit 0
fi

echo ""
print_info "开始卸载..."

# 级别1和级别2和级别3都需要：删除管理脚本
if [[ -d /opt/s-xray ]]; then
    print_info "删除管理脚本和modules..."
    rm -rf /opt/s-xray
    print_success "管理脚本已删除"
fi

# 级别1：仅卸载脚本（到此结束）
if [[ "$UNINSTALL_LEVEL" == "script" ]]; then
    print_success "管理脚本卸载完成！"
    print_info "Xray核心和配置文件已保留"
    exit 0
fi

# 级别2和级别3都需要：删除配置文件
if [[ -d /usr/local/xray/data ]]; then
    print_info "删除配置文件..."
    rm -rf /usr/local/xray/data
    print_success "配置文件已删除"
fi

if [[ -f /usr/local/xray/config.json ]]; then
    rm -f /usr/local/xray/config.json
fi

# 级别2：卸载脚本和配置（到此结束）
if [[ "$UNINSTALL_LEVEL" == "script_config" ]]; then
    print_success "管理脚本和配置文件卸载完成！"
    print_info "Xray核心程序已保留"
    exit 0
fi

# 级别3：完全卸载
print_info "执行完全卸载..."

# 停止 Xray 服务
if systemctl is-active --quiet xray 2>/dev/null; then
    print_info "停止 Xray 服务..."
    systemctl stop xray
    print_success "服务已停止"
fi

# 禁用并删除服务
if [[ -f /etc/systemd/system/xray.service ]]; then
    print_info "删除系统服务..."
    systemctl disable xray 2>/dev/null || true
    rm -f /etc/systemd/system/xray.service
    systemctl daemon-reload
    print_success "服务已删除"
fi

# 停止订阅服务
print_info "停止订阅服务..."
pkill -f "subscription_server.py" 2>/dev/null || true
pkill -f "python.*8080" 2>/dev/null || true
print_success "订阅服务已停止"

# 删除 Xray 程序
if [[ -d /usr/local/xray ]]; then
    print_info "删除 Xray 核心程序..."
    rm -rf /usr/local/xray
    print_success "Xray 核心已删除"
fi

# 6. 删除全局命令
print_info "删除全局命令..."
rm -f /usr/local/bin/s-xray
rm -f /usr/local/bin/xray-manager
print_success "全局命令已删除"

# 7. 清理防火墙规则（可选）
echo ""
print_warning "是否清理防火墙规则?"
echo -e "  ${YELLOW}注意：${NC}这将关闭所有由脚本开放的端口"
read -p "清理防火墙规则? [y/N]: " clean_firewall

if [[ "$clean_firewall" == "y" || "$clean_firewall" == "Y" ]]; then
    print_info "清理防火墙规则..."

    # 检测防火墙类型
    if command -v ufw >/dev/null 2>&1 && ufw status | grep -q "Status: active"; then
        # UFW 防火墙
        print_info "检测到 UFW 防火墙，请手动检查规则: ufw status numbered"
    elif command -v firewall-cmd >/dev/null 2>&1; then
        # Firewalld 防火墙
        print_info "检测到 Firewalld 防火墙，请手动检查规则: firewall-cmd --list-all"
    else
        print_info "未检测到活动的防火墙管理工具"
    fi
fi

echo ""
echo -e "${GREEN}=====================================${NC}"
echo -e "${GREEN}         卸载完成！${NC}"
echo -e "${GREEN}=====================================${NC}"
echo ""
echo -e "${CYAN}卸载摘要：${NC}"
echo -e "  ${GREEN}✓${NC} Xray 服务已停止并删除"
echo -e "  ${GREEN}✓${NC} 管理脚本已删除"
echo -e "  ${GREEN}✓${NC} 全局命令已删除"

if [[ "$delete_data" == "y" || "$delete_data" == "Y" ]]; then
    echo -e "  ${GREEN}✓${NC} 用户数据已删除"
else
    echo -e "  ${YELLOW}!${NC} 用户数据已保留: /usr/local/xray/data/"
    echo -e "    如需完全清理，请手动删除: ${YELLOW}rm -rf /usr/local/xray${NC}"
fi

echo ""
echo -e "${CYAN}感谢使用 s-xray 管理脚本！${NC}"
echo ""
