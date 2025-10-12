#!/bin/bash

#================================================================
# 出站规则管理模块
# 功能：管理出站连接规则、Mux配置、代理链
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
        freedom) echo "直连出站 (Freedom)" ;;
        blackhole) echo "黑洞出站 (Blackhole)" ;;
        vless) echo "VLESS 代理" ;;
        vmess) echo "VMess 代理" ;;
        trojan) echo "Trojan 代理" ;;
        shadowsocks) echo "Shadowsocks 代理" ;;
        socks) echo "Socks 代理" ;;
        http) echo "HTTP 代理" ;;
        dns) echo "DNS 出站" ;;
        loopback) echo "回环代理" ;;
        *) echo "未知类型" ;;
    esac
}

#================================================================
# 添加 Freedom 出站（直连）
#================================================================
add_freedom_outbound() {
    clear
    echo -e "${OUTBOUND_CYAN}╔═══════════════════════════════════════╗${OUTBOUND_NC}"
    echo -e "${OUTBOUND_CYAN}║      添加 Freedom 直连出站          ║${OUTBOUND_NC}"
    echo -e "${OUTBOUND_CYAN}╚═══════════════════════════════════════╝${OUTBOUND_NC}"
    echo ""

    echo -e "${OUTBOUND_YELLOW}Freedom 说明：${OUTBOUND_NC}"
    echo -e "  • 直接向目标发送数据（正常转发）"
    echo -e "  • 适用于国内流量、白名单网站"
    echo -e "  • 支持域名策略、TCP分片等功能"
    echo ""

    # 输入标签
    read -p "请输入出站标签 (例如: direct): " tag
    if [[ -z "$tag" ]]; then
        print_error "标签不能为空"
        return 1
    fi

    # 检查标签是否已存在
    if jq -e ".outbounds[] | select(.tag == \"$tag\")" "$OUTBOUND_FILE" >/dev/null 2>&1; then
        print_error "标签 '$tag' 已存在"
        return 1
    fi

    # 域名策略
    echo ""
    echo -e "${OUTBOUND_YELLOW}域名策略：${OUTBOUND_NC}"
    echo -e "${OUTBOUND_GREEN}1.${OUTBOUND_NC} AsIs (默认，使用系统DNS)"
    echo -e "${OUTBOUND_GREEN}2.${OUTBOUND_NC} UseIP (使用内置DNS，IPv4优先)"
    echo -e "${OUTBOUND_GREEN}3.${OUTBOUND_NC} UseIPv4 (仅IPv4)"
    echo -e "${OUTBOUND_GREEN}4.${OUTBOUND_NC} UseIPv6 (仅IPv6)"
    echo ""
    read -p "请选择 [1-4, 默认: 1]: " domain_strategy_choice
    domain_strategy_choice=${domain_strategy_choice:-1}

    local domain_strategy="AsIs"
    case $domain_strategy_choice in
        1) domain_strategy="AsIs" ;;
        2) domain_strategy="UseIP" ;;
        3) domain_strategy="UseIPv4" ;;
        4) domain_strategy="UseIPv6" ;;
    esac

    # 是否启用TCP分片
    echo ""
    read -p "是否启用 TCP 分片（用于绕过 SNI 检测）? [y/N]: " enable_fragment
    local fragment_config=""
    if [[ "$enable_fragment" == "y" || "$enable_fragment" == "Y" ]]; then
        echo ""
        echo -e "${OUTBOUND_YELLOW}TCP 分片配置：${OUTBOUND_NC}"
        read -p "分片包长度范围 (默认: 100-200): " frag_length
        frag_length=${frag_length:-"100-200"}
        read -p "分片间隔(ms) (默认: 10-20): " frag_interval
        frag_interval=${frag_interval:-"10-20"}

        fragment_config=",\"fragment\":{\"packets\":\"tlshello\",\"length\":\"$frag_length\",\"interval\":\"$frag_interval\"}"
    fi

    # 构建配置JSON
    local outbound_config=$(cat <<EOF
{
  "protocol": "freedom",
  "tag": "$tag",
  "settings": {
    "domainStrategy": "$domain_strategy"
    $fragment_config
  }
}
EOF
)

    # 添加到文件
    init_outbound_file
    jq ".outbounds += [$(echo "$outbound_config")]" "$OUTBOUND_FILE" > "${OUTBOUND_FILE}.tmp"
    mv "${OUTBOUND_FILE}.tmp" "$OUTBOUND_FILE"

    print_success "Freedom 出站添加成功！"
    echo ""
    echo -e "${OUTBOUND_CYAN}出站信息：${OUTBOUND_NC}"
    echo -e "  标签: $tag"
    echo -e "  协议: Freedom (直连)"
    echo -e "  域名策略: $domain_strategy"
    [[ -n "$fragment_config" ]] && echo -e "  TCP分片: 已启用"
}

#================================================================
# 添加 Blackhole 出站（黑洞）
#================================================================
add_blackhole_outbound() {
    clear
    echo -e "${OUTBOUND_CYAN}╔═══════════════════════════════════════╗${OUTBOUND_NC}"
    echo -e "${OUTBOUND_CYAN}║      添加 Blackhole 黑洞出站        ║${OUTBOUND_NC}"
    echo -e "${OUTBOUND_CYAN}╚═══════════════════════════════════════╝${OUTBOUND_NC}"
    echo ""

    echo -e "${OUTBOUND_YELLOW}Blackhole 说明：${OUTBOUND_NC}"
    echo -e "  • 阻止所有数据出站（屏蔽访问）"
    echo -e "  • 适用于广告域名、恶意网站"
    echo -e "  • 配合路由规则使用"
    echo ""

    # 输入标签
    read -p "请输入出站标签 (例如: block): " tag
    if [[ -z "$tag" ]]; then
        print_error "标签不能为空"
        return 1
    fi

    # 检查标签是否已存在
    if jq -e ".outbounds[] | select(.tag == \"$tag\")" "$OUTBOUND_FILE" >/dev/null 2>&1; then
        print_error "标签 '$tag' 已存在"
        return 1
    fi

    # 响应类型
    echo ""
    echo -e "${OUTBOUND_YELLOW}响应类型：${OUTBOUND_NC}"
    echo -e "${OUTBOUND_GREEN}1.${OUTBOUND_NC} none (直接关闭连接)"
    echo -e "${OUTBOUND_GREEN}2.${OUTBOUND_NC} http (返回 HTTP 403)"
    echo ""
    read -p "请选择 [1-2, 默认: 1]: " response_type_choice
    response_type_choice=${response_type_choice:-1}

    local response_type="none"
    [[ "$response_type_choice" == "2" ]] && response_type="http"

    # 构建配置JSON
    local outbound_config=$(cat <<EOF
{
  "protocol": "blackhole",
  "tag": "$tag",
  "settings": {
    "response": {
      "type": "$response_type"
    }
  }
}
EOF
)

    # 添加到文件
    init_outbound_file
    jq ".outbounds += [$(echo "$outbound_config")]" "$OUTBOUND_FILE" > "${OUTBOUND_FILE}.tmp"
    mv "${OUTBOUND_FILE}.tmp" "$OUTBOUND_FILE"

    print_success "Blackhole 出站添加成功！"
    echo ""
    echo -e "${OUTBOUND_CYAN}出站信息：${OUTBOUND_NC}"
    echo -e "  标签: $tag"
    echo -e "  协议: Blackhole (黑洞)"
    echo -e "  响应: $response_type"
}

#================================================================
# 添加代理出站（从现有节点）
#================================================================
add_proxy_outbound() {
    clear
    echo -e "${OUTBOUND_CYAN}╔═══════════════════════════════════════╗${OUTBOUND_NC}"
    echo -e "${OUTBOUND_CYAN}║      添加代理出站                    ║${OUTBOUND_NC}"
    echo -e "${OUTBOUND_CYAN}╚═══════════════════════════════════════╝${OUTBOUND_NC}"
    echo ""

    echo -e "${OUTBOUND_YELLOW}代理出站说明：${OUTBOUND_NC}"
    echo -e "  • 使用现有节点作为出站代理"
    echo -e "  • 适用于代理链、多级跳转"
    echo -e "  • 支持 VLESS、VMess、Trojan、SS"
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

    local index=1
    jq -r '.nodes[] | "\(.protocol)|\(.port)|\(.security // "none")|\(.transport // "tcp")"' "$NODES_FILE" | while IFS='|' read -r protocol port security transport; do
        echo -e "${OUTBOUND_GREEN}[$index]${OUTBOUND_NC} 协议: $protocol, 端口: $port, 加密: $security, 传输: $transport"
        ((index++))
    done

    echo ""
    read -p "请选择节点序号: " node_index
    if [[ ! "$node_index" =~ ^[0-9]+$ ]]; then
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
    if jq -e ".outbounds[] | select(.tag == \"$tag\")" "$OUTBOUND_FILE" >/dev/null 2>&1; then
        print_error "标签 '$tag' 已存在"
        return 1
    fi

    # 是否启用 Mux
    echo ""
    read -p "是否启用 Mux 多路复用? [y/N]: " enable_mux
    local mux_config=""
    if [[ "$enable_mux" == "y" || "$enable_mux" == "Y" ]]; then
        echo ""
        read -p "Mux 并发数 (1-128, 默认: 8): " mux_concurrency
        mux_concurrency=${mux_concurrency:-8}
        mux_config=",\"mux\":{\"enabled\":true,\"concurrency\":$mux_concurrency}"
    fi

    # 根据协议构建出站配置（这里简化处理，实际应根据节点完整信息）
    local outbound_config=$(cat <<EOF
{
  "protocol": "$protocol",
  "tag": "$tag",
  "settings": $(echo "$node" | jq '.settings // {}'),
  "streamSettings": $(echo "$node" | jq '{network: .transport, security: .security} + (.extra // {})')
  $mux_config
}
EOF
)

    # 添加到文件
    init_outbound_file
    jq ".outbounds += [$(echo "$outbound_config")]" "$OUTBOUND_FILE" > "${OUTBOUND_FILE}.tmp"
    mv "${OUTBOUND_FILE}.tmp" "$OUTBOUND_FILE"

    print_success "代理出站添加成功！"
    echo ""
    echo -e "${OUTBOUND_CYAN}出站信息：${OUTBOUND_NC}"
    echo -e "  标签: $tag"
    echo -e "  协议: $protocol"
    echo -e "  端口: $port"
    [[ -n "$mux_config" ]] && echo -e "  Mux: 已启用 (并发: $mux_concurrency)"
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

    echo -e "${OUTBOUND_YELLOW}共 $count 条出站规则${OUTBOUND_NC}"
    echo ""
    printf "${OUTBOUND_CYAN}%-5s %-20s %-20s %-15s %s${OUTBOUND_NC}\n" "序号" "标签" "协议" "类型" "说明"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    local index=1
    jq -r '.outbounds[] | "\(.tag)|\(.protocol)|\(.settings.domainStrategy // "N/A")|\(.mux.enabled // false)"' "$OUTBOUND_FILE" 2>/dev/null | while IFS='|' read -r tag protocol domain_strategy mux_enabled; do
        local type_name=$(get_outbound_type_name "$protocol")
        local mux_status="否"
        [[ "$mux_enabled" == "true" ]] && mux_status="是"

        local desc=""
        case $protocol in
            freedom) desc="直连, 策略: $domain_strategy" ;;
            blackhole) desc="黑洞屏蔽" ;;
            *) desc="Mux: $mux_status" ;;
        esac

        printf "${OUTBOUND_GREEN}%-5s${OUTBOUND_NC} %-20s %-20s %-15s %s\n" "$index" "$tag" "$protocol" "$type_name" "$desc"
        ((index++))
    done

    echo ""
    echo -e "${OUTBOUND_YELLOW}提示：${OUTBOUND_NC}"
    echo -e "  • 第一条出站规则为默认出站"
    echo -e "  • 路由不匹配时使用默认出站"
}

#================================================================
# 删除出站规则
#================================================================
delete_outbound() {
    list_outbounds

    echo ""
    read -p "请输入要删除的出站规则序号: " index
    if [[ ! "$index" =~ ^[0-9]+$ ]]; then
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
    print_info "将删除出站规则: $tag"
    read -p "确认删除? [y/N]: " confirm
    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
        print_info "已取消删除"
        return 0
    fi

    # 删除出站
    jq "del(.outbounds[$((index-1))])" "$OUTBOUND_FILE" > "${OUTBOUND_FILE}.tmp"
    mv "${OUTBOUND_FILE}.tmp" "$OUTBOUND_FILE"

    print_success "出站规则删除成功！"
}

#================================================================
# 设置默认出站
#================================================================
set_default_outbound() {
    list_outbounds

    echo ""
    read -p "请输入要设为默认的出站规则序号: " index
    if [[ ! "$index" =~ ^[0-9]+$ ]]; then
        print_error "无效的序号"
        return 1
    fi

    # 获取目标出站
    local outbound=$(jq ".outbounds[$((index-1))]" "$OUTBOUND_FILE" 2>/dev/null)
    if [[ -z "$outbound" || "$outbound" == "null" ]]; then
        print_error "出站规则不存在"
        return 1
    fi

    local tag=$(echo "$outbound" | jq -r '.tag')

    # 移动到第一位
    jq ".outbounds = [.outbounds[$((index-1))]] + [.outbounds[] | select(.tag != \"$tag\")]" "$OUTBOUND_FILE" > "${OUTBOUND_FILE}.tmp"
    mv "${OUTBOUND_FILE}.tmp" "$OUTBOUND_FILE"

    print_success "默认出站已设置为: $tag"
}

#================================================================
# 修改出站Mux配置
#================================================================
modify_outbound_mux() {
    list_outbounds

    echo ""
    read -p "请输入要修改Mux配置的出站规则序号: " index
    if [[ ! "$index" =~ ^[0-9]+$ ]]; then
        print_error "无效的序号"
        return 1
    fi

    local protocol=$(jq -r ".outbounds[$((index-1))].protocol" "$OUTBOUND_FILE" 2>/dev/null)
    if [[ -z "$protocol" || "$protocol" == "null" ]]; then
        print_error "出站规则不存在"
        return 1
    fi

    # 检查协议是否支持Mux
    if [[ "$protocol" == "freedom" || "$protocol" == "blackhole" || "$protocol" == "dns" ]]; then
        print_error "协议 $protocol 不支持 Mux"
        return 1
    fi

    echo ""
    echo -e "${OUTBOUND_YELLOW}Mux 配置：${OUTBOUND_NC}"
    echo -e "${OUTBOUND_GREEN}1.${OUTBOUND_NC} 启用 Mux"
    echo -e "${OUTBOUND_GREEN}2.${OUTBOUND_NC} 禁用 Mux"
    echo -e "${OUTBOUND_GREEN}0.${OUTBOUND_NC} 返回"
    echo ""
    read -p "请选择 [0-2]: " mux_choice

    case $mux_choice in
        1)
            read -p "Mux 并发数 (1-128, 默认: 8): " mux_concurrency
            mux_concurrency=${mux_concurrency:-8}
            jq ".outbounds[$((index-1))].mux = {\"enabled\":true,\"concurrency\":$mux_concurrency}" "$OUTBOUND_FILE" > "${OUTBOUND_FILE}.tmp"
            mv "${OUTBOUND_FILE}.tmp" "$OUTBOUND_FILE"
            print_success "Mux 已启用 (并发: $mux_concurrency)"
            ;;
        2)
            jq "del(.outbounds[$((index-1))].mux)" "$OUTBOUND_FILE" > "${OUTBOUND_FILE}.tmp"
            mv "${OUTBOUND_FILE}.tmp" "$OUTBOUND_FILE"
            print_success "Mux 已禁用"
            ;;
        0)
            return 0
            ;;
        *)
            print_error "无效选择"
            ;;
    esac
}

#================================================================
# 导出出站配置到Xray
#================================================================
export_outbounds_to_xray() {
    clear
    echo -e "${OUTBOUND_CYAN}╔═══════════════════════════════════════╗${OUTBOUND_NC}"
    echo -e "${OUTBOUND_CYAN}║      导出出站配置到 Xray            ║${OUTBOUND_NC}"
    echo -e "${OUTBOUND_CYAN}╚═══════════════════════════════════════╝${OUTBOUND_NC}"
    echo ""

    init_outbound_file

    local count=$(jq '.outbounds | length' "$OUTBOUND_FILE" 2>/dev/null || echo "0")
    if [[ "$count" -eq 0 ]]; then
        print_error "暂无出站规则"
        return 1
    fi

    echo -e "${OUTBOUND_YELLOW}即将导出 $count 条出站规则到 Xray 配置${OUTBOUND_NC}"
    echo ""
    read -p "确认导出? [y/N]: " confirm
    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
        print_info "已取消导出"
        return 0
    fi

    # 备份当前配置
    if [[ -f "$XRAY_CONFIG" ]]; then
        cp "$XRAY_CONFIG" "${XRAY_CONFIG}.backup.$(date +%s)"
        print_info "已备份当前配置"
    fi

    # 合并出站配置到Xray config.json
    local outbounds=$(jq '.outbounds' "$OUTBOUND_FILE")
    jq ".outbounds = $outbounds" "$XRAY_CONFIG" > "${XRAY_CONFIG}.tmp"
    mv "${XRAY_CONFIG}.tmp" "$XRAY_CONFIG"

    print_success "出站配置导出成功！"
    echo ""
    read -p "是否重启 Xray 服务使配置生效? [y/N]: " restart
    if [[ "$restart" == "y" || "$restart" == "Y" ]]; then
        systemctl restart xray && print_success "Xray 服务重启成功" || print_error "Xray 服务重启失败"
    fi
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
        echo -e "${OUTBOUND_GREEN}2.${OUTBOUND_NC} 添加 Freedom 出站（直连）"
        echo -e "${OUTBOUND_GREEN}3.${OUTBOUND_NC} 添加 Blackhole 出站（黑洞）"
        echo -e "${OUTBOUND_GREEN}4.${OUTBOUND_NC} 添加代理出站（从现有节点）"
        echo -e "${OUTBOUND_GREEN}5.${OUTBOUND_NC} 删除出站规则"
        echo -e "${OUTBOUND_GREEN}6.${OUTBOUND_NC} 设置默认出站"
        echo -e "${OUTBOUND_GREEN}7.${OUTBOUND_NC} 修改 Mux 配置"
        echo -e "${OUTBOUND_GREEN}8.${OUTBOUND_NC} 导出到 Xray 配置"
        echo -e "${OUTBOUND_GREEN}0.${OUTBOUND_NC} 返回主菜单"
        echo ""
        read -p "请选择操作 [0-8]: " choice

        case $choice in
            1) list_outbounds ;;
            2) add_freedom_outbound ;;
            3) add_blackhole_outbound ;;
            4) add_proxy_outbound ;;
            5) delete_outbound ;;
            6) set_default_outbound ;;
            7) modify_outbound_mux ;;
            8) export_outbounds_to_xray ;;
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
