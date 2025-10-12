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
readonly NODE_USERS_FILE="${DATA_DIR}/node_users.json"  # 新架构：节点-用户绑定关系
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

    # 导出 MODULES_DIR 为全局变量
    export MODULES_DIR="${script_dir}/modules"

    if [[ ! -d "$MODULES_DIR" ]]; then
        echo -e "${RED}[ERROR]${NC} 模块目录不存在: $MODULES_DIR"
        echo -e "${RED}[ERROR]${NC} 脚本路径: $script_path"
        echo -e "${RED}[ERROR]${NC} 脚本目录: $script_dir"
        exit 1
    fi

    # 优先加载公共库
    if [[ -f "${MODULES_DIR}/common.sh" ]]; then
        source "${MODULES_DIR}/common.sh"
    else
        echo -e "${RED}[ERROR]${NC} 公共库不存在: ${MODULES_DIR}/common.sh"
        exit 1
    fi

    # 加载输入验证模块
    if [[ -f "${MODULES_DIR}/input-validation.sh" ]]; then
        source "${MODULES_DIR}/input-validation.sh"
    fi

    # 加载其他模块
    for module in "${MODULES_DIR}"/*.sh; do
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

# 获取 Xray 状态信息
get_xray_status() {
    local version="未安装"
    local status="${RED}未运行${NC}"

    if [[ -f "$XRAY_BIN" ]]; then
        version=$("$XRAY_BIN" version 2>/dev/null | head -1 | awk '{print $2}')
        [[ -z "$version" ]] && version="unknown"

        if systemctl is-active xray &>/dev/null; then
            status="${GREEN}运行中${NC}"
        else
            status="${RED}已停止${NC}"
        fi
    fi

    echo "$version|$status"
}

# 获取在线节点数量
get_online_nodes() {
    local online=0

    if [[ ! -f "$NODES_FILE" ]]; then
        echo "0"
        return
    fi

    # 检查每个节点的端口是否在监听
    while IFS= read -r node; do
        if [[ -z "$node" || "$node" == "null" ]]; then
            continue
        fi

        local port=$(echo "$node" | jq -r '.port // empty' 2>/dev/null)
        if [[ -n "$port" ]]; then
            # 检查端口是否在监听（支持ss或netstat）
            if command -v ss &>/dev/null; then
                if ss -tlnp 2>/dev/null | grep -q ":$port "; then
                    ((online++))
                fi
            elif command -v netstat &>/dev/null; then
                if netstat -tlnp 2>/dev/null | grep -q ":$port "; then
                    ((online++))
                fi
            fi
        fi
    done < <(jq -c '.nodes[]' "$NODES_FILE" 2>/dev/null)

    echo "$online"
}

# 主菜单
show_menu() {
    clear

    # 获取状态信息
    local status_info=$(get_xray_status)
    local version=$(echo "$status_info" | cut -d'|' -f1)
    local status=$(echo "$status_info" | cut -d'|' -f2)

    # 获取节点数量
    local node_count=0
    if [[ -f "$NODES_FILE" ]]; then
        node_count=$(jq '.nodes | length' "$NODES_FILE" 2>/dev/null || echo "0")
    fi

    # 获取用户数量
    local user_count=0
    if [[ -f "$USERS_FILE" ]]; then
        user_count=$(jq '.users | length' "$USERS_FILE" 2>/dev/null || echo "0")
    fi

    # 获取在线节点数量
    local online_count=$(get_online_nodes)

    echo -e "${CYAN}╔═══════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║    Xray-Core 一键管理脚本 v1.2.2    ║${NC}"
    echo -e "${CYAN}╚═══════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${CYAN}┌─────────────────────────────────────┐${NC}"
    echo -e "${CYAN}│${NC}  ${YELLOW}系统状态${NC}                           ${CYAN}│${NC}"
    echo -e "${CYAN}├─────────────────────────────────────┤${NC}"
    echo -e "${CYAN}│${NC}  内核版本: ${YELLOW}${version}${NC}"
    echo -e "${CYAN}│${NC}  运行状态: ${status}"
    echo -e "${CYAN}│${NC}  用户数量: ${BLUE}${user_count}${NC}"
    echo -e "${CYAN}│${NC}  节点总数: ${BLUE}${node_count}${NC}"
    echo -e "${CYAN}│${NC}  在线节点: ${GREEN}${online_count}${NC}/${BLUE}${node_count}${NC}"
    echo -e "${CYAN}└─────────────────────────────────────┘${NC}"
    echo ""
    echo -e "${CYAN}┌─────────────────────────────────────┐${NC}"
    echo -e "${CYAN}│${NC}  ${YELLOW}功能菜单${NC}                           ${CYAN}│${NC}"
    echo -e "${CYAN}├─────────────────────────────────────┤${NC}"
    echo -e "${CYAN}│${NC}  ${GREEN}1.${NC}  Xray 管理                      ${CYAN}│${NC}"
    echo -e "${CYAN}│${NC}  ${GREEN}2.${NC}  用户管理                       ${CYAN}│${NC}"
    echo -e "${CYAN}│${NC}  ${GREEN}3.${NC}  节点管理                       ${CYAN}│${NC}"
    echo -e "${CYAN}│${NC}  ${GREEN}4.${NC}  订阅管理                       ${CYAN}│${NC}"
    echo -e "${CYAN}│${NC}  ${GREEN}5.${NC}  域名管理                       ${CYAN}│${NC}"
    echo -e "${CYAN}│${NC}  ${GREEN}6.${NC}  证书管理                       ${CYAN}│${NC}"
    echo -e "${CYAN}│${NC}  ${GREEN}7.${NC}  出站规则                       ${CYAN}│${NC}"
    echo -e "${CYAN}│${NC}  ${GREEN}8.${NC}  防火墙管理                     ${CYAN}│${NC}"
    echo -e "${CYAN}├─────────────────────────────────────┤${NC}"
    echo -e "${CYAN}│${NC}  ${GREEN}9.${NC}  脚本管理                       ${CYAN}│${NC}"
    echo -e "${CYAN}│${NC}  ${GREEN}0.${NC}  退出脚本                       ${CYAN}│${NC}"
    echo -e "${CYAN}└─────────────────────────────────────┘${NC}"
    echo ""
}

# Xray管理菜单
menu_core() {
    while true; do
        clear
        echo -e "${CYAN}╔═══════════════════════════════════════╗${NC}"
        echo -e "${CYAN}║          Xray 管理                   ║${NC}"
        echo -e "${CYAN}╚═══════════════════════════════════════╝${NC}"
        echo ""
        echo -e "${GREEN}1.${NC} 安装 Xray"
        echo -e "${GREEN}2.${NC} 启动 Xray"
        echo -e "${GREEN}3.${NC} 停止 Xray"
        echo -e "${GREEN}4.${NC} 重启 Xray"
        echo -e "${GREEN}5.${NC} 卸载 Xray"
        echo -e "${GREEN}6.${NC} 更新 Xray"
        echo -e "${GREEN}7.${NC} 查看日志"
        echo -e "${GREEN}0.${NC} 返回主菜单"
        echo ""
        read -p "请选择操作 [0-7]: " choice

        case $choice in
            1) install_xray ;;
            2) start_xray ;;
            3) stop_xray ;;
            4) restart_xray ;;
            5) uninstall_xray ;;
            6) update_xray ;;
            7)
                # 查看日志
                clear
                echo -e "${CYAN}╔═══════════════════════════════════════╗${NC}"
                echo -e "${CYAN}║          Xray 日志                   ║${NC}"
                echo -e "${CYAN}╚═══════════════════════════════════════╝${NC}"
                echo ""
                echo -e "${GREEN}1.${NC} 实时日志（最新50行）"
                echo -e "${GREEN}2.${NC} 完整日志"
                echo -e "${GREEN}3.${NC} 错误日志"
                echo -e "${GREEN}0.${NC} 返回"
                echo ""
                read -p "请选择 [0-3]: " log_choice

                case $log_choice in
                    1)
                        echo ""
                        echo -e "${CYAN}实时日志（Ctrl+C退出）:${NC}"
                        echo ""
                        journalctl -u xray -f -n 50
                        ;;
                    2)
                        echo ""
                        echo -e "${CYAN}完整日志:${NC}"
                        echo ""
                        journalctl -u xray --no-pager | less
                        ;;
                    3)
                        echo ""
                        echo -e "${CYAN}错误日志:${NC}"
                        echo ""
                        journalctl -u xray -p err --no-pager | less
                        ;;
                    0) ;;
                    *) print_error "无效选择" ;;
                esac
                ;;
            0) break ;;
            *) print_error "无效选择" ;;
        esac

        read -p "按 Enter 键继续..."
    done
}

# 节点管理菜单（重构精简版）
menu_node() {
    # 引入统一选择器
    if [[ -f "${MODULES_DIR}/selector.sh" ]]; then
        source "${MODULES_DIR}/selector.sh"
    fi

    while true; do
        clear
        echo -e "${CYAN}╔═══════════════════════════════════════╗${NC}"
        echo -e "${CYAN}║          节点管理                    ║${NC}"
        echo -e "${CYAN}╚═══════════════════════════════════════╝${NC}"
        echo ""
        echo -e "${GREEN}1.${NC} 快速搭建（VLESS + Reality 推荐）"
        echo -e "${GREEN}2.${NC} 添加节点（VLESS/VMess/Trojan/SS）"
        echo -e "${GREEN}3.${NC} 节点列表与详情"
        echo -e "${GREEN}4.${NC} 修改节点（含删除）"
        echo -e "${GREEN}5.${NC} 批量操作"
        echo -e "${GREEN}6.${NC} 节点用户管理"
        echo -e "${GREEN}0.${NC} 返回主菜单"
        echo ""
        read -p "请选择操作 [0-6]: " choice

        case $choice in
            1) quick_add_vless_reality ;;
            2) menu_node_add ;;
            3) menu_node_list_and_detail ;;
            4) menu_node_modify ;;
            5) menu_node_batch ;;
            6) menu_node_users ;;
            0) break ;;
            *) print_error "无效选择" ;;
        esac

        read -p "按 Enter 键继续..."
    done
}

# 添加节点子菜单
menu_node_add() {
    while true; do
        clear
        echo -e "${CYAN}╔═══════════════════════════════════════╗${NC}"
        echo -e "${CYAN}║          添加节点                    ║${NC}"
        echo -e "${CYAN}╚═══════════════════════════════════════╝${NC}"
        echo ""
        echo -e "${GREEN}1.${NC} VLESS 节点（支持 Reality/TLS/TCP）"
        echo -e "${GREEN}2.${NC} VMess 节点"
        echo -e "${GREEN}3.${NC} Trojan 节点"
        echo -e "${GREEN}4.${NC} Shadowsocks 节点"
        echo -e "${GREEN}0.${NC} 返回上级菜单"
        echo ""
        read -p "请选择协议 [0-4]: " choice

        case $choice in
            1) add_vless_node ;;
            2) add_vmess_node ;;
            3) add_trojan_node ;;
            4) add_shadowsocks_node ;;
            0) break ;;
            *) print_error "无效选择" ;;
        esac

        read -p "按 Enter 键继续..."
    done
}

# 节点列表与详情子菜单
menu_node_list_and_detail() {
    while true; do
        clear
        echo -e "${CYAN}╔═══════════════════════════════════════╗${NC}"
        echo -e "${CYAN}║      节点列表与详情                  ║${NC}"
        echo -e "${CYAN}╚═══════════════════════════════════════╝${NC}"
        echo ""

        # 显示节点列表
        list_nodes

        echo ""
        echo -e "${GREEN}1.${NC} 查看节点详情（用户、配置）"
        echo -e "${GREEN}2.${NC} 查看节点分享链接"
        echo -e "${GREEN}3.${NC} 刷新列表"
        echo -e "${GREEN}0.${NC} 返回上级菜单"
        echo ""
        read -p "请选择操作 [0-3]: " choice

        case $choice in
            1)
                echo ""
                read -p "请输入节点序号: " node_idx
                if [[ -n "$node_idx" ]]; then
                    # 显示节点用户列表
                    show_node_users
                fi
                read -p "按 Enter 键继续..."
                ;;
            2)
                show_node_share_link
                read -p "按 Enter 键继续..."
                ;;
            3)
                continue
                ;;
            0)
                break
                ;;
            *)
                print_error "无效选择"
                read -p "按 Enter 键继续..."
                ;;
        esac
    done
}

# 节点修改子菜单（整合删除）
menu_node_modify() {
    while true; do
        clear
        echo -e "${CYAN}╔═══════════════════════════════════════╗${NC}"
        echo -e "${CYAN}║          修改节点                    ║${NC}"
        echo -e "${CYAN}╚═══════════════════════════════════════╝${NC}"
        echo ""

        # 显示节点列表
        list_nodes

        echo ""
        echo -e "${GREEN}1.${NC} 修改节点配置（端口、传输、加密）"
        echo -e "${GREEN}2.${NC} 删除节点"
        echo -e "${GREEN}0.${NC} 返回上级菜单"
        echo ""
        read -p "请选择操作 [0-2]: " choice

        case $choice in
            1)
                modify_node
                read -p "按 Enter 键继续..."
                ;;
            2)
                delete_node
                read -p "按 Enter 键继续..."
                ;;
            0)
                break
                ;;
            *)
                print_error "无效选择"
                read -p "按 Enter 键继续..."
                ;;
        esac
    done
}

# 节点批量操作子菜单
menu_node_batch() {
    while true; do
        clear
        echo -e "${CYAN}╔═══════════════════════════════════════╗${NC}"
        echo -e "${CYAN}║          批量操作                    ║${NC}"
        echo -e "${CYAN}╚═══════════════════════════════════════╝${NC}"
        echo ""
        echo -e "${GREEN}1.${NC} 批量删除节点"
        echo -e "${GREEN}2.${NC} 批量启用/禁用节点"
        echo -e "${GREEN}3.${NC} 批量修改端口"
        echo -e "${GREEN}0.${NC} 返回上级菜单"
        echo ""
        read -p "请选择操作 [0-3]: " choice

        case $choice in
            1)
                batch_delete_nodes
                read -p "按 Enter 键继续..."
                ;;
            2)
                batch_toggle_nodes
                read -p "按 Enter 键继续..."
                ;;
            3)
                batch_modify_ports
                read -p "按 Enter 键继续..."
                ;;
            0)
                break
                ;;
            *)
                print_error "无效选择"
                read -p "按 Enter 键继续..."
                ;;
        esac
    done
}

# 节点用户管理子菜单
menu_node_users() {
    while true; do
        clear
        echo -e "${CYAN}╔═══════════════════════════════════════╗${NC}"
        echo -e "${CYAN}║      节点用户管理                    ║${NC}"
        echo -e "${CYAN}╚═══════════════════════════════════════╝${NC}"
        echo ""
        echo -e "${GREEN}1.${NC} 查看节点的用户列表"
        echo -e "${GREEN}2.${NC} 查看所有用户-节点绑定关系"
        echo -e "${GREEN}0.${NC} 返回上级菜单"
        echo ""
        read -p "请选择操作 [0-2]: " choice

        case $choice in
            1)
                show_node_users
                read -p "按 Enter 键继续..."
                ;;
            2)
                show_user_node_bindings
                read -p "按 Enter 键继续..."
                ;;
            0)
                break
                ;;
            *)
                print_error "无效选择"
                read -p "按 Enter 键继续..."
                ;;
        esac
    done
}

# 用户管理菜单（重构精简版）
menu_user() {
    # 引入统一选择器
    if [[ -f "${MODULES_DIR}/selector.sh" ]]; then
        source "${MODULES_DIR}/selector.sh"
    fi

    while true; do
        clear
        echo -e "${CYAN}╔═══════════════════════════════════════╗${NC}"
        echo -e "${CYAN}║          用户管理                    ║${NC}"
        echo -e "${CYAN}╚═══════════════════════════════════════╝${NC}"
        echo ""
        echo -e "${GREEN}1.${NC} 用户列表与详情"
        echo -e "${GREEN}2.${NC} 添加用户"
        echo -e "${GREEN}3.${NC} 修改用户（含删除、绑定、解绑）"
        echo -e "${GREEN}4.${NC} 批量操作"
        echo -e "${GREEN}5.${NC} 生成 UUID"
        echo -e "${GREEN}0.${NC} 返回主菜单"
        echo ""
        read -p "请选择操作 [0-5]: " choice

        case $choice in
            1) menu_user_list_and_detail ;;
            2) add_global_user ;;
            3) menu_user_modify ;;
            4) menu_user_batch ;;
            5)
                echo ""
                local uuid=$(generate_uuid)
                print_success "生成的UUID: $uuid"
                ;;
            0) break ;;
            *) print_error "无效选择" ;;
        esac

        read -p "按 Enter 键继续..."
    done
}

# 用户列表与详情子菜单
menu_user_list_and_detail() {
    while true; do
        clear
        echo -e "${CYAN}╔═══════════════════════════════════════╗${NC}"
        echo -e "${CYAN}║      用户列表与详情                  ║${NC}"
        echo -e "${CYAN}╚═══════════════════════════════════════╝${NC}"
        echo ""

        # 显示全局用户列表
        list_global_users

        echo ""
        echo -e "${GREEN}1.${NC} 查看用户详情（绑定节点、流量统计）"
        echo -e "${GREEN}2.${NC} 刷新列表"
        echo -e "${GREEN}0.${NC} 返回上级菜单"
        echo ""
        read -p "请选择操作 [0-2]: " choice

        case $choice in
            1)
                echo ""
                read -p "请输入用户邮箱: " user_email
                if [[ -n "$user_email" ]]; then
                    show_user_nodes "$user_email"
                fi
                read -p "按 Enter 键继续..."
                ;;
            2)
                continue
                ;;
            0)
                break
                ;;
            *)
                print_error "无效选择"
                read -p "按 Enter 键继续..."
                ;;
        esac
    done
}

# 用户修改子菜单（整合删除、绑定、解绑）
menu_user_modify() {
    while true; do
        clear
        echo -e "${CYAN}╔═══════════════════════════════════════╗${NC}"
        echo -e "${CYAN}║          修改用户                    ║${NC}"
        echo -e "${CYAN}╚═══════════════════════════════════════╝${NC}"
        echo ""

        # 显示用户列表供选择
        list_global_users

        echo ""
        echo -e "${GREEN}1.${NC} 修改用户基本信息（用户名、密码、UUID）"
        echo -e "${GREEN}2.${NC} 绑定用户到节点"
        echo -e "${GREEN}3.${NC} 从节点解绑用户"
        echo -e "${GREEN}4.${NC} 删除用户"
        echo -e "${GREEN}0.${NC} 返回上级菜单"
        echo ""
        read -p "请选择操作 [0-4]: " choice

        case $choice in
            1)
                modify_user
                read -p "按 Enter 键继续..."
                ;;
            2)
                bind_user_to_node
                read -p "按 Enter 键继续..."
                ;;
            3)
                unbind_user_from_node
                read -p "按 Enter 键继续..."
                ;;
            4)
                delete_global_user
                read -p "按 Enter 键继续..."
                ;;
            0)
                break
                ;;
            *)
                print_error "无效选择"
                read -p "按 Enter 键继续..."
                ;;
        esac
    done
}

# 用户批量操作子菜单
menu_user_batch() {
    while true; do
        clear
        echo -e "${CYAN}╔═══════════════════════════════════════╗${NC}"
        echo -e "${CYAN}║          批量操作                    ║${NC}"
        echo -e "${CYAN}╚═══════════════════════════════════════╝${NC}"
        echo ""
        echo -e "${GREEN}1.${NC} 批量绑定用户到多个节点"
        echo -e "${GREEN}2.${NC} 批量解绑用户"
        echo -e "${GREEN}3.${NC} 批量删除用户"
        echo -e "${GREEN}4.${NC} 批量重置流量"
        echo -e "${GREEN}0.${NC} 返回上级菜单"
        echo ""
        read -p "请选择操作 [0-4]: " choice

        case $choice in
            1)
                batch_bind_user_to_nodes
                read -p "按 Enter 键继续..."
                ;;
            2)
                batch_unbind_users
                read -p "按 Enter 键继续..."
                ;;
            3)
                batch_delete_users
                read -p "按 Enter 键继续..."
                ;;
            4)
                batch_reset_traffic
                read -p "按 Enter 键继续..."
                ;;
            0)
                break
                ;;
            *)
                print_error "无效选择"
                read -p "按 Enter 键继续..."
                ;;
        esac
    done
}

# 订阅管理菜单
menu_subscription() {
    while true; do
        clear
        echo -e "${CYAN}╔═══════════════════════════════════════╗${NC}"
        echo -e "${CYAN}║          订阅管理                    ║${NC}"
        echo -e "${CYAN}╚═══════════════════════════════════════╝${NC}"
        echo ""
        echo -e "${GREEN}1.${NC} 查看节点链接"
        echo -e "${GREEN}2.${NC} 生成订阅链接"
        echo -e "${GREEN}3.${NC} 查看订阅链接"
        echo -e "${GREEN}4.${NC} 更新订阅"
        echo -e "${GREEN}5.${NC} 删除订阅"
        echo -e "${GREEN}0.${NC} 返回主菜单"
        echo ""
        read -p "请选择操作 [0-5]: " choice

        case $choice in
            1) show_node_share_link ;;  # 查看单个节点链接
            2) generate_subscription_with_user ;;  # 生成订阅链接（支持用户绑定）
            3) show_subscription ;;      # 查看所有订阅链接
            4)
                # 更新订阅（重新生成现有订阅）
                show_subscription
                echo ""
                read -p "请输入要更新的订阅名称: " sub_name
                if [[ -n "$sub_name" ]]; then
                    # 调用重新生成函数
                    regenerate_subscription "$sub_name"
                fi
                ;;
            5) delete_subscription ;;
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

# 脚本管理菜单
menu_script() {
    while true; do
        clear
        echo -e "${CYAN}╔═══════════════════════════════════════╗${NC}"
        echo -e "${CYAN}║          脚本管理                    ║${NC}"
        echo -e "${CYAN}╚═══════════════════════════════════════╝${NC}"
        echo ""
        echo -e "${GREEN}1.${NC} 更新脚本"
        echo -e "${GREEN}2.${NC} 卸载管理（三级选项）"
        echo -e "${GREEN}0.${NC} 返回主菜单"
        echo ""
        read -p "请选择操作 [0-2]: " choice

        case $choice in
            1)
                # 更新脚本
                clear
                echo -e "${CYAN}正在更新脚本...${NC}"

                local script_path="${BASH_SOURCE[0]}"
                if [[ -L "$script_path" ]]; then
                    script_path="$(readlink -f "$script_path")"
                fi
                local script_dir="$(cd "$(dirname "$script_path")" && pwd)"

                cd "$script_dir" || {
                    print_error "无法进入脚本目录"
                    read -p "按 Enter 键继续..."
                    continue
                }

                if [[ -d ".git" ]]; then
                    git pull || print_error "更新失败"
                    print_success "脚本更新完成"
                else
                    print_warning "当前不是Git仓库，无法自动更新"
                    echo -e "${YELLOW}请手动下载最新版本${NC}"
                fi
                ;;
            2)
                # 卸载管理（调用uninstall.sh，提供三级选项）
                clear
                echo -e "${RED}╔═══════════════════════════════════════╗${NC}"
                echo -e "${RED}║          卸载管理                    ║${NC}"
                echo -e "${RED}╚═══════════════════════════════════════╝${NC}"
                echo ""
                echo -e "${YELLOW}即将进入卸载程序，提供以下选项：${NC}"
                echo -e "  ${CYAN}1.${NC} 仅卸载管理脚本（保留Xray核心和配置）"
                echo -e "  ${CYAN}2.${NC} 卸载脚本和配置文件（保留Xray核心）"
                echo -e "  ${CYAN}3.${NC} 完全卸载（包括Xray核心）"
                echo ""

                if confirm "确认进入卸载程序" "n"; then
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
                    print_info "已取消卸载"
                fi
                ;;
            0) break ;;
            *) print_error "无效选择" ;;
        esac

        read -p "按 Enter 键继续..."
    done
}

# 出站规则管理菜单
menu_outbound() {
    # 调用出站管理模块
    if [[ -f "${MODULES_DIR}/outbound.sh" ]]; then
        source "${MODULES_DIR}/outbound.sh"
        outbound_management_menu
    else
        print_error "出站管理模块未找到: ${MODULES_DIR}/outbound.sh"
        read -p "按 Enter 键继续..."
    fi
}

# 主程序
main() {
    # 检查 root 权限
    require_root

    # 初始化数据目录
    init_data_dir

    # 加载所有模块
    source_modules

    # 初始化默认admin用户
    init_admin_user

    log_info "Xray 管理脚本启动 (v1.2.2)"

    while true; do
        show_menu
        read -p "请选择操作: " choice

        case $choice in
            1) menu_core ;;              # Xray管理
            2) menu_user ;;              # 用户管理
            3) menu_node ;;              # 节点管理
            4) menu_subscription ;;      # 订阅管理
            5) domain_management_menu ;; # 域名管理
            6) certificate_management_menu ;; # 证书管理
            7) menu_outbound ;;          # 出站规则
            8) menu_firewall ;;          # 防火墙管理
            9) menu_script ;;            # 脚本管理
            0)
                echo ""
                echo -e "${GREEN}感谢使用 Xray 管理脚本！${NC}"
                echo ""
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
