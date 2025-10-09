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

# 卸载确认
print_warning "此操作将完全卸载 s-xray 管理脚本和相关配置"
echo ""
echo -e "将执行以下操作："
echo -e "  ${RED}✗${NC} 停止并删除 Xray 服务"
echo -e "  ${RED}✗${NC} 删除 Xray 程序和配置文件"
echo -e "  ${RED}✗${NC} 删除管理脚本 (/opt/s-xray)"
echo -e "  ${RED}✗${NC} 删除全局命令 (s-xray, xray-manager)"
echo -e "  ${YELLOW}!${NC} 保留用户数据和备份 (可选择删除)"
echo ""
read -p "确定要继续卸载吗? [y/N]: " confirm

if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
    print_info "卸载已取消"
    exit 0
fi

echo ""
print_info "开始卸载..."

# 1. 停止 Xray 服务
if systemctl is-active --quiet xray 2>/dev/null; then
    print_info "停止 Xray 服务..."
    systemctl stop xray
    print_success "服务已停止"
fi

# 2. 禁用并删除服务
if [[ -f /etc/systemd/system/xray.service ]]; then
    print_info "删除系统服务..."
    systemctl disable xray 2>/dev/null || true
    rm -f /etc/systemd/system/xray.service
    systemctl daemon-reload
    print_success "服务已删除"
fi

# 3. 停止订阅服务
print_info "停止订阅服务..."
pkill -f "subscription_server.py" 2>/dev/null || true
pkill -f "python.*8080" 2>/dev/null || true
print_success "订阅服务已停止"

# 4. 询问是否删除用户数据
echo ""
print_warning "是否删除用户数据和配置备份?"
echo -e "  数据位置: ${YELLOW}/usr/local/xray/data/${NC}"
echo -e "  包含内容: 用户信息、节点配置、订阅数据、配置备份"
read -p "删除用户数据? [y/N]: " delete_data

if [[ "$delete_data" == "y" || "$delete_data" == "Y" ]]; then
    # 删除 Xray 完整目录
    if [[ -d /usr/local/xray ]]; then
        print_info "删除 Xray 程序和数据..."
        rm -rf /usr/local/xray
        print_success "Xray 数据已删除"
    fi
else
    # 仅删除 Xray 程序，保留数据
    if [[ -d /usr/local/xray ]]; then
        print_info "删除 Xray 程序（保留数据）..."
        rm -f /usr/local/xray/xray
        rm -f /usr/local/xray/config.json
        rm -f /usr/local/xray/*.log
        print_success "Xray 程序已删除"
        print_info "用户数据已保留在: /usr/local/xray/data/"
    fi
fi

# 5. 删除管理脚本
if [[ -d /opt/s-xray ]]; then
    print_info "删除管理脚本..."
    rm -rf /opt/s-xray
    print_success "管理脚本已删除"
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
