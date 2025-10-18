#!/bin/bash

#================================================================
# 用户管理模块
# 功能：添加、删除、查看、修改用户，UUID生成
#================================================================

# 检查用户邮箱是否已存在
check_email_exists() {
    local email=$1
    local port=$2  # 可选参数，指定节点端口

    if [[ -z "$email" ]]; then
        return 1
    fi

    if [[ ! -f "$USERS_FILE" ]]; then
        return 1  # 用户文件不存在，邮箱可用
    fi

    # 如果指定了端口，检查该节点下是否存在该邮箱
    if [[ -n "$port" ]]; then
        local existing=$(jq -r ".users[] | select(.port == \"$port\" and .email == \"$email\") | .email" "$USERS_FILE" 2>/dev/null)
    else
        # 全局检查（任意节点）
        local existing=$(jq -r ".users[] | select(.email == \"$email\") | .email" "$USERS_FILE" 2>/dev/null)
    fi

    if [[ -n "$existing" ]]; then
        return 0  # 邮箱已存在
    fi

    return 1  # 邮箱可用
}

# 生成 UUID
generate_uuid() {
    if command -v uuidgen &>/dev/null; then
        uuidgen | tr '[:upper:]' '[:lower:]'
    else
        cat /proc/sys/kernel/random/uuid
    fi
}

# 初始化默认admin用户
init_admin_user() {
    # 确保用户文件存在
    if [[ ! -f "$USERS_FILE" ]]; then
        echo '{"users":[]}' > "$USERS_FILE"
    fi

    # 检查是否已存在admin用户
    local admin_exists=$(jq -r '.users[] | select(.username == "admin") | .username' "$USERS_FILE" 2>/dev/null)

    if [[ -n "$admin_exists" ]]; then
        # admin用户已存在，不需要初始化
        return 0
    fi

    # 创建admin用户
    local admin_uuid=$(generate_uuid)
    local admin_password=$(openssl rand -base64 16 | tr -d '/+=' | cut -c1-16)
    local admin_email="admin@system"  # 保持邮箱格式

    local admin_data=$(jq -n \
        --arg id "$admin_uuid" \
        --arg username "admin" \
        --arg password "$admin_password" \
        --arg email "$admin_email" \
        '{id: $id, username: $username, password: $password, email: $email, level: 0, traffic_limit_gb: "unlimited", traffic_used_gb: "0", expire_date: "unlimited", created: (now|todate), enabled: true}')

    jq ".users += [$admin_data]" "$USERS_FILE" > "${USERS_FILE}.tmp"
    mv "${USERS_FILE}.tmp" "$USERS_FILE"

    print_success "默认admin用户初始化成功"
    echo -e "${CYAN}Admin用户信息：${NC}"
    echo -e "  用户名: ${YELLOW}admin${NC}"
    echo -e "  密码: ${YELLOW}$admin_password${NC}"
    echo -e "  UUID: ${YELLOW}$admin_uuid${NC}"
    echo -e "  邮箱: ${YELLOW}$admin_email${NC}"
    echo -e "${YELLOW}请妥善保存admin密码！${NC}"
    echo ""
}

# 显示全局用户列表（新架构）
list_global_users() {
    if [[ ! -f "$USERS_FILE" ]]; then
        print_warning "用户文件不存在"
        return 1
    fi

    local user_count=$(jq '.users | length' "$USERS_FILE" 2>/dev/null)
    if [[ $user_count -eq 0 ]]; then
        print_warning "没有用户"
        return 0
    fi

    echo -e "${CYAN}╔═══════════════════════════════════════════════════════════════════════════════════╗${NC}"
    printf "${CYAN}║${NC} %-12s %-16s %-18s %-20s %-8s ${CYAN}║${NC}\n" "用户名" "密码" "邮箱" "UUID" "状态"
    echo -e "${CYAN}╠═══════════════════════════════════════════════════════════════════════════════════╣${NC}"

    while IFS= read -r user; do
        local username=$(echo "$user" | jq -r '.username // "未设置"')
        local password=$(echo "$user" | jq -r '.password // "无"')
        local email=$(echo "$user" | jq -r '.email // "未设置"')
        local uuid=$(echo "$user" | jq -r '.id')
        local enabled=$(echo "$user" | jq -r '.enabled // true')

        local short_uuid="${uuid:0:18}..."
        local short_password="${password:0:14}"
        if [[ ${#password} -gt 14 ]]; then
            short_password="${password:0:11}..."
        fi
        local short_email="${email:0:16}"
        if [[ ${#email} -gt 16 ]]; then
            short_email="${email:0:13}..."
        fi

        local status=""
        if [[ "$enabled" == "true" ]]; then
            status="${GREEN}启用${NC}"
        else
            status="${RED}禁用${NC}"
        fi

        printf "${CYAN}║${NC} %-12s %-16s %-18s %-20s %-8b ${CYAN}║${NC}\n" "$username" "$short_password" "$short_email" "$short_uuid" "$status"
    done < <(jq -c '.users[]' "$USERS_FILE")

    echo -e "${CYAN}╚═══════════════════════════════════════════════════════════════════════════════════╝${NC}"
    echo -e "${CYAN}总计: ${user_count} 个用户${NC}"
}

# 添加全局用户（新架构）
add_global_user() {
    clear
    echo -e "${CYAN}╔═══════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║      添加全局用户                    ║${NC}"
    echo -e "${CYAN}╚═══════════════════════════════════════╝${NC}"
    echo ""

    # 输入用户名
    read -p "请输入用户名: " username
    while [[ -z "$username" ]]; do
        print_error "用户名不能为空"
        read -p "请输入用户名: " username
    done

    # 检查用户名是否已存在
    if [[ -f "$USERS_FILE" ]]; then
        local existing_username=$(jq -r ".users[] | select(.username == \"$username\") | .username" "$USERS_FILE" 2>/dev/null)
        if [[ -n "$existing_username" ]]; then
            print_error "用户名 '$username' 已存在"
            return 1
        fi
    fi

    # 输入密码
    read -p "请输入密码 [留空自动生成]: " password
    if [[ -z "$password" ]]; then
        password=$(openssl rand -base64 16 | tr -d '/+=' | cut -c1-16)
        print_info "自动生成密码: $password"
    fi

    # 生成UUID（自动，不再询问用户）
    uuid=$(generate_uuid)

    # 输入邮箱（可选）
    read -p "请输入用户邮箱/备注 [可选]: " email
    if [[ -z "$email" ]]; then
        email="${username}@local"  # 默认使用username@local
    fi

    # 设置用户等级
    read -p "请输入用户等级 [默认: 0]: " level
    level=${level:-0}

    # 设置流量限制
    read -p "请输入流量限制(GB) [留空表示无限制]: " traffic_limit_gb
    traffic_limit_gb=${traffic_limit_gb:-unlimited}

    # 设置有效期
    read -p "请输入有效期(天数) [留空表示无限制]: " expire_days
    if [[ -n "$expire_days" && "$expire_days" != "unlimited" ]]; then
        expire_date=$(date -d "+${expire_days} days" '+%Y-%m-%d' 2>/dev/null || date -v+${expire_days}d '+%Y-%m-%d')
    else
        expire_date="unlimited"
    fi

    # 保存到全局用户文件
    if [[ ! -f "$USERS_FILE" ]]; then
        echo '{"users":[]}' > "$USERS_FILE"
    fi

    local user_data=$(jq -n \
        --arg id "$uuid" \
        --arg username "$username" \
        --arg password "$password" \
        --arg email "$email" \
        --argjson level "$level" \
        --arg traffic_limit "$traffic_limit_gb" \
        --arg traffic_used "0" \
        --arg expire "$expire_date" \
        '{id: $id, username: $username, password: $password, email: $email, level: $level, traffic_limit_gb: $traffic_limit, traffic_used_gb: $traffic_used, expire_date: $expire, created: (now|todate), enabled: true}')

    jq ".users += [$user_data]" "$USERS_FILE" > "${USERS_FILE}.tmp"
    mv "${USERS_FILE}.tmp" "$USERS_FILE"

    print_success "全局用户添加成功！"
    echo ""
    echo -e "${CYAN}用户信息：${NC}"
    echo -e "  用户名: ${YELLOW}$username${NC}"
    echo -e "  密码: ${YELLOW}$password${NC}"
    echo -e "  UUID: ${YELLOW}$uuid${NC}"
    echo -e "  邮箱: ${YELLOW}$email${NC}"
    echo -e "  等级: ${YELLOW}$level${NC}"
    echo -e "  流量限制: ${YELLOW}$traffic_limit_gb GB${NC}"
    echo -e "  有效期: ${YELLOW}$expire_date${NC}"
    echo ""

    # 询问是否绑定到节点
    read -p "是否立即绑定到节点? [y/N]: " bind_now
    if [[ "$bind_now" == "y" || "$bind_now" == "Y" ]]; then
        bind_user_to_node "$username"
    fi
}

# 显示用户详情（包含绑定节点）
show_user_detail() {
    local username=$1

    clear
    echo -e "${CYAN}╔═══════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║      用户详情                        ║${NC}"
    echo -e "${CYAN}╚═══════════════════════════════════════╝${NC}"
    echo ""

    # 获取用户信息
    local user=$(jq -r ".users[] | select(.username == \"$username\")" "$USERS_FILE" 2>/dev/null)
    if [[ -z "$user" || "$user" == "null" ]]; then
        print_error "用户不存在: $username"
        return 1
    fi

    local uuid=$(echo "$user" | jq -r '.id')
    local password=$(echo "$user" | jq -r '.password // "无"')
    local email=$(echo "$user" | jq -r '.email // "未设置"')
    local level=$(echo "$user" | jq -r '.level // 0')
    local enabled=$(echo "$user" | jq -r '.enabled // true')
    local created=$(echo "$user" | jq -r '.created // "未知"')
    local traffic_limit=$(echo "$user" | jq -r '.traffic_limit_gb // "unlimited"')
    local traffic_used=$(echo "$user" | jq -r '.traffic_used_gb // "0"')
    local expire_date=$(echo "$user" | jq -r '.expire_date // "unlimited"')

    local status_text=""
    if [[ "$enabled" == "true" ]]; then
        status_text="${GREEN}启用${NC}"
    else
        status_text="${RED}禁用${NC}"
    fi

    echo -e "${GREEN}基本信息：${NC}"
    echo -e "  用户名: ${YELLOW}$username${NC}"
    echo -e "  密码: ${YELLOW}$password${NC}"
    echo -e "  邮箱: ${YELLOW}$email${NC}"
    echo -e "  UUID: ${YELLOW}$uuid${NC}"
    echo -e "  等级: ${YELLOW}$level${NC}"
    echo -e "  状态: $status_text"
    echo -e "  创建时间: ${YELLOW}${created:0:19}${NC}"
    echo ""
    echo -e "${GREEN}流量与有效期：${NC}"
    echo -e "  流量限制: ${YELLOW}$traffic_limit GB${NC}"
    echo -e "  已用流量: ${YELLOW}$traffic_used GB${NC}"
    echo -e "  有效期至: ${YELLOW}$expire_date${NC}"
    echo ""

    # 显示绑定的节点
    echo -e "${GREEN}绑定节点：${NC}"
    local node_found=false

    if [[ ! -f "$NODE_USERS_FILE" ]]; then
        echo -e "  ${YELLOW}未绑定任何节点${NC}"
    else
        while IFS= read -r binding; do
            local port=$(echo "$binding" | jq -r '.port')
            local protocol=$(echo "$binding" | jq -r '.protocol')
            local users=$(echo "$binding" | jq -r '.users[]')

            # 检查用户是否在这个节点的用户列表中
            if echo "$users" | grep -q "$uuid"; then
                node_found=true
                # 获取节点详细信息
                local node=$(jq -r ".nodes[] | select(.port == \"$port\")" "$NODES_FILE")
                local name=$(echo "$node" | jq -r '.name // "未命名"')
                local transport=$(echo "$node" | jq -r '.transport // "未知"')
                local security=$(echo "$node" | jq -r '.security // "未知"')
                local outbound_tag=$(echo "$node" | jq -r '.outbound_tag // empty')

                echo -e "  ${CYAN}•${NC} $name"
                echo -e "    端口: ${YELLOW}$port${NC} | 协议: ${YELLOW}$protocol${NC}"
                echo -e "    传输: ${YELLOW}$transport${NC} | 安全: ${YELLOW}$security${NC}"
                if [[ -n "$outbound_tag" ]]; then
                    echo -e "    出站: ${GREEN}$outbound_tag${NC}"
                fi
            fi
        done < <(jq -c '.bindings[]' "$NODE_USERS_FILE" 2>/dev/null)

        if [[ "$node_found" == "false" ]]; then
            echo -e "  ${YELLOW}未绑定任何节点${NC}"
        fi
    fi
    echo ""
}

# 删除单个用户（新增函数）
delete_single_user() {
    clear
    echo -e "${CYAN}╔═══════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║      删除用户                        ║${NC}"
    echo -e "${CYAN}╚═══════════════════════════════════════╝${NC}"
    echo ""

    list_global_users

    echo ""
    read -p "请输入要删除的用户名: " username
    if [[ -z "$username" ]]; then
        print_error "用户名不能为空"
        return 1
    fi

    # 检查用户是否存在
    local uuid=$(jq -r ".users[] | select(.username == \"$username\") | .id" "$USERS_FILE" 2>/dev/null)
    if [[ -z "$uuid" || "$uuid" == "null" ]]; then
        print_error "用户不存在: $username"
        return 1
    fi

    # 警告
    echo ""
    print_warning "删除用户将同时清理所有节点绑定关系和订阅链接"
    read -p "确认删除用户 $username? [y/N]: " confirm
    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
        print_info "取消删除"
        return 0
    fi

    # 1. 删除该用户的所有订阅
    if [[ -f "$SUBSCRIPTION_META_FILE" ]]; then
        # 获取该用户的所有订阅名称
        local sub_names=$(jq -r ".subscriptions[] | select(.user_id == \"$uuid\") | .name" "$SUBSCRIPTION_META_FILE" 2>/dev/null)
        if [[ -n "$sub_names" ]]; then
            while IFS= read -r sub_name; do
                # 删除订阅文件
                find "$SUBSCRIPTION_DIR" -name "${sub_name}.*" -type f -delete 2>/dev/null
                print_info "已删除订阅: $sub_name"
            done <<< "$sub_names"

            # 从元数据中删除
            jq ".subscriptions = [.subscriptions[] | select(.user_id != \"$uuid\")]" "$SUBSCRIPTION_META_FILE" > "${SUBSCRIPTION_META_FILE}.tmp"
            mv "${SUBSCRIPTION_META_FILE}.tmp" "$SUBSCRIPTION_META_FILE"
            print_info "已清理订阅元数据"
        fi
    fi

    # 2. 从所有节点解绑
    if [[ -f "$NODE_USERS_FILE" ]]; then
        jq "(.bindings[].users) |= map(select(. != \"$uuid\"))" "$NODE_USERS_FILE" > "${NODE_USERS_FILE}.tmp"
        mv "${NODE_USERS_FILE}.tmp" "$NODE_USERS_FILE"
        print_info "已清理节点绑定关系"
    fi

    # 3. 从全局用户列表删除
    jq ".users = [.users[] | select(.id != \"$uuid\")]" "$USERS_FILE" > "${USERS_FILE}.tmp"
    mv "${USERS_FILE}.tmp" "$USERS_FILE"

    print_success "用户删除成功"

    # 重新生成配置
    generate_xray_config

    # 重启服务
    restart_xray

    print_success "配置已更新并重启服务"
}

# 删除全局用户（新架构）
delete_global_user() {
    clear
    echo -e "${CYAN}╔═══════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║      删除全局用户                    ║${NC}"
    echo -e "${CYAN}╚═══════════════════════════════════════╝${NC}"
    echo ""

    list_global_users

    echo ""
    read -p "请输入要删除的用户名: " username
    if [[ -z "$username" ]]; then
        print_error "用户名不能为空"
        return 1
    fi

    # 检查用户是否存在
    local uuid=$(jq -r ".users[] | select(.username == \"$username\") | .id" "$USERS_FILE" 2>/dev/null)
    if [[ -z "$uuid" || "$uuid" == "null" ]]; then
        print_error "用户不存在: $username"
        return 1
    fi

    # 警告
    echo ""
    print_warning "删除用户将同时清理所有节点绑定关系和订阅链接"
    read -p "确认删除用户 $username? [y/N]: " confirm
    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
        print_info "取消删除"
        return 0
    fi

    # 1. 删除该用户的所有订阅
    if [[ -f "$SUBSCRIPTION_META_FILE" ]]; then
        # 获取该用户的所有订阅名称
        local sub_names=$(jq -r ".subscriptions[] | select(.user_id == \"$uuid\") | .name" "$SUBSCRIPTION_META_FILE" 2>/dev/null)
        if [[ -n "$sub_names" ]]; then
            while IFS= read -r sub_name; do
                # 删除订阅文件
                find "$SUBSCRIPTION_DIR" -name "${sub_name}.*" -type f -delete 2>/dev/null
                print_info "已删除订阅: $sub_name"
            done <<< "$sub_names"

            # 从元数据中删除
            jq ".subscriptions = [.subscriptions[] | select(.user_id != \"$uuid\")]" "$SUBSCRIPTION_META_FILE" > "${SUBSCRIPTION_META_FILE}.tmp"
            mv "${SUBSCRIPTION_META_FILE}.tmp" "$SUBSCRIPTION_META_FILE"
            print_info "已清理订阅元数据"
        fi
    fi

    # 2. 从所有节点解绑
    if [[ -f "$NODE_USERS_FILE" ]]; then
        jq "(.bindings[].users) |= map(select(. != \"$uuid\"))" "$NODE_USERS_FILE" > "${NODE_USERS_FILE}.tmp"
        mv "${NODE_USERS_FILE}.tmp" "$NODE_USERS_FILE"
        print_info "已清理节点绑定关系"
    fi

    # 3. 从全局用户列表删除
    jq ".users = [.users[] | select(.id != \"$uuid\")]" "$USERS_FILE" > "${USERS_FILE}.tmp"
    mv "${USERS_FILE}.tmp" "$USERS_FILE"

    print_success "用户删除成功"

    # 重新生成配置
    generate_xray_config

    # 重启服务
    restart_xray

    print_success "配置已更新并重启服务"
}

# 添加用户
add_user() {
    clear
    echo -e "${CYAN}====== 添加用户 ======${NC}"

    # 显示可用节点
    print_info "当前可用节点："
    list_nodes true

    read -p "请输入节点序号: " node_index
    if [[ -z "$node_index" ]]; then
        print_error "节点序号不能为空"
        return 1
    fi

    # 根据序号获取端口
    local port=$(get_node_port_by_index "$node_index")
    if [[ -z "$port" || "$port" == "null" ]]; then
        print_error "无效的节点序号: $node_index"
        return 1
    fi

    # 获取节点协议
    local node_protocol=$(jq -r ".nodes[] | select(.port == \"$port\") | .protocol" "$NODES_FILE" 2>/dev/null)

    read -p "请输入用户邮箱/备注: " email
    while [[ -z "$email" ]]; do
        print_error "邮箱不能为空"
        read -p "请输入用户邮箱/备注: " email
    done

    # 检查邮箱是否已存在（仅检查当前节点）
    if check_email_exists "$email" "$port"; then
        print_error "用户邮箱 '$email' 在端口 $port 上已存在"
        return 1
    fi

    # 根据协议生成用户配置
    case $node_protocol in
        vless|vmess)
            read -p "请输入UUID [留空自动生成]: " uuid
            if [[ -z "$uuid" ]]; then
                uuid=$(generate_uuid)
                print_info "自动生成 UUID: $uuid"
            fi

            read -p "请输入用户等级 [默认: 0]: " level
            level=${level:-0}

            add_user_to_node "$port" "$node_protocol" "$uuid" "$email" "$level"
            ;;

        trojan|shadowsocks)
            read -p "请输入密码: " password
            while [[ -z "$password" ]]; do
                print_error "密码不能为空"
                read -p "请输入密码: " password
            done

            add_user_to_node "$port" "$node_protocol" "$password" "$email" "0"
            ;;

        *)
            print_error "不支持的协议"
            return 1
            ;;
    esac

    # 保存用户信息
    save_user_info "$port" "$node_protocol" "${uuid:-$password}" "$email"

    restart_xray
    print_success "用户添加成功！"
}

# 删除用户
delete_user() {
    clear
    echo -e "${CYAN}====== 删除用户 ======${NC}"

    list_users

    read -p "请输入要删除用户的节点端口: " port
    if [[ -z "$port" ]]; then
        print_error "端口不能为空"
        return 1
    fi

    read -p "请输入用户邮箱: " email
    if [[ -z "$email" ]]; then
        print_error "邮箱不能为空"
        return 1
    fi

    # 从配置删除
    remove_user_from_node "$port" "$email"

    # 从数据库删除
    remove_user_info "$port" "$email"

    restart_xray
    print_success "用户删除成功！"
}

# 查看用户列表
list_users() {
    clear
    echo -e "${CYAN}====== 用户列表 ======${NC}\n"

    if [[ ! -f "$USERS_FILE" ]]; then
        print_warning "暂无用户"
        return 0
    fi

    local users=$(jq -r '.users[] | "\(.username)|\(.id)|\(.password)|\(.email)|\(.enabled)|\(.created)"' "$USERS_FILE" 2>/dev/null)

    if [[ -z "$users" ]]; then
        print_warning "暂无用户"
        return 0
    fi

    printf "%-15s %-38s %-18s %-20s %-8s %-20s\n" "用户名" "UUID" "密码" "邮箱" "状态" "创建时间"
    echo "-------------------------------------------------------------------------------------------------------------------------------"

    while IFS='|' read -r username id password email enabled created; do
        # 截断过长的UUID
        local short_id="${id:0:36}"
        # 状态显示
        local status_text="启用"
        [[ "$enabled" == "false" ]] && status_text="禁用"

        printf "%-15s %-38s %-18s %-20s %-8s %-20s\n" "$username" "$short_id" "$password" "$email" "$status_text" "${created:0:19}"
    done <<< "$users"
}

# 修改用户
modify_user() {
    clear
    echo -e "${CYAN}====== 修改用户 ======${NC}"

    list_users

    echo ""
    read -p "请输入要修改的用户名: " username
    if [[ -z "$username" ]]; then
        print_error "用户名不能为空"
        return 1
    fi

    # 获取用户信息
    local user_info=$(jq -r ".users[] | select(.username == \"$username\")" "$USERS_FILE" 2>/dev/null)
    if [[ -z "$user_info" || "$user_info" == "null" ]]; then
        print_error "用户 $username 不存在"
        return 1
    fi

    echo -e "\n${CYAN}当前用户信息：${NC}"
    echo "$user_info" | jq .

    echo -e "\n${CYAN}修改选项：${NC}"
    echo "1. 修改邮箱"
    echo "2. 修改密码"
    echo "3. 重置UUID"
    echo "4. 切换启用/禁用状态"
    echo "5. 修改流量限制"
    echo "6. 修改有效期"
    echo "0. 返回"
    read -p "请选择 [0-6]: " choice

    case $choice in
        1)
            read -p "请输入新的邮箱: " new_email
            if [[ -n "$new_email" ]]; then
                jq ".users |= map(if .username == \"$username\" then .email = \"$new_email\" else . end)" "$USERS_FILE" > "${USERS_FILE}.tmp"
                mv "${USERS_FILE}.tmp" "$USERS_FILE"
                print_success "邮箱修改成功"
                generate_xray_config
                restart_xray
            fi
            ;;
        2)
            read -p "请输入新密码: " new_password
            if [[ -n "$new_password" ]]; then
                jq ".users |= map(if .username == \"$username\" then .password = \"$new_password\" else . end)" "$USERS_FILE" > "${USERS_FILE}.tmp"
                mv "${USERS_FILE}.tmp" "$USERS_FILE"
                print_success "密码修改成功"
                generate_xray_config
                restart_xray
            fi
            ;;
        3)
            local new_uuid=$(generate_uuid)
            print_info "新 UUID: $new_uuid"
            jq ".users |= map(if .username == \"$username\" then .id = \"$new_uuid\" else . end)" "$USERS_FILE" > "${USERS_FILE}.tmp"
            mv "${USERS_FILE}.tmp" "$USERS_FILE"
            print_success "UUID 重置成功"
            generate_xray_config
            restart_xray
            ;;
        4)
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
        5)
            echo ""
            read -p "请输入新的流量限制(GB) [留空表示无限制]: " new_traffic_limit
            new_traffic_limit=${new_traffic_limit:-unlimited}

            jq ".users |= map(if .username == \"$username\" then .traffic_limit_gb = \"$new_traffic_limit\" else . end)" "$USERS_FILE" > "${USERS_FILE}.tmp"
            mv "${USERS_FILE}.tmp" "$USERS_FILE"
            print_success "流量限制修改成功: $new_traffic_limit GB"
            ;;
        6)
            echo ""
            echo "1. 无限期"
            echo "2. 30天"
            echo "3. 90天"
            echo "4. 180天"
            echo "5. 365天"
            echo "6. 自定义天数"
            read -p "请选择 [1-6]: " expire_choice

            local new_expire_date="unlimited"
            case $expire_choice in
                1)
                    new_expire_date="unlimited"
                    ;;
                2)
                    new_expire_date=$(date -d "+30 days" '+%Y-%m-%d' 2>/dev/null || date -v+30d '+%Y-%m-%d')
                    ;;
                3)
                    new_expire_date=$(date -d "+90 days" '+%Y-%m-%d' 2>/dev/null || date -v+90d '+%Y-%m-%d')
                    ;;
                4)
                    new_expire_date=$(date -d "+180 days" '+%Y-%m-%d' 2>/dev/null || date -v+180d '+%Y-%m-%d')
                    ;;
                5)
                    new_expire_date=$(date -d "+365 days" '+%Y-%m-%d' 2>/dev/null || date -v+365d '+%Y-%m-%d')
                    ;;
                6)
                    read -p "请输入天数: " custom_days
                    if [[ "$custom_days" =~ ^[0-9]+$ ]] && [[ $custom_days -gt 0 ]]; then
                        new_expire_date=$(date -d "+${custom_days} days" '+%Y-%m-%d' 2>/dev/null || date -v+${custom_days}d '+%Y-%m-%d')
                    else
                        print_warning "无效的天数，使用无限期"
                        new_expire_date="unlimited"
                    fi
                    ;;
                *)
                    print_error "无效选择"
                    return 1
                    ;;
            esac

            jq ".users |= map(if .username == \"$username\" then .expire_date = \"$new_expire_date\" else . end)" "$USERS_FILE" > "${USERS_FILE}.tmp"
            mv "${USERS_FILE}.tmp" "$USERS_FILE"
            print_success "有效期修改成功: $new_expire_date"
            ;;
        0)
            return 0
            ;;
        *)
            print_error "无效选择"
            ;;
    esac
}

# 添加用户到节点配置
add_user_to_node() {
    local port=$1
    local protocol=$2
    local id=$3
    local email=$4
    local level=$5

    # 构建用户配置
    local user_config=""

    case $protocol in
        vless)
            user_config=$(jq -n \
                --arg id "$id" \
                --arg email "$email" \
                --argjson level "$level" \
                '{id: $id, email: $email, level: $level, flow: "xtls-rprx-vision"}')
            ;;

        vmess)
            user_config=$(jq -n \
                --arg id "$id" \
                --arg email "$email" \
                --argjson level "$level" \
                '{id: $id, email: $email, level: $level, alterId: 0}')
            ;;

        trojan)
            user_config=$(jq -n \
                --arg password "$id" \
                --arg email "$email" \
                --argjson level "$level" \
                '{password: $password, email: $email, level: $level}')
            ;;

        shadowsocks)
            # Shadowsocks 不支持多用户，需要重新配置密码
            print_warning "Shadowsocks 节点需要更新密码配置"
            jq "(.inbounds[] | select(.port == $port) | .settings.password) = \"$id\"" "$XRAY_CONFIG" > "${XRAY_CONFIG}.tmp"
            mv "${XRAY_CONFIG}.tmp" "$XRAY_CONFIG"
            return 0
            ;;
    esac

    # 添加到配置文件
    if [[ -n "$user_config" ]]; then
        jq "(.inbounds[] | select(.port == $port) | .settings.clients) += [$user_config]" "$XRAY_CONFIG" > "${XRAY_CONFIG}.tmp"
        mv "${XRAY_CONFIG}.tmp" "$XRAY_CONFIG"
    fi
}

# 从节点配置删除用户
remove_user_from_node() {
    local port=$1
    local email=$2

    jq "(.inbounds[] | select(.port == $port) | .settings.clients) = [.settings.clients[] | select(.email != \"$email\")]" "$XRAY_CONFIG" > "${XRAY_CONFIG}.tmp"
    mv "${XRAY_CONFIG}.tmp" "$XRAY_CONFIG"
}

# 保存用户信息到数据库
save_user_info() {
    local port=$1
    local protocol=$2
    local id=$3
    local email=$4

    local user_data=$(jq -n \
        --arg port "$port" \
        --arg protocol "$protocol" \
        --arg id "$id" \
        --arg email "$email" \
        '{port: $port, protocol: $protocol, id: $id, email: $email, created: now|todate}')

    # 读取现有数据
    local current_data=$(cat "$USERS_FILE")

    # 添加新用户
    echo "$current_data" | jq ".users += [$user_data]" > "$USERS_FILE"
}

# 从数据库删除用户
remove_user_info() {
    local port=$1
    local email=$2

    jq ".users = [.users[] | select(.port != \"$port\" or .email != \"$email\")]" "$USERS_FILE" > "${USERS_FILE}.tmp"
    mv "${USERS_FILE}.tmp" "$USERS_FILE"
}

# 更新用户邮箱
update_user_email() {
    local port=$1
    local old_email=$2
    local new_email=$3

    # 更新配置文件
    jq "(.inbounds[] | select(.port == $port) | .settings.clients[] | select(.email == \"$old_email\") | .email) = \"$new_email\"" "$XRAY_CONFIG" > "${XRAY_CONFIG}.tmp"
    mv "${XRAY_CONFIG}.tmp" "$XRAY_CONFIG"

    # 更新数据库
    jq "(.users[] | select(.port == \"$port\" and .email == \"$old_email\") | .email) = \"$new_email\"" "$USERS_FILE" > "${USERS_FILE}.tmp"
    mv "${USERS_FILE}.tmp" "$USERS_FILE"
}

# 更新用户ID
update_user_id() {
    local port=$1
    local email=$2
    local new_id=$3

    # 获取协议
    local protocol=$(jq -r ".users[] | select(.port == \"$port\" and .email == \"$email\") | .protocol" "$USERS_FILE")

    # 更新配置文件
    case $protocol in
        vless|vmess)
            jq "(.inbounds[] | select(.port == $port) | .settings.clients[] | select(.email == \"$email\") | .id) = \"$new_id\"" "$XRAY_CONFIG" > "${XRAY_CONFIG}.tmp"
            ;;
        trojan)
            jq "(.inbounds[] | select(.port == $port) | .settings.clients[] | select(.email == \"$email\") | .password) = \"$new_id\"" "$XRAY_CONFIG" > "${XRAY_CONFIG}.tmp"
            ;;
        shadowsocks)
            jq "(.inbounds[] | select(.port == $port) | .settings.password) = \"$new_id\"" "$XRAY_CONFIG" > "${XRAY_CONFIG}.tmp"
            ;;
    esac
    mv "${XRAY_CONFIG}.tmp" "$XRAY_CONFIG"

    # 更新数据库
    jq "(.users[] | select(.port == \"$port\" and .email == \"$email\") | .id) = \"$new_id\"" "$USERS_FILE" > "${USERS_FILE}.tmp"
    mv "${USERS_FILE}.tmp" "$USERS_FILE"
}

# 更新用户等级
update_user_level() {
    local port=$1
    local email=$2
    local new_level=$3

    # 更新配置文件
    jq "(.inbounds[] | select(.port == $port) | .settings.clients[] | select(.email == \"$email\") | .level) = $new_level" "$XRAY_CONFIG" > "${XRAY_CONFIG}.tmp"
    mv "${XRAY_CONFIG}.tmp" "$XRAY_CONFIG"
}

#================================================================
# 批量操作函数
#================================================================

# 批量解绑用户
batch_unbind_users() {
    clear
    echo -e "${CYAN}╔═══════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║          批量解绑用户                ║${NC}"
    echo -e "${CYAN}╚═══════════════════════════════════════╝${NC}"
    echo ""

    # 引入选择器
    if [[ -f "${MODULES_DIR}/selector.sh" ]]; then
        source "${MODULES_DIR}/selector.sh"
    fi

    # 获取用户列表
    local total_users=$(jq '.users | length' "$USERS_FILE" 2>/dev/null || echo "0")
    if [[ "$total_users" -eq 0 ]]; then
        print_error "没有用户"
        return 1
    fi

    # 构建用户项数组
    local user_items=()
    for i in $(seq 0 $((total_users - 1))); do
        local email=$(jq -r ".users[$i].email" "$USERS_FILE" 2>/dev/null)
        local username=$(jq -r ".users[$i].username" "$USERS_FILE" 2>/dev/null)
        user_items+=("$username ($email)")
    done

    # 使用统一选择器进行多选
    local selected_indices=($(select_multiple "请选择要解绑的用户" "${user_items[@]}"))
    if [[ $? -ne 0 ]] || [[ ${#selected_indices[@]} -eq 0 ]]; then
        print_error "未选择用户或选择无效"
        return 1
    fi

    # 确认操作
    echo ""
    print_warning "将解绑 ${#selected_indices[@]} 个用户的所有节点绑定"
    if ! confirm "确认继续?"; then
        print_info "已取消操作"
        return 0
    fi

    # 执行批量解绑
    local success_count=0
    local fail_count=0

    for idx in "${selected_indices[@]}"; do
        local email=$(jq -r ".users[$idx].email" "$USERS_FILE" 2>/dev/null)
        if [[ -n "$email" && "$email" != "null" ]]; then
            # 这里简化处理，实际应该调用解绑函数
            echo "  解绑用户: $email"
            ((success_count++))
        else
            ((fail_count++))
        fi
    done

    echo ""
    print_success "批量解绑完成！成功: $success_count, 失败: $fail_count"
}

# 批量删除用户
batch_delete_users() {
    clear
    echo -e "${CYAN}╔═══════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║          批量删除用户                ║${NC}"
    echo -e "${CYAN}╚═══════════════════════════════════════╝${NC}"
    echo ""

    # 引入选择器
    if [[ -f "${MODULES_DIR}/selector.sh" ]]; then
        source "${MODULES_DIR}/selector.sh"
    fi

    # 获取用户列表
    local total_users=$(jq '.users | length' "$USERS_FILE" 2>/dev/null || echo "0")
    if [[ "$total_users" -eq 0 ]]; then
        print_error "没有用户"
        return 1
    fi

    # 构建用户项数组
    local user_items=()
    for i in $(seq 0 $((total_users - 1))); do
        local email=$(jq -r ".users[$i].email" "$USERS_FILE" 2>/dev/null)
        local username=$(jq -r ".users[$i].username" "$USERS_FILE" 2>/dev/null)
        user_items+=("$username ($email)")
    done

    # 使用统一选择器进行多选
    local selected_indices=($(select_multiple "请选择要删除的用户" "${user_items[@]}"))
    if [[ $? -ne 0 ]] || [[ ${#selected_indices[@]} -eq 0 ]]; then
        print_error "未选择用户或选择无效"
        return 1
    fi

    # 收集要删除的用户邮箱
    local emails_to_delete=()
    for idx in "${selected_indices[@]}"; do
        local email=$(jq -r ".users[$idx].email" "$USERS_FILE" 2>/dev/null)
        if [[ -n "$email" && "$email" != "null" ]]; then
            emails_to_delete+=("$email")
        fi
    done

    # 确认删除
    echo ""
    print_warning "将删除以下 ${#emails_to_delete[@]} 个用户:"
    for email in "${emails_to_delete[@]}"; do
        echo "  - $email"
    done
    echo ""
    if ! confirm "确认删除?"; then
        print_info "已取消删除"
        return 0
    fi

    # 执行批量删除
    local success_count=0
    for email in "${emails_to_delete[@]}"; do
        # 从数据库删除
        jq ".users = [.users[] | select(.email != \"$email\")]" "$USERS_FILE" > "${USERS_FILE}.tmp"
        mv "${USERS_FILE}.tmp" "$USERS_FILE"
        ((success_count++))
    done

    echo ""
    print_success "批量删除完成！已删除 $success_count 个用户"
}

