#!/bin/bash

#================================================================
# Xray-Core 一键管理脚本
# 支持功能：内核管理、节点管理、用户管理、订阅管理、状态监控、防火墙管理
# 版本：v1.2.0
# 优化：基于 s-hy2 最佳实践
#================================================================

# 严格模式
set -uo pipefail

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# 全局变量
readonly XRAY_DIR="/usr/local/xray"
readonly XRAY_BIN="${XRAY_DIR}/xray"
readonly XRAY_CONFIG="${XRAY_DIR}/config.json"
readonly XRAY_SERVICE="/etc/systemd/system/xray.service"
readonly DATA_DIR="${XRAY_DIR}/data"
readonly USERS_FILE="${DATA_DIR}/users.json"
readonly NODES_FILE="${DATA_DIR}/nodes.json"
readonly SUBSCRIPTION_DIR="${DATA_DIR}/subscriptions"

# 日志配置
export LOG_FILE="/var/log/xray-manager.log"
export LOG_LEVEL=${LOG_LEVEL:-1}  # 默认 INFO 级别

# 加载模块
source_modules() {
    # 解析真实脚本路径（处理软链接）
    local script_path="${BASH_SOURCE[0]}"

    # 如果是软链接，解析真实路径
    if [[ -L "$script_path" ]]; then
        script_path="$(readlink -f "$script_path")"
    fi

    local script_dir="$(cd "$(dirname "$script_path")" && pwd)"
    local modules_dir="${script_dir}/modules"

    if [[ ! -d "$modules_dir" ]]; then
        echo -e "${RED}[ERROR]${NC} 模块目录不存在: $modules_dir"
        echo -e "${RED}[ERROR]${NC} 脚本路径: $script_path"
        echo -e "${RED}[ERROR]${NC} 脚本目录: $script_dir"
        exit 1
    fi

    # 优先加载公共库
    if [[ -f "${modules_dir}/common.sh" ]]; then
        source "${modules_dir}/common.sh"
    else
        echo -e "${RED}[ERROR]${NC} 公共库不存在: ${modules_dir}/common.sh"
        exit 1
    fi

    # 加载输入验证模块
    if [[ -f "${modules_dir}/input-validation.sh" ]]; then
        source "${modules_dir}/input-validation.sh"
    fi

    # 加载其他模块
    for module in "${modules_dir}"/*.sh; do
        if [[ -f "$module" ]] && [[ "$module" != */common.sh ]] && [[ "$module" != */input-validation.sh ]]; then
            source "$module"
            log_debug "已加载模块: $(basename "$module")"
        fi
    done

    log_info "所有模块加载完成"
}

# 初始化数据目录
init_data_dir() {
    mkdir -p "$DATA_DIR"
    mkdir -p "$SUBSCRIPTION_DIR"

    # 初始化用户文件
    if [[ ! -f "$USERS_FILE" ]]; then
        echo '{"users":[]}' > "$USERS_FILE"
    fi

    # 初始化节点文件
    if [[ ! -f "$NODES_FILE" ]]; then
        echo '{"nodes":[]}' > "$NODES_FILE"
    fi
}

# 主菜单
show_menu() {
    clear
    echo -e "${CYAN}=====================================${NC}"
    echo -e "${CYAN}    Xray-Core 一键管理脚本${NC}"
    echo -e "${CYAN}=====================================${NC}"
    echo ""
    echo -e "${GREEN}1.${NC}  内核管理"
    echo -e "${GREEN}2.${NC}  节点管理"
    echo -e "${GREEN}3.${NC}  用户管理"
    echo -e "${GREEN}4.${NC}  订阅管理"
    echo -e "${GREEN}5.${NC}  状态监控"
    echo -e "${GREEN}6.${NC}  防火墙管理"
    echo -e "${GREEN}7.${NC}  配置管理"
    echo -e "${GREEN}8.${NC}  域名管理"
    echo -e "${GREEN}9.${NC}  证书管理"
    echo ""
    echo -e "${RED}99.${NC} 卸载脚本"
    echo -e "${GREEN}0.${NC}  退出脚本"
    echo ""
    echo -e "${CYAN}=====================================${NC}"
}

# 内核管理菜单
menu_core() {
    while true; do
        clear
        echo -e "${CYAN}====== 内核管理 ======${NC}"
        echo -e "${GREEN}1.${NC} 安装 Xray"
        echo -e "${GREEN}2.${NC} 卸载 Xray"
        echo -e "${GREEN}3.${NC} 更新 Xray"
        echo -e "${GREEN}4.${NC} 启动 Xray"
        echo -e "${GREEN}5.${NC} 停止 Xray"
        echo -e "${GREEN}6.${NC} 重启 Xray"
        echo -e "${GREEN}7.${NC} 查看版本"
        echo -e "${GREEN}0.${NC} 返回主菜单"
        echo ""
        read -p "请选择操作 [0-7]: " choice

        case $choice in
            1) install_xray ;;
            2) uninstall_xray ;;
            3) update_xray ;;
            4) start_xray ;;
            5) stop_xray ;;
            6) restart_xray ;;
            7) show_version ;;
            0) break ;;
            *) print_error "无效选择" ;;
        esac

        read -p "按 Enter 键继续..."
    done
}

# 节点管理菜单
menu_node() {
    while true; do
        clear
        echo -e "${CYAN}====== 节点管理 ======${NC}"
        echo ""
        echo -e "${YELLOW}⚡ 快速搭建：${NC}"
        echo -e "${GREEN}1.${NC} 【推荐】一键搭建 VLESS + Reality 节点"
        echo ""
        echo -e "${CYAN}📡 协议管理：${NC}"
        echo -e "${GREEN}2.${NC} 添加 VLESS 节点 (自定义)"
        echo -e "${GREEN}3.${NC} 添加 VMess 节点"
        echo -e "${GREEN}4.${NC} 添加 Trojan 节点"
        echo -e "${GREEN}5.${NC} 添加 Shadowsocks 节点"
        echo ""
        echo -e "${CYAN}🔧 节点管理：${NC}"
        echo -e "${GREEN}6.${NC} 删除节点"
        echo -e "${GREEN}7.${NC} 查看节点列表"
        echo -e "${GREEN}8.${NC} 修改节点配置"
        echo ""
        echo -e "${GREEN}0.${NC} 返回主菜单"
        echo ""
        read -p "请选择操作 [0-8]: " choice

        case $choice in
            1) quick_add_vless_reality ;;
            2) add_vless_node ;;
            3) add_vmess_node ;;
            4) add_trojan_node ;;
            5) add_shadowsocks_node ;;
            6) delete_node ;;
            7) list_nodes ;;
            8) modify_node ;;
            0) break ;;
            *) print_error "无效选择" ;;
        esac

        read -p "按 Enter 键继续..."
    done
}

# 用户管理菜单
menu_user() {
    while true; do
        clear
        echo -e "${CYAN}====== 用户管理 ======${NC}"
        echo -e "${GREEN}1.${NC} 添加用户"
        echo -e "${GREEN}2.${NC} 删除用户"
        echo -e "${GREEN}3.${NC} 查看用户列表"
        echo -e "${GREEN}4.${NC} 修改用户配置"
        echo -e "${GREEN}5.${NC} 生成 UUID"
        echo -e "${GREEN}0.${NC} 返回主菜单"
        echo ""
        read -p "请选择操作 [0-5]: " choice

        case $choice in
            1) add_user ;;
            2) delete_user ;;
            3) list_users ;;
            4) modify_user ;;
            5) generate_uuid ;;
            0) break ;;
            *) print_error "无效选择" ;;
        esac

        read -p "按 Enter 键继续..."
    done
}

# 订阅管理菜单
menu_subscription() {
    while true; do
        clear
        echo -e "${CYAN}====== 订阅管理 ======${NC}"
        echo -e "${GREEN}1.${NC} 生成订阅链接"
        echo -e "${GREEN}2.${NC} 查看订阅链接"
        echo -e "${GREEN}3.${NC} 更新订阅内容"
        echo -e "${GREEN}4.${NC} 删除订阅"
        echo -e "${GREEN}5.${NC} 订阅配置"
        echo -e "${GREEN}0.${NC} 返回主菜单"
        echo ""
        read -p "请选择操作 [0-5]: " choice

        case $choice in
            1) generate_subscription ;;
            2) show_subscription ;;
            3) update_subscription ;;
            4) delete_subscription ;;
            5) config_subscription ;;
            0) break ;;
            *) print_error "无效选择" ;;
        esac

        read -p "按 Enter 键继续..."
    done
}

# 状态监控菜单
menu_monitor() {
    while true; do
        clear
        echo -e "${CYAN}====== 状态监控 ======${NC}"
        echo -e "${GREEN}1.${NC} 查看运行状态"
        echo -e "${GREEN}2.${NC} 查看流量统计"
        echo -e "${GREEN}3.${NC} 查看连接信息"
        echo -e "${GREEN}4.${NC} 查看日志"
        echo -e "${GREEN}5.${NC} 实时监控"
        echo -e "${GREEN}0.${NC} 返回主菜单"
        echo ""
        read -p "请选择操作 [0-5]: " choice

        case $choice in
            1) show_status ;;
            2) show_traffic ;;
            3) show_connections ;;
            4) show_logs ;;
            5) monitor_realtime ;;
            0) break ;;
            *) print_error "无效选择" ;;
        esac

        read -p "按 Enter 键继续..."
    done
}

# 防火墙管理菜单
menu_firewall() {
    while true; do
        clear
        echo -e "${CYAN}====== 防火墙管理 ======${NC}"
        echo -e "${GREEN}1.${NC} 开放端口"
        echo -e "${GREEN}2.${NC} 关闭端口"
        echo -e "${GREEN}3.${NC} 查看规则"
        echo -e "${GREEN}4.${NC} 重置防火墙"
        echo -e "${GREEN}5.${NC} 禁用防火墙"
        echo -e "${GREEN}6.${NC} 启用防火墙"
        echo -e "${GREEN}0.${NC} 返回主菜单"
        echo ""
        read -p "请选择操作 [0-6]: " choice

        case $choice in
            1) open_port ;;
            2) close_port ;;
            3) show_firewall_rules ;;
            4) reset_firewall ;;
            5) disable_firewall ;;
            6) enable_firewall ;;
            0) break ;;
            *) print_error "无效选择" ;;
        esac

        read -p "按 Enter 键继续..."
    done
}

# 配置管理菜单
menu_config() {
    while true; do
        clear
        echo -e "${CYAN}====== 配置管理 ======${NC}"
        echo -e "${GREEN}1.${NC} 查看当前配置"
        echo -e "${GREEN}2.${NC} 编辑配置文件"
        echo -e "${GREEN}3.${NC} 备份配置"
        echo -e "${GREEN}4.${NC} 恢复配置"
        echo -e "${GREEN}5.${NC} 验证配置"
        echo -e "${GREEN}0.${NC} 返回主菜单"
        echo ""
        read -p "请选择操作 [0-5]: " choice

        case $choice in
            1) show_config ;;
            2) edit_config ;;
            3) backup_config ;;
            4) restore_config ;;
            5) validate_config ;;
            0) break ;;
            *) print_error "无效选择" ;;
        esac

        read -p "按 Enter 键继续..."
    done
}

# 主程序
main() {
    # 检查 root 权限
    require_root

    # 初始化数据目录
    init_data_dir

    # 加载所有模块
    source_modules

    log_info "Xray 管理脚本启动 (v1.2.0)"

    while true; do
        show_menu
        read -p "请选择操作: " choice

        case $choice in
            1) menu_core ;;
            2) menu_node ;;
            3) menu_user ;;
            4) menu_subscription ;;
            5) menu_monitor ;;
            6) menu_firewall ;;
            7) menu_config ;;
            8) domain_management_menu ;;
            9) certificate_management_menu ;;
            99)
                # 卸载脚本
                clear
                echo -e "${RED}=====================================${NC}"
                echo -e "${RED}         警告：卸载脚本${NC}"
                echo -e "${RED}=====================================${NC}"
                echo ""
                echo -e "${YELLOW}此操作将卸载 s-xray 管理脚本${NC}"
                echo ""

                if confirm "确认卸载" "n"; then
                    # 检查卸载脚本是否存在
                    local script_path="${BASH_SOURCE[0]}"
                    if [[ -L "$script_path" ]]; then
                        script_path="$(readlink -f "$script_path")"
                    fi
                    local script_dir="$(cd "$(dirname "$script_path")" && pwd)"

                    if [[ -f "${script_dir}/uninstall.sh" ]]; then
                        log_info "执行卸载脚本: ${script_dir}/uninstall.sh"
                        exec bash "${script_dir}/uninstall.sh"
                    elif [[ -f "/opt/s-xray/uninstall.sh" ]]; then
                        log_info "执行卸载脚本: /opt/s-xray/uninstall.sh"
                        exec bash "/opt/s-xray/uninstall.sh"
                    else
                        log_error "未找到卸载脚本"
                        log_info "请手动运行: bash /opt/s-xray/uninstall.sh"
                    fi
                else
                    log_info "已取消卸载"
                fi
                ;;
            0)
                log_info "感谢使用 Xray 管理脚本！"
                exit 0
                ;;
            *)
                log_error "无效选择，请重新输入"
                sleep 1
                ;;
        esac
    done
}

# 运行主程序
main
