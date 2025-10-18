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
        echo -e "${GREEN}8.${NC} 查看配置"
        echo -e "${GREEN}0.${NC} 返回主菜单"
        echo ""
        read -p "请选择操作 [0-8]: " choice

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
            8)
                # 查看配置
                clear
                echo -e "${CYAN}╔═══════════════════════════════════════╗${NC}"
                echo -e "${CYAN}║          Xray 配置文件               ║${NC}"
                echo -e "${CYAN}╚═══════════════════════════════════════╝${NC}"
                echo ""

                if [[ ! -f "$XRAY_CONFIG" ]]; then
                    print_error "配置文件不存在: $XRAY_CONFIG"
                else
                    echo -e "${YELLOW}配置文件路径: $XRAY_CONFIG${NC}"
                    echo ""
                    echo -e "${CYAN}配置内容:${NC}"
                    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
                    cat "$XRAY_CONFIG" | jq '.' 2>/dev/null || cat "$XRAY_CONFIG"
                    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
                    echo ""
                    echo -e "${GREEN}提示: 可以复制上面的配置用于调试${NC}"
                fi
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
        echo -e "${GREEN}4.${NC} 修改节点"
        echo -e "${GREEN}5.${NC} 删除节点"
        echo -e "${GREEN}0.${NC} 返回主菜单"
        echo ""
        read -p "请选择操作 [0-5]: " choice

        case $choice in
            1) quick_add_vless_reality ;;
            2) menu_node_add ;;
            3) view_node_detail ;;
            4) modify_node_menu ;;
            5) delete_node_smart ;;
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
        echo -e "${GREEN}5.${NC} HTTP 入站节点"
        echo -e "${GREEN}6.${NC} SOCKS 入站节点"
        echo -e "${GREEN}0.${NC} 返回上级菜单"
        echo ""
        read -p "请选择协议 [0-6]: " choice

        case $choice in
            1) add_vless_node ;;
            2) add_vmess_node ;;
            3) add_trojan_node ;;
            4) add_shadowsocks_node ;;
            5) add_http_inbound_node ;;
            6) add_socks_inbound_node ;;
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
# 修改节点菜单（二级菜单）
modify_node_menu() {
    clear
    echo -e "${CYAN}╔═══════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║      修改节点                        ║${NC}"
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

    # 获取节点名称
    local node_name=$(jq -r ".nodes[] | select(.port == \"$port\") | .name // \"未命名节点\"" "$NODES_FILE" 2>/dev/null)

    while true; do
        clear
        echo -e "${CYAN}╔═══════════════════════════════════════╗${NC}"
        echo -e "${CYAN}║      修改节点: ${YELLOW}$node_name${CYAN}            ║${NC}"
        echo -e "${CYAN}╚═══════════════════════════════════════╝${NC}"
        echo -e "${YELLOW}端口: $port${NC}"
        echo ""
        echo -e "${GREEN}1.${NC} 修改基本配置"
        echo -e "${GREEN}2.${NC} 添加绑定用户"
        echo -e "${GREEN}3.${NC} 移除绑定用户"
        echo -e "${GREEN}0.${NC} 返回"
        echo ""
        read -p "请选择操作 [0-3]: " choice

        case $choice in
            1)
                modify_node_config_direct "$port"
                # 重新获取节点名称（可能被修改）
                node_name=$(jq -r ".nodes[] | select(.port == \"$port\") | .name // \"未命名节点\"" "$NODES_FILE" 2>/dev/null)
                ;;
            2)
                bind_users_to_node_smart "$port"
                ;;
            3)
                unbind_users_from_node_smart "$port"
                ;;
            0)
                return 0
                ;;
            *)
                print_error "无效选择"
                ;;
        esac

        read -p "按 Enter 键继续..."
    done
}

# 智能删除节点（自动识别单个/批量）
delete_node_smart() {
    clear
    echo -e "${CYAN}╔═══════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║      删除节点                        ║${NC}"
    echo -e "${CYAN}╚═══════════════════════════════════════╝${NC}"
    echo ""

    list_nodes

    echo ""
    echo -e "${YELLOW}请输入节点序号（单个或多个用空格分隔）${NC}"
    read -p "节点序号: " node_indices

    if [[ -z "$node_indices" ]]; then
        print_error "节点序号不能为空"
        return 1
    fi

    # 收集要删除的端口
    local ports_to_delete=()
    for idx in $node_indices; do
        local port=$(get_node_port_by_index "$idx")
        if [[ -n "$port" && "$port" != "null" ]]; then
            ports_to_delete+=("$port")
        else
            print_error "无效的节点序号: $idx"
        fi
    done

    if [[ ${#ports_to_delete[@]} -eq 0 ]]; then
        print_error "没有有效的节点可删除"
        return 1
    fi

    # 确认删除
    echo ""
    echo -e "${YELLOW}即将删除以下节点：${NC}"
    for port in "${ports_to_delete[@]}"; do
        local protocol=$(jq -r ".nodes[] | select(.port == \"$port\") | .protocol" "$NODES_FILE" 2>/dev/null)
        echo "  - 端口 $port ($protocol)"
    done
    echo ""
    read -p "确认删除？(y/N): " confirm

    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        print_info "已取消删除"
        return 0
    fi

    local success_count=0
    local fail_count=0

    for port in "${ports_to_delete[@]}"; do
        # 删除节点
        jq ".nodes |= map(select(.port != \"$port\"))" "$NODES_FILE" > "${NODES_FILE}.tmp"
        mv "${NODES_FILE}.tmp" "$NODES_FILE"

        # 删除绑定关系
        if [[ -f "$NODE_USERS_FILE" ]]; then
            jq ".bindings |= map(select(.port != \"$port\"))" "$NODE_USERS_FILE" > "${NODE_USERS_FILE}.tmp"
            mv "${NODE_USERS_FILE}.tmp" "$NODE_USERS_FILE"
        fi

        # 从配置中移除
        remove_inbound_from_config "$port"

        print_success "已删除节点: 端口 $port"
        ((success_count++))
    done

    echo ""
    print_info "操作完成：成功 $success_count 个，失败 $fail_count 个"

    if [[ $success_count -gt 0 ]]; then
        generate_xray_config
        restart_xray
        print_success "配置已更新并重启服务"
    fi
}

# 直接修改节点基本配置
modify_node_config_direct() {
    local port=$1

    # 获取节点信息
    local node=$(jq -r ".nodes[] | select(.port == \"$port\")" "$NODES_FILE" 2>/dev/null)
    if [[ -z "$node" || "$node" == "null" ]]; then
        print_error "节点不存在: $port"
        return 1
    fi

    local security=$(echo "$node" | jq -r '.security // "none"')

    while true; do
        # 显示当前节点详情
        show_node_detail "$port"

        echo ""
        echo -e "${CYAN}可修改的项目：${NC}"
        echo -e "${GREEN}1.${NC} 修改节点名称"
        echo -e "${GREEN}2.${NC} 修改端口"

        # Reality节点显示额外选项
        if [[ "$security" == "reality" ]]; then
            echo -e "${GREEN}3.${NC} 修改伪装域名 (SNI)"
            echo -e "${GREEN}4.${NC} 重置公私钥对"
        fi

        echo -e "${GREEN}0.${NC} 返回"
        echo ""

        local max_choice=2
        [[ "$security" == "reality" ]] && max_choice=4

        read -p "请选择 [0-$max_choice]: " choice

        case $choice in
            1)
                # 修改节点名称
                echo ""
                local current_name=$(echo "$node" | jq -r '.name // "未命名"')
                echo -e "${YELLOW}当前名称: $current_name${NC}"
                read -p "请输入新的节点名称: " new_name
                if [[ -n "$new_name" ]]; then
                    jq ".nodes |= map(if .port == \"$port\" then .name = \"$new_name\" else . end)" "$NODES_FILE" > "${NODES_FILE}.tmp"
                    mv "${NODES_FILE}.tmp" "$NODES_FILE"
                    print_success "节点名称已修改为: $new_name"
                    # 重新加载节点信息
                    node=$(jq -r ".nodes[] | select(.port == \"$port\")" "$NODES_FILE" 2>/dev/null)
                fi
                ;;
            2)
                # 修改端口
                echo ""
                read -p "请输入新端口: " new_port
                if [[ -n "$new_port" ]]; then
                    # 检查新端口是否已被占用
                    if check_port_exists "$new_port"; then
                        print_error "端口 $new_port 已被占用"
                        continue
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
                    port=$new_port  # 更新当前端口变量
                fi
                ;;
            3)
                # 修改伪装域名 (仅Reality节点)
                if [[ "$security" != "reality" ]]; then
                    print_error "此选项仅适用于 Reality 节点"
                    continue
                fi

                echo ""
                echo -e "${CYAN}修改 Reality 伪装域名${NC}"
                echo ""

                # 显示当前配置
                local extra=$(echo "$node" | jq -r '.extra')
                local current_dest=$(echo "$extra" | jq -r '.dest // "未设置"')
                local current_sni=$(echo "$extra" | jq -r '.server_names[0] // "未设置"')

                echo -e "${YELLOW}当前配置：${NC}"
                echo -e "  伪装目标 (dest): $current_dest"
                echo -e "  伪装域名 (SNI): $current_sni"
                echo ""

                echo -e "${YELLOW}请选择：${NC}"
                echo -e "${GREEN}1.${NC} 手动输入域名"
                echo -e "${GREEN}2.${NC} 自动优选域名"
                echo -e "${GREEN}0.${NC} 取消"
                echo ""
                read -p "请选择 [0-2]: " domain_choice

                case $domain_choice in
                    1)
                        # 手动输入
                        echo ""
                        read -p "请输入新的伪装域名: " new_domain
                        if [[ -n "$new_domain" ]]; then
                            # 测试域名可用性
                            print_info "测试域名连接性..."
                            if timeout 3 bash -c "echo '' | openssl s_client -connect $new_domain:443 -servername $new_domain" >/dev/null 2>&1; then
                                print_success "域名测试通过"

                                # 更新节点extra字段
                                jq ".nodes |= map(if .port == \"$port\" then .extra.dest = \"$new_domain:443\" | .extra.server_names = [\"$new_domain\"] else . end)" "$NODES_FILE" > "${NODES_FILE}.tmp"
                                mv "${NODES_FILE}.tmp" "$NODES_FILE"

                                # 重新生成配置
                                generate_xray_config
                                restart_xray

                                print_success "伪装域名已更新为: $new_domain"

                                # 重新加载节点信息
                                node=$(jq -r ".nodes[] | select(.port == \"$port\")" "$NODES_FILE" 2>/dev/null)
                            else
                                print_warning "域名测试失败，但仍可继续使用"
                                read -p "是否仍要使用此域名? [y/N]: " confirm
                                if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
                                    jq ".nodes |= map(if .port == \"$port\" then .extra.dest = \"$new_domain:443\" | .extra.server_names = [\"$new_domain\"] else . end)" "$NODES_FILE" > "${NODES_FILE}.tmp"
                                    mv "${NODES_FILE}.tmp" "$NODES_FILE"
                                    generate_xray_config
                                    restart_xray
                                    print_success "伪装域名已更新为: $new_domain"
                                    node=$(jq -r ".nodes[] | select(.port == \"$port\")" "$NODES_FILE" 2>/dev/null)
                                fi
                            fi
                        fi
                        ;;
                    2)
                        # 自动优选（调用domain模块的优选功能）
                        if [[ -f "${MODULES_DIR}/domain.sh" ]]; then
                            source "${MODULES_DIR}/domain.sh"

                            print_info "开始自动优选伪装域名..."
                            echo ""

                            # 使用临时文件存储结果
                            local temp_file=$(mktemp)

                            # 测试候选域名
                            local candidates=("www.cloudflare.com" "www.google.com" "www.microsoft.com" "www.apple.com" "www.amazon.com")
                            local best_domain=""
                            local best_latency=9999

                            for domain in "${candidates[@]}"; do
                                print_info "测试: $domain"
                                local t1=$(date +%s%3N)
                                if timeout 2 bash -c "echo '' | openssl s_client -connect $domain:443 -servername $domain" >/dev/null 2>&1; then
                                    local t2=$(date +%s%3N)
                                    local latency=$((t2 - t1))
                                    echo -e "  ${GREEN}✓${NC} 延迟: ${latency}ms"

                                    if [[ $latency -lt $best_latency ]]; then
                                        best_latency=$latency
                                        best_domain=$domain
                                    fi
                                else
                                    echo -e "  ${RED}✗${NC} 连接失败"
                                fi
                            done

                            if [[ -n "$best_domain" ]]; then
                                echo ""
                                print_success "优选完成！最佳域名: $best_domain (${best_latency}ms)"

                                # 更新节点
                                jq ".nodes |= map(if .port == \"$port\" then .extra.dest = \"$best_domain:443\" | .extra.server_names = [\"$best_domain\"] else . end)" "$NODES_FILE" > "${NODES_FILE}.tmp"
                                mv "${NODES_FILE}.tmp" "$NODES_FILE"

                                generate_xray_config
                                restart_xray

                                print_success "伪装域名已自动更新为: $best_domain"
                                node=$(jq -r ".nodes[] | select(.port == \"$port\")" "$NODES_FILE" 2>/dev/null)
                            else
                                print_error "自动优选失败，未找到可用域名"
                            fi

                            rm -f "$temp_file"
                        else
                            print_error "domain 模块未找到"
                        fi
                        ;;
                    0)
                        # 取消
                        ;;
                    *)
                        print_error "无效选择"
                        ;;
                esac
                ;;
            4)
                # 重置公私钥对 (仅Reality节点)
                if [[ "$security" != "reality" ]]; then
                    print_error "此选项仅适用于 Reality 节点"
                    continue
                fi

                echo ""
                echo -e "${CYAN}重置 Reality 公私钥对${NC}"
                echo ""
                echo -e "${YELLOW}警告：重置后需要更新所有客户端配置！${NC}"
                echo ""
                read -p "确认重置? [y/N]: " confirm

                if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
                    print_info "生成新的密钥对..."

                    # 生成新密钥对
                    local keypair=$("$XRAY_BIN" x25519 2>/dev/null)

                    if [[ $? -ne 0 || -z "$keypair" ]]; then
                        print_error "密钥生成失败"
                        continue
                    fi

                    # 解析密钥 (支持多种格式)
                    local private_key=$(echo "$keypair" | grep -i "Private" | awk '{print $NF}')
                    local public_key=$(echo "$keypair" | grep -i "Public" | awk '{print $NF}')

                    if [[ -z "$private_key" || -z "$public_key" ]]; then
                        # 尝试其他格式
                        private_key=$(echo "$keypair" | sed -n '1p' | awk '{print $NF}')
                        public_key=$(echo "$keypair" | sed -n '2p' | awk '{print $NF}')
                    fi

                    if [[ -z "$private_key" || -z "$public_key" ]]; then
                        print_error "密钥解析失败"
                        echo "$keypair"
                        continue
                    fi

                    print_success "新密钥对生成成功"
                    echo -e "  私钥: ${YELLOW}${private_key:0:20}...${NC}"
                    echo -e "  公钥: ${YELLOW}${public_key:0:20}...${NC}"
                    echo ""

                    # 更新节点extra字段
                    jq ".nodes |= map(if .port == \"$port\" then .extra.private_key = \"$private_key\" | .extra.public_key = \"$public_key\" else . end)" "$NODES_FILE" > "${NODES_FILE}.tmp"
                    mv "${NODES_FILE}.tmp" "$NODES_FILE"

                    # 重新生成配置
                    generate_xray_config
                    restart_xray

                    print_success "密钥对已重置"
                    echo ""
                    echo -e "${YELLOW}重要提示：${NC}"
                    echo -e "  1. 新公钥: ${GREEN}$public_key${NC}"
                    echo -e "  2. 请更新所有客户端的公钥配置"
                    echo -e "  3. 可在节点详情中查看完整配置"

                    # 重新加载节点信息
                    node=$(jq -r ".nodes[] | select(.port == \"$port\")" "$NODES_FILE" 2>/dev/null)
                fi
                ;;
            0)
                return 0
                ;;
            *)
                print_error "无效选择"
                ;;
        esac

        echo ""
        read -p "按 Enter 键继续..."
    done
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
        echo -e "${GREEN}3.${NC} 修改用户"
        echo -e "${GREEN}4.${NC} 删除用户"
        echo -e "${GREEN}0.${NC} 返回主菜单"
        echo ""
        read -p "请选择操作 [0-4]: " choice

        case $choice in
            1) view_user_detail ;;
            2) add_global_user ;;
            3) modify_user_menu ;;
            4) delete_user_smart ;;
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

# 修改用户菜单（二级菜单）
modify_user_menu() {
    clear
    echo -e "${CYAN}╔═══════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║      修改用户                        ║${NC}"
    echo -e "${CYAN}╚═══════════════════════════════════════╝${NC}"
    echo ""

    list_global_users

    echo ""
    read -p "请输入要修改的用户名: " username
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

    while true; do
        clear
        echo -e "${CYAN}╔═══════════════════════════════════════╗${NC}"
        echo -e "${CYAN}║      修改用户: ${YELLOW}$username${CYAN}              ║${NC}"
        echo -e "${CYAN}╚═══════════════════════════════════════╝${NC}"
        echo ""
        echo -e "${GREEN}1.${NC} 修改基础信息"
        echo -e "${GREEN}2.${NC} 修改流量与有效期"
        echo -e "${GREEN}3.${NC} 添加绑定节点"
        echo -e "${GREEN}4.${NC} 移除绑定节点"
        echo -e "${GREEN}0.${NC} 返回"
        echo ""
        read -p "请选择操作 [0-4]: " choice

        case $choice in
            1)
                modify_user_info_direct "$username"
                # 检查用户名是否被修改
                local new_username=$(jq -r ".users[] | select(.id == \"$(jq -r ".users[] | select(.username == \"$username\") | .id" "$USERS_FILE" 2>/dev/null)\") | .username" "$USERS_FILE" 2>/dev/null)
                if [[ -n "$new_username" && "$new_username" != "$username" ]]; then
                    username="$new_username"
                fi
                ;;
            2)
                modify_user_traffic_and_expire "$username"
                ;;
            3)
                bind_nodes_to_user_smart "$username"
                ;;
            4)
                unbind_nodes_from_user_smart "$username"
                ;;
            0)
                return 0
                ;;
            *)
                print_error "无效选择"
                ;;
        esac

        read -p "按 Enter 键继续..."
    done
}

# 修改用户流量与有效期
modify_user_traffic_and_expire() {
    local username="$1"

    # 获取用户当前信息
    local user_info=$(jq -r ".users[] | select(.username == \"$username\")" "$USERS_FILE" 2>/dev/null)
    if [[ -z "$user_info" || "$user_info" == "null" ]]; then
        print_error "用户不存在: $username"
        return 1
    fi

    local current_traffic_limit=$(echo "$user_info" | jq -r '.traffic_limit_gb // "unlimited"')
    local current_expire=$(echo "$user_info" | jq -r '.expire_date // "unlimited"')

    clear
    echo -e "${CYAN}╔═══════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║      修改流量与有效期                ║${NC}"
    echo -e "${CYAN}╚═══════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${GREEN}用户: ${YELLOW}$username${NC}"
    echo -e "${GREEN}当前流量限制: ${YELLOW}$current_traffic_limit GB${NC}"
    echo -e "${GREEN}当前有效期: ${YELLOW}$current_expire${NC}"
    echo ""

    # 修改流量限制
    read -p "请输入新的流量限制(GB) [留空保持不变，输入unlimited表示无限]: " new_traffic_limit
    if [[ -z "$new_traffic_limit" ]]; then
        new_traffic_limit="$current_traffic_limit"
    fi

    # 修改有效期
    echo ""
    echo -e "${CYAN}有效期设置：${NC}"
    echo -e "  ${GREEN}1.${NC} 保持不变 ($current_expire)"
    echo -e "  ${GREEN}2.${NC} 无限期"
    echo -e "  ${GREEN}3.${NC} 30天后"
    echo -e "  ${GREEN}4.${NC} 90天后"
    echo -e "  ${GREEN}5.${NC} 180天后"
    echo -e "  ${GREEN}6.${NC} 365天后"
    echo -e "  ${GREEN}7.${NC} 自定义天数"
    echo ""
    read -p "请选择 [1-7]: " expire_choice

    local new_expire="$current_expire"
    case $expire_choice in
        1)
            new_expire="$current_expire"
            ;;
        2)
            new_expire="unlimited"
            ;;
        3)
            new_expire=$(date -d "+30 days" '+%Y-%m-%d' 2>/dev/null || date -v+30d '+%Y-%m-%d')
            ;;
        4)
            new_expire=$(date -d "+90 days" '+%Y-%m-%d' 2>/dev/null || date -v+90d '+%Y-%m-%d')
            ;;
        5)
            new_expire=$(date -d "+180 days" '+%Y-%m-%d' 2>/dev/null || date -v+180d '+%Y-%m-%d')
            ;;
        6)
            new_expire=$(date -d "+365 days" '+%Y-%m-%d' 2>/dev/null || date -v+365d '+%Y-%m-%d')
            ;;
        7)
            read -p "请输入天数: " custom_days
            if [[ "$custom_days" =~ ^[0-9]+$ ]] && [[ $custom_days -gt 0 ]]; then
                new_expire=$(date -d "+${custom_days} days" '+%Y-%m-%d' 2>/dev/null || date -v+${custom_days}d '+%Y-%m-%d')
            else
                print_warning "无效的天数，保持不变"
                new_expire="$current_expire"
            fi
            ;;
        *)
            print_warning "无效选择，保持不变"
            new_expire="$current_expire"
            ;;
    esac

    # 更新用户信息
    jq ".users |= map(if .username == \"$username\" then .traffic_limit_gb = \"$new_traffic_limit\" | .expire_date = \"$new_expire\" else . end)" \
        "$USERS_FILE" > "${USERS_FILE}.tmp"
    mv "${USERS_FILE}.tmp" "$USERS_FILE"

    echo ""
    print_success "流量与有效期修改成功"
    echo -e "  流量限制: ${YELLOW}$new_traffic_limit GB${NC}"
    echo -e "  有效期: ${YELLOW}$new_expire${NC}"
}

# 智能删除用户（自动识别单个/批量）
delete_user_smart() {
    clear
    echo -e "${CYAN}╔═══════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║      删除用户                        ║${NC}"
    echo -e "${CYAN}╚═══════════════════════════════════════╝${NC}"
    echo ""

    list_global_users

    echo ""
    echo -e "${YELLOW}请输入用户名（单个或多个用空格分隔）${NC}"
    read -p "用户名: " usernames

    if [[ -z "$usernames" ]]; then
        print_error "用户名不能为空"
        return 1
    fi

    # 确认删除
    echo ""
    echo -e "${YELLOW}即将删除以下用户：${NC}"
    for username in $usernames; do
        echo "  - $username"
    done
    echo ""
    read -p "确认删除？(y/N): " confirm

    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        print_info "已取消删除"
        return 0
    fi

    local success_count=0
    local fail_count=0

    for username in $usernames; do
        # 获取用户UUID
        local uuid=$(jq -r ".users[] | select(.username == \"$username\") | .id" "$USERS_FILE" 2>/dev/null)

        if [[ -z "$uuid" ]]; then
            print_error "用户不存在: $username"
            ((fail_count++))
            continue
        fi

        # 从绑定关系中移除该用户
        if [[ -f "$NODE_USERS_FILE" ]]; then
            jq "(.bindings[].users) |= map(select(. != \"$uuid\"))" "$NODE_USERS_FILE" > "${NODE_USERS_FILE}.tmp"
            mv "${NODE_USERS_FILE}.tmp" "$NODE_USERS_FILE"
        fi

        # 从用户文件中删除
        jq ".users |= map(select(.username != \"$username\"))" "$USERS_FILE" > "${USERS_FILE}.tmp"
        mv "${USERS_FILE}.tmp" "$USERS_FILE"

        print_success "已删除用户: $username"
        ((success_count++))
    done

    echo ""
    print_info "操作完成：成功 $success_count 个，失败 $fail_count 个"

    if [[ $success_count -gt 0 ]]; then
        generate_xray_config
        restart_xray
        print_success "配置已更新并重启服务"
    fi
}

# 直接修改用户基础信息
modify_user_info_direct() {
    local username=$1

    # 获取用户信息
    local user_info=$(jq -r ".users[] | select(.username == \"$username\")" "$USERS_FILE" 2>/dev/null)
    if [[ -z "$user_info" || "$user_info" == "null" ]]; then
        print_error "用户 $username 不存在"
        return 1
    fi

    clear
    echo -e "${CYAN}╔═══════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║      修改用户基础信息: ${YELLOW}$username${CYAN}      ║${NC}"
    echo -e "${CYAN}╚═══════════════════════════════════════╝${NC}"
    echo ""

    echo -e "${YELLOW}当前用户信息：${NC}"
    echo "$user_info" | jq -r '"  用户名: \(.username)\n  邮箱: \(.email // "未设置")\n  UUID: \(.id)\n  状态: \(if .enabled then "启用" else "禁用" end)"'
    echo ""

    echo -e "${CYAN}修改选项：${NC}"
    echo -e "${GREEN}1.${NC} 修改用户名"
    echo -e "${GREEN}2.${NC} 修改邮箱"
    echo -e "${GREEN}3.${NC} 修改密码"
    echo -e "${GREEN}4.${NC} 重置UUID"
    echo -e "${GREEN}5.${NC} 切换启用/禁用状态"
    echo -e "${GREEN}0.${NC} 返回"
    echo ""
    read -p "请选择 [0-5]: " choice

    case $choice in
        1)
            # 修改用户名
            echo ""
            read -p "请输入新用户名: " new_username
            if [[ -n "$new_username" ]]; then
                # 检查新用户名是否已存在
                local exists=$(jq -r ".users[] | select(.username == \"$new_username\") | .username" "$USERS_FILE" 2>/dev/null)
                if [[ -n "$exists" ]]; then
                    print_error "用户名已存在: $new_username"
                else
                    # 更新用户名
                    jq ".users |= map(if .username == \"$username\" then .username = \"$new_username\" else . end)" "$USERS_FILE" > "${USERS_FILE}.tmp"
                    mv "${USERS_FILE}.tmp" "$USERS_FILE"

                    generate_xray_config
                    restart_xray

                    print_success "用户名已修改为: $new_username"
                    # 注意：调用者需要更新username变量
                fi
            fi
            ;;
        2)
            # 修改邮箱
            echo ""
            read -p "请输入新的邮箱: " new_email
            if [[ -n "$new_email" ]]; then
                jq ".users |= map(if .username == \"$username\" then .email = \"$new_email\" else . end)" "$USERS_FILE" > "${USERS_FILE}.tmp"
                mv "${USERS_FILE}.tmp" "$USERS_FILE"
                print_success "邮箱修改成功"
                generate_xray_config
                restart_xray
            fi
            ;;
        3)
            # 修改密码
            echo ""
            read -p "请输入新密码: " new_password
            if [[ -n "$new_password" ]]; then
                jq ".users |= map(if .username == \"$username\" then .password = \"$new_password\" else . end)" "$USERS_FILE" > "${USERS_FILE}.tmp"
                mv "${USERS_FILE}.tmp" "$USERS_FILE"
                print_success "密码修改成功"
                generate_xray_config
                restart_xray
            fi
            ;;
        4)
            # 重置UUID
            echo ""
            local new_uuid=$(generate_uuid)
            print_info "新 UUID: $new_uuid"

            # 更新用户UUID
            jq ".users |= map(if .username == \"$username\" then .id = \"$new_uuid\" else . end)" "$USERS_FILE" > "${USERS_FILE}.tmp"
            mv "${USERS_FILE}.tmp" "$USERS_FILE"

            # 同步更新绑定关系中的UUID
            if [[ -f "$NODE_USERS_FILE" ]]; then
                local old_uuid=$(echo "$user_info" | jq -r '.id')
                jq "(.bindings[].users) |= map(if . == \"$old_uuid\" then \"$new_uuid\" else . end)" "$NODE_USERS_FILE" > "${NODE_USERS_FILE}.tmp"
                mv "${NODE_USERS_FILE}.tmp" "$NODE_USERS_FILE"
            fi

            print_success "UUID 重置成功"
            generate_xray_config
            restart_xray
            ;;
        5)
            # 切换启用/禁用状态
            echo ""
            local current_enabled=$(echo "$user_info" | jq -r '.enabled')
            local new_enabled="true"
            [[ "$current_enabled" == "true" ]] && new_enabled="false"

            jq ".users |= map(if .username == \"$username\" then .enabled = $new_enabled else . end)" "$USERS_FILE" > "${USERS_FILE}.tmp"
            mv "${USERS_FILE}.tmp" "$USERS_FILE"

            if [[ "$new_enabled" == "true" ]]; then
                print_success "用户已启用"
            else
                print_success "用户已禁用"
            fi
            generate_xray_config
            restart_xray
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
        echo -e "${GREEN}4.${NC} 修改订阅配置"
        echo -e "${GREEN}5.${NC} 删除订阅"
        echo -e "${GREEN}0.${NC} 返回主菜单"
        echo ""
        read -p "请选择操作 [0-5]: " choice

        case $choice in
            1) show_node_share_link ;;  # 查看单个节点链接
            2) generate_subscription_with_user ;;  # 生成订阅链接（支持用户绑定）
            3) show_subscription_links ;;      # 查看所有订阅链接
            4) modify_subscription_menu ;;  # 修改订阅配置
            5) delete_subscription_smart ;;  # 智能删除订阅（支持批量）
            0) break ;;
            *) print_error "无效选择" ;;
        esac

        read -p "按 Enter 键继续..."
    done
}

# 修改订阅配置菜单
modify_subscription_menu() {
    clear
    echo -e "${CYAN}╔═══════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║      修改订阅配置                    ║${NC}"
    echo -e "${CYAN}╚═══════════════════════════════════════╝${NC}"
    echo ""

    # 显示订阅列表
    show_subscription

    echo ""
    read -p "请输入要修改的订阅名称（不包含扩展名）: " sub_name

    if [[ -z "$sub_name" ]]; then
        print_error "订阅名称不能为空"
        return 1
    fi

    # 查找订阅文件的实际路径
    local sub_file=$(find_subscription_file "$sub_name")
    if [[ -z "$sub_file" ]]; then
        print_error "订阅不存在: $sub_name"
        echo ""
        echo -e "${YELLOW}提示：${NC}请输入订阅基础名称（不包含 .txt、_raw.txt 或 _clash.yaml 等后缀）"
        return 1
    fi

    while true; do
        clear
        echo -e "${CYAN}╔═══════════════════════════════════════╗${NC}"
        echo -e "${CYAN}║      修改订阅: ${YELLOW}$sub_name${CYAN}          ║${NC}"
        echo -e "${CYAN}╚═══════════════════════════════════════╝${NC}"
        echo ""

        echo -e "${GREEN}1.${NC} 修改订阅名称"
        echo -e "${GREEN}2.${NC} 重新生成订阅内容"
        echo -e "${GREEN}0.${NC} 返回"
        echo ""
        echo -e "${YELLOW}提示：流量和有效期请在用户管理中修改${NC}"
        echo ""
        read -p "请选择操作 [0-2]: " choice

        case $choice in
            1)
                # 修改订阅名称
                echo ""
                read -p "请输入新的订阅名称（不包含扩展名）: " new_sub_name
                if [[ -n "$new_sub_name" ]]; then
                    # 清理名称
                    new_sub_name=$(echo "$new_sub_name" | tr -cd 'a-zA-Z0-9_-')
                    if [[ -z "$new_sub_name" ]]; then
                        print_error "订阅名称无效"
                        continue
                    fi

                    # 检查新名称是否已存在
                    local check_file=$(find_subscription_file "$new_sub_name")
                    if [[ -n "$check_file" ]]; then
                        print_error "订阅名称已存在: $new_sub_name"
                        continue
                    fi

                    # 保留原文件的扩展名
                    local old_basename=$(basename "$sub_file")
                    local extension=""

                    if [[ "$old_basename" == *"_clash.yaml" ]]; then
                        extension="_clash.yaml"
                    elif [[ "$old_basename" == *"_raw.txt" ]]; then
                        extension="_raw.txt"
                    elif [[ "$old_basename" == *".txt" ]]; then
                        extension=".txt"
                    fi

                    local new_sub_file="${SUBSCRIPTION_DIR}/${new_sub_name}${extension}"

                    # 重命名文件
                    mv "$sub_file" "$new_sub_file"

                    # 更新订阅数据库中的名称和文件路径
                    update_subscription_name "$sub_name" "$new_sub_name"
                    update_subscription_file "$new_sub_name" "$new_sub_file"

                    # 更新元数据中的名称
                    local old_metadata=$(get_subscription_metadata "$sub_name")
                    if [[ -n "$old_metadata" && "$old_metadata" != "{}" ]]; then
                        delete_subscription_metadata "$sub_name"
                        local old_user_id=$(echo "$old_metadata" | jq -r '.user_id // empty')
                        local old_type=$(echo "$old_metadata" | jq -r '.type // "general"')
                        save_subscription_metadata "$new_sub_name" "$old_user_id" "$old_type"
                    fi

                    print_success "订阅名称已修改为: $new_sub_name"
                    sub_name="$new_sub_name"
                    sub_file="$new_sub_file"
                fi
                ;;
            2)
                # 重新生成订阅内容
                echo ""
                print_info "重新生成订阅内容..."
                if regenerate_subscription "$sub_name"; then
                    print_success "订阅内容已更新"
                else
                    print_error "订阅更新失败"
                fi
                ;;
            0)
                return 0
                ;;
            *)
                print_error "无效选择"
                ;;
        esac

        echo ""
        read -p "按 Enter 键继续..."
    done
}

# 智能删除订阅（支持批量）
delete_subscription_smart() {
    clear
    echo -e "${CYAN}╔═══════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║      删除订阅                        ║${NC}"
    echo -e "${CYAN}╚═══════════════════════════════════════╝${NC}"
    echo ""

    # 显示订阅列表
    show_subscription

    echo ""
    echo -e "${YELLOW}请输入要删除的订阅名称（多个用空格分隔，不包含扩展名）${NC}"
    read -p "订阅名称: " sub_names

    if [[ -z "$sub_names" ]]; then
        print_error "订阅名称不能为空"
        return 1
    fi

    # 确认删除前检查所有订阅是否存在
    local valid_subs=()
    local invalid_subs=()

    for sub_name in $sub_names; do
        local sub_file=$(find_subscription_file "$sub_name")
        if [[ -n "$sub_file" ]]; then
            valid_subs+=("$sub_name")
        else
            invalid_subs+=("$sub_name")
        fi
    done

    # 显示无效的订阅名称
    if [[ ${#invalid_subs[@]} -gt 0 ]]; then
        echo ""
        echo -e "${RED}以下订阅不存在：${NC}"
        for sub_name in "${invalid_subs[@]}"; do
            echo "  - $sub_name"
        done
    fi

    # 如果没有有效的订阅,直接返回
    if [[ ${#valid_subs[@]} -eq 0 ]]; then
        print_error "没有找到有效的订阅"
        echo ""
        echo -e "${YELLOW}提示：${NC}请输入订阅基础名称（不包含 .txt、_raw.txt 或 _clash.yaml 等后缀）"
        return 1
    fi

    # 确认删除
    echo ""
    echo -e "${YELLOW}即将删除以下订阅：${NC}"
    for sub_name in "${valid_subs[@]}"; do
        echo "  - $sub_name"
    done
    echo ""
    read -p "确认删除？(y/N): " confirm

    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        print_info "已取消删除"
        return 0
    fi

    local success_count=0
    local fail_count=0

    for sub_name in "${valid_subs[@]}"; do
        local sub_file=$(find_subscription_file "$sub_name")

        if [[ -z "$sub_file" ]]; then
            print_error "订阅不存在: $sub_name"
            ((fail_count++))
            continue
        fi

        # 删除订阅文件
        if ! rm -f "$sub_file"; then
            print_error "删除订阅文件失败: $sub_name"
            ((fail_count++))
            continue
        fi

        # 删除订阅数据库记录
        if ! remove_subscription_info "$sub_name"; then
            print_error "删除订阅数据库记录失败: $sub_name"
            ((fail_count++))
            continue
        fi

        # 删除订阅元数据
        if ! delete_subscription_metadata "$sub_name"; then
            print_warning "删除订阅元数据失败: $sub_name (非关键错误)"
        fi

        print_success "已删除订阅: $sub_name"
        ((success_count++))
    done

    echo ""
    print_info "操作完成：成功 $success_count 个，失败 $fail_count 个"
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
