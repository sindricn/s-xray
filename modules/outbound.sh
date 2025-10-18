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
    local username=""
    local password=""
    if [[ "$need_auth" == "y" || "$need_auth" == "Y" ]]; then
        read -p "请输入用户名: " username
        read -p "请输入密码: " password
    fi

    # 构建出站配置 (使用jq确保JSON格式正确)
    local server_config=$(jq -n \
        --arg address "$server" \
        --argjson port "$port" \
        '{address: $address, port: $port}')

    # 如果需要认证,添加users数组
    if [[ -n "$username" && -n "$password" ]]; then
        local users_array=$(jq -n \
            --arg user "$username" \
            --arg pass "$password" \
            '[{user: $user, pass: $pass, level: 0}]')
        server_config=$(echo "$server_config" | jq \
            --argjson users "$users_array" \
            '. + {users: $users}')
    fi

    local outbound_config=$(jq -n \
        --arg tag "$tag" \
        --argjson server "$server_config" \
        '{
            protocol: "http",
            tag: $tag,
            settings: {
                servers: [$server],
                headers: {
                    "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
                    "Accept-Language": "zh-CN,zh;q=0.9,en;q=0.8"
                }
            }
        }')

    # 添加到文件
    init_outbound_file
    jq --argjson outbound "$outbound_config" '.outbounds += [$outbound]' "$OUTBOUND_FILE" > "${OUTBOUND_FILE}.tmp"
    mv "${OUTBOUND_FILE}.tmp" "$OUTBOUND_FILE"

    print_success "HTTP 出站添加成功！"
    echo ""
    echo -e "${OUTBOUND_CYAN}出站信息：${OUTBOUND_NC}"
    echo -e "  标签: $tag"
    echo -e "  服务器: $server:$port"
    [[ -n "$username" ]] && echo -e "  认证: 已启用 (用户: $username)"
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
    local username=""
    local password=""
    if [[ "$need_auth" == "y" || "$need_auth" == "Y" ]]; then
        read -p "请输入用户名: " username
        read -p "请输入密码: " password
    fi

    # 构建出站配置 (使用jq确保JSON格式正确)
    local server_config=$(jq -n \
        --arg address "$server" \
        --argjson port "$port" \
        '{address: $address, port: $port}')

    # 如果需要认证,添加users数组
    if [[ -n "$username" && -n "$password" ]]; then
        local users_array=$(jq -n \
            --arg user "$username" \
            --arg pass "$password" \
            '[{user: $user, pass: $pass, level: 0}]')
        server_config=$(echo "$server_config" | jq \
            --argjson users "$users_array" \
            '. + {users: $users}')
    fi

    local outbound_config=$(jq -n \
        --arg tag "$tag" \
        --argjson server "$server_config" \
        '{
            protocol: "socks",
            tag: $tag,
            settings: {
                servers: [$server]
            }
        }')

    # 添加到文件
    init_outbound_file
    jq --argjson outbound "$outbound_config" '.outbounds += [$outbound]' "$OUTBOUND_FILE" > "${OUTBOUND_FILE}.tmp"
    mv "${OUTBOUND_FILE}.tmp" "$OUTBOUND_FILE"

    print_success "SOCKS 出站添加成功！"
    echo ""
    echo -e "${OUTBOUND_CYAN}出站信息：${OUTBOUND_NC}"
    echo -e "  标签: $tag"
    echo -e "  服务器: $server:$port"
    [[ -n "$username" ]] && echo -e "  认证: 已启用 (用户: $username)"
}

#================================================================
# 添加 VLESS 出站
#================================================================
add_vless_outbound() {
    clear
    echo -e "${OUTBOUND_CYAN}╔═══════════════════════════════════════╗${OUTBOUND_NC}"
    echo -e "${OUTBOUND_CYAN}║      添加 VLESS 出站                 ║${OUTBOUND_NC}"
    echo -e "${OUTBOUND_CYAN}╚═══════════════════════════════════════╝${OUTBOUND_NC}"
    echo ""

    echo -e "${OUTBOUND_YELLOW}VLESS 出站说明：${OUTBOUND_NC}"
    echo -e "  • 无状态轻量传输协议"
    echo -e "  • 支持 XTLS Vision 流控"
    echo -e "  • 需要配合 TLS/Reality 使用"
    echo ""

    # 输入标签
    read -p "请输入出站标签 (例如: vless-proxy): " tag
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

    read -p "请输入端口 (默认: 443): " port
    port=${port:-443}

    # UUID
    read -p "请输入用户UUID: " uuid
    if [[ -z "$uuid" ]]; then
        print_error "UUID不能为空"
        return 1
    fi

    # Flow (可选)
    echo ""
    echo -e "${OUTBOUND_YELLOW}流控模式 (可选):${OUTBOUND_NC}"
    echo -e "  1. 无流控 (适用于 ws/grpc 等传输)"
    echo -e "  2. xtls-rprx-vision (推荐，配合 Reality/TLS)"
    read -p "请选择 [1-2，默认1]: " flow_choice

    local flow=""
    case $flow_choice in
        2) flow="xtls-rprx-vision" ;;
        *) flow="" ;;
    esac

    # 构建 user 配置
    local user_config=$(jq -n \
        --arg id "$uuid" \
        --argjson level 0 \
        '{id: $id, encryption: "none", level: $level}')

    if [[ -n "$flow" ]]; then
        user_config=$(echo "$user_config" | jq --arg flow "$flow" '. + {flow: $flow}')
    fi

    # 构建完整出站配置
    local outbound_config=$(jq -n \
        --arg tag "$tag" \
        --arg address "$server" \
        --argjson port "$port" \
        --argjson user "$user_config" \
        '{
            protocol: "vless",
            tag: $tag,
            settings: {
                vnext: [{
                    address: $address,
                    port: $port,
                    users: [$user]
                }]
            }
        }')

    # 添加到文件
    init_outbound_file
    jq --argjson outbound "$outbound_config" '.outbounds += [$outbound]' "$OUTBOUND_FILE" > "${OUTBOUND_FILE}.tmp"
    mv "${OUTBOUND_FILE}.tmp" "$OUTBOUND_FILE"

    print_success "VLESS 出站添加成功！"
    echo ""
    echo -e "${OUTBOUND_CYAN}出站信息：${OUTBOUND_NC}"
    echo -e "  标签: $tag"
    echo -e "  服务器: $server:$port"
    echo -e "  UUID: ${uuid:0:8}...${uuid: -8}"
    [[ -n "$flow" ]] && echo -e "  流控: $flow"
}

#================================================================
# 添加 VMess 出站
#================================================================
add_vmess_outbound() {
    clear
    echo -e "${OUTBOUND_CYAN}╔═══════════════════════════════════════╗${OUTBOUND_NC}"
    echo -e "${OUTBOUND_CYAN}║      添加 VMess 出站                 ║${OUTBOUND_NC}"
    echo -e "${OUTBOUND_CYAN}╚═══════════════════════════════════════╝${OUTBOUND_NC}"
    echo ""

    echo -e "${OUTBOUND_YELLOW}VMess 出站说明：${OUTBOUND_NC}"
    echo -e "  • 加密传输协议"
    echo -e "  • 依赖系统时间同步"
    echo -e "  • 支持多种加密方式"
    echo ""

    # 输入标签
    read -p "请输入出站标签 (例如: vmess-proxy): " tag
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

    read -p "请输入端口 (默认: 443): " port
    port=${port:-443}

    # UUID
    read -p "请输入用户UUID: " uuid
    if [[ -z "$uuid" ]]; then
        print_error "UUID不能为空"
        return 1
    fi

    # 加密方式
    echo ""
    echo -e "${OUTBOUND_YELLOW}加密方式:${OUTBOUND_NC}"
    echo -e "  1. auto (自动选择，推荐)"
    echo -e "  2. aes-128-gcm"
    echo -e "  3. chacha20-poly1305"
    echo -e "  4. none (不加密)"
    read -p "请选择 [1-4，默认1]: " security_choice

    local security="auto"
    case $security_choice in
        2) security="aes-128-gcm" ;;
        3) security="chacha20-poly1305" ;;
        4) security="none" ;;
        *) security="auto" ;;
    esac

    # 构建 user 配置
    local user_config=$(jq -n \
        --arg id "$uuid" \
        --arg security "$security" \
        --argjson level 0 \
        '{id: $id, security: $security, level: $level}')

    # 构建完整出站配置
    local outbound_config=$(jq -n \
        --arg tag "$tag" \
        --arg address "$server" \
        --argjson port "$port" \
        --argjson user "$user_config" \
        '{
            protocol: "vmess",
            tag: $tag,
            settings: {
                vnext: [{
                    address: $address,
                    port: $port,
                    users: [$user]
                }]
            }
        }')

    # 添加到文件
    init_outbound_file
    jq --argjson outbound "$outbound_config" '.outbounds += [$outbound]' "$OUTBOUND_FILE" > "${OUTBOUND_FILE}.tmp"
    mv "${OUTBOUND_FILE}.tmp" "$OUTBOUND_FILE"

    print_success "VMess 出站添加成功！"
    echo ""
    echo -e "${OUTBOUND_CYAN}出站信息：${OUTBOUND_NC}"
    echo -e "  标签: $tag"
    echo -e "  服务器: $server:$port"
    echo -e "  UUID: ${uuid:0:8}...${uuid: -8}"
    echo -e "  加密: $security"
}

#================================================================
# 添加 Trojan 出站
#================================================================
add_trojan_outbound() {
    clear
    echo -e "${OUTBOUND_CYAN}╔═══════════════════════════════════════╗${OUTBOUND_NC}"
    echo -e "${OUTBOUND_CYAN}║      添加 Trojan 出站                ║${OUTBOUND_NC}"
    echo -e "${OUTBOUND_CYAN}╚═══════════════════════════════════════╝${OUTBOUND_NC}"
    echo ""

    echo -e "${OUTBOUND_YELLOW}Trojan 出站说明：${OUTBOUND_NC}"
    echo -e "  • 设计工作在 TLS 隧道中"
    echo -e "  • 使用密码认证"
    echo -e "  • 需要配合 TLS 使用"
    echo ""

    # 输入标签
    read -p "请输入出站标签 (例如: trojan-proxy): " tag
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

    read -p "请输入端口 (默认: 443): " port
    port=${port:-443}

    # 密码
    read -p "请输入密码: " password
    if [[ -z "$password" ]]; then
        print_error "密码不能为空"
        return 1
    fi

    # 构建 server 配置
    local server_config=$(jq -n \
        --arg address "$server" \
        --argjson port "$port" \
        --arg password "$password" \
        --argjson level 0 \
        '{address: $address, port: $port, password: $password, level: $level}')

    # 构建完整出站配置
    local outbound_config=$(jq -n \
        --arg tag "$tag" \
        --argjson server "$server_config" \
        '{
            protocol: "trojan",
            tag: $tag,
            settings: {
                servers: [$server]
            }
        }')

    # 添加到文件
    init_outbound_file
    jq --argjson outbound "$outbound_config" '.outbounds += [$outbound]' "$OUTBOUND_FILE" > "${OUTBOUND_FILE}.tmp"
    mv "${OUTBOUND_FILE}.tmp" "$OUTBOUND_FILE"

    print_success "Trojan 出站添加成功！"
    echo ""
    echo -e "${OUTBOUND_CYAN}出站信息：${OUTBOUND_NC}"
    echo -e "  标签: $tag"
    echo -e "  服务器: $server:$port"
    echo -e "  密码: ${password:0:4}***${password: -4}"
}

#================================================================
# 添加 Shadowsocks 出站
#================================================================
add_shadowsocks_outbound() {
    clear
    echo -e "${OUTBOUND_CYAN}╔═══════════════════════════════════════╗${OUTBOUND_NC}"
    echo -e "${OUTBOUND_CYAN}║      添加 Shadowsocks 出站           ║${OUTBOUND_NC}"
    echo -e "${OUTBOUND_CYAN}╚═══════════════════════════════════════╝${OUTBOUND_NC}"
    echo ""

    echo -e "${OUTBOUND_YELLOW}Shadowsocks 出站说明：${OUTBOUND_NC}"
    echo -e "  • 支持 TCP 和 UDP"
    echo -e "  • 多种加密方式"
    echo -e "  • 推荐使用 2022 新协议"
    echo ""

    # 输入标签
    read -p "请输入出站标签 (例如: ss-proxy): " tag
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

    read -p "请输入端口 (默认: 8388): " port
    port=${port:-8388}

    # 加密方式
    echo ""
    echo -e "${OUTBOUND_YELLOW}加密方式:${OUTBOUND_NC}"
    echo -e "  1. 2022-blake3-aes-128-gcm (推荐)"
    echo -e "  2. 2022-blake3-aes-256-gcm"
    echo -e "  3. 2022-blake3-chacha20-poly1305"
    echo -e "  4. aes-256-gcm"
    echo -e "  5. aes-128-gcm"
    echo -e "  6. chacha20-ietf-poly1305"
    read -p "请选择 [1-6，默认1]: " method_choice

    local method="2022-blake3-aes-128-gcm"
    case $method_choice in
        2) method="2022-blake3-aes-256-gcm" ;;
        3) method="2022-blake3-chacha20-poly1305" ;;
        4) method="aes-256-gcm" ;;
        5) method="aes-128-gcm" ;;
        6) method="chacha20-ietf-poly1305" ;;
        *) method="2022-blake3-aes-128-gcm" ;;
    esac

    # 密码
    read -p "请输入密码: " password
    if [[ -z "$password" ]]; then
        print_error "密码不能为空"
        return 1
    fi

    # 构建 server 配置
    local server_config=$(jq -n \
        --arg address "$server" \
        --argjson port "$port" \
        --arg method "$method" \
        --arg password "$password" \
        --argjson level 0 \
        '{address: $address, port: $port, method: $method, password: $password, level: $level}')

    # 构建完整出站配置
    local outbound_config=$(jq -n \
        --arg tag "$tag" \
        --argjson server "$server_config" \
        '{
            protocol: "shadowsocks",
            tag: $tag,
            settings: {
                servers: [$server]
            }
        }')

    # 添加到文件
    init_outbound_file
    jq --argjson outbound "$outbound_config" '.outbounds += [$outbound]' "$OUTBOUND_FILE" > "${OUTBOUND_FILE}.tmp"
    mv "${OUTBOUND_FILE}.tmp" "$OUTBOUND_FILE"

    print_success "Shadowsocks 出站添加成功！"
    echo ""
    echo -e "${OUTBOUND_CYAN}出站信息：${OUTBOUND_NC}"
    echo -e "  标签: $tag"
    echo -e "  服务器: $server:$port"
    echo -e "  加密: $method"
    echo -e "  密码: ${password:0:4}***${password: -4}"
}

#================================================================
# 应用出站规则到节点
#================================================================
apply_outbound_to_node() {
    clear
    echo -e "${OUTBOUND_CYAN}╔═══════════════════════════════════════╗${OUTBOUND_NC}"
    echo -e "${OUTBOUND_CYAN}║      应用出站规则                    ║${OUTBOUND_NC}"
    echo -e "${OUTBOUND_CYAN}╚═══════════════════════════════════════╝${OUTBOUND_NC}"
    echo ""

    # 检查是否有出站规则
    init_outbound_file
    local outbound_count=$(jq '.outbounds | length' "$OUTBOUND_FILE" 2>/dev/null || echo "0")
    if [[ "$outbound_count" -eq 0 ]]; then
        print_error "暂无出站规则，请先添加出站规则"
        return 1
    fi

    # 显示出站规则列表
    echo -e "${OUTBOUND_CYAN}现有出站规则：${OUTBOUND_NC}"
    echo ""
    local index=1
    while read -r outbound; do
        local tag=$(echo "$outbound" | jq -r '.tag')
        local protocol=$(echo "$outbound" | jq -r '.protocol')
        echo -e "${OUTBOUND_GREEN}[$index]${OUTBOUND_NC} 标签: $tag, 协议: $protocol"
        ((index++))
    done < <(jq -c '.outbounds[]' "$OUTBOUND_FILE" 2>/dev/null)

    echo ""
    read -p "请选择出站规则序号: " outbound_index
    if [[ ! "$outbound_index" =~ ^[0-9]+$ ]] || [[ "$outbound_index" -lt 1 ]] || [[ "$outbound_index" -gt "$outbound_count" ]]; then
        print_error "无效的序号"
        return 1
    fi

    local outbound=$(jq ".outbounds[$((outbound_index-1))]" "$OUTBOUND_FILE" 2>/dev/null)
    local outbound_tag=$(echo "$outbound" | jq -r '.tag')

    # 检查节点文件
    if [[ ! -f "$NODES_FILE" ]]; then
        print_error "节点文件不存在"
        return 1
    fi

    # 显示节点列表
    echo ""
    echo -e "${OUTBOUND_CYAN}现有节点列表：${OUTBOUND_NC}"
    echo ""
    printf "${OUTBOUND_CYAN}%-4s %-20s %-12s %-8s %-20s${OUTBOUND_NC}\n" "序号" "节点名称" "协议" "端口" "当前出站"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    index=1
    while read -r node; do
        local name=$(echo "$node" | jq -r '.name // "未命名"')
        local protocol=$(echo "$node" | jq -r '.protocol')
        local port=$(echo "$node" | jq -r '.port')
        local current_outbound=$(echo "$node" | jq -r '.outbound_tag // "未设置"')

        # 截断过长的名称
        if [[ ${#name} -gt 18 ]]; then
            name="${name:0:15}..."
        fi

        printf "%-4s %-20s %-12s %-8s %-20s\n" "$index" "$name" "$protocol" "$port" "$current_outbound"
        ((index++))
    done < <(jq -c '.nodes[]' "$NODES_FILE" 2>/dev/null)

    echo ""
    read -p "请输入节点序号（多个用空格分隔）: " node_indices

    if [[ -z "$node_indices" ]]; then
        print_error "请至少选择一个节点"
        return 1
    fi

    local success_count=0
    for node_idx in $node_indices; do
        if [[ ! "$node_idx" =~ ^[0-9]+$ ]]; then
            print_warning "跳过无效序号: $node_idx"
            continue
        fi

        # 更新节点的出站标签
        jq "(.nodes[$((node_idx-1))].outbound_tag) = \"$outbound_tag\"" "$NODES_FILE" > "${NODES_FILE}.tmp"
        if [[ $? -eq 0 ]]; then
            mv "${NODES_FILE}.tmp" "$NODES_FILE"
            ((success_count++))
        else
            rm -f "${NODES_FILE}.tmp"
        fi
    done

    if [[ $success_count -gt 0 ]]; then
        generate_xray_config
        restart_xray
        print_success "成功将出站规则 '$outbound_tag' 应用到 $success_count 个节点"
    else
        print_error "未能应用出站规则到任何节点"
    fi
}

#================================================================
# 禁用节点的出站规则
#================================================================
disable_outbound_from_node() {
    clear
    echo -e "${OUTBOUND_CYAN}╔═══════════════════════════════════════╗${OUTBOUND_NC}"
    echo -e "${OUTBOUND_CYAN}║      禁用出站规则                    ║${OUTBOUND_NC}"
    echo -e "${OUTBOUND_CYAN}╚═══════════════════════════════════════╝${OUTBOUND_NC}"
    echo ""

    # 检查节点文件
    if [[ ! -f "$NODES_FILE" ]]; then
        print_error "节点文件不存在"
        return 1
    fi

    # 显示有出站规则的节点
    echo -e "${OUTBOUND_CYAN}已应用出站规则的节点：${OUTBOUND_NC}"
    echo ""
    printf "${OUTBOUND_CYAN}%-4s %-20s %-12s %-8s %-20s${OUTBOUND_NC}\n" "序号" "节点名称" "协议" "端口" "出站规则"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    local index=1
    local has_outbound=false
    while read -r node; do
        local outbound_tag=$(echo "$node" | jq -r '.outbound_tag // ""')
        if [[ -n "$outbound_tag" ]]; then
            local name=$(echo "$node" | jq -r '.name // "未命名"')
            local protocol=$(echo "$node" | jq -r '.protocol')
            local port=$(echo "$node" | jq -r '.port')

            # 截断过长的名称
            if [[ ${#name} -gt 18 ]]; then
                name="${name:0:15}..."
            fi

            printf "%-4s %-20s %-12s %-8s %-20s\n" "$index" "$name" "$protocol" "$port" "$outbound_tag"
            has_outbound=true
        fi
        ((index++))
    done < <(jq -c '.nodes[]' "$NODES_FILE" 2>/dev/null)

    if [[ "$has_outbound" == "false" ]]; then
        print_warning "暂无节点应用了出站规则"
        return 0
    fi

    echo ""
    read -p "请输入节点序号（多个用空格分隔，0=全部）: " node_indices

    if [[ -z "$node_indices" ]]; then
        print_error "请至少选择一个节点"
        return 1
    fi

    # 如果选择0，禁用所有节点的出站规则
    if [[ "$node_indices" == "0" ]]; then
        jq '(.nodes[].outbound_tag) = null' "$NODES_FILE" > "${NODES_FILE}.tmp"
        mv "${NODES_FILE}.tmp" "$NODES_FILE"
        generate_xray_config
        restart_xray
        print_success "已禁用所有节点的出站规则"
        return 0
    fi

    local success_count=0
    for node_idx in $node_indices; do
        if [[ ! "$node_idx" =~ ^[0-9]+$ ]]; then
            print_warning "跳过无效序号: $node_idx"
            continue
        fi

        # 移除节点的出站标签
        jq "(.nodes[$((node_idx-1))].outbound_tag) = null" "$NODES_FILE" > "${NODES_FILE}.tmp"
        if [[ $? -eq 0 ]]; then
            mv "${NODES_FILE}.tmp" "$NODES_FILE"
            ((success_count++))
        else
            rm -f "${NODES_FILE}.tmp"
        fi
    done

    if [[ $success_count -gt 0 ]]; then
        generate_xray_config
        restart_xray
        print_success "成功禁用 $success_count 个节点的出站规则"
    else
        print_error "未能禁用任何节点的出站规则"
    fi
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

    # 检查是否有节点使用该出站规则
    local affected_nodes=""
    if [[ -f "$NODES_FILE" ]]; then
        affected_nodes=$(jq -r ".nodes[] | select(.outbound_tag == \"$tag\") | .port" "$NODES_FILE" 2>/dev/null)
    fi

    echo ""
    if [[ -n "$affected_nodes" ]]; then
        print_warning "以下节点正在使用该出站规则："
        echo "$affected_nodes" | while read -r port; do
            local node_name=$(jq -r ".nodes[] | select(.port == \"$port\") | .name" "$NODES_FILE" 2>/dev/null)
            echo "  - 端口 $port ($node_name)"
        done
        print_warning "删除后这些节点的出站规则将被清空"
    fi

    read -p "确认删除出站规则 '$tag'? [y/N]: " confirm
    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
        print_info "已取消删除"
        return 0
    fi

    # 1. 从使用该出站的节点中移除 outbound_tag
    if [[ -n "$affected_nodes" ]] && [[ -f "$NODES_FILE" ]]; then
        jq --arg tag "$tag" '
            .nodes = [.nodes[] |
                if .outbound_tag == $tag then
                    del(.outbound_tag)
                else
                    .
                end
            ]
        ' "$NODES_FILE" > "${NODES_FILE}.tmp"
        mv "${NODES_FILE}.tmp" "$NODES_FILE"
        print_info "已更新节点配置"
    fi

    # 2. 删除出站规则
    jq --arg tag "$tag" '.outbounds = [.outbounds[] | select(.tag != $tag)]' "$OUTBOUND_FILE" > "${OUTBOUND_FILE}.tmp"
    mv "${OUTBOUND_FILE}.tmp" "$OUTBOUND_FILE"

    print_success "出站规则已删除: $tag"

    # 3. 重新生成 Xray 配置
    if [[ -n "$affected_nodes" ]]; then
        print_info "正在重新生成配置..."
        generate_xray_config
        restart_xray
        print_success "配置已更新并重启服务"
    fi
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
        echo -e "${OUTBOUND_GREEN}2.${OUTBOUND_NC} 添加出站规则"
        echo -e "${OUTBOUND_GREEN}3.${OUTBOUND_NC} 应用出站规则到节点"
        echo -e "${OUTBOUND_GREEN}4.${OUTBOUND_NC} 禁用节点的出站规则"
        echo -e "${OUTBOUND_GREEN}5.${OUTBOUND_NC} 修改出站规则"
        echo -e "${OUTBOUND_GREEN}6.${OUTBOUND_NC} 删除出站规则"
        echo -e "${OUTBOUND_GREEN}0.${OUTBOUND_NC} 返回主菜单"
        echo ""
        read -p "请选择操作 [0-6]: " choice

        case $choice in
            1) list_outbounds ;;
            2)
                # 添加出站规则子菜单
                clear
                echo -e "${OUTBOUND_CYAN}╔═══════════════════════════════════════╗${OUTBOUND_NC}"
                echo -e "${OUTBOUND_CYAN}║      添加出站规则                    ║${OUTBOUND_NC}"
                echo -e "${OUTBOUND_CYAN}╚═══════════════════════════════════════╝${OUTBOUND_NC}"
                echo ""
                echo -e "${OUTBOUND_GREEN}1.${OUTBOUND_NC} HTTP 代理"
                echo -e "${OUTBOUND_GREEN}2.${OUTBOUND_NC} SOCKS 代理"
                echo -e "${OUTBOUND_GREEN}3.${OUTBOUND_NC} VLESS 协议"
                echo -e "${OUTBOUND_GREEN}4.${OUTBOUND_NC} VMess 协议"
                echo -e "${OUTBOUND_GREEN}5.${OUTBOUND_NC} Trojan 协议"
                echo -e "${OUTBOUND_GREEN}6.${OUTBOUND_NC} Shadowsocks 协议"
                echo -e "${OUTBOUND_GREEN}0.${OUTBOUND_NC} 返回"
                echo ""
                read -p "请选择协议 [0-6]: " protocol_choice

                case $protocol_choice in
                    1) add_http_outbound ;;
                    2) add_socks_outbound ;;
                    3) add_vless_outbound ;;
                    4) add_vmess_outbound ;;
                    5) add_trojan_outbound ;;
                    6) add_shadowsocks_outbound ;;
                    0) ;;
                    *) print_error "无效选择" ;;
                esac
                ;;
            3) apply_outbound_to_node ;;
            4) disable_outbound_from_node ;;
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
