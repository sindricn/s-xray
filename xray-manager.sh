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

# 节点管理菜单（扁平化结构）
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
        echo -e "${GREEN}2.${NC} 添加节点"
        echo -e "${GREEN}3.${NC} 查看节点"
        echo -e "${GREEN}4.${NC} 修改节点基本配置"
        echo -e "${GREEN}5.${NC} 修改节点绑定用户"
        echo -e "${GREEN}6.${NC} 删除节点"
        echo -e "${GREEN}0.${NC} 返回主菜单"
        echo ""
        read -p "请选择操作 [0-6]: " choice

        case $choice in
            1) quick_add_vless_reality ;;
            2) menu_node_add ;;
            3) view_node_detail ;;
            4) modify_node_config_only ;;
            5) modify_node_users ;;
            6) delete_node_menu ;;
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

# 查看节点详情（扁平化）
view_node_detail() {
    clear
    echo -e "${CYAN}╔═══════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║      查看节点                        ║${NC}"
    echo -e "${CYAN}╚═══════════════════════════════════════╝${NC}"
    echo ""

    # 显示节点列表
    list_nodes

    echo ""
    read -p "请输入节点序号查看详情: " node_idx

    if [[ -z "$node_idx" ]]; then
        print_error "输入不能为空"
        return 1
    fi

    # 获取节点端口
    local port=$(get_node_port_by_index "$node_idx")
    if [[ -z "$port" || "$port" == "null" ]]; then
        print_error "无效的节点序号"
        return 1
    fi

    # 显示节点详情（包含用户、配置、分享链接）
    show_node_detail "$port"
}

# 修改节点基本配置（扁平化，只修改配置不涉及用户）
modify_node_config_only() {
    clear
    echo -e "${CYAN}╔═══════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║      修改节点基本配置                ║${NC}"
    echo -e "${CYAN}╚═══════════════════════════════════════╝${NC}"
    echo ""

    list_nodes

    echo ""
    read -p "请输入节点序号: " node_idx
    if [[ -z "$node_idx" ]]; then
        print_error "输入不能为空"
        return 1
    fi

    local port=$(get_node_port_by_index "$node_idx")
    if [[ -z "$port" || "$port" == "null" ]]; then
        print_error "无效的节点序号"
        return 1
    fi

    # 显示当前节点详情
    show_node_detail "$port"

    echo ""
    echo -e "${CYAN}可修改的项目：${NC}"
    echo -e "${GREEN}1.${NC} 修改端口"
    echo -e "${GREEN}0.${NC} 返回"
    echo ""
    read -p "请选择 [0-1]: " choice

    case $choice in
        1)
            echo ""
            read -p "请输入新端口: " new_port
            if [[ -n "$new_port" ]]; then
                # 检查新端口是否已被占用
                if check_port_exists "$new_port"; then
                    print_error "端口 $new_port 已被占用"
                    return 1
                fi

                # 更新节点信息
                jq ".nodes |= map(if .port == \"$port\" then .port = \"$new_port\" else . end)" "$NODES_FILE" > "${NODES_FILE}.tmp"
                mv "${NODES_FILE}.tmp" "$NODES_FILE"

                # 更新绑定信息
                if [[ -f "$NODE_USERS_FILE" ]]; then
                    jq ".bindings |= map(if .port == \"$port\" then .port = \"$new_port\" else . end)" "$NODE_USERS_FILE" > "${NODE_USERS_FILE}.tmp"
                    mv "${NODE_USERS_FILE}.tmp" "$NODE_USERS_FILE"
                fi

                # 更新配置文件
                remove_inbound_from_config "$port"
                generate_xray_config
                restart_xray

                print_success "端口已修改为 $new_port"
            fi
            ;;
        0)
            return 0
            ;;
        *)
            print_error "无效选择"
            ;;
    esac
}

# 修改节点绑定用户（扁平化，支持添加和移除）
modify_node_users() {
    clear
    echo -e "${CYAN}╔═══════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║      修改节点绑定用户                ║${NC}"
    echo -e "${CYAN}╚═══════════════════════════════════════╝${NC}"
    echo ""

    list_nodes

    echo ""
    read -p "请输入节点序号: " node_idx
    if [[ -z "$node_idx" ]]; then
        print_error "输入不能为空"
        return 1
    fi

    local port=$(get_node_port_by_index "$node_idx")
    if [[ -z "$port" || "$port" == "null" ]]; then
        print_error "无效的节点序号"
        return 1
    fi

    echo ""
    echo -e "${CYAN}当前节点端口: ${YELLOW}$port${NC}"
    echo ""
    echo -e "${GREEN}1.${NC} 添加绑定用户（单个）"
    echo -e "${GREEN}2.${NC} 添加绑定用户（多个）"
    echo -e "${GREEN}3.${NC} 移除绑定用户（单个）"
    echo -e "${GREEN}4.${NC} 移除绑定用户（多个）"
    echo -e "${GREEN}0.${NC} 返回"
    echo ""
    read -p "请选择操作 [0-4]: " choice

    case $choice in
        1)
            # 单个添加
            bind_single_user_to_node "$port"
            ;;
        2)
            # 多个添加
            batch_bind_users_to_node "$port"
            ;;
        3)
            # 单个移除
            unbind_single_user_from_node "$port"
            ;;
        4)
            # 多个移除
            batch_unbind_users_from_node "$port"
            ;;
        0)
            return 0
            ;;
        *)
            print_error "无效选择"
            ;;
    esac
}

# 删除节点菜单（扁平化，支持单个和批量）
delete_node_menu() {
    clear
    echo -e "${CYAN}╔═══════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║      删除节点                        ║${NC}"
    echo -e "${CYAN}╚═══════════════════════════════════════╝${NC}"
    echo ""

    list_nodes

    echo ""
    echo -e "${GREEN}1.${NC} 删除单个节点"
    echo -e "${GREEN}2.${NC} 批量删除节点"
    echo -e "${GREEN}0.${NC} 返回"
    echo ""
    read -p "请选择操作 [0-2]: " choice

    case $choice in
        1)
            delete_single_node
            ;;
        2)
            batch_delete_nodes
            ;;
        0)
            return 0
            ;;
        *)
            print_error "无效选择"
            ;;
    esac
}

# 用户管理菜单（扁平化结构）
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
        echo -e "${GREEN}1.${NC} 查看用户"
        echo -e "${GREEN}2.${NC} 添加用户"
        echo -e "${GREEN}3.${NC} 修改用户基础信息"
        echo -e "${GREEN}4.${NC} 修改用户绑定节点"
        echo -e "${GREEN}5.${NC} 删除用户"
        echo -e "${GREEN}0.${NC} 返回主菜单"
        echo ""
        read -p "请选择操作 [0-5]: " choice

        case $choice in
            1) view_user_detail ;;
            2) add_global_user ;;
            3) modify_user_info ;;
            4) modify_user_bindings ;;
            5) delete_user_menu ;;
            0) break ;;
            *) print_error "无效选择" ;;
        esac

        read -p "按 Enter 键继续..."
    done
}

# 查看用户详情（扁平化）
view_user_detail() {
    clear
    echo -e "${CYAN}╔═══════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║      查看用户                        ║${NC}"
    echo -e "${CYAN}╚═══════════════════════════════════════╝${NC}"
    echo ""

    # 显示全局用户列表
    list_global_users

    echo ""
    read -p "请输入用户名查看详情: " username

    if [[ -z "$username" ]]; then
        print_error "输入不能为空"
        return 1
    fi

    # 显示用户详情（包含绑定节点）
    show_user_detail "$username"
}

# 修改用户基础信息（扁平化）
modify_user_info() {
    clear
    echo -e "${CYAN}╔═══════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║      修改用户基础信息                ║${NC}"
    echo -e "${CYAN}╚═══════════════════════════════════════╝${NC}"
    echo ""

    list_global_users

    echo ""
    read -p "请输入要修改的用户名: " username
    if [[ -z "$username" ]]; then
        print_error "用户名不能为空"
        return 1
    fi

    # 调用原有的modify_user函数
    modify_user
}

# 修改用户绑定节点（扁平化，支持添加和移除）
modify_user_bindings() {
    clear
    echo -e "${CYAN}╔═══════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║      修改用户绑定节点                ║${NC}"
    echo -e "${CYAN}╚═══════════════════════════════════════╝${NC}"
    echo ""

    list_global_users

    echo ""
    read -p "请输入用户名: " username
    if [[ -z "$username" ]]; then
        print_error "用户名不能为空"
        return 1
    fi

    # 检查用户是否存在
    local uuid=$(jq -r ".users[] | select(.username == \"$username\") | .id" "$USERS_FILE" 2>/dev/null)
    if [[ -z "$uuid" ]]; then
        print_error "用户不存在: $username"
        return 1
    fi

    echo ""
    echo -e "${CYAN}当前用户: ${YELLOW}$username${NC}"
    echo ""
    echo -e "${GREEN}1.${NC} 添加绑定节点（单个）"
    echo -e "${GREEN}2.${NC} 添加绑定节点（多个）"
    echo -e "${GREEN}3.${NC} 移除绑定节点（单个）"
    echo -e "${GREEN}4.${NC} 移除绑定节点（多个）"
    echo -e "${GREEN}0.${NC} 返回"
    echo ""
    read -p "请选择操作 [0-4]: " choice

    case $choice in
        1)
            # 单个添加
            bind_single_node_to_user "$username"
            ;;
        2)
            # 多个添加
            batch_bind_nodes_to_user "$username"
            ;;
        3)
            # 单个移除
            unbind_single_node_from_user "$username"
            ;;
        4)
            # 多个移除
            batch_unbind_nodes_from_user "$username"
            ;;
        0)
            return 0
            ;;
        *)
            print_error "无效选择"
            ;;
    esac
}

# 删除用户菜单（扁平化，支持单个和多个）
delete_user_menu() {
    clear
    echo -e "${CYAN}╔═══════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║      删除用户                        ║${NC}"
    echo -e "${CYAN}╚═══════════════════════════════════════╝${NC}"
    echo ""

    list_global_users

    echo ""
    echo -e "${GREEN}1.${NC} 删除单个用户"
    echo -e "${GREEN}2.${NC} 批量删除用户"
    echo -e "${GREEN}0.${NC} 返回"
    echo ""
    read -p "请选择操作 [0-2]: " choice

    case $choice in
        1)
            delete_single_user
            ;;
        2)
            batch_delete_users
            ;;
        0)
            return 0
            ;;
        *)
            print_error "无效选择"
            ;;
    esac
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
