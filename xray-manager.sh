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
        echo -e "${CYAN}👥 节点用户管理：${NC}"
        echo -e "${GREEN}9.${NC} 查看节点的用户列表"
        echo -e "${GREEN}10.${NC} 查看所有绑定关系"
        echo ""
        echo -e "${GREEN}0.${NC} 返回主菜单"
        echo ""
        read -p "请选择操作 [0-10]: " choice

        case $choice in
            1) quick_add_vless_reality ;;
            2) add_vless_node ;;
            3) add_vmess_node ;;
            4) add_trojan_node ;;
            5) add_shadowsocks_node ;;
            6) delete_node ;;
            7) list_nodes ;;
            8) modify_node ;;
            9) show_node_users ;;
            10) show_user_node_bindings ;;
            0) break ;;
            *) print_error "无效选择" ;;
        esac

        read -p "按 Enter 键继续..."
    done
}

# 用户管理菜单（新架构）
menu_user() {
    while true; do
        clear
        echo -e "${CYAN}╔═══════════════════════════════════════╗${NC}"
        echo -e "${CYAN}║          用户管理                    ║${NC}"
        echo -e "${CYAN}╚═══════════════════════════════════════╝${NC}"
        echo ""
        echo -e "${CYAN}👥 全局用户管理：${NC}"
        echo -e "${GREEN}1.${NC} 查看全局用户列表"
        echo -e "${GREEN}2.${NC} 添加全局用户"
        echo -e "${GREEN}3.${NC} 删除全局用户"
        echo -e "${GREEN}4.${NC} 修改用户配置"
        echo ""
        echo -e "${CYAN}🔗 用户节点绑定：${NC}"
        echo -e "${GREEN}5.${NC} 绑定用户到节点"
        echo -e "${GREEN}6.${NC} 从节点解绑用户"
        echo -e "${GREEN}7.${NC} 查看用户可访问的节点"
        echo -e "${GREEN}8.${NC} 批量绑定用户到多个节点"
        echo ""
        echo -e "${CYAN}🔧 其他功能：${NC}"
        echo -e "${GREEN}9.${NC} 生成 UUID"
        echo ""
        echo -e "${CYAN}📋 旧版功能（兼容）：${NC}"
        echo -e "${GREEN}11.${NC} 添加用户（旧版-绑定到节点）"
        echo -e "${GREEN}12.${NC} 查看用户列表（旧版-按节点）"
        echo ""
        echo -e "${GREEN}0.${NC} 返回主菜单"
        echo ""
        read -p "请选择操作 [0-12]: " choice

        case $choice in
            1) list_global_users ;;
            2) add_global_user ;;
            3) delete_global_user ;;
            4) modify_user ;;
            5) bind_user_to_node ;;
            6) unbind_user_from_node ;;
            7) show_user_nodes ;;
            8) batch_bind_user_to_nodes ;;
            9)
                echo ""
                local uuid=$(generate_uuid)
                print_success "生成的UUID: $uuid"
                ;;
            11) add_user ;;  # 旧版功能
            12) list_users ;;  # 旧版功能
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
        echo -e "${GREEN}2.${NC} 卸载脚本"
        echo -e "${GREEN}3.${NC} 卸载脚本及依赖"
        echo -e "${GREEN}0.${NC} 返回主菜单"
        echo ""
        read -p "请选择操作 [0-3]: " choice

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
                # 卸载脚本
                clear
                echo -e "${RED}╔═══════════════════════════════════════╗${NC}"
                echo -e "${RED}║          警告：卸载脚本              ║${NC}"
                echo -e "${RED}╚═══════════════════════════════════════╝${NC}"
                echo ""
                echo -e "${YELLOW}此操作将卸载 s-xray 管理脚本${NC}"
                echo -e "${YELLOW}包括所有配置文件和数据${NC}"
                echo -e "${RED}Xray核心将保留${NC}"
                echo ""

                if confirm "确认卸载脚本" "n"; then
                    local script_path="${BASH_SOURCE[0]}"
                    if [[ -L "$script_path" ]]; then
                        script_path="$(readlink -f "$script_path")"
                    fi
                    local script_dir="$(cd "$(dirname "$script_path")" && pwd)"

                    # 删除脚本目录
                    rm -rf "$script_dir"
                    # 删除软链接
                    rm -f /usr/local/bin/xray

                    print_success "脚本已卸载"
                    echo -e "${YELLOW}Xray核心保留在系统中${NC}"
                    exit 0
                else
                    print_info "已取消卸载"
                fi
                ;;
            3)
                # 卸载脚本及依赖
                clear
                echo -e "${RED}╔═══════════════════════════════════════╗${NC}"
                echo -e "${RED}║      警告：完全卸载                  ║${NC}"
                echo -e "${RED}╚═══════════════════════════════════════╝${NC}"
                echo ""
                echo -e "${RED}此操作将完全卸载：${NC}"
                echo -e "${YELLOW}  • s-xray 管理脚本${NC}"
                echo -e "${YELLOW}  • Xray 核心程序${NC}"
                echo -e "${YELLOW}  • 所有配置文件和数据${NC}"
                echo ""

                if confirm "确认完全卸载" "n"; then
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
    while true; do
        clear
        echo -e "${CYAN}╔═══════════════════════════════════════╗${NC}"
        echo -e "${CYAN}║          出站规则管理                ║${NC}"
        echo -e "${CYAN}╚═══════════════════════════════════════╝${NC}"
        echo ""
        echo -e "${GREEN}1.${NC} 查看规则"
        echo -e "${GREEN}2.${NC} 添加规则"
        echo -e "${GREEN}3.${NC} 修改规则"
        echo -e "${GREEN}4.${NC} 删除规则"
        echo -e "${GREEN}5.${NC} 启用规则"
        echo -e "${GREEN}6.${NC} 禁用规则"
        echo -e "${GREEN}0.${NC} 返回主菜单"
        echo ""
        read -p "请选择操作 [0-6]: " choice

        case $choice in
            1)
                print_warning "出站规则功能正在开发中..."
                echo -e "${YELLOW}即将支持：${NC}"
                echo -e "  • 域名分流规则"
                echo -e "  • IP分流规则"
                echo -e "  • 直连/代理/拦截设置"
                ;;
            2|3|4|5|6)
                print_warning "此功能正在开发中，敬请期待"
                ;;
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
