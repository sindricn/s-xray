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

    echo -e "${CYAN}╔════════════════════════════════════════════════════════════════════════════════════════════════╗${NC}"
    printf "${CYAN}║${NC} %-12s %-14s %-16s %-18s %-8s %-10s ${CYAN}║${NC}\n" "用户名" "密码" "邮箱" "UUID" "状态" "在线"
    echo -e "${CYAN}╠════════════════════════════════════════════════════════════════════════════════════════════════╣${NC}"

    while IFS= read -r user; do
        local username=$(echo "$user" | jq -r '.username // "未设置"')
        local password=$(echo "$user" | jq -r '.password // "无"')
        local email=$(echo "$user" | jq -r '.email // "未设置"')
        local uuid=$(echo "$user" | jq -r '.id')
        local enabled=$(echo "$user" | jq -r '.enabled // true')

        local short_uuid="${uuid:0:16}..."
        local short_password="${password:0:12}"
        if [[ ${#password} -gt 12 ]]; then
            short_password="${password:0:9}..."
        fi
        local short_email="${email:0:14}"
        if [[ ${#email} -gt 14 ]]; then
            short_email="${email:0:11}..."
        fi

        local status=""
        if [[ "$enabled" == "true" ]]; then
            status="${GREEN}启用${NC}"
        else
            status="${RED}禁用${NC}"
        fi

        # 获取在线状态
        local online_status=""
        if [[ "$enabled" == "true" ]]; then
            local port=$(get_user_first_port "$uuid")
            if [[ -n "$port" ]]; then
                local user_status=$(get_user_online_status "$email" "$port")
                case $user_status in
                    online) online_status="${GREEN}在线${NC}" ;;
                    offline) online_status="${YELLOW}离线${NC}" ;;
                    never) online_status="${GRAY}未连接${NC}" ;;
                    *) online_status="${GRAY}未知${NC}" ;;
                esac
            else
                online_status="${GRAY}未绑定${NC}"
            fi
        else
            online_status="${GRAY}已禁用${NC}"
        fi

        printf "${CYAN}║${NC} %-12s %-14s %-16s %-18s %-8b %-10b ${CYAN}║${NC}\n" "$username" "$short_password" "$short_email" "$short_uuid" "$status" "$online_status"
    done < <(jq -c '.users[]' "$USERS_FILE")

    echo -e "${CYAN}╚════════════════════════════════════════════════════════════════════════════════════════════════╝${NC}"
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
# 用户在线状态检测
#================================================================

# 检查用户是否有流量记录
check_user_has_traffic() {
    local email=$1
    local api_addr="127.0.0.1:10085"
    local xray_bin="/usr/local/xray/xray"

    # 检查 API 端口是否在监听
    if ! ss -lnt 2>/dev/null | grep -q ":10085 " && ! netstat -lnt 2>/dev/null | grep -q ":10085 "; then
        echo "unknown"
        return
    fi

    # 检查 xray 命令是否可用
    if [[ ! -x "$xray_bin" ]]; then
        echo "unknown"
        return
    fi

    # 查询上行流量
    local uplink=$($xray_bin api statsquery --server=$api_addr --name "user>>>${email}>>>traffic>>>uplink" 2>/dev/null | grep "value" | awk '{print $2}' | tr -d '\r')
    uplink=${uplink:-0}

    # 查询下行流量
    local downlink=$($xray_bin api statsquery --server=$api_addr --name "user>>>${email}>>>traffic>>>downlink" 2>/dev/null | grep "value" | awk '{print $2}' | tr -d '\r')
    downlink=${downlink:-0}

    # 检查是否有流量数据
    if [[ "$uplink" -gt 0 ]] || [[ "$downlink" -gt 0 ]]; then
        echo "yes"
        return
    fi

    echo "no"
}

# 检查端口是否有活跃连接
check_port_has_connections() {
    local port=$1

    # 使用 ss 或 netstat 检查
    if command -v ss &>/dev/null; then
        if ss -tn 2>/dev/null | grep -q ":${port}.*ESTABLISHED"; then
            echo "yes"
            return
        fi
    elif command -v netstat &>/dev/null; then
        if netstat -tn 2>/dev/null | grep -q ":${port}.*ESTABLISHED"; then
            echo "yes"
            return
        fi
    fi

    echo "no"
}

# 获取用户在线状态（混合方案）
get_user_online_status() {
    local email=$1
    local port=$2

    # 检查流量记录
    local has_traffic=$(check_user_has_traffic "$email")

    if [[ "$has_traffic" == "unknown" ]]; then
        echo "unknown"  # API 不可用
        return
    elif [[ "$has_traffic" == "yes" ]]; then
        echo "online"  # 有流量即认为在线
        return
    fi

    # 没有流量记录时,检查端口是否有活跃连接
    local has_conn=$(check_port_has_connections "$port")

    if [[ "$has_conn" == "yes" ]]; then
        echo "online"  # 端口有连接,可能刚连接还没产生流量
    else
        echo "offline"  # 既无流量也无连接,确认离线
    fi
}

# 获取用户绑定的第一个节点端口
get_user_first_port() {
    local uuid=$1

    if [[ ! -f "$NODE_USERS_FILE" ]]; then
        echo ""
        return
    fi

    # 查找包含该用户的第一个节点
    local port=$(jq -r ".bindings[] | select(.users[] == \"$uuid\") | .port" "$NODE_USERS_FILE" 2>/dev/null | head -n 1)
    echo "$port"
}

# 获取用户流量摘要
get_user_traffic_summary() {
    local email=$1
    local api_addr="127.0.0.1:10085"
    local xray_bin="/usr/local/xray/xray"

    # 检查 API 端口是否在监听
    if ! ss -lnt 2>/dev/null | grep -q ":10085 " && ! netstat -lnt 2>/dev/null | grep -q ":10085 "; then
        echo "N/A"
        return
    fi

    # 检查 xray 命令是否可用
    if [[ ! -x "$xray_bin" ]]; then
        echo "N/A"
        return
    fi

    # 查询上行流量
    local uplink=$($xray_bin api statsquery --server=$api_addr --name "user>>>${email}>>>traffic>>>uplink" 2>/dev/null | grep "value" | awk '{print $2}' | tr -d '\r')
    uplink=${uplink:-0}

    # 查询下行流量
    local downlink=$($xray_bin api statsquery --server=$api_addr --name "user>>>${email}>>>traffic>>>downlink" 2>/dev/null | grep "value" | awk '{print $2}' | tr -d '\r')
    downlink=${downlink:-0}

    # 转换为人类可读格式
    local uplink_mb=$((uplink / 1048576))
    local downlink_mb=$((downlink / 1048576))

    echo "↑${uplink_mb}MB ↓${downlink_mb}MB"
}

# 查看在线用户
show_online_users() {
    clear
    echo -e "${CYAN}╔═══════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║      在线用户列表                    ║${NC}"
    echo -e "${CYAN}╚═══════════════════════════════════════╝${NC}"
    echo ""

    # 获取所有用户
    if [[ ! -f "$USERS_FILE" ]]; then
        print_warning "用户文件不存在"
        return 1
    fi

    local total_users=$(jq '.users | length' "$USERS_FILE" 2>/dev/null)
    if [[ "$total_users" -eq 0 ]]; then
        print_warning "没有用户"
        return 0
    fi

    local online_count=0

    echo -e "${CYAN}╔═════════════════════════════════════════════════════════════════════════════╗${NC}"
    printf "${CYAN}║${NC} %-15s %-20s %-10s %-20s %-12s ${CYAN}║${NC}\n" "用户名" "邮箱" "节点端口" "流量统计" "连接状态"
    echo -e "${CYAN}╠═════════════════════════════════════════════════════════════════════════════╣${NC}"

    while IFS= read -r user; do
        local username=$(echo "$user" | jq -r '.username')
        local email=$(echo "$user" | jq -r '.email')
        local uuid=$(echo "$user" | jq -r '.id')
        local enabled=$(echo "$user" | jq -r '.enabled // true')

        # 只显示启用的用户
        if [[ "$enabled" != "true" ]]; then
            continue
        fi

        # 获取用户绑定的节点
        local port=$(get_user_first_port "$uuid")
        if [[ -z "$port" ]]; then
            continue
        fi

        # 检测在线状态
        local status=$(get_user_online_status "$email" "$port")

        # 只显示在线或可能在线的用户
        if [[ "$status" == "online" ]]; then
            ((online_count++))

            # 获取流量统计
            local traffic=$(get_user_traffic_summary "$email")

            # 截断显示
            local short_username="${username:0:15}"
            local short_email="${email:0:20}"
            local short_traffic="${traffic:0:20}"

            printf "${CYAN}║${NC} %-15s %-20s %-10s %-20s ${GREEN}%-12s${NC} ${CYAN}║${NC}\n" \
                "$short_username" "$short_email" "$port" "$short_traffic" "在线"
        fi
    done < <(jq -c '.users[]' "$USERS_FILE")

    echo -e "${CYAN}╚═════════════════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${CYAN}在线用户总数: ${GREEN}${online_count}${NC}"
}


