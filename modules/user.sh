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
    local admin_email="admin@system"

    local admin_data=$(jq -n \
        --arg id "$admin_uuid" \
        --arg username "admin" \
        --arg password "$admin_password" \
        --arg email "$admin_email" \
        '{id: $id, username: $username, password: $password, email: $email, level: 0, created: (now|todate), enabled: true}')

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

    echo -e "${CYAN}╔══════════════════════════════════════════════════════════════════╗${NC}"
    printf "${CYAN}║${NC} %-15s %-18s %-20s %-8s ${CYAN}║${NC}\n" "用户名" "密码" "UUID" "状态"
    echo -e "${CYAN}╠══════════════════════════════════════════════════════════════════╣${NC}"

    while IFS= read -r user; do
        local username=$(echo "$user" | jq -r '.username // "未设置"')
        local password=$(echo "$user" | jq -r '.password // "无"')
        local uuid=$(echo "$user" | jq -r '.id')
        local enabled=$(echo "$user" | jq -r '.enabled // true')

        local short_uuid="${uuid:0:16}..."
        local short_password="${password:0:16}"
        if [[ ${#password} -gt 16 ]]; then
            short_password="${password:0:13}..."
        fi

        local status=""
        if [[ "$enabled" == "true" ]]; then
            status="${GREEN}启用${NC}"
        else
            status="${RED}禁用${NC}"
        fi

        printf "${CYAN}║${NC} %-15s %-18s %-20s %-8b ${CYAN}║${NC}\n" "$username" "$short_password" "$short_uuid" "$status"
    done < <(jq -c '.users[]' "$USERS_FILE")

    echo -e "${CYAN}╚══════════════════════════════════════════════════════════════════╝${NC}"
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
        '{id: $id, username: $username, password: $password, email: $email, level: $level, created: (now|todate), enabled: true}')

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
    echo ""

    # 询问是否绑定到节点
    read -p "是否立即绑定到节点? [y/N]: " bind_now
    if [[ "$bind_now" == "y" || "$bind_now" == "Y" ]]; then
        bind_user_to_node
    fi
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
    read -p "请输入要删除的用户邮箱: " email
    if [[ -z "$email" ]]; then
        print_error "邮箱不能为空"
        return 1
    fi

    # 检查用户是否存在
    local uuid=$(jq -r ".users[] | select(.email == \"$email\") | .id" "$USERS_FILE" 2>/dev/null)
    if [[ -z "$uuid" ]]; then
        print_error "用户不存在: $email"
        return 1
    fi

    # 警告
    echo ""
    print_warning "删除用户将同时清理所有节点绑定关系"
    read -p "确认删除用户 $email? [y/N]: " confirm
    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
        print_info "取消删除"
        return 0
    fi

    # 从所有节点解绑
    if [[ -f "$NODE_USERS_FILE" ]]; then
        jq "(.bindings[].users) |= map(select(. != \"$uuid\"))" "$NODE_USERS_FILE" > "${NODE_USERS_FILE}.tmp"
        mv "${NODE_USERS_FILE}.tmp" "$NODE_USERS_FILE"
        print_info "已清理节点绑定关系"
    fi

    # 从全局用户列表删除
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
    list_nodes

    read -p "请输入要添加用户的节点端口: " port
    if [[ -z "$port" ]]; then
        print_error "端口不能为空"
        return 1
    fi

    # 检查节点是否存在
    local node_protocol=$(jq -r ".nodes[] | select(.port == \"$port\") | .protocol" "$NODES_FILE" 2>/dev/null)
    if [[ -z "$node_protocol" ]]; then
        print_error "节点不存在"
        return 1
    fi

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

    local users=$(jq -r '.users[] | "\(.port)|\(.protocol)|\(.id)|\(.email)|\(.created)"' "$USERS_FILE" 2>/dev/null)

    if [[ -z "$users" ]]; then
        print_warning "暂无用户"
        return 0
    fi

    printf "%-10s %-15s %-40s %-20s %-20s\n" "端口" "协议" "ID/密码" "邮箱" "创建时间"
    echo "------------------------------------------------------------------------------------------------------------------------"

    while IFS='|' read -r port protocol id email created; do
        # 截断过长的ID
        local short_id="${id:0:36}"
        printf "%-10s %-15s %-40s %-20s %-20s\n" "$port" "$protocol" "$short_id" "$email" "${created:0:19}"
    done <<< "$users"
}

# 修改用户
modify_user() {
    clear
    echo -e "${CYAN}====== 修改用户 ======${NC}"

    list_users

    read -p "请输入要修改用户的节点端口: " port
    if [[ -z "$port" ]]; then
        print_error "端口不能为空"
        return 1
    fi

    read -p "请输入用户邮箱: " email
    if [[ -z "$email" ]]; then
        print_error "邮箱不能为空"
        return 1
    fi

    # 获取用户信息
    local user_info=$(jq -r ".users[] | select(.port == \"$port\" and .email == \"$email\")" "$USERS_FILE" 2>/dev/null)
    if [[ -z "$user_info" ]]; then
        print_error "用户不存在"
        return 1
    fi

    echo -e "\n${CYAN}当前用户信息：${NC}"
    echo "$user_info" | jq .

    echo -e "\n${CYAN}修改选项：${NC}"
    echo "1. 修改邮箱/备注"
    echo "2. 重置UUID/密码"
    echo "3. 修改用户等级"
    echo "0. 返回"
    read -p "请选择 [0-3]: " choice

    case $choice in
        1)
            read -p "请输入新的邮箱/备注: " new_email
            if [[ -n "$new_email" ]]; then
                update_user_email "$port" "$email" "$new_email"
                print_success "邮箱修改成功"
            fi
            ;;
        2)
            local protocol=$(echo "$user_info" | jq -r '.protocol')
            case $protocol in
                vless|vmess)
                    local new_uuid=$(generate_uuid)
                    print_info "新 UUID: $new_uuid"
                    update_user_id "$port" "$email" "$new_uuid"
                    print_success "UUID 重置成功"
                    ;;
                trojan|shadowsocks)
                    read -p "请输入新密码: " new_password
                    if [[ -n "$new_password" ]]; then
                        update_user_id "$port" "$email" "$new_password"
                        print_success "密码修改成功"
                    fi
                    ;;
            esac
            ;;
        3)
            read -p "请输入新的用户等级 [0-10]: " new_level
            if [[ "$new_level" =~ ^[0-9]+$ && "$new_level" -ge 0 && "$new_level" -le 10 ]]; then
                update_user_level "$port" "$email" "$new_level"
                print_success "用户等级修改成功"
            else
                print_error "无效的等级"
            fi
            ;;
        0)
            return 0
            ;;
        *)
            print_error "无效选择"
            ;;
    esac

    restart_xray
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
