#!/bin/bash

#================================================================
# 用户-节点绑定管理模块（新架构）
# 功能：绑定用户到节点、解绑、查看绑定关系
#================================================================

# 绑定用户到节点
bind_user_to_node() {
    clear
    echo -e "${CYAN}╔═══════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║      绑定用户到节点                  ║${NC}"
    echo -e "${CYAN}╚═══════════════════════════════════════╝${NC}"
    echo ""

    # 显示所有用户
    echo -e "${YELLOW}可用用户列表：${NC}"
    list_global_users

    echo ""
    read -p "请输入用户邮箱: " email
    if [[ -z "$email" ]]; then
        print_error "邮箱不能为空"
        return 1
    fi

    # 获取用户UUID
    local uuid=$(jq -r ".users[] | select(.email == \"$email\") | .id" "$USERS_FILE" 2>/dev/null)
    if [[ -z "$uuid" ]]; then
        print_error "用户不存在: $email"
        return 1
    fi

    # 显示所有节点
    echo ""
    echo -e "${YELLOW}可用节点列表：${NC}"
    list_nodes

    echo ""
    read -p "请输入节点端口: " port
    if [[ -z "$port" ]]; then
        print_error "端口不能为空"
        return 1
    fi

    # 检查节点是否存在
    local node_exists=$(jq -r ".nodes[] | select(.port == \"$port\") | .port" "$NODES_FILE" 2>/dev/null)
    if [[ -z "$node_exists" ]]; then
        print_error "节点不存在: $port"
        return 1
    fi

    # 检查是否已绑定
    local already_bound=$(jq -r ".bindings[] | select(.port == \"$port\") | .users[] | select(. == \"$uuid\")" "$NODE_USERS_FILE" 2>/dev/null)
    if [[ -n "$already_bound" ]]; then
        print_warning "用户 $email 已绑定到端口 $port"
        return 0
    fi

    # 添加绑定
    if [[ ! -f "$NODE_USERS_FILE" ]]; then
        echo '{"bindings":[]}' > "$NODE_USERS_FILE"
    fi

    # 检查该端口的绑定是否存在
    local binding_exists=$(jq -r ".bindings[] | select(.port == \"$port\") | .port" "$NODE_USERS_FILE" 2>/dev/null)

    if [[ -z "$binding_exists" ]]; then
        # 创建新绑定
        local protocol=$(jq -r ".nodes[] | select(.port == \"$port\") | .protocol" "$NODES_FILE")
        jq ".bindings += [{port: \"$port\", protocol: \"$protocol\", users: [\"$uuid\"]}]" "$NODE_USERS_FILE" > "${NODE_USERS_FILE}.tmp"
    else
        # 添加用户到现有绑定
        jq "(.bindings[] | select(.port == \"$port\") | .users) += [\"$uuid\"]" "$NODE_USERS_FILE" > "${NODE_USERS_FILE}.tmp"
    fi

    mv "${NODE_USERS_FILE}.tmp" "$NODE_USERS_FILE"

    print_success "用户 $email 已绑定到端口 $port"

    # 重新生成配置
    generate_xray_config

    # 重启服务
    restart_xray

    print_success "配置已更新并重启服务"
}

# 解绑用户
unbind_user_from_node() {
    clear
    echo -e "${CYAN}╔═══════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║      解绑用户                        ║${NC}"
    echo -e "${CYAN}╚═══════════════════════════════════════╝${NC}"
    echo ""

    # 显示当前绑定关系
    show_user_node_bindings

    echo ""
    read -p "请输入用户邮箱: " email
    if [[ -z "$email" ]]; then
        print_error "邮箱不能为空"
        return 1
    fi

    # 获取用户UUID
    local uuid=$(jq -r ".users[] | select(.email == \"$email\") | .id" "$USERS_FILE" 2>/dev/null)
    if [[ -z "$uuid" ]]; then
        print_error "用户不存在: $email"
        return 1
    fi

    echo ""
    read -p "请输入节点端口: " port
    if [[ -z "$port" ]]; then
        print_error "端口不能为空"
        return 1
    fi

    # 检查绑定是否存在
    local bound=$(jq -r ".bindings[] | select(.port == \"$port\") | .users[] | select(. == \"$uuid\")" "$NODE_USERS_FILE" 2>/dev/null)
    if [[ -z "$bound" ]]; then
        print_error "用户 $email 未绑定到端口 $port"
        return 1
    fi

    # 解绑用户
    jq "(.bindings[] | select(.port == \"$port\") | .users) |= map(select(. != \"$uuid\"))" "$NODE_USERS_FILE" > "${NODE_USERS_FILE}.tmp"
    mv "${NODE_USERS_FILE}.tmp" "$NODE_USERS_FILE"

    print_success "用户 $email 已从端口 $port 解绑"

    # 重新生成配置
    generate_xray_config

    # 重启服务
    restart_xray

    print_success "配置已更新并重启服务"
}

# 显示用户-节点绑定关系
show_user_node_bindings() {
    echo -e "${CYAN}╔═══════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║      用户-节点绑定关系              ║${NC}"
    echo -e "${CYAN}╚═══════════════════════════════════════╝${NC}"
    echo ""

    if [[ ! -f "$NODE_USERS_FILE" ]]; then
        print_warning "绑定关系文件不存在"
        return 1
    fi

    local binding_count=$(jq '.bindings | length' "$NODE_USERS_FILE")
    if [[ $binding_count -eq 0 ]]; then
        print_warning "没有绑定关系"
        return 0
    fi

    # 遍历所有绑定
    while IFS= read -r binding; do
        local port=$(echo "$binding" | jq -r '.port')
        local protocol=$(echo "$binding" | jq -r '.protocol')
        local users=$(echo "$binding" | jq -r '.users[]')

        echo -e "${GREEN}端口 $port ($protocol):${NC}"

        if [[ -z "$users" ]]; then
            echo -e "  ${YELLOW}无绑定用户${NC}"
        else
            while IFS= read -r uuid; do
                local email=$(jq -r ".users[] | select(.id == \"$uuid\") | .email" "$USERS_FILE" 2>/dev/null)
                if [[ -n "$email" ]]; then
                    echo -e "  ${CYAN}•${NC} $email (${uuid:0:8}...)"
                fi
            done <<< "$users"
        fi
        echo ""
    done < <(jq -c '.bindings[]' "$NODE_USERS_FILE")
}

# 查看用户可访问的节点
show_user_nodes() {
    clear
    echo -e "${CYAN}╔═══════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║      用户可访问节点                  ║${NC}"
    echo -e "${CYAN}╚═══════════════════════════════════════╝${NC}"
    echo ""

    # 显示所有用户
    list_global_users

    echo ""
    read -p "请输入用户邮箱: " email
    if [[ -z "$email" ]]; then
        print_error "邮箱不能为空"
        return 1
    fi

    # 获取用户UUID
    local uuid=$(jq -r ".users[] | select(.email == \"$email\") | .id" "$USERS_FILE" 2>/dev/null)
    if [[ -z "$uuid" ]]; then
        print_error "用户不存在: $email"
        return 1
    fi

    echo ""
    echo -e "${GREEN}用户 $email 可访问的节点：${NC}"
    echo ""

    # 查找该用户绑定的所有节点
    local node_found=false
    while IFS= read -r binding; do
        local port=$(echo "$binding" | jq -r '.port')
        local protocol=$(echo "$binding" | jq -r '.protocol')
        local users=$(echo "$binding" | jq -r '.users[]')

        # 检查用户是否在这个节点的用户列表中
        if echo "$users" | grep -q "$uuid"; then
            node_found=true
            # 获取节点详细信息
            local node=$(jq -r ".nodes[] | select(.port == \"$port\")" "$NODES_FILE")
            local transport=$(echo "$node" | jq -r '.transport')
            local security=$(echo "$node" | jq -r '.security')

            echo -e "${CYAN}端口 $port:${NC}"
            echo -e "  协议: $protocol"
            echo -e "  传输: $transport"
            echo -e "  安全: $security"
            echo ""
        fi
    done < <(jq -c '.bindings[]' "$NODE_USERS_FILE" 2>/dev/null)

    if [[ "$node_found" == "false" ]]; then
        print_warning "用户 $email 未绑定到任何节点"
    fi
}

# 查看节点的用户列表
show_node_users() {
    clear
    echo -e "${CYAN}╔═══════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║      节点用户列表                    ║${NC}"
    echo -e "${CYAN}╚═══════════════════════════════════════╝${NC}"
    echo ""

    # 显示所有节点
    list_nodes

    echo ""
    read -p "请输入节点端口: " port
    if [[ -z "$port" ]]; then
        print_error "端口不能为空"
        return 1
    fi

    # 检查节点是否存在
    local node_exists=$(jq -r ".nodes[] | select(.port == \"$port\") | .port" "$NODES_FILE" 2>/dev/null)
    if [[ -z "$node_exists" ]]; then
        print_error "节点不存在: $port"
        return 1
    fi

    echo ""
    echo -e "${GREEN}端口 $port 的用户列表：${NC}"
    echo ""

    # 获取该节点的用户列表
    local users=$(jq -r ".bindings[] | select(.port == \"$port\") | .users[]" "$NODE_USERS_FILE" 2>/dev/null)

    if [[ -z "$users" ]]; then
        print_warning "该节点没有绑定用户"
        return 0
    fi

    # 显示用户信息
    while IFS= read -r uuid; do
        local user=$(jq -r ".users[] | select(.id == \"$uuid\")" "$USERS_FILE" 2>/dev/null)
        if [[ -n "$user" && "$user" != "null" ]]; then
            local email=$(echo "$user" | jq -r '.email')
            local level=$(echo "$user" | jq -r '.level // 0')
            local enabled=$(echo "$user" | jq -r '.enabled // true')

            local status_text=""
            if [[ "$enabled" == "true" ]]; then
                status_text="${GREEN}启用${NC}"
            else
                status_text="${RED}禁用${NC}"
            fi

            echo -e "${CYAN}•${NC} $email"
            echo -e "  UUID: ${uuid:0:8}...${uuid: -8}"
            echo -e "  等级: $level"
            echo -e "  状态: $status_text"
            echo ""
        fi
    done <<< "$users"
}

# 批量绑定用户到多个节点
batch_bind_user_to_nodes() {
    clear
    echo -e "${CYAN}╔═══════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║      批量绑定用户到节点              ║${NC}"
    echo -e "${CYAN}╚═══════════════════════════════════════╝${NC}"
    echo ""

    # 显示所有用户
    echo -e "${YELLOW}可用用户列表：${NC}"
    list_global_users

    echo ""
    read -p "请输入用户邮箱: " email
    if [[ -z "$email" ]]; then
        print_error "邮箱不能为空"
        return 1
    fi

    # 获取用户UUID
    local uuid=$(jq -r ".users[] | select(.email == \"$email\") | .id" "$USERS_FILE" 2>/dev/null)
    if [[ -z "$uuid" ]]; then
        print_error "用户不存在: $email"
        return 1
    fi

    # 显示所有节点
    echo ""
    echo -e "${YELLOW}可用节点列表：${NC}"
    list_nodes

    echo ""
    echo -e "${YELLOW}输入节点端口（多个端口用空格分隔，如: 443 8443 10086）${NC}"
    read -p "端口列表: " ports

    if [[ -z "$ports" ]]; then
        print_error "端口列表不能为空"
        return 1
    fi

    # 绑定到每个节点
    local success_count=0
    local fail_count=0

    for port in $ports; do
        # 检查节点是否存在
        local node_exists=$(jq -r ".nodes[] | select(.port == \"$port\") | .port" "$NODES_FILE" 2>/dev/null)
        if [[ -z "$node_exists" ]]; then
            print_error "节点不存在: $port"
            ((fail_count++))
            continue
        fi

        # 检查是否已绑定
        local already_bound=$(jq -r ".bindings[] | select(.port == \"$port\") | .users[] | select(. == \"$uuid\")" "$NODE_USERS_FILE" 2>/dev/null)
        if [[ -n "$already_bound" ]]; then
            print_info "端口 $port 已绑定，跳过"
            continue
        fi

        # 添加绑定
        local binding_exists=$(jq -r ".bindings[] | select(.port == \"$port\") | .port" "$NODE_USERS_FILE" 2>/dev/null)

        if [[ -z "$binding_exists" ]]; then
            # 创建新绑定
            local protocol=$(jq -r ".nodes[] | select(.port == \"$port\") | .protocol" "$NODES_FILE")
            jq ".bindings += [{port: \"$port\", protocol: \"$protocol\", users: [\"$uuid\"]}]" "$NODE_USERS_FILE" > "${NODE_USERS_FILE}.tmp"
        else
            # 添加用户到现有绑定
            jq "(.bindings[] | select(.port == \"$port\") | .users) += [\"$uuid\"]" "$NODE_USERS_FILE" > "${NODE_USERS_FILE}.tmp"
        fi

        mv "${NODE_USERS_FILE}.tmp" "$NODE_USERS_FILE"
        print_success "已绑定到端口 $port"
        ((success_count++))
    done

    echo ""
    print_info "批量绑定完成：成功 $success_count 个，失败 $fail_count 个"

    if [[ $success_count -gt 0 ]]; then
        # 重新生成配置
        generate_xray_config

        # 重启服务
        restart_xray

        print_success "配置已更新并重启服务"
    fi
}
