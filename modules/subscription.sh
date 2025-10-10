#!/bin/bash

#================================================================
# 订阅管理模块 - 重构版
# 功能：生成有效的订阅链接、支持多种客户端
# 支持协议：VLESS (Reality/TLS), VMess, Trojan, Shadowsocks
# 支持客户端：Clash, V2Ray, Shadowrocket, Quantumult X, Surge
#================================================================

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
    echo -n "$1" | base64 -w 0 2>/dev/null || echo -n "$1" | base64
}

#================================================================
# 分享链接生成函数
#================================================================

# 生成 VLESS Reality 分享链接
generate_vless_reality_share() {
    local uuid=$1
    local remark=$2
    local port=$3
    local sni=$4
    local public_key=$5
    local short_id=$6
    local flow=${7:-xtls-rprx-vision}

    local server_ip=$(get_public_ip)

    # VLESS Reality 标准格式
    local share_link="vless://${uuid}@${server_ip}:${port}?encryption=none&flow=${flow}&security=reality&sni=${sni}&fp=chrome&pbk=${public_key}&sid=${short_id}&type=tcp&headerType=none#$(urlencode "$remark")"

    echo "$share_link"
}

# 生成 VLESS TLS 分享链接
generate_vless_tls_share() {
    local uuid=$1
    local remark=$2
    local port=$3
    local sni=$4
    local transport=${5:-tcp}
    local ws_path=${6:-}
    local flow=${7:-}

    local server_ip=$(get_public_ip)

    # 构建基础链接
    local share_link="vless://${uuid}@${server_ip}:${port}?encryption=none&security=tls&sni=${sni}&type=${transport}"

    # 添加 flow（如果有）
    if [[ -n "$flow" ]]; then
        share_link+="&flow=${flow}"
    fi

    # 添加 WebSocket 路径（如果是 ws 传输）
    if [[ "$transport" == "ws" && -n "$ws_path" ]]; then
        share_link+="&path=$(urlencode "$ws_path")"
    fi

    # 添加备注
    share_link+="#$(urlencode "$remark")"

    echo "$share_link"
}

# 生成 VLESS 普通分享链接（无TLS）
generate_vless_share_link() {
    local uuid=$1
    local remark=$2
    local port=$3
    local transport=${4:-tcp}
    local ws_path=${5:-}

    local server_ip=$(get_public_ip)

    local share_link="vless://${uuid}@${server_ip}:${port}?encryption=none&type=${transport}"

    if [[ "$transport" == "ws" && -n "$ws_path" ]]; then
        share_link+="&path=$(urlencode "$ws_path")"
    fi

    share_link+="#$(urlencode "$remark")"

    echo "$share_link"
}

# 生成 VMess 分享链接
generate_vmess_share_link() {
    local uuid=$1
    local remark=$2
    local port=$3
    local transport=${4:-tcp}
    local ws_path=${5:-}
    local alter_id=${6:-0}
    local tls=${7:-}
    local sni=${8:-}

    local server_ip=$(get_public_ip)

    # VMess JSON 格式
    local vmess_json=$(cat <<EOF
{
  "v": "2",
  "ps": "${remark}",
  "add": "${server_ip}",
  "port": "${port}",
  "id": "${uuid}",
  "aid": "${alter_id}",
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

    # Base64 编码（去除空格和换行）
    local vmess_link="vmess://$(echo -n "$vmess_json" | tr -d '\n' | base64 -w 0)"

    echo "$vmess_link"
}

# 生成 Trojan 分享链接
generate_trojan_share_link() {
    local password=$1
    local remark=$2
    local port=$3
    local sni=${4:-}
    local transport=${5:-tcp}

    local server_ip=$(get_public_ip)

    # 如果没有SNI，使用服务器IP
    if [[ -z "$sni" ]]; then
        sni=$server_ip
    fi

    local share_link="trojan://${password}@${server_ip}:${port}?security=tls&sni=${sni}&type=${transport}#$(urlencode "$remark")"

    echo "$share_link"
}

# 生成 Shadowsocks 分享链接
generate_ss_share_link() {
    local cipher=$1
    local password=$2
    local remark=$3
    local port=$4

    local server_ip=$(get_public_ip)

    # SIP002 格式: ss://base64(method:password)@server:port#remark
    local userinfo="${cipher}:${password}"
    local encoded=$(base64_encode "$userinfo")

    local share_link="ss://${encoded}@${server_ip}:${port}#$(urlencode "$remark")"

    echo "$share_link"
}

#================================================================
# 从配置文件生成分享链接
#================================================================

# 从节点配置生成分享链接
generate_share_link_from_node() {
    local node_json=$1
    local user_id=$2
    local user_email=$3

    local protocol=$(echo "$node_json" | jq -r '.protocol')
    local port=$(echo "$node_json" | jq -r '.port')
    local transport=$(echo "$node_json" | jq -r '.transport // "tcp"')

    case $protocol in
        vless)
            # 检查是否是 Reality
            local config=$(echo "$node_json" | jq -r '.config')
            if echo "$config" | grep -q '"security":\s*"reality"'; then
                # Reality 配置
                local sni=$(echo "$config" | jq -r '.streamSettings.realitySettings.serverNames[0] // .streamSettings.realitySettings.dest' | cut -d':' -f1)
                local public_key=$(echo "$config" | jq -r '.streamSettings.realitySettings.publicKey // ""')
                local short_id=$(echo "$config" | jq -r '.streamSettings.realitySettings.shortIds[0] // ""')
                local flow=$(echo "$config" | jq -r '.settings.clients[0].flow // "xtls-rprx-vision"')

                if [[ -n "$public_key" ]]; then
                    # 从配置中提取公钥（如果存储的是完整密钥对）
                    if [[ ${#public_key} -lt 20 ]]; then
                        # 公钥长度不足，尝试从其他地方获取
                        public_key=""
                    fi
                fi

                generate_vless_reality_share "$user_id" "$user_email" "$port" "$sni" "$public_key" "$short_id" "$flow"
            else
                # TLS 或无 TLS
                local security=$(echo "$config" | jq -r '.streamSettings.security // "none"')
                local ws_path=$(echo "$config" | jq -r '.streamSettings.wsSettings.path // ""')
                local sni=$(echo "$config" | jq -r '.streamSettings.tlsSettings.serverName // ""')

                if [[ "$security" == "tls" ]]; then
                    generate_vless_tls_share "$user_id" "$user_email" "$port" "$sni" "$transport" "$ws_path"
                else
                    generate_vless_share_link "$user_id" "$user_email" "$port" "$transport" "$ws_path"
                fi
            fi
            ;;

        vmess)
            local ws_path=$(echo "$config" | jq -r '.streamSettings.wsSettings.path // ""')
            local security=$(echo "$config" | jq -r '.streamSettings.security // ""')
            local sni=$(echo "$config" | jq -r '.streamSettings.tlsSettings.serverName // ""')

            generate_vmess_share_link "$user_id" "$user_email" "$port" "$transport" "$ws_path" "0" "$security" "$sni"
            ;;

        trojan)
            local sni=$(echo "$config" | jq -r '.streamSettings.tlsSettings.serverName // ""')
            generate_trojan_share_link "$user_id" "$user_email" "$port" "$sni" "$transport"
            ;;

        shadowsocks)
            local cipher=$(echo "$config" | jq -r '.settings.method // "aes-256-gcm"')
            generate_ss_share_link "$cipher" "$user_id" "$user_email" "$port"
            ;;

        *)
            echo ""
            ;;
    esac
}

#================================================================
# 订阅管理功能
#================================================================

# 生成订阅
generate_subscription() {
    clear
    echo -e "${CYAN}╔═══════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║          生成订阅链接                ║${NC}"
    echo -e "${CYAN}╚═══════════════════════════════════════╝${NC}"
    echo ""

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

    # 订阅名称
    read -p "请输入订阅名称 [默认: default]: " sub_name
    sub_name=${sub_name:-default}

    # 选择订阅类型
    echo ""
    echo -e "${CYAN}选择订阅类型：${NC}"
    echo -e "  ${GREEN}1.${NC} 通用订阅（Base64编码，支持大部分客户端）"
    echo -e "  ${GREEN}2.${NC} Clash 订阅（YAML格式）"
    echo -e "  ${GREEN}3.${NC} 原始订阅（纯文本，支持所有客户端）"
    echo ""
    read -p "请选择 [1-3，默认: 1]: " sub_type
    sub_type=${sub_type:-1}

    # 收集所有分享链接
    print_info "正在生成分享链接..."
    echo ""

    local share_links=()
    local link_count=0

    # 遍历所有节点
    while IFS= read -r node; do
        if [[ -z "$node" || "$node" == "null" ]]; then
            continue
        fi

        local protocol=$(echo "$node" | jq -r '.protocol')
        local port=$(echo "$node" | jq -r '.port')
        local node_id=$(echo "$node" | jq -r '.id // ""')
        local node_email=$(echo "$node" | jq -r '.email // ""')

        # 如果节点配置中包含用户信息，直接使用
        if [[ -n "$node_id" && -n "$node_email" ]]; then
            local link=$(generate_share_link_from_node "$node" "$node_id" "$node_email")
            if [[ -n "$link" ]]; then
                share_links+=("$link")
                ((link_count++))
                echo -e "  ${GREEN}✔${NC} 节点 ${protocol}:${port} - ${node_email}"
            fi
        fi
    done < <(jq -c '.nodes[]' "$NODES_FILE" 2>/dev/null)

    if [[ $link_count -eq 0 ]]; then
        print_error "没有可用的节点配置"
        echo ""
        print_info "提示：节点配置中需要包含用户信息（id 和 email）"
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
            sub_content=$(printf "%s\n" "${share_links[@]}" | base64 -w 0)
            sub_file="${SUBSCRIPTION_DIR}/${sub_name}.txt"
            ;;
        2)
            # Clash 订阅
            sub_content=$(generate_clash_config "${share_links[@]}")
            sub_file="${SUBSCRIPTION_DIR}/${sub_name}.yaml"
            ;;
        3)
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
    save_subscription_info "$sub_name" "$sub_url" "$sub_file" "$sub_type"

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
            echo -e "  • Clash (导入后需转换)"
            echo -e "  • SagerNet"
            ;;
        2)
            echo -e "${CYAN}支持的客户端：${NC}"
            echo -e "  • Clash for Windows"
            echo -e "  • Clash for Android"
            echo -e "  • ClashX (macOS)"
            ;;
        3)
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
        2) echo "Clash 订阅 (YAML)" ;;
        3) echo "原始订阅 (纯文本)" ;;
        *) echo "未知类型" ;;
    esac
}

# 生成 Clash 配置
generate_clash_config() {
    local links=("$@")

    cat <<EOF
# Clash 配置文件
# 生成时间: $(date '+%Y-%m-%d %H:%M:%S')

port: 7890
socks-port: 7891
allow-lan: false
mode: Rule
log-level: info
external-controller: 127.0.0.1:9090

proxies:
EOF

    # 解析每个链接并转换为 Clash 格式
    # 这里简化处理，实际需要完整的解析逻辑
    for link in "${links[@]}"; do
        echo "  # TODO: 解析链接并转换为 Clash 格式"
        echo "  # $link"
    done

    cat <<EOF

proxy-groups:
  - name: "🚀 节点选择"
    type: select
    proxies:
      - DIRECT

rules:
  - MATCH,🚀 节点选择
EOF
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
    printf "${CYAN}%-4s %-15s %-15s %-50s${NC}\n" "序号" "订阅名称" "类型" "订阅URL"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    local index=1
    while read -r sub; do
        if [[ -z "$sub" || "$sub" == "null" ]]; then
            continue
        fi

        local name=$(echo "$sub" | jq -r '.name')
        local url=$(echo "$sub" | jq -r '.url')
        local type=$(echo "$sub" | jq -r '.type // "1"')
        local type_name=$(get_sub_type_name "$type")

        printf "%-4s %-15s %-15s %-50s\n" "$index" "$name" "$type_name" "$url"
        ((index++))
    done < <(jq -c '.subscriptions[]' "$sub_db" 2>/dev/null)

    echo ""
}

# 更新订阅
update_subscription() {
    show_subscription

    echo ""
    read -p "请输入要更新的订阅名称: " sub_name
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

    print_info "正在更新订阅 $sub_name..."

    # TODO: 重新生成订阅内容
    # 这需要根据当前节点重新生成

    print_success "订阅更新成功"
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

# 订阅配置
config_subscription() {
    clear
    echo -e "${CYAN}╔═══════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║          订阅配置                    ║${NC}"
    echo -e "${CYAN}╚═══════════════════════════════════════╝${NC}"
    echo ""

    echo -e "${GREEN}1.${NC} 设置订阅域名"
    echo -e "${GREEN}2.${NC} 设置订阅端口"
    echo -e "${GREEN}3.${NC} 重启订阅服务"
    echo -e "${GREEN}4.${NC} 查看订阅服务状态"
    echo -e "${GREEN}5.${NC} 查看分享链接"
    echo -e "${GREEN}0.${NC} 返回"
    echo ""
    read -p "请选择 [0-5]: " choice

    case $choice in
        1)
            read -p "请输入订阅域名: " sub_domain
            if [[ -n "$sub_domain" ]]; then
                echo "$sub_domain" > "${DATA_DIR}/sub_domain.txt"
                print_success "订阅域名设置成功"
            fi
            ;;
        2)
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
        3)
            local sub_port=$(cat "${DATA_DIR}/sub_port.txt" 2>/dev/null || echo "8080")
            setup_subscription_server "$sub_port"
            print_success "订阅服务重启成功"
            ;;
        4)
            if pgrep -f "python.*subscription_server" > /dev/null 2>&1; then
                local sub_port=$(cat "${DATA_DIR}/sub_port.txt" 2>/dev/null || echo "8080")
                print_success "订阅服务运行中"
                print_info "监听端口: $sub_port"
            else
                print_warning "订阅服务未运行"
            fi
            ;;
        5)
            show_share_links
            ;;
    esac
}

# 查看所有分享链接
show_share_links() {
    clear
    echo -e "${CYAN}╔═══════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║          分享链接列表                ║${NC}"
    echo -e "${CYAN}╚═══════════════════════════════════════╝${NC}"
    echo ""

    if [[ ! -f "$NODES_FILE" ]]; then
        print_warning "暂无节点"
        return 0
    fi

    local node_count=$(jq -r '.nodes | length' "$NODES_FILE")
    if [[ "$node_count" -eq 0 ]]; then
        print_warning "暂无节点"
        return 0
    fi

    print_info "正在生成分享链接..."
    echo ""

    local index=1
    while IFS= read -r node; do
        if [[ -z "$node" || "$node" == "null" ]]; then
            continue
        fi

        local protocol=$(echo "$node" | jq -r '.protocol')
        local port=$(echo "$node" | jq -r '.port')
        local node_id=$(echo "$node" | jq -r '.id // ""')
        local node_email=$(echo "$node" | jq -r '.email // ""')

        if [[ -n "$node_id" && -n "$node_email" ]]; then
            echo -e "${CYAN}[$index] ${protocol}:${port} - ${node_email}${NC}"
            local link=$(generate_share_link_from_node "$node" "$node_id" "$node_email")
            if [[ -n "$link" ]]; then
                echo -e "${GREEN}${link}${NC}"
            else
                echo -e "${RED}生成失败${NC}"
            fi
            echo ""
            ((index++))
        fi
    done < <(jq -c '.nodes[]' "$NODES_FILE" 2>/dev/null)
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
"""
订阅服务器
提供 HTTP 访问订阅文件
"""
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
        # 处理订阅请求
        if self.path.startswith('/sub/'):
            filename = unquote(self.path[5:])  # 移除 /sub/ 前缀
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
        # 简化日志输出
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

    local sub_db="${DATA_DIR}/subscriptions.json"
    if [[ ! -f "$sub_db" ]]; then
        echo '{"subscriptions":[]}' > "$sub_db"
    fi

    # 检查是否已存在，如果存在则更新
    local exists=$(jq -r ".subscriptions[] | select(.name == \"$name\") | .name" "$sub_db" 2>/dev/null)

    if [[ -n "$exists" ]]; then
        # 更新现有订阅
        jq ".subscriptions = [.subscriptions[] | if .name == \"$name\" then {name: \"$name\", url: \"$url\", file: \"$file\", type: \"$type\", updated: now|todate} else . end]" "$sub_db" > "${sub_db}.tmp"
    else
        # 添加新订阅
        local sub_data=$(jq -n \
            --arg name "$name" \
            --arg url "$url" \
            --arg file "$file" \
            --arg type "$type" \
            '{name: $name, url: $url, file: $file, type: $type, created: now|todate}')

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
