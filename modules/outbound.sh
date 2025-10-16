#!/bin/bash

#================================================================
# 出站规则管理模块 - 重构版
# 功能：管理常用出站协议（HTTP、SOCKS）、代理链
# 移除：Freedom、Blackhole、默认出站等无用功能
# 优化：出站规则统一修改、绑定到节点的逻辑
#================================================================

# 全局变量
OUTBOUND_FILE="${DATA_DIR}/outbounds.json"

# 颜色定义（继承主脚本）
readonly OUTBOUND_CYAN="${CYAN:-\033[0;36m}"
readonly OUTBOUND_GREEN="${GREEN:-\033[0;32m}"
readonly OUTBOUND_YELLOW="${YELLOW:-\033[1;33m}"
readonly OUTBOUND_RED="${RED:-\033[0;31m}"
readonly OUTBOUND_NC="${NC:-\033[0m}"

# 初始化出站规则文件
init_outbound_file() {
    if [[ ! -f "$OUTBOUND_FILE" ]]; then
        echo '{"outbounds":[]}' > "$OUTBOUND_FILE"
    fi
}

#================================================================
# 出站协议类型枚举
#================================================================
get_outbound_type_name() {
    case $1 in
        vless) echo "VLESS 代理" ;;
        vmess) echo "VMess 代理" ;;
        trojan) echo "Trojan 代理" ;;
        shadowsocks) echo "Shadowsocks 代理" ;;
        socks) echo "Socks 代理" ;;
        http) echo "HTTP 代理" ;;
        wireguard) echo "WireGuard 代理" ;;
        *) echo "未知类型" ;;
    esac
}

#================================================================
# 添加 HTTP 出站
#================================================================
add_http_outbound() {
    clear
    echo -e "${OUTBOUND_CYAN}╔═══════════════════════════════════════╗${OUTBOUND_NC}"
    echo -e "${OUTBOUND_CYAN}║      添加 HTTP 出站                  ║${OUTBOUND_NC}"
    echo -e "${OUTBOUND_CYAN}╚═══════════════════════════════════════╝${OUTBOUND_NC}"
    echo ""

    echo -e "${OUTBOUND_YELLOW}HTTP 出站说明：${OUTBOUND_NC}"
    echo -e "  • 使用 HTTP/HTTPS 代理协议"
    echo -e "  • 适用于需要 HTTP 代理的场景"
    echo -e "  • 支持用户名密码认证"
    echo ""

    # 输入标签
    read -p "请输入出站标签 (例如: http-proxy): " tag
    if [[ -z "$tag" ]]; then
        print_error "标签不能为空"
        return 1
    fi

    # 检查标签是否已存在
    if jq -e --arg tag "$tag" '.outbounds[] | select(.tag == $tag)' "$OUTBOUND_FILE" >/dev/null 2>&1; then
        print_error "标签 '$tag' 已存在"
        return 1
    fi

    # 服务器地址和端口
    echo ""
    read -p "请输入服务器地址: " server
    if [[ -z "$server" ]]; then
        print_error "服务器地址不能为空"
        return 1
    fi

    read -p "请输入端口 (默认: 3128): " port
    port=${port:-3128}

    # 是否需要认证
    echo ""
    read -p "是否需要用户名密码认证? [y/N]: " need_auth
    local auth_config=""
    if [[ "$need_auth" == "y" || "$need_auth" == "Y" ]]; then
        read -p "请输入用户名: " username
        read -p "请输入密码: " password
        if [[ -n "$username" && -n "$password" ]]; then
            auth_config=",\"user\":\"$username\",\"pass\":\"$password\""
        fi
    fi

    # 构建出站配置
    local outbound_config=$(cat <<EOF
{
  "protocol": "http",
  "tag": "$tag",
  "settings": {
    "servers": [{
      "address": "$server",
      "port": $port
      $auth_config
    }]
  }
}
EOF
)

    # 添加到文件
    init_outbound_file
    jq --argjson outbound "$outbound_config" '.outbounds += [$outbound]' "$OUTBOUND_FILE" > "${OUTBOUND_FILE}.tmp"
    mv "${OUTBOUND_FILE}.tmp" "$OUTBOUND_FILE"

    print_success "HTTP 出站添加成功！"
    echo ""
    echo -e "${OUTBOUND_CYAN}出站信息：${OUTBOUND_NC}"
    echo -e "  标签: $tag"
    echo -e "  服务器: $server:$port"
    [[ -n "$auth_config" ]] && echo -e "  认证: 已启用"
}

#================================================================
# 添加 SOCKS 出站
#================================================================
add_socks_outbound() {
    clear
    echo -e "${OUTBOUND_CYAN}╔═══════════════════════════════════════╗${OUTBOUND_NC}"
    echo -e "${OUTBOUND_CYAN}║      添加 SOCKS 出站                 ║${OUTBOUND_NC}"
    echo -e "${OUTBOUND_CYAN}╚═══════════════════════════════════════╝${OUTBOUND_NC}"
    echo ""

    echo -e "${OUTBOUND_YELLOW}SOCKS 出站说明：${OUTBOUND_NC}"
    echo -e "  • 使用 SOCKS5/SOCKS4 代理协议"
    echo -e "  • 适用于需要 SOCKS 代理的场景"
    echo -e "  • 支持用户名密码认证"
    echo ""

    # 输入标签
    read -p "请输入出站标签 (例如: socks-proxy): " tag
    if [[ -z "$tag" ]]; then
        print_error "标签不能为空"
        return 1
    fi

    # 检查标签是否已存在
    if jq -e --arg tag "$tag" '.outbounds[] | select(.tag == $tag)' "$OUTBOUND_FILE" >/dev/null 2>&1; then
        print_error "标签 '$tag' 已存在"
        return 1
    fi

    # 服务器地址和端口
    echo ""
    read -p "请输入服务器地址: " server
    if [[ -z "$server" ]]; then
        print_error "服务器地址不能为空"
        return 1
    fi

    read -p "请输入端口 (默认: 1080): " port
    port=${port:-1080}

    # 是否需要认证
    echo ""
    read -p "是否需要用户名密码认证? [y/N]: " need_auth
    local auth_config=""
    if [[ "$need_auth" == "y" || "$need_auth" == "Y" ]]; then
        read -p "请输入用户名: " username
        read -p "请输入密码: " password
        if [[ -n "$username" && -n "$password" ]]; then
            auth_config=",\"user\":\"$username\",\"pass\":\"$password\""
        fi
    fi

    # 构建出站配置
    local outbound_config=$(cat <<EOF
{
  "protocol": "socks",
  "tag": "$tag",
  "settings": {
    "servers": [{
      "address": "$server",
      "port": $port
      $auth_config
    }]
  }
}
EOF
)

    # 添加到文件
    init_outbound_file
    jq --argjson outbound "$outbound_config" '.outbounds += [$outbound]' "$OUTBOUND_FILE" > "${OUTBOUND_FILE}.tmp"
    mv "${OUTBOUND_FILE}.tmp" "$OUTBOUND_FILE"

    print_success "SOCKS 出站添加成功！"
    echo ""
    echo -e "${OUTBOUND_CYAN}出站信息：${OUTBOUND_NC}"
    echo -e "  标签: $tag"
    echo -e "  服务器: $server:$port"
    [[ -n "$auth_config" ]] && echo -e "  认证: 已启用"
}

#================================================================
# 从节点添加代理出站
#================================================================
add_proxy_outbound_from_node() {
    clear
    echo -e "${OUTBOUND_CYAN}╔═══════════════════════════════════════╗${OUTBOUND_NC}"
    echo -e "${OUTBOUND_CYAN}║      从节点添加代理出站              ║${OUTBOUND_NC}"
    echo -e "${OUTBOUND_CYAN}╚═══════════════════════════════════════╝${OUTBOUND_NC}"
    echo ""

    echo -e "${OUTBOUND_YELLOW}代理出站说明：${OUTBOUND_NC}"
    echo -e "  • 使用现有节点配置作为出站代理"
    echo -e "  • 支持 VLESS、VMess、Trojan、Shadowsocks"
    echo -e "  • 适用于代理链、多级跳转场景"
    echo ""

    # 检查节点是否存在
    if [[ ! -f "$NODES_FILE" ]]; then
        print_error "节点文件不存在，请先添加节点"
        return 1
    fi

    local node_count=$(jq '.nodes | length' "$NODES_FILE" 2>/dev/null || echo "0")
    if [[ "$node_count" -eq 0 ]]; then
        print_error "暂无节点，请先添加节点"
        return 1
    fi

    # 显示节点列表
    echo -e "${OUTBOUND_CYAN}现有节点列表：${OUTBOUND_NC}"
    echo ""
    printf "${OUTBOUND_CYAN}%-4s %-12s %-8s %-12s %-12s${OUTBOUND_NC}\n" "序号" "协议" "端口" "加密" "传输"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    local index=1
    while read -r line; do
        local protocol=$(echo "$line" | jq -r '.protocol')
        local port=$(echo "$line" | jq -r '.port')
        local security=$(echo "$line" | jq -r '.security // "none"')
        local transport=$(echo "$line" | jq -r '.transport // "tcp"')
        printf "%-4s %-12s %-8s %-12s %-12s\n" "$index" "$protocol" "$port" "$security" "$transport"
        ((index++))
    done < <(jq -c '.nodes[]' "$NODES_FILE" 2>/dev/null)

    echo ""
    read -p "请选择节点序号: " node_index
    if [[ ! "$node_index" =~ ^[0-9]+$ ]] || [[ "$node_index" -lt 1 ]] || [[ "$node_index" -gt "$node_count" ]]; then
        print_error "无效的序号"
        return 1
    fi

    # 获取节点配置
    local node=$(jq ".nodes[$((node_index-1))]" "$NODES_FILE" 2>/dev/null)
    if [[ -z "$node" || "$node" == "null" ]]; then
        print_error "节点不存在"
        return 1
    fi

    local protocol=$(echo "$node" | jq -r '.protocol')
    local port=$(echo "$node" | jq -r '.port')

    # 输入出站标签
    echo ""
    read -p "请输入出站标签 (例如: proxy-${protocol}-${port}): " tag
    tag=${tag:-"proxy-${protocol}-${port}"}

    # 检查标签是否已存在
    if jq -e --arg tag "$tag" '.outbounds[] | select(.tag == $tag)' "$OUTBOUND_FILE" >/dev/null 2>&1; then
        print_error "标签 '$tag' 已存在"
        return 1
    fi

    # Mux 配置
    echo ""
    read -p "是否启用 Mux 多路复用? [y/N]: " enable_mux
    local mux_enabled="false"
    local mux_concurrency=8
    if [[ "$enable_mux" == "y" || "$enable_mux" == "Y" ]]; then
        mux_enabled="true"
        read -p "Mux 并发数 (1-128, 默认: 8): " input_concurrency
        mux_concurrency=${input_concurrency:-8}
    fi

    # 构建出站配置
    local settings=$(echo "$node" | jq '.settings // {}')
    local stream_settings=$(echo "$node" | jq '{network: .transport, security: .security} + (.extra // {})')

    local outbound_config=$(jq -n \
        --arg protocol "$protocol" \
        --arg tag "$tag" \
        --argjson settings "$settings" \
        --argjson streamSettings "$stream_settings" \
        --argjson mux_enabled "$mux_enabled" \
        --argjson mux_concurrency "$mux_concurrency" \
        '{
            protocol: $protocol,
            tag: $tag,
            settings: $settings,
            streamSettings: $streamSettings,
            mux: {
                enabled: $mux_enabled,
                concurrency: $mux_concurrency
            }
        }')

    # 添加到文件
    init_outbound_file
    jq --argjson outbound "$outbound_config" '.outbounds += [$outbound]' "$OUTBOUND_FILE" > "${OUTBOUND_FILE}.tmp"
    mv "${OUTBOUND_FILE}.tmp" "$OUTBOUND_FILE"

    print_success "代理出站添加成功！"
    echo ""
    echo -e "${OUTBOUND_CYAN}出站信息：${OUTBOUND_NC}"
    echo -e "  标签: $tag"
    echo -e "  协议: $protocol"
    echo -e "  端口: $port"
    echo -e "  Mux: $([[ "$mux_enabled" == "true" ]] && echo "已启用 (并发: $mux_concurrency)" || echo "未启用")"
}

#================================================================
# 查看出站规则列表
#================================================================
list_outbounds() {
    clear
    echo -e "${OUTBOUND_CYAN}╔═══════════════════════════════════════╗${OUTBOUND_NC}"
    echo -e "${OUTBOUND_CYAN}║          出站规则列表                ║${OUTBOUND_NC}"
    echo -e "${OUTBOUND_CYAN}╚═══════════════════════════════════════╝${OUTBOUND_NC}"
    echo ""

    init_outbound_file

    local count=$(jq '.outbounds | length' "$OUTBOUND_FILE" 2>/dev/null || echo "0")
    if [[ "$count" -eq 0 ]]; then
        print_warning "暂无出站规则"
        return 0
    fi

    echo -e "${OUTBOUND_YELLOW}出站规则总数:${OUTBOUND_NC} $count"
    echo ""
    printf "${OUTBOUND_CYAN}%-4s %-20s %-18s %-12s %-10s${OUTBOUND_NC}\n" "序号" "标签" "协议" "Mux" "地址/端口"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    local index=1
    while read -r outbound; do
        local tag=$(echo "$outbound" | jq -r '.tag')
        local protocol=$(echo "$outbound" | jq -r '.protocol')
        local mux_enabled=$(echo "$outbound" | jq -r '.mux.enabled // false')
        local mux_concurrency=$(echo "$outbound" | jq -r '.mux.concurrency // 0')

        # 获取地址和端口（不同协议结构不同）
        local address=$(echo "$outbound" | jq -r '.settings.servers[0].address // .settings.vnext[0].address // "N/A"')
        local port=$(echo "$outbound" | jq -r '.settings.servers[0].port // .settings.vnext[0].port // "N/A"')

        local mux_display="否"
        if [[ "$mux_enabled" == "true" ]]; then
            mux_display="是($mux_concurrency)"
        fi

        printf "%-4s %-20s %-18s %-12s %-10s\n" "$index" "$tag" "$protocol" "$mux_display" "$address:$port"
        ((index++))
    done < <(jq -c '.outbounds[]' "$OUTBOUND_FILE" 2>/dev/null)

    echo ""
}

#================================================================
# 删除出站规则
#================================================================
delete_outbound() {
    list_outbounds

    local count=$(jq '.outbounds | length' "$OUTBOUND_FILE" 2>/dev/null || echo "0")
    if [[ "$count" -eq 0 ]]; then
        return 0
    fi

    echo ""
    read -p "请输入要删除的出站规则序号: " index
    if [[ ! "$index" =~ ^[0-9]+$ ]] || [[ "$index" -lt 1 ]] || [[ "$index" -gt "$count" ]]; then
        print_error "无效的序号"
        return 1
    fi

    # 获取标签
    local tag=$(jq -r ".outbounds[$((index-1))].tag" "$OUTBOUND_FILE" 2>/dev/null)
    if [[ -z "$tag" || "$tag" == "null" ]]; then
        print_error "出站规则不存在"
        return 1
    fi

    echo ""
    read -p "确认删除出站规则 '$tag'? [y/N]: " confirm
    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
        print_info "已取消删除"
        return 0
    fi

    # 删除
    jq --arg tag "$tag" '.outbounds = [.outbounds[] | select(.tag != $tag)]' "$OUTBOUND_FILE" > "${OUTBOUND_FILE}.tmp"
    mv "${OUTBOUND_FILE}.tmp" "$OUTBOUND_FILE"

    print_success "出站规则已删除: $tag"
}

#================================================================
# 修改出站规则
#================================================================
modify_outbound() {
    list_outbounds

    local count=$(jq '.outbounds | length' "$OUTBOUND_FILE" 2>/dev/null || echo "0")
    if [[ "$count" -eq 0 ]]; then
        return 0
    fi

    echo ""
    read -p "请输入要修改的出站规则序号: " index
    if [[ ! "$index" =~ ^[0-9]+$ ]] || [[ "$index" -lt 1 ]] || [[ "$index" -gt "$count" ]]; then
        print_error "无效的序号"
        return 1
    fi

    local outbound=$(jq ".outbounds[$((index-1))]" "$OUTBOUND_FILE" 2>/dev/null)
    if [[ -z "$outbound" || "$outbound" == "null" ]]; then
        print_error "出站规则不存在"
        return 1
    fi

    local tag=$(echo "$outbound" | jq -r '.tag')
    local protocol=$(echo "$outbound" | jq -r '.protocol')

    clear
    echo -e "${OUTBOUND_CYAN}╔═══════════════════════════════════════╗${OUTBOUND_NC}"
    echo -e "${OUTBOUND_CYAN}║      修改出站规则: ${OUTBOUND_YELLOW}$tag${OUTBOUND_CYAN}         ║${OUTBOUND_NC}"
    echo -e "${OUTBOUND_CYAN}╚═══════════════════════════════════════╝${OUTBOUND_NC}"
    echo ""
    echo -e "${OUTBOUND_GREEN}1.${OUTBOUND_NC} 修改标签"
    echo -e "${OUTBOUND_GREEN}2.${OUTBOUND_NC} 修改 Mux 配置"
    echo -e "${OUTBOUND_GREEN}3.${OUTBOUND_NC} 修改服务器地址/端口 (HTTP/SOCKS)"
    echo -e "${OUTBOUND_GREEN}4.${OUTBOUND_NC} 修改认证信息 (HTTP/SOCKS)"
    echo -e "${OUTBOUND_GREEN}0.${OUTBOUND_NC} 返回"
    echo ""
    read -p "请选择操作 [0-4]: " choice

    case $choice in
        1) modify_outbound_tag "$index" "$tag" ;;
        2) modify_outbound_mux_config "$index" "$tag" ;;
        3) modify_outbound_server "$index" "$tag" "$protocol" ;;
        4) modify_outbound_auth "$index" "$tag" "$protocol" ;;
        0) return 0 ;;
        *) print_error "无效选择" ;;
    esac
}

# 修改标签
modify_outbound_tag() {
    local index=$1
    local old_tag=$2

    echo ""
    read -p "请输入新标签: " new_tag
    if [[ -z "$new_tag" ]]; then
        print_error "标签不能为空"
        return 1
    fi

    # 检查新标签是否已存在
    if jq -e --arg tag "$new_tag" '.outbounds[] | select(.tag == $tag)' "$OUTBOUND_FILE" >/dev/null 2>&1; then
        print_error "标签 '$new_tag' 已存在"
        return 1
    fi

    jq "(.outbounds[$((index-1))].tag) = \"$new_tag\"" "$OUTBOUND_FILE" > "${OUTBOUND_FILE}.tmp"
    mv "${OUTBOUND_FILE}.tmp" "$OUTBOUND_FILE"

    print_success "标签已更新: $old_tag -> $new_tag"
}

# 修改 Mux 配置
modify_outbound_mux_config() {
    local index=$1
    local tag=$2

    local current_enabled=$(jq -r ".outbounds[$((index-1))].mux.enabled // false" "$OUTBOUND_FILE")
    local current_concurrency=$(jq -r ".outbounds[$((index-1))].mux.concurrency // 8" "$OUTBOUND_FILE")

    echo ""
    echo -e "${OUTBOUND_YELLOW}当前 Mux 配置：${OUTBOUND_NC}"
    echo -e "  启用: $current_enabled"
    [[ "$current_enabled" == "true" ]] && echo -e "  并发数: $current_concurrency"
    echo ""

    read -p "是否启用 Mux? [y/N]: " enable_mux
    local mux_enabled="false"
    local mux_concurrency=8
    if [[ "$enable_mux" == "y" || "$enable_mux" == "Y" ]]; then
        mux_enabled="true"
        read -p "Mux 并发数 (1-128, 默认: 8): " input_concurrency
        mux_concurrency=${input_concurrency:-8}
    fi

    jq --argjson enabled "$mux_enabled" --argjson concurrency "$mux_concurrency" \
       "(.outbounds[$((index-1))].mux) = {enabled: \$enabled, concurrency: \$concurrency}" \
       "$OUTBOUND_FILE" > "${OUTBOUND_FILE}.tmp"
    mv "${OUTBOUND_FILE}.tmp" "$OUTBOUND_FILE"

    print_success "Mux 配置已更新"
}

# 修改服务器地址/端口
modify_outbound_server() {
    local index=$1
    local tag=$2
    local protocol=$3

    if [[ "$protocol" != "http" && "$protocol" != "socks" ]]; then
        print_error "只有 HTTP 和 SOCKS 协议支持此操作"
        return 1
    fi

    local current_address=$(jq -r ".outbounds[$((index-1))].settings.servers[0].address" "$OUTBOUND_FILE")
    local current_port=$(jq -r ".outbounds[$((index-1))].settings.servers[0].port" "$OUTBOUND_FILE")

    echo ""
    echo -e "${OUTBOUND_YELLOW}当前服务器：${OUTBOUND_NC}"
    echo -e "  地址: $current_address"
    echo -e "  端口: $current_port"
    echo ""

    read -p "请输入新的服务器地址 (回车保持不变): " new_address
    read -p "请输入新的端口 (回车保持不变): " new_port

    new_address=${new_address:-$current_address}
    new_port=${new_port:-$current_port}

    jq --arg address "$new_address" --argjson port "$new_port" \
       "(.outbounds[$((index-1))].settings.servers[0].address) = \$address |
        (.outbounds[$((index-1))].settings.servers[0].port) = \$port" \
       "$OUTBOUND_FILE" > "${OUTBOUND_FILE}.tmp"
    mv "${OUTBOUND_FILE}.tmp" "$OUTBOUND_FILE"

    print_success "服务器配置已更新"
}

# 修改认证信息
modify_outbound_auth() {
    local index=$1
    local tag=$2
    local protocol=$3

    if [[ "$protocol" != "http" && "$protocol" != "socks" ]]; then
        print_error "只有 HTTP 和 SOCKS 协议支持此操作"
        return 1
    fi

    local current_user=$(jq -r ".outbounds[$((index-1))].settings.servers[0].user // \"\"" "$OUTBOUND_FILE")

    echo ""
    [[ -n "$current_user" ]] && echo -e "${OUTBOUND_YELLOW}当前认证用户: $current_user${OUTBOUND_NC}"
    echo ""

    read -p "是否启用认证? [y/N]: " enable_auth
    if [[ "$enable_auth" != "y" && "$enable_auth" != "Y" ]]; then
        # 移除认证
        jq "del(.outbounds[$((index-1))].settings.servers[0].user, .outbounds[$((index-1))].settings.servers[0].pass)" \
           "$OUTBOUND_FILE" > "${OUTBOUND_FILE}.tmp"
        mv "${OUTBOUND_FILE}.tmp" "$OUTBOUND_FILE"
        print_success "认证已禁用"
        return 0
    fi

    read -p "请输入用户名: " username
    read -p "请输入密码: " password

    if [[ -z "$username" || -z "$password" ]]; then
        print_error "用户名和密码不能为空"
        return 1
    fi

    jq --arg user "$username" --arg pass "$password" \
       "(.outbounds[$((index-1))].settings.servers[0].user) = \$user |
        (.outbounds[$((index-1))].settings.servers[0].pass) = \$pass" \
       "$OUTBOUND_FILE" > "${OUTBOUND_FILE}.tmp"
    mv "${OUTBOUND_FILE}.tmp" "$OUTBOUND_FILE"

    print_success "认证信息已更新"
}

#================================================================
# 出站规则管理菜单
#================================================================
outbound_management_menu() {
    while true; do
        clear
        echo -e "${OUTBOUND_CYAN}╔═══════════════════════════════════════╗${OUTBOUND_NC}"
        echo -e "${OUTBOUND_CYAN}║          出站规则管理                ║${OUTBOUND_NC}"
        echo -e "${OUTBOUND_CYAN}╚═══════════════════════════════════════╝${OUTBOUND_NC}"
        echo ""
        echo -e "${OUTBOUND_GREEN}1.${OUTBOUND_NC} 查看出站规则"
        echo -e "${OUTBOUND_GREEN}2.${OUTBOUND_NC} 添加 HTTP 出站"
        echo -e "${OUTBOUND_GREEN}3.${OUTBOUND_NC} 添加 SOCKS 出站"
        echo -e "${OUTBOUND_GREEN}4.${OUTBOUND_NC} 从节点添加代理出站"
        echo -e "${OUTBOUND_GREEN}5.${OUTBOUND_NC} 修改出站规则"
        echo -e "${OUTBOUND_GREEN}6.${OUTBOUND_NC} 删除出站规则"
        echo -e "${OUTBOUND_GREEN}0.${OUTBOUND_NC} 返回主菜单"
        echo ""
        read -p "请选择操作 [0-6]: " choice

        case $choice in
            1) list_outbounds ;;
            2) add_http_outbound ;;
            3) add_socks_outbound ;;
            4) add_proxy_outbound_from_node ;;
            5) modify_outbound ;;
            6) delete_outbound ;;
            0) break ;;
            *) print_error "无效选择" ;;
        esac

        read -p "按 Enter 键继续..."
    done
}

# 如果直接运行此脚本，显示菜单
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    outbound_management_menu
fi
