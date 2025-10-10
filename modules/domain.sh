#!/bin/bash

#================================================================
# 域名和证书管理模块
# 功能：域名管理、证书管理、伪装域名优选
#================================================================

# 全局变量
DOMAIN_FILE="${DATA_DIR}/domains.json"
CERT_DIR="${XRAY_DIR}/certs"
DEFAULT_DOMAIN_FILE="${DATA_DIR}/default_domain.txt"

# 初始化域名数据文件
init_domain_file() {
    if [[ ! -f "$DOMAIN_FILE" ]]; then
        echo '{"domains":[],"certificates":[]}' > "$DOMAIN_FILE"
    fi
}

# 获取默认伪装域名
get_default_domain() {
    if [[ -f "$DEFAULT_DOMAIN_FILE" ]]; then
        cat "$DEFAULT_DOMAIN_FILE"
    else
        echo "www.microsoft.com"
    fi
}

# 设置默认伪装域名
set_default_domain() {
    local domain=$1
    echo "$domain" > "$DEFAULT_DOMAIN_FILE"
    print_success "默认伪装域名已设置为: $domain"
}

# 伪装域名优选（延迟测试 + DNS 解析验证）
test_best_reality_domains() {
    clear
    echo -e "${CYAN}╔═══════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║    Reality 伪装域名智能优选测试     ║${NC}"
    echo -e "${CYAN}╚═══════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${YELLOW}测试说明：${NC}"
    echo -e "  ✓ 测试多个知名网站的连接延迟"
    echo -e "  ✓ 验证 DNS 解析和 TLS 握手"
    echo -e "  ✓ 智能推荐延迟最低的域名"
    echo ""

    print_info "开始智能优选伪装域名..."
    echo ""

    # 创建临时文件存储结果
    local temp_file=$(mktemp)

    # 测试域名列表（扩展版，包含更多常用域名）
    local domains=(
        www.cloudflare.com
        www.apple.com
        www.microsoft.com
        www.bing.com
        developer.apple.com
        www.gstatic.com
        fonts.gstatic.com
        fonts.googleapis.com
        res-1.cdn.office.net
        aws.amazon.com
        www.aws.com
        d1.awsstatic.com
        cdn.jsdelivr.net
        www.sony.com
        www.w3.org
        www.wikipedia.org
        ajax.cloudflare.com
        www.mozilla.org
        www.intel.com
        images.unsplash.com
    )

    local total=${#domains[@]}
    local count=0
    local success_count=0
    local best_latency=9999
    local best_domain=""

    echo -e "${BLUE}正在测试域名延迟...${NC}"
    echo ""

    for domain in "${domains[@]}"; do
        ((count++))

        # 记录开始时间（毫秒）
        local t1=$(date +%s%3N)

        # 测试连接（超时2秒）
        if timeout 2 openssl s_client -connect "$domain:443" -servername "$domain" </dev/null &>/dev/null 2>&1; then
            local t2=$(date +%s%3N)
            local latency=$((t2 - t1))

            # 验证 DNS 解析
            if host "$domain" &>/dev/null 2>&1; then
                echo "$latency $domain" >> "$temp_file"
                ((success_count++))

                # 更新最佳域名
                if [[ $latency -lt $best_latency ]]; then
                    best_latency=$latency
                    best_domain=$domain
                fi

                # 实时显示成功结果
                printf "  ${GREEN}✔${NC} [%2d/%2d] %-35s ${CYAN}%4d ms${NC}\n" "$count" "$total" "$domain" "$latency"
            fi
        else
            printf "  ${RED}✘${NC} [%2d/%2d] %-35s ${YELLOW}超时${NC}\n" "$count" "$total" "$domain"
        fi
    done

    echo ""

    # 检查是否有成功的结果
    if [[ ! -s "$temp_file" || $success_count -eq 0 ]]; then
        print_error "所有域名测试均失败，请检查网络连接"
        rm -f "$temp_file"
        return 1
    fi

    # 显示优选结果
    echo -e "${GREEN}╔═══════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║        优选结果 - 推荐域名          ║${NC}"
    echo -e "${GREEN}╚═══════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${CYAN}最佳域名:${NC} ${YELLOW}$best_domain${NC}"
    echo -e "${CYAN}延迟:${NC} ${YELLOW}${best_latency}ms${NC}"
    echo -e "${CYAN}成功测试:${NC} ${YELLOW}${success_count}/${total}${NC} 个域名"
    echo ""

    # 显示延迟最低的前10个域名
    echo -e "${BLUE}延迟最低的前 10 个域名：${NC}"
    echo ""
    printf "${CYAN}%-5s %-40s %10s${NC}\n" "序号" "域名" "延迟"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    local index=1
    sort -n "$temp_file" | head -n 10 | while read -r latency domain; do
        if [[ $latency -lt 200 ]]; then
            printf "${GREEN}%-5s %-40s %7s ms${NC}\n" "$index" "$domain" "$latency"
        elif [[ $latency -lt 500 ]]; then
            printf "${YELLOW}%-5s %-40s %7s ms${NC}\n" "$index" "$domain" "$latency"
        else
            printf "${RED}%-5s %-40s %7s ms${NC}\n" "$index" "$domain" "$latency"
        fi
        ((index++))
    done

    echo ""
    echo -e "${YELLOW}提示：${NC}"
    echo -e "  ${GREEN}●${NC} 绿色 (<200ms): 优秀，强烈推荐"
    echo -e "  ${YELLOW}●${NC} 黄色 (200-500ms): 良好，可以使用"
    echo -e "  ${RED}●${NC} 红色 (>500ms): 较慢，不推荐"
    echo ""

    # 保存推荐域名到文件
    local recommended_file="${DATA_DIR}/recommended_domains.txt"
    sort -n "$temp_file" | head -n 10 | awk '{print $2}' > "$recommended_file"
    print_success "推荐域名已保存到: $recommended_file"

    # 询问是否设置为默认伪装域名
    echo ""
    read -p "是否将延迟最低的域名 ($best_domain) 设置为默认伪装域名? [Y/n]: " set_default
    if [[ "$set_default" != "n" && "$set_default" != "N" ]]; then
        set_default_domain "$best_domain"
    else
        # 询问是否选择其他域名
        read -p "是否选择其他域名作为默认? [y/N]: " choose_other
        if [[ "$choose_other" == "y" || "$choose_other" == "Y" ]]; then
            read -p "请输入域名序号 (1-10): " domain_index
            if [[ "$domain_index" =~ ^[1-9]$|^10$ ]]; then
                local selected_domain=$(sort -n "$temp_file" | head -n 10 | sed -n "${domain_index}p" | awk '{print $2}')
                if [[ -n "$selected_domain" ]]; then
                    set_default_domain "$selected_domain"
                fi
            fi
        fi
    fi

    # 清理临时文件
    rm -f "$temp_file"
}

# 测试自定义域名
test_custom_domain() {
    clear
    echo -e "${CYAN}====== 测试自定义域名 ======${NC}"
    echo ""

    read -p "请输入要测试的域名: " domain
    if [[ -z "$domain" ]]; then
        print_error "域名不能为空"
        return 1
    fi

    # 验证域名格式
    if ! [[ "$domain" =~ ^[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?)*$ ]]; then
        print_error "域名格式不正确"
        return 1
    fi

    echo ""
    print_info "开始测试域名: $domain"
    echo ""

    # DNS 解析测试
    print_info "1. DNS 解析测试..."
    if host "$domain" &>/dev/null; then
        local ip=$(host "$domain" | grep "has address" | awk '{print $4}' | head -1)
        print_success "DNS 解析成功: $ip"
    else
        print_error "DNS 解析失败"
        return 1
    fi

    # TLS 握手测试
    print_info "2. TLS 握手测试..."
    local t1=$(date +%s%3N)

    if timeout 3 openssl s_client -connect "$domain:443" -servername "$domain" </dev/null &>/dev/null; then
        local t2=$(date +%s%3N)
        local latency=$((t2 - t1))
        print_success "TLS 握手成功，延迟: ${latency}ms"

        # 询问是否设置为默认伪装域名
        echo ""
        read -p "是否将此域名设置为默认伪装域名? [y/N]: " set_default
        if [[ "$set_default" == "y" || "$set_default" == "Y" ]]; then
            set_default_domain "$domain"
        fi
    else
        print_error "TLS 握手失败"
        return 1
    fi
}

# DNS 解析测试
test_dns_resolution() {
    clear
    echo -e "${CYAN}====== DNS 解析测试 ======${NC}"
    echo ""

    read -p "请输入要测试的域名: " domain
    if [[ -z "$domain" ]]; then
        print_error "域名不能为空"
        return 1
    fi

    echo ""
    print_info "测试域名: $domain"
    echo ""

    # 使用 host 命令测试
    print_info "使用 host 命令测试..."
    if host "$domain"; then
        print_success "DNS 解析成功"
    else
        print_error "DNS 解析失败"
    fi

    echo ""

    # 使用 dig 命令测试（如果可用）
    if command -v dig &>/dev/null; then
        print_info "使用 dig 命令测试..."
        dig "$domain" +short
    fi

    echo ""

    # 使用 nslookup 命令测试（如果可用）
    if command -v nslookup &>/dev/null; then
        print_info "使用 nslookup 命令测试..."
        nslookup "$domain"
    fi
}

# 添加自定义域名
add_custom_domain() {
    clear
    echo -e "${CYAN}====== 添加自定义域名 ======${NC}"
    echo ""

    read -p "请输入域名: " domain
    if [[ -z "$domain" ]]; then
        print_error "域名不能为空"
        return 1
    fi

    # 验证域名格式
    if ! [[ "$domain" =~ ^[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?)*$ ]]; then
        print_error "域名格式不正确"
        return 1
    fi

    # 测试 DNS 解析
    print_info "测试 DNS 解析..."
    if host "$domain" &>/dev/null; then
        local ip=$(host "$domain" | grep "has address" | awk '{print $4}' | head -1)
        print_success "DNS 解析成功: $ip"
    else
        print_warning "DNS 解析失败，但仍可添加"
    fi

    read -p "请输入备注 [可选]: " note

    # 保存域名
    init_domain_file
    local domain_data=$(jq -n \
        --arg domain "$domain" \
        --arg note "$note" \
        '{domain: $domain, note: $note, type: "custom", created: now|todate}')

    local current_data=$(cat "$DOMAIN_FILE")
    echo "$current_data" | jq ".domains += [$domain_data]" > "$DOMAIN_FILE"

    print_success "域名添加成功！"
}

# 查看域名列表
list_domains() {
    clear
    echo -e "${CYAN}====== 域名列表 ======${NC}\n"

    init_domain_file

    local domains=$(jq -r '.domains[] | "\(.domain)|\(.note)|\(.type)"' "$DOMAIN_FILE" 2>/dev/null)

    if [[ -z "$domains" ]]; then
        print_warning "暂无域名"
        return 0
    fi

    printf "%-5s %-40s %-20s %-15s\n" "序号" "域名" "备注" "类型"
    echo "--------------------------------------------------------------------------------------------"

    local index=1
    while IFS='|' read -r domain note type; do
        printf "%-5s %-40s %-20s %-15s\n" "$index" "$domain" "$note" "$type"
        ((index++))
    done <<< "$domains"
}

# 删除域名
delete_domain() {
    list_domains

    echo ""
    read -p "请输入要删除的域名序号: " index
    if [[ -z "$index" ]]; then
        print_error "序号不能为空"
        return 1
    fi

    # 获取域名
    local domain=$(jq -r ".domains[$((index-1))].domain" "$DOMAIN_FILE" 2>/dev/null)
    if [[ -z "$domain" || "$domain" == "null" ]]; then
        print_error "无效的序号"
        return 1
    fi

    print_info "将删除域名: $domain"
    read -p "确认删除? [y/N]: " confirm
    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
        print_info "已取消删除"
        return 0
    fi

    # 删除域名
    jq ".domains = [.domains[] | select(.domain != \"$domain\")]" "$DOMAIN_FILE" > "${DOMAIN_FILE}.tmp"
    mv "${DOMAIN_FILE}.tmp" "$DOMAIN_FILE"

    print_success "域名删除成功！"
}

# 添加证书
add_certificate() {
    clear
    echo -e "${CYAN}====== 添加证书 ======${NC}"
    echo ""

    read -p "请输入域名: " domain
    if [[ -z "$domain" ]]; then
        print_error "域名不能为空"
        return 1
    fi

    echo ""
    echo -e "${CYAN}证书类型：${NC}"
    echo "1. 自签名证书（自动生成）"
    echo "2. 手动导入证书"
    read -p "请选择 [1-2]: " cert_type

    local cert_file=""
    local key_file=""

    if [[ "$cert_type" == "1" ]]; then
        # 生成自签名证书
        print_info "生成自签名证书..."
        mkdir -p "$CERT_DIR"

        openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
            -keyout "${CERT_DIR}/${domain}.key" \
            -out "${CERT_DIR}/${domain}.crt" \
            -subj "/C=US/ST=State/L=City/O=Organization/CN=${domain}" \
            2>/dev/null

        cert_file="${CERT_DIR}/${domain}.crt"
        key_file="${CERT_DIR}/${domain}.key"

        print_success "证书生成成功"
    else
        # 手动导入
        read -p "请输入证书文件路径: " cert_file
        read -p "请输入密钥文件路径: " key_file

        if [[ ! -f "$cert_file" ]]; then
            print_error "证书文件不存在: $cert_file"
            return 1
        fi

        if [[ ! -f "$key_file" ]]; then
            print_error "密钥文件不存在: $key_file"
            return 1
        fi

        # 复制到证书目录
        mkdir -p "$CERT_DIR"
        cp "$cert_file" "${CERT_DIR}/${domain}.crt"
        cp "$key_file" "${CERT_DIR}/${domain}.key"

        cert_file="${CERT_DIR}/${domain}.crt"
        key_file="${CERT_DIR}/${domain}.key"

        print_success "证书导入成功"
    fi

    # 保存证书信息
    init_domain_file
    local cert_data=$(jq -n \
        --arg domain "$domain" \
        --arg cert_file "$cert_file" \
        --arg key_file "$key_file" \
        --arg type "$([ "$cert_type" == "1" ] && echo "self-signed" || echo "imported")" \
        '{domain: $domain, cert_file: $cert_file, key_file: $key_file, type: $type, created: now|todate}')

    local current_data=$(cat "$DOMAIN_FILE")
    echo "$current_data" | jq ".certificates += [$cert_data]" > "$DOMAIN_FILE"

    echo ""
    echo -e "${CYAN}证书信息：${NC}"
    echo -e "  域名: $domain"
    echo -e "  证书: $cert_file"
    echo -e "  密钥: $key_file"
}

# 查看证书列表
list_certificates() {
    clear
    echo -e "${CYAN}====== 证书列表 ======${NC}\n"

    init_domain_file

    local certs=$(jq -r '.certificates[] | "\(.domain)|\(.type)|\(.cert_file)"' "$DOMAIN_FILE" 2>/dev/null)

    if [[ -z "$certs" ]]; then
        print_warning "暂无证书"
        return 0
    fi

    printf "%-5s %-40s %-20s %-50s\n" "序号" "域名" "类型" "证书路径"
    echo "---------------------------------------------------------------------------------------------------------------------"

    local index=1
    while IFS='|' read -r domain type cert_file; do
        local type_display="未知"
        [[ "$type" == "self-signed" ]] && type_display="自签名"
        [[ "$type" == "imported" ]] && type_display="导入"

        printf "%-5s %-40s %-20s %-50s\n" "$index" "$domain" "$type_display" "$cert_file"
        ((index++))
    done <<< "$certs"
}

# 删除证书
delete_certificate() {
    list_certificates

    echo ""
    read -p "请输入要删除的证书序号: " index
    if [[ -z "$index" ]]; then
        print_error "序号不能为空"
        return 1
    fi

    # 获取证书信息
    local domain=$(jq -r ".certificates[$((index-1))].domain" "$DOMAIN_FILE" 2>/dev/null)
    local cert_file=$(jq -r ".certificates[$((index-1))].cert_file" "$DOMAIN_FILE" 2>/dev/null)
    local key_file=$(jq -r ".certificates[$((index-1))].key_file" "$DOMAIN_FILE" 2>/dev/null)

    if [[ -z "$domain" || "$domain" == "null" ]]; then
        print_error "无效的序号"
        return 1
    fi

    print_info "将删除域名 $domain 的证书"
    read -p "是否同时删除证书文件? [y/N]: " delete_files

    # 删除证书记录
    jq ".certificates = [.certificates[] | select(.domain != \"$domain\")]" "$DOMAIN_FILE" > "${DOMAIN_FILE}.tmp"
    mv "${DOMAIN_FILE}.tmp" "$DOMAIN_FILE"

    # 删除文件
    if [[ "$delete_files" == "y" || "$delete_files" == "Y" ]]; then
        rm -f "$cert_file" "$key_file"
        print_success "证书记录和文件已删除"
    else
        print_success "证书记录已删除（文件保留）"
    fi
}

# 查看默认伪装域名
show_default_domain() {
    clear
    echo -e "${CYAN}====== 默认伪装域名 ======${NC}"
    echo ""
    local default_domain=$(get_default_domain)
    echo -e "${GREEN}当前默认伪装域名:${NC} $default_domain"
    echo ""
}

# 手动设置默认伪装域名
manual_set_default_domain() {
    clear
    echo -e "${CYAN}====== 设置默认伪装域名 ======${NC}"
    echo ""

    # 显示当前默认域名
    local current_default=$(get_default_domain)
    echo -e "${BLUE}当前默认域名:${NC} $current_default"
    echo ""

    read -p "请输入新的默认伪装域名: " domain
    if [[ -z "$domain" ]]; then
        print_error "域名不能为空"
        return 1
    fi

    # 验证域名格式
    if ! [[ "$domain" =~ ^[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?)*$ ]]; then
        print_error "域名格式不正确"
        return 1
    fi

    set_default_domain "$domain"
}

# 域名管理菜单
domain_management_menu() {
    while true; do
        clear

        # 显示当前默认域名
        local default_domain=$(get_default_domain)

        echo -e "${CYAN}====== 域名管理 ======${NC}"
        echo ""
        echo -e "${BLUE}默认伪装域名:${NC} $default_domain"
        echo ""
        echo -e "${YELLOW}⚡ 域名优选：${NC}"
        echo -e "${GREEN}1.${NC} Reality 伪装域名优选测试"
        echo -e "${GREEN}2.${NC} 测试自定义域名"
        echo ""
        echo -e "${CYAN}🔧 域名管理：${NC}"
        echo -e "${GREEN}3.${NC} 设置默认伪装域名"
        echo -e "${GREEN}4.${NC} 添加自定义域名"
        echo -e "${GREEN}5.${NC} 查看域名列表"
        echo -e "${GREEN}6.${NC} 删除域名"
        echo ""
        echo -e "${CYAN}🔍 域名测试：${NC}"
        echo -e "${GREEN}7.${NC} DNS 解析测试"
        echo ""
        echo -e "${GREEN}0.${NC} 返回上级菜单"
        echo ""
        read -p "请选择操作 [0-7]: " choice

        case $choice in
            1) test_best_reality_domains ;;
            2) test_custom_domain ;;
            3) manual_set_default_domain ;;
            4) add_custom_domain ;;
            5) list_domains ;;
            6) delete_domain ;;
            7) test_dns_resolution ;;
            0) break ;;
            *) print_error "无效选择" ;;
        esac

        read -p "按 Enter 键继续..."
    done
}

# 证书管理菜单
certificate_management_menu() {
    while true; do
        clear
        echo -e "${CYAN}====== 证书管理 ======${NC}"
        echo ""
        echo -e "${GREEN}1.${NC} 添加证书"
        echo -e "${GREEN}2.${NC} 查看证书列表"
        echo -e "${GREEN}3.${NC} 删除证书"
        echo ""
        echo -e "${GREEN}0.${NC} 返回上级菜单"
        echo ""
        read -p "请选择操作 [0-3]: " choice

        case $choice in
            1) add_certificate ;;
            2) list_certificates ;;
            3) delete_certificate ;;
            0) break ;;
            *) print_error "无效选择" ;;
        esac

        read -p "按 Enter 键继续..."
    done
}
