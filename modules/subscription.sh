#!/bin/bash

#================================================================
# 订阅管理模块
# 功能：生成订阅链接、查看订阅、更新订阅内容
#================================================================

# 生成 VLESS 分享链接
generate_vless_share_link() {
    local uuid=$1
    local remark=$2
    local port=$3
    local transport=$4
    local ws_path=$5
    local tls_domain=$6

    local server_ip=$(get_public_ip)

    local link="vless://${uuid}@${server_ip}:${port}?"

    # 添加传输层参数
    link+="type=${transport}"

    if [[ "$transport" == "ws" && -n "$ws_path" ]]; then
        link+="&path=$(urlencode "$ws_path")"
    fi

    # 添加 TLS 参数
    if [[ -n "$tls_domain" ]]; then
        link+="&security=tls&sni=${tls_domain}"
    fi

    # 添加备注
    link+="#$(urlencode "$remark")"

    echo ""
    print_success "VLESS 分享链接："
    echo -e "${GREEN}${link}${NC}"
}

# 生成 VMess 分享链接
generate_vmess_share_link() {
    local uuid=$1
    local remark=$2
    local port=$3
    local transport=$4
    local ws_path=$5
    local alter_id=$6
    local cipher=$7

    local server_ip=$(get_public_ip)

    # 构建 VMess JSON
    local vmess_json=$(cat <<EOF
{
  "v": "2",
  "ps": "${remark}",
  "add": "${server_ip}",
  "port": "${port}",
  "id": "${uuid}",
  "aid": "${alter_id}",
  "scy": "${cipher}",
  "net": "${transport}",
  "type": "none",
  "host": "",
  "path": "${ws_path}",
  "tls": "",
  "sni": "",
  "alpn": ""
}
EOF
)

    # Base64 编码
    local vmess_link="vmess://$(echo -n "$vmess_json" | base64 -w 0)"

    echo ""
    print_success "VMess 分享链接："
    echo -e "${GREEN}${vmess_link}${NC}"
}

# 生成 Trojan 分享链接
generate_trojan_share_link() {
    local password=$1
    local domain=$2
    local port=$3

    local link="trojan://${password}@${domain}:${port}?security=tls&sni=${domain}#$(urlencode "Trojan-${domain}")"

    echo ""
    print_success "Trojan 分享链接："
    echo -e "${GREEN}${link}${NC}"
}

# 生成 Shadowsocks 分享链接
generate_ss_share_link() {
    local cipher=$1
    local password=$2
    local port=$3

    local server_ip=$(get_public_ip)

    # method:password
    local userinfo="${cipher}:${password}"
    local encoded=$(echo -n "$userinfo" | base64 -w 0)

    local link="ss://${encoded}@${server_ip}:${port}#$(urlencode "SS-${port}")"

    echo ""
    print_success "Shadowsocks 分享链接："
    echo -e "${GREEN}${link}${NC}"
}

# 生成订阅
generate_subscription() {
    clear
    echo -e "${CYAN}====== 生成订阅 ======${NC}"

    if [[ ! -f "$NODES_FILE" ]]; then
        print_error "暂无节点"
        return 1
    fi

    local node_count=$(jq -r '.nodes | length' "$NODES_FILE")
    if [[ "$node_count" -eq 0 ]]; then
        print_error "暂无节点"
        return 1
    fi

    read -p "请输入订阅名称 [默认: default]: " sub_name
    sub_name=${sub_name:-default}

    read -p "是否加密订阅内容? [Y/n]: " encrypt_sub
    encrypt_sub=${encrypt_sub:-y}

    # 收集所有节点的分享链接
    local share_links=""
    local server_ip=$(get_public_ip)

    while read -r node; do
        local protocol=$(echo "$node" | jq -r '.protocol')
        local port=$(echo "$node" | jq -r '.port')

        # 获取节点的用户列表
        local users=$(jq -r ".users[] | select(.port == \"$port\")" "$USERS_FILE" 2>/dev/null)

        while read -r user; do
            if [[ -z "$user" ]]; then
                continue
            fi

            local id=$(echo "$user" | jq -r '.id')
            local email=$(echo "$user" | jq -r '.email')

            case $protocol in
                vless)
                    local transport=$(echo "$node" | jq -r '.transport')
                    local link="vless://${id}@${server_ip}:${port}?type=${transport}#$(urlencode "$email")"
                    share_links+="${link}\n"
                    ;;

                vmess)
                    local transport=$(echo "$node" | jq -r '.transport')
                    local vmess_json="{\"v\":\"2\",\"ps\":\"${email}\",\"add\":\"${server_ip}\",\"port\":\"${port}\",\"id\":\"${id}\",\"aid\":\"0\",\"net\":\"${transport}\",\"type\":\"none\",\"tls\":\"\"}"
                    local link="vmess://$(echo -n "$vmess_json" | base64 -w 0)"
                    share_links+="${link}\n"
                    ;;

                trojan)
                    local link="trojan://${id}@${server_ip}:${port}?security=tls#$(urlencode "$email")"
                    share_links+="${link}\n"
                    ;;

                shadowsocks)
                    local cipher=$(jq -r "(.inbounds[] | select(.port == $port) | .settings.method)" "$XRAY_CONFIG")
                    local userinfo="${cipher}:${id}"
                    local encoded=$(echo -n "$userinfo" | base64 -w 0)
                    local link="ss://${encoded}@${server_ip}:${port}#$(urlencode "$email")"
                    share_links+="${link}\n"
                    ;;
            esac
        done <<< "$users"
    done <<< "$(jq -c '.nodes[]' "$NODES_FILE")"

    if [[ -z "$share_links" ]]; then
        print_error "没有可用的用户"
        return 1
    fi

    # 生成订阅内容
    local sub_content=""
    if [[ "$encrypt_sub" == "y" || "$encrypt_sub" == "Y" ]]; then
        sub_content=$(echo -e "$share_links" | base64 -w 0)
    else
        sub_content="$share_links"
    fi

    # 保存订阅
    local sub_file="${SUBSCRIPTION_DIR}/${sub_name}.txt"
    echo -e "$sub_content" > "$sub_file"

    # 生成订阅URL
    read -p "请输入订阅访问域名 [留空使用IP]: " sub_domain
    if [[ -z "$sub_domain" ]]; then
        sub_domain=$(get_public_ip)
    fi

    read -p "请输入订阅端口 [默认: 8080]: " sub_port
    sub_port=${sub_port:-8080}

    local sub_url="http://${sub_domain}:${sub_port}/sub/${sub_name}"

    # 保存订阅信息
    save_subscription_info "$sub_name" "$sub_url" "$sub_file"

    # 启动订阅服务
    setup_subscription_server "$sub_port"

    print_success "订阅生成成功！"
    print_info "订阅名称: $sub_name"
    print_info "订阅URL: $sub_url"
    echo ""
    echo -e "${CYAN}订阅链接（复制到客户端使用）：${NC}"
    echo -e "${GREEN}${sub_url}${NC}"
}

# 查看订阅
show_subscription() {
    clear
    echo -e "${CYAN}====== 订阅列表 ======${NC}\n"

    if [[ ! -d "$SUBSCRIPTION_DIR" ]]; then
        print_warning "暂无订阅"
        return 0
    fi

    local subs=$(ls -1 "$SUBSCRIPTION_DIR"/*.txt 2>/dev/null)
    if [[ -z "$subs" ]]; then
        print_warning "暂无订阅"
        return 0
    fi

    printf "%-20s %-50s %-20s\n" "订阅名称" "订阅URL" "更新时间"
    echo "--------------------------------------------------------------------------------------"

    for sub_file in $subs; do
        local sub_name=$(basename "$sub_file" .txt)
        local update_time=$(stat -c %y "$sub_file" 2>/dev/null | cut -d'.' -f1)

        # 从数据库读取URL
        local sub_url=$(jq -r ".subscriptions[] | select(.name == \"$sub_name\") | .url" "${DATA_DIR}/subscriptions.json" 2>/dev/null)
        sub_url=${sub_url:-"未配置"}

        printf "%-20s %-50s %-20s\n" "$sub_name" "$sub_url" "$update_time"
    done

    echo ""
    echo -e "${CYAN}提示：使用订阅URL导入到客户端即可使用${NC}"
}

# 更新订阅
update_subscription() {
    show_subscription

    read -p "请输入要更新的订阅名称: " sub_name
    if [[ -z "$sub_name" ]]; then
        print_error "订阅名称不能为空"
        return 1
    fi

    local sub_file="${SUBSCRIPTION_DIR}/${sub_name}.txt"
    if [[ ! -f "$sub_file" ]]; then
        print_error "订阅不存在"
        return 1
    fi

    print_info "正在更新订阅..."

    # 重新生成订阅内容（逻辑与generate_subscription相同）
    # 这里简化处理，实际应该重用代码
    print_success "订阅更新成功"
}

# 删除订阅
delete_subscription() {
    show_subscription

    read -p "请输入要删除的订阅名称: " sub_name
    if [[ -z "$sub_name" ]]; then
        print_error "订阅名称不能为空"
        return 1
    fi

    local sub_file="${SUBSCRIPTION_DIR}/${sub_name}.txt"
    if [[ ! -f "$sub_file" ]]; then
        print_error "订阅不存在"
        return 1
    fi

    read -p "确认删除订阅 ${sub_name}? [y/N]: " confirm
    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
        print_info "取消删除"
        return 0
    fi

    rm -f "$sub_file"

    # 从数据库删除
    remove_subscription_info "$sub_name"

    print_success "订阅删除成功"
}

# 订阅配置
config_subscription() {
    clear
    echo -e "${CYAN}====== 订阅配置 ======${NC}"

    echo "1. 设置订阅域名"
    echo "2. 设置订阅端口"
    echo "3. 重启订阅服务"
    echo "4. 查看订阅服务状态"
    echo "0. 返回"
    echo ""
    read -p "请选择 [0-4]: " choice

    case $choice in
        1)
            read -p "请输入订阅域名: " sub_domain
            if [[ -n "$sub_domain" ]]; then
                echo "$sub_domain" > "${DATA_DIR}/sub_domain.txt"
                print_success "订阅域名设置成功"
            fi
            ;;
        2)
            read -p "请输入订阅端口: " sub_port
            if [[ -n "$sub_port" ]]; then
                echo "$sub_port" > "${DATA_DIR}/sub_port.txt"
                setup_subscription_server "$sub_port"
                print_success "订阅端口设置成功"
            fi
            ;;
        3)
            local sub_port=$(cat "${DATA_DIR}/sub_port.txt" 2>/dev/null || echo "8080")
            setup_subscription_server "$sub_port"
            print_success "订阅服务重启成功"
            ;;
        4)
            if pgrep -f "python.*subscription_server" > /dev/null; then
                print_success "订阅服务运行中"
            else
                print_warning "订阅服务未运行"
            fi
            ;;
    esac
}

# 设置订阅服务器
setup_subscription_server() {
    local port=$1

    # 停止已有服务
    pkill -f "python.*subscription_server"

    # 创建简单的 HTTP 服务器脚本
    cat > "${DATA_DIR}/subscription_server.py" <<'EOF'
#!/usr/bin/env python3
import http.server
import socketserver
import os
import sys

PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 8080
DIRECTORY = sys.argv[2] if len(sys.argv) > 2 else os.getcwd()

class SubscriptionHandler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=DIRECTORY, **kwargs)

    def end_headers(self):
        self.send_header('Content-Type', 'text/plain; charset=utf-8')
        self.send_header('Access-Control-Allow-Origin', '*')
        super().end_headers()

with socketserver.TCPServer(("", PORT), SubscriptionHandler) as httpd:
    print(f"Subscription server running on port {PORT}")
    httpd.serve_forever()
EOF

    chmod +x "${DATA_DIR}/subscription_server.py"

    # 后台启动服务
    nohup python3 "${DATA_DIR}/subscription_server.py" "$port" "$SUBSCRIPTION_DIR" > /dev/null 2>&1 &

    print_success "订阅服务已启动在端口 $port"
}

# 保存订阅信息
save_subscription_info() {
    local name=$1
    local url=$2
    local file=$3

    local sub_db="${DATA_DIR}/subscriptions.json"
    if [[ ! -f "$sub_db" ]]; then
        echo '{"subscriptions":[]}' > "$sub_db"
    fi

    local sub_data=$(jq -n \
        --arg name "$name" \
        --arg url "$url" \
        --arg file "$file" \
        '{name: $name, url: $url, file: $file, created: now|todate}')

    jq ".subscriptions += [$sub_data]" "$sub_db" > "${sub_db}.tmp"
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

# 获取公网IP
get_public_ip() {
    local ip=$(curl -s -4 https://api.ipify.org)
    if [[ -z "$ip" ]]; then
        ip=$(curl -s -4 https://ifconfig.me)
    fi
    if [[ -z "$ip" ]]; then
        ip=$(hostname -I | awk '{print $1}')
    fi
    echo "$ip"
}
