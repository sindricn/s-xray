#!/bin/bash

#================================================================
# 节点管理模块
# 功能：添加、删除、查看、修改节点（VLESS/VMess/Trojan/Shadowsocks）
#================================================================

# 读取 VLESS 配置文档
read_vless_doc() {
    local vless_doc="$script_dir/docs/inbounds/vless.md"
    if [[ -f "$vless_doc" ]]; then
        cat "$vless_doc"
    fi
}

# 添加 VLESS 节点
add_vless_node() {
    clear
    echo -e "${CYAN}====== 添加 VLESS 节点 ======${NC}"

    # 输入配置
    read -p "请输入端口 [默认: 443]: " port
    port=${port:-443}

    read -p "请输入用户UUID [留空自动生成]: " uuid
    if [[ -z "$uuid" ]]; then
        uuid=$(generate_uuid)
        print_info "自动生成 UUID: $uuid"
    fi

    read -p "请输入用户邮箱/备注 [默认: user@vless]: " email
    email=${email:-user@vless}

    # 选择传输协议
    echo -e "\n${CYAN}传输协议选择：${NC}"
    echo "1. TCP"
    echo "2. WebSocket"
    echo "3. gRPC"
    echo "4. HTTP/2"
    read -p "请选择 [1-4]: " transport_choice

    case $transport_choice in
        1) transport="tcp" ;;
        2) transport="ws" ;;
        3) transport="grpc" ;;
        4) transport="h2" ;;
        *) transport="tcp" ;;
    esac

    # WebSocket 特殊配置
    local ws_path=""
    if [[ "$transport" == "ws" ]]; then
        read -p "WebSocket 路径 [默认: /ws]: " ws_path
        ws_path=${ws_path:-/ws}
    fi

    # gRPC 特殊配置
    local grpc_service=""
    if [[ "$transport" == "grpc" ]]; then
        read -p "gRPC 服务名 [默认: GunService]: " grpc_service
        grpc_service=${grpc_service:-GunService}
    fi

    # TLS 配置
    read -p "是否启用 TLS? [y/N]: " enable_tls
    local tls_config=""
    local tls_domain=""
    local tls_cert=""
    local tls_key=""

    if [[ "$enable_tls" == "y" || "$enable_tls" == "Y" ]]; then
        read -p "请输入域名: " tls_domain
        read -p "请输入证书路径 [留空使用自签名]: " tls_cert

        if [[ -n "$tls_cert" ]]; then
            read -p "请输入密钥路径: " tls_key
        else
            print_info "将使用自签名证书"
            generate_self_signed_cert "$tls_domain"
            tls_cert="${XRAY_DIR}/certs/${tls_domain}.crt"
            tls_key="${XRAY_DIR}/certs/${tls_domain}.key"
        fi
    fi

    # 生成配置
    local inbound_config=$(cat <<EOF
    {
      "port": ${port},
      "protocol": "vless",
      "tag": "vless-${port}",
      "settings": {
        "clients": [
          {
            "id": "${uuid}",
            "email": "${email}",
            "level": 0,
            "flow": "xtls-rprx-vision"
          }
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "${transport}"
EOF
)

    # 添加传输层配置
    if [[ "$transport" == "ws" ]]; then
        inbound_config+=",
        \"wsSettings\": {
          \"path\": \"${ws_path}\"
        }"
    elif [[ "$transport" == "grpc" ]]; then
        inbound_config+=",
        \"grpcSettings\": {
          \"serviceName\": \"${grpc_service}\"
        }"
    fi

    # 添加 TLS 配置
    if [[ "$enable_tls" == "y" || "$enable_tls" == "Y" ]]; then
        inbound_config+=",
        \"security\": \"tls\",
        \"tlsSettings\": {
          \"serverName\": \"${tls_domain}\",
          \"certificates\": [
            {
              \"certificateFile\": \"${tls_cert}\",
              \"keyFile\": \"${tls_key}\"
            }
          ]
        }"
    fi

    inbound_config+="
      },
      \"sniffing\": {
        \"enabled\": true,
        \"destOverride\": [\"http\", \"tls\"]
      }
    }"

    # 保存节点信息
    save_node_info "vless" "$port" "$uuid" "$email" "$transport" "$inbound_config"

    # 更新配置文件
    add_inbound_to_config "$inbound_config"

    # 重启服务
    restart_xray

    print_success "VLESS 节点添加成功！"
    print_info "端口: $port"
    print_info "UUID: $uuid"
    print_info "传输: $transport"

    # 生成分享链接
    generate_vless_share_link "$uuid" "$email" "$port" "$transport" "$ws_path" "$tls_domain"
}

# 添加 VMess 节点
add_vmess_node() {
    clear
    echo -e "${CYAN}====== 添加 VMess 节点 ======${NC}"

    read -p "请输入端口 [默认: 10086]: " port
    port=${port:-10086}

    read -p "请输入用户UUID [留空自动生成]: " uuid
    if [[ -z "$uuid" ]]; then
        uuid=$(generate_uuid)
        print_info "自动生成 UUID: $uuid"
    fi

    read -p "请输入用户邮箱/备注 [默认: user@vmess]: " email
    email=${email:-user@vmess}

    read -p "请输入 alterId [默认: 0]: " alter_id
    alter_id=${alter_id:-0}

    # 选择加密方式
    echo -e "\n${CYAN}加密方式：${NC}"
    echo "1. auto"
    echo "2. aes-128-gcm"
    echo "3. chacha20-poly1305"
    echo "4. none"
    read -p "请选择 [1-4]: " cipher_choice

    case $cipher_choice in
        1) cipher="auto" ;;
        2) cipher="aes-128-gcm" ;;
        3) cipher="chacha20-poly1305" ;;
        4) cipher="none" ;;
        *) cipher="auto" ;;
    esac

    # 传输协议选择
    echo -e "\n${CYAN}传输协议：${NC}"
    echo "1. TCP"
    echo "2. WebSocket"
    echo "3. mKCP"
    read -p "请选择 [1-3]: " transport_choice

    case $transport_choice in
        1) transport="tcp" ;;
        2) transport="ws" ;;
        3) transport="mkcp" ;;
        *) transport="tcp" ;;
    esac

    local ws_path=""
    if [[ "$transport" == "ws" ]]; then
        read -p "WebSocket 路径 [默认: /vmess]: " ws_path
        ws_path=${ws_path:-/vmess}
    fi

    # 生成配置
    local inbound_config=$(cat <<EOF
    {
      "port": ${port},
      "protocol": "vmess",
      "tag": "vmess-${port}",
      "settings": {
        "clients": [
          {
            "id": "${uuid}",
            "email": "${email}",
            "level": 0,
            "alterId": ${alter_id}
          }
        ]
      },
      "streamSettings": {
        "network": "${transport}"
EOF
)

    if [[ "$transport" == "ws" ]]; then
        inbound_config+=",
        \"wsSettings\": {
          \"path\": \"${ws_path}\"
        }"
    fi

    inbound_config+="
      },
      \"sniffing\": {
        \"enabled\": true,
        \"destOverride\": [\"http\", \"tls\"]
      }
    }"

    # 保存并应用
    save_node_info "vmess" "$port" "$uuid" "$email" "$transport" "$inbound_config"
    add_inbound_to_config "$inbound_config"
    restart_xray

    print_success "VMess 节点添加成功！"
    print_info "端口: $port"
    print_info "UUID: $uuid"
    print_info "AlterID: $alter_id"
    print_info "加密: $cipher"

    generate_vmess_share_link "$uuid" "$email" "$port" "$transport" "$ws_path" "$alter_id" "$cipher"
}

# 添加 Trojan 节点
add_trojan_node() {
    clear
    echo -e "${CYAN}====== 添加 Trojan 节点 ======${NC}"

    read -p "请输入端口 [默认: 443]: " port
    port=${port:-443}

    read -p "请输入密码: " password
    while [[ -z "$password" ]]; do
        print_error "密码不能为空"
        read -p "请输入密码: " password
    done

    read -p "请输入用户邮箱/备注 [默认: user@trojan]: " email
    email=${email:-user@trojan}

    # TLS 配置（Trojan 必须使用 TLS）
    read -p "请输入域名: " tls_domain
    while [[ -z "$tls_domain" ]]; do
        print_error "域名不能为空"
        read -p "请输入域名: " tls_domain
    done

    read -p "请输入证书路径 [留空使用自签名]: " tls_cert
    if [[ -n "$tls_cert" ]]; then
        read -p "请输入密钥路径: " tls_key
    else
        generate_self_signed_cert "$tls_domain"
        tls_cert="${XRAY_DIR}/certs/${tls_domain}.crt"
        tls_key="${XRAY_DIR}/certs/${tls_domain}.key"
    fi

    # 回落配置
    read -p "是否配置回落? [y/N]: " enable_fallback
    local fallback_config=""
    if [[ "$enable_fallback" == "y" || "$enable_fallback" == "Y" ]]; then
        read -p "回落地址 [默认: 127.0.0.1]: " fallback_dest
        fallback_dest=${fallback_dest:-127.0.0.1}
        read -p "回落端口 [默认: 80]: " fallback_port
        fallback_port=${fallback_port:-80}

        fallback_config=",
        \"fallbacks\": [
          {
            \"dest\": \"${fallback_dest}:${fallback_port}\"
          }
        ]"
    fi

    # 生成配置
    local inbound_config=$(cat <<EOF
    {
      "port": ${port},
      "protocol": "trojan",
      "tag": "trojan-${port}",
      "settings": {
        "clients": [
          {
            "password": "${password}",
            "email": "${email}",
            "level": 0
          }
        ]${fallback_config}
      },
      "streamSettings": {
        "network": "tcp",
        "security": "tls",
        "tlsSettings": {
          "serverName": "${tls_domain}",
          "alpn": ["http/1.1"],
          "certificates": [
            {
              "certificateFile": "${tls_cert}",
              "keyFile": "${tls_key}"
            }
          ]
        }
      },
      "sniffing": {
        "enabled": true,
        "destOverride": ["http", "tls"]
      }
    }
EOF
)

    save_node_info "trojan" "$port" "$password" "$email" "tcp" "$inbound_config"
    add_inbound_to_config "$inbound_config"
    restart_xray

    print_success "Trojan 节点添加成功！"
    print_info "端口: $port"
    print_info "密码: $password"
    print_info "域名: $tls_domain"

    generate_trojan_share_link "$password" "$tls_domain" "$port"
}

# 添加 Shadowsocks 节点
add_shadowsocks_node() {
    clear
    echo -e "${CYAN}====== 添加 Shadowsocks 节点 ======${NC}"

    read -p "请输入端口 [默认: 8388]: " port
    port=${port:-8388}

    read -p "请输入密码: " password
    while [[ -z "$password" ]]; do
        print_error "密码不能为空"
        read -p "请输入密码: " password
    done

    # 选择加密方式
    echo -e "\n${CYAN}加密方式：${NC}"
    echo "1. aes-256-gcm (推荐)"
    echo "2. aes-128-gcm"
    echo "3. chacha20-poly1305"
    echo "4. chacha20-ietf-poly1305"
    read -p "请选择 [1-4]: " cipher_choice

    case $cipher_choice in
        1) cipher="aes-256-gcm" ;;
        2) cipher="aes-128-gcm" ;;
        3) cipher="chacha20-poly1305" ;;
        4) cipher="chacha20-ietf-poly1305" ;;
        *) cipher="aes-256-gcm" ;;
    esac

    read -p "请输入用户邮箱/备注 [默认: user@ss]: " email
    email=${email:-user@ss}

    # 生成配置
    local inbound_config=$(cat <<EOF
    {
      "port": ${port},
      "protocol": "shadowsocks",
      "tag": "ss-${port}",
      "settings": {
        "method": "${cipher}",
        "password": "${password}",
        "email": "${email}",
        "level": 0,
        "network": "tcp,udp"
      },
      "sniffing": {
        "enabled": true,
        "destOverride": ["http", "tls"]
      }
    }
EOF
)

    save_node_info "shadowsocks" "$port" "$password" "$email" "tcp" "$inbound_config"
    add_inbound_to_config "$inbound_config"
    restart_xray

    print_success "Shadowsocks 节点添加成功！"
    print_info "端口: $port"
    print_info "密码: $password"
    print_info "加密: $cipher"

    generate_ss_share_link "$cipher" "$password" "$port"
}

# 删除节点
delete_node() {
    list_nodes

    read -p "请输入要删除的节点端口: " port
    if [[ -z "$port" ]]; then
        print_error "端口不能为空"
        return 1
    fi

    # 从配置文件中删除
    remove_inbound_from_config "$port"

    # 从节点数据库中删除
    remove_node_info "$port"

    restart_xray
    print_success "节点删除成功！"
}

# 查看节点列表
list_nodes() {
    clear
    echo -e "${CYAN}====== 节点列表 ======${NC}\n"

    if [[ ! -f "$NODES_FILE" ]]; then
        print_warning "暂无节点"
        return 0
    fi

    local nodes=$(jq -r '.nodes[] | "\(.protocol)|\(.port)|\(.id)|\(.email)"' "$NODES_FILE" 2>/dev/null)

    if [[ -z "$nodes" ]]; then
        print_warning "暂无节点"
        return 0
    fi

    printf "%-15s %-10s %-40s %-20s\n" "协议" "端口" "ID/密码" "备注"
    echo "--------------------------------------------------------------------------------------------------------"

    while IFS='|' read -r protocol port id email; do
        printf "%-15s %-10s %-40s %-20s\n" "$protocol" "$port" "$id" "$email"
    done <<< "$nodes"
}

# 修改节点
modify_node() {
    list_nodes

    read -p "请输入要修改的节点端口: " port
    if [[ -z "$port" ]]; then
        print_error "端口不能为空"
        return 1
    fi

    print_info "节点修改功能开发中..."
    # TODO: 实现修改节点配置
}

# 生成自签名证书
generate_self_signed_cert() {
    local domain=$1
    local cert_dir="${XRAY_DIR}/certs"

    mkdir -p "$cert_dir"

    print_info "生成自签名证书: $domain"

    openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
        -keyout "${cert_dir}/${domain}.key" \
        -out "${cert_dir}/${domain}.crt" \
        -subj "/C=US/ST=State/L=City/O=Organization/CN=${domain}" \
        2>/dev/null

    print_success "证书生成完成"
}

# 保存节点信息到数据库
save_node_info() {
    local protocol=$1
    local port=$2
    local id=$3
    local email=$4
    local transport=$5
    local config=$6

    local node_data=$(jq -n \
        --arg protocol "$protocol" \
        --arg port "$port" \
        --arg id "$id" \
        --arg email "$email" \
        --arg transport "$transport" \
        --arg config "$config" \
        '{protocol: $protocol, port: $port, id: $id, email: $email, transport: $transport, config: $config, created: now|todate}')

    # 读取现有数据
    local current_data=$(cat "$NODES_FILE")

    # 添加新节点
    echo "$current_data" | jq ".nodes += [$node_data]" > "$NODES_FILE"
}

# 从数据库删除节点
remove_node_info() {
    local port=$1
    jq ".nodes = [.nodes[] | select(.port != \"$port\")]" "$NODES_FILE" > "${NODES_FILE}.tmp"
    mv "${NODES_FILE}.tmp" "$NODES_FILE"
}

# 添加入站到配置文件
add_inbound_to_config() {
    local inbound=$1

    # 读取当前配置
    local current_config=$(cat "$XRAY_CONFIG")

    # 添加新的入站
    echo "$current_config" | jq ".inbounds += [$inbound]" > "$XRAY_CONFIG"
}

# 从配置文件删除入站
remove_inbound_from_config() {
    local port=$1
    jq ".inbounds = [.inbounds[] | select(.port != $port)]" "$XRAY_CONFIG" > "${XRAY_CONFIG}.tmp"
    mv "${XRAY_CONFIG}.tmp" "$XRAY_CONFIG"
}
