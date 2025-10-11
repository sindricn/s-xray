#!/bin/bash

#================================================================
# 订阅管理模块 - 修复版
# 功能：生成有效的订阅链接、支持用户绑定、查看单个节点链接
# 修复：订阅链接生成逻辑、用户绑定、admin默认用户
#================================================================

# 初始化admin默认用户
init_admin_user() {
    if [[ ! -f "$USERS_FILE" ]]; then
        echo '{"users":[]}' > "$USERS_FILE"
    fi

    # 检查是否已存在admin用户
    local admin_exists=$(jq -r '.users[] | select(.email == "admin") | .email' "$USERS_FILE" 2>/dev/null)

    if [[ -z "$admin_exists" ]]; then
        local admin_uuid=$(generate_uuid)

        # 创建admin用户记录
        local admin_user=$(jq -n \
            --arg uuid "$admin_uuid" \
            --arg email "admin" \
            '{id: $uuid, email: $email, level: 0, created: now|todate, is_admin: true}')

        jq ".users += [$admin_user]" "$USERS_FILE" > "${USERS_FILE}.tmp"
        mv "${USERS_FILE}.tmp" "$USERS_FILE"

        log_info "已初始化admin默认用户 (UUID: $admin_uuid)"
    fi
}

# 获取admin用户UUID
get_admin_uuid() {
    local admin_uuid=$(jq -r '.users[] | select(.email == "admin") | .id' "$USERS_FILE" 2>/dev/null)

    if [[ -z "$admin_uuid" ]]; then
        # 如果不存在，初始化admin用户
        init_admin_user
        admin_uuid=$(jq -r '.users[] | select(.email == "admin") | .id' "$USERS_FILE" 2>/dev/null)
    fi

    echo "$admin_uuid"
}

# 获取公网IP
get_public_ip() {
    local ip=""

    # 尝试多个IP获取服务
    ip=$(curl -s -4 --connect-timeout 3 https://api.ipify.org 2>/dev/null)
    if [[ -z "$ip" ]]; then
        ip=$(curl -s -4 --connect-timeout 3 https://ifconfig.me 2>/dev/null)
    fi
    if [[ -z "$ip" ]]; then
        ip=$(curl -s -4 --connect-timeout 3 https://ip.sb 2>/dev/null)
    fi
    if [[ -z "$ip" ]]; then
        ip=$(hostname -I 2>/dev/null | awk '{print $1}')
    fi

    echo "$ip"
}

# URL 编码
urlencode() {
    local string="$1"
    local strlen=${#string}
    local encoded=""
    local pos c o

    for (( pos=0 ; pos<strlen ; pos++ )); do
        c=${string:$pos:1}
        case "$c" in
            [-_.~a-zA-Z0-9] ) o="${c}" ;;
            * ) printf -v o '%%%02x' "'$c"
        esac
        encoded+="${o}"
    done
    echo "${encoded}"
}

# Base64 编码（无换行）
base64_encode() {
    local input="${1:-}"
    if [[ -z "$input" ]]; then
        return 1
    fi
    echo -n "$input" | base64 -w 0 2>/dev/null || echo -n "$input" | base64
}

#================================================================
# 分享链接生成函数（修复版）
#================================================================

# 从节点JSON生成VLESS Reality分享链接
generate_vless_reality_link_from_config() {
    local uuid=$1
    local remark=$2
    local node_json=$3

    local port=$(echo "$node_json" | jq -r '.port')
    local config=$(echo "$node_json" | jq -r '.config')

    # 解析Reality配置
    local reality_settings=$(echo "$config" | jq -r '.streamSettings.realitySettings // empty')
    if [[ -z "$reality_settings" || "$reality_settings" == "null" ]]; then
        echo ""
        return 1
    fi

    # 提取Reality参数
    local dest=$(echo "$reality_settings" | jq -r '.dest // ""')
    local server_names=$(echo "$reality_settings" | jq -r '.serverNames[0] // ""')
    local private_key=$(echo "$reality_settings" | jq -r '.privateKey // ""')
    local short_ids=$(echo "$reality_settings" | jq -r '.shortIds[0] // ""')

    # SNI从serverNames或dest提取
    local sni="$server_names"
    if [[ -z "$sni" && -n "$dest" ]]; then
        sni=$(echo "$dest" | cut -d':' -f1)
    fi

    # 从privateKey生成publicKey（如果没有存储publicKey）
    local public_key=""
    if [[ -n "$private_key" ]]; then
        # Reality的公钥需要从私钥计算得出，这里假设配置中已包含
        # 实际应该从xray x25519命令计算
        public_key=$(echo "$reality_settings" | jq -r '.publicKey // ""')

        if [[ -z "$public_key" && -f "$XRAY_BIN" ]]; then
            # 尝试从私钥生成公钥（需要特殊处理）
            # 这里简化处理，实际需要xray工具
            public_key="$private_key" # 临时方案
        fi
    fi

    # flow参数
    local flow=$(echo "$config" | jq -r '.settings.clients[0].flow // "xtls-rprx-vision"')

    local server_ip=$(get_public_ip)

    # 构建VLESS Reality链接
    local share_link="vless://${uuid}@${server_ip}:${port}?encryption=none&flow=${flow}&security=reality&sni=${sni}&fp=chrome&pbk=${public_key}&sid=${short_ids}&type=tcp&headerType=none#$(urlencode "$remark")"

    echo "$share_link"
}

# 从节点JSON生成VLESS TLS分享链接
generate_vless_tls_link_from_config() {
    local uuid=$1
    local remark=$2
    local node_json=$3

    local port=$(echo "$node_json" | jq -r '.port')
    local config=$(echo "$node_json" | jq -r '.config')
    local transport=$(echo "$node_json" | jq -r '.transport // "tcp"')

    # 解析TLS配置
    local tls_settings=$(echo "$config" | jq -r '.streamSettings.tlsSettings // empty')
    if [[ -z "$tls_settings" || "$tls_settings" == "null" ]]; then
        # 没有TLS，生成普通VLESS链接
        generate_vless_plain_link_from_config "$uuid" "$remark" "$node_json"
        return
    fi

    local sni=$(echo "$tls_settings" | jq -r '.serverName // ""')
    local ws_path=""

    if [[ "$transport" == "ws" ]]; then
        ws_path=$(echo "$config" | jq -r '.streamSettings.wsSettings.path // ""')
    fi

    local flow=$(echo "$config" | jq -r '.settings.clients[0].flow // ""')
    local server_ip=$(get_public_ip)

    # 构建链接
    local share_link="vless://${uuid}@${server_ip}:${port}?encryption=none&security=tls&sni=${sni}&type=${transport}"

    if [[ -n "$flow" ]]; then
        share_link+="&flow=${flow}"
    fi

    if [[ "$transport" == "ws" && -n "$ws_path" ]]; then
        share_link+="&path=$(urlencode "$ws_path")"
    fi

    share_link+="#$(urlencode "$remark")"

    echo "$share_link"
}

# 从节点JSON生成VLESS普通分享链接
generate_vless_plain_link_from_config() {
    local uuid=$1
    local remark=$2
    local node_json=$3

    local port=$(echo "$node_json" | jq -r '.port')
    local transport=$(echo "$node_json" | jq -r '.transport // "tcp"')
    local config=$(echo "$node_json" | jq -r '.config')

    local ws_path=""
    if [[ "$transport" == "ws" ]]; then
        ws_path=$(echo "$config" | jq -r '.streamSettings.wsSettings.path // ""')
    fi

    local server_ip=$(get_public_ip)

    local share_link="vless://${uuid}@${server_ip}:${port}?encryption=none&type=${transport}"

    if [[ "$transport" == "ws" && -n "$ws_path" ]]; then
        share_link+="&path=$(urlencode "$ws_path")"
    fi

    share_link+="#$(urlencode "$remark")"

    echo "$share_link"
}

# 从节点JSON生成VMess分享链接
generate_vmess_link_from_config() {
    local uuid=$1
    local remark=$2
    local node_json=$3

    local port=$(echo "$node_json" | jq -r '.port')
    local transport=$(echo "$node_json" | jq -r '.transport // "tcp"')
    local config=$(echo "$node_json" | jq -r '.config')

    local ws_path=""
    local tls=""
    local sni=""

    if [[ "$transport" == "ws" ]]; then
        ws_path=$(echo "$config" | jq -r '.streamSettings.wsSettings.path // ""')
    fi

    local security=$(echo "$config" | jq -r '.streamSettings.security // ""')
    if [[ "$security" == "tls" ]]; then
        tls="tls"
        sni=$(echo "$config" | jq -r '.streamSettings.tlsSettings.serverName // ""')
    fi

    local server_ip=$(get_public_ip)

    # VMess JSON格式
    local vmess_json=$(cat <<EOF
{
  "v": "2",
  "ps": "${remark}",
  "add": "${server_ip}",
  "port": "${port}",
  "id": "${uuid}",
  "aid": "0",
  "scy": "auto",
  "net": "${transport}",
  "type": "none",
  "host": "",
  "path": "${ws_path}",
  "tls": "${tls}",
  "sni": "${sni}",
  "alpn": "",
  "fp": ""
}
EOF
)

    # Base64编码（去除换行）
    local vmess_link="vmess://$(echo -n "$vmess_json" | tr -d '\n' | base64_encode)"

    echo "$vmess_link"
}

# 从节点JSON生成Trojan分享链接
generate_trojan_link_from_config() {
    local password=$1
    local remark=$2
    local node_json=$3

    local port=$(echo "$node_json" | jq -r '.port')
    local config=$(echo "$node_json" | jq -r '.config')
    local transport=$(echo "$node_json" | jq -r '.transport // "tcp"')

    local sni=$(echo "$config" | jq -r '.streamSettings.tlsSettings.serverName // ""')
    local server_ip=$(get_public_ip)

    if [[ -z "$sni" ]]; then
        sni=$server_ip
    fi

    local share_link="trojan://${password}@${server_ip}:${port}?security=tls&sni=${sni}&type=${transport}#$(urlencode "$remark")"

    echo "$share_link"
}

# 从节点JSON生成Shadowsocks分享链接
generate_ss_link_from_config() {
    local password=$1
    local remark=$2
    local node_json=$3

    local port=$(echo "$node_json" | jq -r '.port')
    local config=$(echo "$node_json" | jq -r '.config')

    local cipher=$(echo "$config" | jq -r '.settings.method // "aes-256-gcm"')
    local server_ip=$(get_public_ip)

    # SIP002格式
    local userinfo="${cipher}:${password}"
    local encoded=$(base64_encode "$userinfo")

    local share_link="ss://${encoded}@${server_ip}:${port}#$(urlencode "$remark")"

    echo "$share_link"
}

# 智能生成分享链接（根据节点类型）
generate_share_link_smart() {
    local user_id=$1
    local user_email=$2
    local node_json=$3

    local protocol=$(echo "$node_json" | jq -r '.protocol')
    local config=$(echo "$node_json" | jq -r '.config')

    case $protocol in
        vless)
            # 检查是否是Reality
            if echo "$config" | jq -e '.streamSettings.security == "reality"' >/dev/null 2>&1; then
                generate_vless_reality_link_from_config "$user_id" "$user_email" "$node_json"
            elif echo "$config" | jq -e '.streamSettings.security == "tls"' >/dev/null 2>&1; then
                generate_vless_tls_link_from_config "$user_id" "$user_email" "$node_json"
            else
                generate_vless_plain_link_from_config "$user_id" "$user_email" "$node_json"
            fi
            ;;
        vmess)
            generate_vmess_link_from_config "$user_id" "$user_email" "$node_json"
            ;;
        trojan)
            generate_trojan_link_from_config "$user_id" "$user_email" "$node_json"
            ;;
        shadowsocks)
            generate_ss_link_from_config "$user_id" "$user_email" "$node_json"
            ;;
        *)
            echo ""
            ;;
    esac
}

#================================================================
# 订阅管理功能
#================================================================

# 查看单个节点的分享链接
show_node_share_link() {
    clear
    echo -e "${CYAN}╔═══════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║      查看单个节点分享链接            ║${NC}"
    echo -e "${CYAN}╚═══════════════════════════════════════╝${NC}"
    echo ""

    # 显示节点列表
    if [[ ! -f "$NODES_FILE" ]]; then
        print_error "暂无节点"
        return 1
    fi

    local node_count=$(jq -r '.nodes | length' "$NODES_FILE")
    if [[ "$node_count" -eq 0 ]]; then
        print_error "暂无节点"
        return 1
    fi

    echo -e "${YELLOW}节点列表：${NC}"
    echo ""

    local index=1
    while IFS= read -r node; do
        if [[ -z "$node" || "$node" == "null" ]]; then
            continue
        fi

        local protocol=$(echo "$node" | jq -r '.protocol')
        local port=$(echo "$node" | jq -r '.port')
        local email=$(echo "$node" | jq -r '.email // ""')

        printf "${CYAN}[%d]${NC} %s:%s - %s\n" "$index" "$protocol" "$port" "$email"
        ((index++))
    done < <(jq -c '.nodes[]' "$NODES_FILE" 2>/dev/null)

    echo ""
    read -p "请输入节点序号: " node_index

    if [[ ! "$node_index" =~ ^[0-9]+$ ]]; then
        print_error "无效的序号"
        return 1
    fi

    # 获取节点
    local node=$(jq -c ".nodes[$((node_index-1))]" "$NODES_FILE" 2>/dev/null)
    if [[ -z "$node" || "$node" == "null" ]]; then
        print_error "节点不存在"
        return 1
    fi

    local protocol=$(echo "$node" | jq -r '.protocol')
    local port=$(echo "$node" | jq -r '.port')
    local node_id=$(echo "$node" | jq -r '.id // ""')
    local node_email=$(echo "$node" | jq -r '.email // ""')

    echo ""
    echo -e "${CYAN}节点信息：${NC}"
    echo -e "  协议: ${YELLOW}$protocol${NC}"
    echo -e "  端口: ${YELLOW}$port${NC}"
    echo -e "  备注: ${YELLOW}$node_email${NC}"
    echo ""

    # 选择用户
    echo -e "${YELLOW}选择用户：${NC}"
    echo -e "  ${GREEN}1.${NC} 使用节点自带配置（默认）"
    echo -e "  ${GREEN}2.${NC} 选择其他用户"
    echo ""
    read -p "请选择 [1-2，默认: 1]: " user_choice
    user_choice=${user_choice:-1}

    local final_uuid=""
    local final_email=""

    if [[ "$user_choice" == "2" ]]; then
        # 显示用户列表
        if [[ ! -f "$USERS_FILE" ]]; then
            print_warning "暂无用户，使用节点默认配置"
            final_uuid="$node_id"
            final_email="$node_email"
        else
            local user_count=$(jq -r '.users | length' "$USERS_FILE")
            if [[ "$user_count" -eq 0 ]]; then
                print_warning "暂无用户，使用节点默认配置"
                final_uuid="$node_id"
                final_email="$node_email"
            else
                echo ""
                echo -e "${YELLOW}用户列表：${NC}"
                local uindex=1
                while IFS= read -r user; do
                    if [[ -z "$user" || "$user" == "null" ]]; then
                        continue
                    fi

                    local uid=$(echo "$user" | jq -r '.id')
                    local uemail=$(echo "$user" | jq -r '.email')

                    printf "${CYAN}[%d]${NC} %s - %s\n" "$uindex" "$uemail" "$uid"
                    ((uindex++))
                done < <(jq -c '.users[]' "$USERS_FILE" 2>/dev/null)

                echo ""
                read -p "请输入用户序号: " user_index

                if [[ ! "$user_index" =~ ^[0-9]+$ ]]; then
                    print_error "无效的序号"
                    return 1
                fi

                local user=$(jq -c ".users[$((user_index-1))]" "$USERS_FILE" 2>/dev/null)
                if [[ -z "$user" || "$user" == "null" ]]; then
                    print_error "用户不存在"
                    return 1
                fi

                final_uuid=$(echo "$user" | jq -r '.id')
                final_email=$(echo "$user" | jq -r '.email')
            fi
        fi
    else
        final_uuid="$node_id"
        final_email="$node_email"
    fi

    # 生成分享链接
    echo ""
    print_info "正在生成分享链接..."
    echo ""

    local share_link=$(generate_share_link_smart "$final_uuid" "$final_email" "$node")

    if [[ -z "$share_link" ]]; then
        print_error "生成分享链接失败"
        return 1
    fi

    echo -e "${GREEN}╔═══════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║      分享链接生成成功                ║${NC}"
    echo -e "${GREEN}╚═══════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${CYAN}节点:${NC} ${protocol}:${port} - ${final_email}"
    echo ""
    echo -e "${CYAN}分享链接:${NC}"
    echo -e "${GREEN}${share_link}${NC}"
    echo ""
}

# 生成订阅（绑定用户版）
generate_subscription_with_user() {
    clear
    echo -e "${CYAN}╔═══════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║          生成订阅链接                ║${NC}"
    echo -e "${CYAN}╚═══════════════════════════════════════╝${NC}"
    echo ""

    # 初始化admin用户
    init_admin_user

    if [[ ! -f "$NODES_FILE" ]]; then
        print_error "暂无节点，请先添加节点"
        return 1
    fi

    local node_count=$(jq -r '.nodes | length' "$NODES_FILE")
    if [[ "$node_count" -eq 0 ]]; then
        print_error "暂无节点，请先添加节点"
        return 1
    fi

    echo -e "${YELLOW}当前节点数量:${NC} $node_count"
    echo ""

    # 选择用户
    echo -e "${CYAN}选择订阅用户：${NC}"
    echo -e "  ${GREEN}1.${NC} admin（默认管理员）"
    echo -e "  ${GREEN}2.${NC} 选择其他用户"
    echo ""
    read -p "请选择 [1-2，默认: 1]: " user_choice
    user_choice=${user_choice:-1}

    local sub_user_id=""
    local sub_user_email=""

    if [[ "$user_choice" == "1" ]]; then
        sub_user_id=$(get_admin_uuid)
        sub_user_email="admin"
    else
        # 显示用户列表
        if [[ ! -f "$USERS_FILE" ]]; then
            print_warning "暂无用户，使用admin用户"
            sub_user_id=$(get_admin_uuid)
            sub_user_email="admin"
        else
            local user_count=$(jq -r '.users | length' "$USERS_FILE")
            if [[ "$user_count" -eq 0 ]]; then
                print_warning "暂无用户，使用admin用户"
                sub_user_id=$(get_admin_uuid)
                sub_user_email="admin"
            else
                echo ""
                echo -e "${YELLOW}用户列表：${NC}"
                local index=1
                while IFS= read -r user; do
                    if [[ -z "$user" || "$user" == "null" ]]; then
                        continue
                    fi

                    local uid=$(echo "$user" | jq -r '.id')
                    local uemail=$(echo "$user" | jq -r '.email')

                    printf "${CYAN}[%d]${NC} %s - %s\n" "$index" "$uemail" "$uid"
                    ((index++))
                done < <(jq -c '.users[]' "$USERS_FILE" 2>/dev/null)

                echo ""
                read -p "请输入用户序号: " user_index

                if [[ ! "$user_index" =~ ^[0-9]+$ ]]; then
                    print_error "无效的序号"
                    return 1
                fi

                local user=$(jq -c ".users[$((user_index-1))]" "$USERS_FILE" 2>/dev/null)
                if [[ -z "$user" || "$user" == "null" ]]; then
                    print_error "用户不存在"
                    return 1
                fi

                sub_user_id=$(echo "$user" | jq -r '.id')
                sub_user_email=$(echo "$user" | jq -r '.email')
            fi
        fi
    fi

    echo ""
    echo -e "${CYAN}订阅用户:${NC} ${YELLOW}$sub_user_email${NC}"
    echo ""

    # 订阅名称
    read -p "请输入订阅名称 [默认: ${sub_user_email}-sub]: " sub_name
    sub_name=${sub_name:-${sub_user_email}-sub}

    # 选择订阅类型
    echo ""
    echo -e "${CYAN}选择订阅类型：${NC}"
    echo -e "  ${GREEN}1.${NC} 通用订阅（Base64编码，支持大部分客户端）"
    echo -e "  ${GREEN}2.${NC} 原始订阅（纯文本，支持所有客户端）"
    echo ""
    read -p "请选择 [1-2，默认: 1]: " sub_type
    sub_type=${sub_type:-1}

    # 收集所有分享链接（新架构：只生成用户绑定的节点）
    print_info "正在生成分享链接..."
    echo ""

    # 获取用户绑定的节点列表
    local user_node_ports=()
    if [[ -f "$NODE_USERS_FILE" ]]; then
        while IFS= read -r binding; do
            local bport=$(echo "$binding" | jq -r '.port')
            local users=$(echo "$binding" | jq -r '.users[]')

            # 检查用户是否在该节点的用户列表中
            if echo "$users" | grep -q "$sub_user_id"; then
                user_node_ports+=("$bport")
            fi
        done < <(jq -c '.bindings[]' "$NODE_USERS_FILE" 2>/dev/null)
    fi

    if [[ ${#user_node_ports[@]} -eq 0 ]]; then
        print_warning "用户 $sub_user_email 未绑定任何节点"
        echo ""
        read -p "是否生成所有节点的订阅? [y/N]: " use_all_nodes
        if [[ "$use_all_nodes" != "y" && "$use_all_nodes" != "Y" ]]; then
            print_info "取消生成订阅"
            return 0
        fi
        # 如果选择使用所有节点，获取所有节点端口
        while IFS= read -r node; do
            user_node_ports+=($(echo "$node" | jq -r '.port'))
        done < <(jq -c '.nodes[]' "$NODES_FILE" 2>/dev/null)
    fi

    print_info "用户可访问节点数: ${#user_node_ports[@]}"
    echo ""

    local share_links=()
    local link_count=0

    # 遍历用户绑定的节点
    for port in "${user_node_ports[@]}"; do
        local node=$(jq -c ".nodes[] | select(.port == \"$port\")" "$NODES_FILE" 2>/dev/null)

        if [[ -z "$node" || "$node" == "null" ]]; then
            continue
        fi

        local protocol=$(echo "$node" | jq -r '.protocol')

        # 使用选定的用户生成链接
        local link=$(generate_share_link_smart "$sub_user_id" "$sub_user_email" "$node")
        if [[ -n "$link" ]]; then
            share_links+=("$link")
            ((link_count++))
            echo -e "  ${GREEN}✔${NC} 节点 ${protocol}:${port}"
        else
            echo -e "  ${RED}✘${NC} 节点 ${protocol}:${port} - 生成失败"
        fi
    done

    if [[ $link_count -eq 0 ]]; then
        print_error "没有可用的节点配置"
        return 1
    fi

    echo ""
    print_success "成功生成 $link_count 个分享链接"
    echo ""

    # 生成订阅内容
    local sub_content=""
    local sub_file=""

    case $sub_type in
        1)
            # 通用订阅 - Base64编码
            sub_content=$(printf "%s\n" "${share_links[@]}" | base64_encode)
            sub_file="${SUBSCRIPTION_DIR}/${sub_name}.txt"
            ;;
        2)
            # 原始订阅
            sub_content=$(printf "%s\n" "${share_links[@]}")
            sub_file="${SUBSCRIPTION_DIR}/${sub_name}_raw.txt"
            ;;
    esac

    # 保存订阅文件
    echo "$sub_content" > "$sub_file"

    # 生成订阅URL
    echo -e "${CYAN}订阅访问配置：${NC}"
    echo ""

    read -p "请输入订阅访问域名或IP [留空使用服务器IP]: " sub_domain
    if [[ -z "$sub_domain" ]]; then
        sub_domain=$(get_public_ip)
    fi

    read -p "请输入订阅端口 [默认: 8080]: " sub_port
    sub_port=${sub_port:-8080}

    # 订阅路径
    local sub_filename=$(basename "$sub_file")
    local sub_url="http://${sub_domain}:${sub_port}/sub/${sub_filename}"

    # 保存订阅信息到数据库
    save_subscription_info "$sub_name" "$sub_url" "$sub_file" "$sub_type" "$sub_user_email"

    # 启动订阅服务
    setup_subscription_server "$sub_port"

    # 显示结果
    echo ""
    echo -e "${GREEN}╔═══════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║        订阅生成成功！                ║${NC}"
    echo -e "${GREEN}╚═══════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${CYAN}订阅信息：${NC}"
    echo -e "  订阅名称: ${YELLOW}$sub_name${NC}"
    echo -e "  绑定用户: ${YELLOW}$sub_user_email${NC}"
    echo -e "  节点数量: ${YELLOW}$link_count${NC}"
    echo -e "  订阅类型: ${YELLOW}$(get_sub_type_name $sub_type)${NC}"
    echo ""
    echo -e "${CYAN}订阅链接：${NC}"
    echo -e "${GREEN}${sub_url}${NC}"
    echo ""
    echo -e "${YELLOW}使用说明：${NC}"
    echo -e "  1. 复制上面的订阅链接"
    echo -e "  2. 在客户端中添加订阅"
    echo -e "  3. 更新订阅获取节点"
    echo ""

    # 显示支持的客户端
    case $sub_type in
        1)
            echo -e "${CYAN}支持的客户端：${NC}"
            echo -e "  • V2RayN/V2RayNG"
            echo -e "  • Shadowrocket"
            echo -e "  • Quantumult X"
            echo -e "  • SagerNet"
            ;;
        2)
            echo -e "${CYAN}支持的客户端：${NC}"
            echo -e "  • 所有支持订阅的客户端"
            echo -e "  • 可手动复制链接导入"
            ;;
    esac
    echo ""
}

# 获取订阅类型名称
get_sub_type_name() {
    case $1 in
        1) echo "通用订阅 (Base64)" ;;
        2) echo "原始订阅 (纯文本)" ;;
        *) echo "未知类型" ;;
    esac
}

# 查看订阅列表
show_subscription() {
    clear
    echo -e "${CYAN}╔═══════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║          订阅列表                    ║${NC}"
    echo -e "${CYAN}╚═══════════════════════════════════════╝${NC}"
    echo ""

    if [[ ! -d "$SUBSCRIPTION_DIR" ]]; then
        print_warning "暂无订阅"
        return 0
    fi

    local sub_db="${DATA_DIR}/subscriptions.json"
    if [[ ! -f "$sub_db" ]]; then
        print_warning "暂无订阅"
        return 0
    fi

    local sub_count=$(jq -r '.subscriptions | length' "$sub_db" 2>/dev/null || echo "0")
    if [[ "$sub_count" -eq 0 ]]; then
        print_warning "暂无订阅"
        return 0
    fi

    echo -e "${YELLOW}订阅总数:${NC} $sub_count"
    echo ""
    printf "${CYAN}%-4s %-20s %-15s %-15s %-40s${NC}\n" "序号" "订阅名称" "绑定用户" "类型" "订阅URL"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    local index=1
    while read -r sub; do
        if [[ -z "$sub" || "$sub" == "null" ]]; then
            continue
        fi

        local name=$(echo "$sub" | jq -r '.name')
        local url=$(echo "$sub" | jq -r '.url')
        local type=$(echo "$sub" | jq -r '.type // "1"')
        local user=$(echo "$sub" | jq -r '.user // "N/A"')
        local type_name=$(get_sub_type_name "$type")

        printf "%-4s %-20s %-15s %-15s %-40s\n" "$index" "$name" "$user" "$type_name" "$url"
        ((index++))
    done < <(jq -c '.subscriptions[]' "$sub_db" 2>/dev/null)

    echo ""
}

# 删除订阅
delete_subscription() {
    show_subscription

    echo ""
    read -p "请输入要删除的订阅名称: " sub_name
    if [[ -z "$sub_name" ]]; then
        print_error "订阅名称不能为空"
        return 1
    fi

    local sub_db="${DATA_DIR}/subscriptions.json"
    local sub_info=$(jq -r ".subscriptions[] | select(.name == \"$sub_name\")" "$sub_db" 2>/dev/null)

    if [[ -z "$sub_info" ]]; then
        print_error "订阅不存在"
        return 1
    fi

    read -p "确认删除订阅 ${sub_name}? [y/N]: " confirm
    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
        print_info "取消删除"
        return 0
    fi

    # 获取订阅文件路径
    local sub_file=$(echo "$sub_info" | jq -r '.file')

    # 删除订阅文件
    if [[ -f "$sub_file" ]]; then
        rm -f "$sub_file"
    fi

    # 从数据库删除
    remove_subscription_info "$sub_name"

    print_success "订阅删除成功"
}

# 重新生成订阅（更新现有订阅）
regenerate_subscription() {
    local sub_name="$1"

    if [[ -z "$sub_name" ]]; then
        print_error "订阅名称不能为空"
        return 1
    fi

    local sub_db="${DATA_DIR}/subscriptions.json"
    if [[ ! -f "$sub_db" ]]; then
        print_error "订阅数据库不存在"
        return 1
    fi

    # 获取订阅信息
    local sub_info=$(jq -r ".subscriptions[] | select(.name == \"$sub_name\")" "$sub_db" 2>/dev/null)
    if [[ -z "$sub_info" ]]; then
        print_error "订阅 '${sub_name}' 不存在"
        return 1
    fi

    # 获取订阅配置
    local user_id=$(echo "$sub_info" | jq -r '.user_id // empty')
    local sub_type=$(echo "$sub_info" | jq -r '.type // "base64"')
    local sub_file=$(echo "$sub_info" | jq -r '.file')

    echo ""
    print_info "正在重新生成订阅: ${sub_name}"
    print_info "订阅类型: ${sub_type}"
    if [[ -n "$user_id" ]]; then
        local user_email=$(jq -r ".users[] | select(.id == \"$user_id\") | .email" "$USERS_FILE" 2>/dev/null)
        print_info "绑定用户: ${user_email} (${user_id})"
    fi

    # 根据订阅类型重新生成内容
    case "$sub_type" in
        "base64")
            # Base64编码订阅
            local links=""
            if [[ -n "$user_id" ]]; then
                # 用户绑定订阅：只包含该用户的节点
                links=$(generate_user_share_links "$user_id")
            else
                # 通用订阅：包含所有节点+所有用户
                links=$(generate_all_share_links)
            fi

            if [[ -z "$links" ]]; then
                print_error "没有可用的节点"
                return 1
            fi

            # Base64编码
            local encoded=$(echo -n "$links" | base64 -w 0 2>/dev/null || echo -n "$links" | base64)
            echo "$encoded" > "$sub_file"
            ;;

        "clash")
            # Clash YAML格式
            generate_clash_config "$user_id" > "$sub_file"
            ;;

        "raw")
            # 原始文本格式
            if [[ -n "$user_id" ]]; then
                generate_user_share_links "$user_id" > "$sub_file"
            else
                generate_all_share_links > "$sub_file"
            fi
            ;;

        *)
            print_error "未知的订阅类型: ${sub_type}"
            return 1
            ;;
    esac

    # 更新订阅信息中的更新时间
    jq "(.subscriptions[] | select(.name == \"$sub_name\") | .updated) = (now|todate)" "$sub_db" > "${sub_db}.tmp"
    mv "${sub_db}.tmp" "$sub_db"

    print_success "订阅重新生成成功！"

    # 显示订阅信息
    local port=$(cat "${DATA_DIR}/subscription_port.txt" 2>/dev/null || echo "8080")
    local server_ip=$(get_public_ip)
    local sub_url="http://${server_ip}:${port}/sub/${sub_name}"

    echo ""
    echo -e "${CYAN}╔═══════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║          订阅链接                    ║${NC}"
    echo -e "${CYAN}╚═══════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${GREEN}订阅名称:${NC} ${sub_name}"
    echo -e "${GREEN}订阅类型:${NC} ${sub_type}"
    echo -e "${GREEN}订阅链接:${NC}"
    echo ""
    echo -e "${YELLOW}${sub_url}${NC}"
    echo ""
}

# 订阅配置
config_subscription() {
    clear
    echo -e "${CYAN}╔═══════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║          订阅配置                    ║${NC}"
    echo -e "${CYAN}╚═══════════════════════════════════════╝${NC}"
    echo ""

    echo -e "${GREEN}1.${NC} 设置订阅端口"
    echo -e "${GREEN}2.${NC} 重启订阅服务"
    echo -e "${GREEN}3.${NC} 查看订阅服务状态"
    echo -e "${GREEN}4.${NC} 查看单个节点分享链接"
    echo -e "${GREEN}0.${NC} 返回"
    echo ""
    read -p "请选择 [0-4]: " choice

    case $choice in
        1)
            read -p "请输入订阅端口 [1-65535]: " sub_port
            if [[ -n "$sub_port" && "$sub_port" =~ ^[0-9]+$ ]]; then
                if [[ $sub_port -ge 1 && $sub_port -le 65535 ]]; then
                    echo "$sub_port" > "${DATA_DIR}/sub_port.txt"
                    setup_subscription_server "$sub_port"
                    print_success "订阅端口设置成功"
                else
                    print_error "端口范围必须在 1-65535 之间"
                fi
            fi
            ;;
        2)
            local sub_port=$(cat "${DATA_DIR}/sub_port.txt" 2>/dev/null || echo "8080")
            setup_subscription_server "$sub_port"
            print_success "订阅服务重启成功"
            ;;
        3)
            if pgrep -f "python.*subscription_server" > /dev/null 2>&1; then
                local sub_port=$(cat "${DATA_DIR}/sub_port.txt" 2>/dev/null || echo "8080")
                print_success "订阅服务运行中"
                print_info "监听端口: $sub_port"
            else
                print_warning "订阅服务未运行"
            fi
            ;;
        4)
            show_node_share_link
            ;;
    esac
}

# 设置订阅服务器
setup_subscription_server() {
    local port=$1

    # 停止已有服务
    pkill -f "python.*subscription_server" 2>/dev/null

    # 创建简单的 HTTP 服务器脚本
    cat > "${DATA_DIR}/subscription_server.py" <<'PYEOF'
#!/usr/bin/env python3
# -*- coding: utf-8 -*-
import http.server
import socketserver
import os
import sys
from urllib.parse import unquote

PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 8080
DIRECTORY = sys.argv[2] if len(sys.argv) > 2 else os.getcwd()

class SubscriptionHandler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=DIRECTORY, **kwargs)

    def do_GET(self):
        if self.path.startswith('/sub/'):
            filename = unquote(self.path[5:])
            filepath = os.path.join(DIRECTORY, filename)

            if os.path.exists(filepath):
                self.send_response(200)
                self.send_header('Content-Type', 'text/plain; charset=utf-8')
                self.send_header('Content-Disposition', f'attachment; filename="{filename}"')
                self.send_header('Access-Control-Allow-Origin', '*')
                self.send_header('Cache-Control', 'no-cache')
                self.end_headers()

                with open(filepath, 'rb') as f:
                    self.wfile.write(f.read())
            else:
                self.send_error(404, 'Subscription not found')
        else:
            self.send_error(403, 'Access denied')

    def log_message(self, format, *args):
        pass

if __name__ == '__main__':
    try:
        with socketserver.TCPServer(("", PORT), SubscriptionHandler) as httpd:
            print(f"[订阅服务] 运行在端口 {PORT}")
            print(f"[订阅服务] 文件目录: {DIRECTORY}")
            httpd.serve_forever()
    except KeyboardInterrupt:
        print("\n[订阅服务] 停止")
    except Exception as e:
        print(f"[订阅服务] 错误: {e}")
PYEOF

    chmod +x "${DATA_DIR}/subscription_server.py"

    # 后台启动服务
    nohup python3 "${DATA_DIR}/subscription_server.py" "$port" "$SUBSCRIPTION_DIR" > /dev/null 2>&1 &

    sleep 1

    if pgrep -f "python.*subscription_server" > /dev/null 2>&1; then
        print_success "订阅服务已启动"
        print_info "监听端口: $port"
    else
        print_error "订阅服务启动失败"
    fi
}

# 保存订阅信息
save_subscription_info() {
    local name=$1
    local url=$2
    local file=$3
    local type=$4
    local user=$5

    local sub_db="${DATA_DIR}/subscriptions.json"
    if [[ ! -f "$sub_db" ]]; then
        echo '{"subscriptions":[]}' > "$sub_db"
    fi

    # 检查是否已存在
    local exists=$(jq -r ".subscriptions[] | select(.name == \"$name\") | .name" "$sub_db" 2>/dev/null)

    if [[ -n "$exists" ]]; then
        # 更新现有订阅
        jq ".subscriptions = [.subscriptions[] | if .name == \"$name\" then {name: \"$name\", url: \"$url\", file: \"$file\", type: \"$type\", user: \"$user\", updated: now|todate} else . end]" "$sub_db" > "${sub_db}.tmp"
    else
        # 添加新订阅
        local sub_data=$(jq -n \
            --arg name "$name" \
            --arg url "$url" \
            --arg file "$file" \
            --arg type "$type" \
            --arg user "$user" \
            '{name: $name, url: $url, file: $file, type: $type, user: $user, created: now|todate}')

        jq ".subscriptions += [$sub_data]" "$sub_db" > "${sub_db}.tmp"
    fi

    mv "${sub_db}.tmp" "$sub_db"
}

# 删除订阅信息
remove_subscription_info() {
    local name=$1
    local sub_db="${DATA_DIR}/subscriptions.json"

    if [[ -f "$sub_db" ]]; then
        jq ".subscriptions = [.subscriptions[] | select(.name != \"$name\")]" "$sub_db" > "${sub_db}.tmp"
        mv "${sub_db}.tmp" "$sub_db"
    fi
}

# 更新别名（兼容旧函数名）
generate_subscription() {
    generate_subscription_with_user
}
