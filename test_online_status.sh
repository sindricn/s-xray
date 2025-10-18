#!/bin/bash

# 测试脚本 - 用户在线状态检测

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
GRAY='\033[0;90m'
NC='\033[0m'

# 全局变量
XRAY_DIR="/usr/local/xray"
DATA_DIR="${XRAY_DIR}/data"
USERS_FILE="${DATA_DIR}/users.json"
NODE_USERS_FILE="${DATA_DIR}/node_users.json"

# 加载用户模块
source /usr/local/bin/modules/user.sh 2>/dev/null || source ./modules/user.sh

echo -e "${CYAN}========== 用户在线状态测试 ==========${NC}"
echo ""

# 测试1: 检查 API 端口
echo -e "${YELLOW}测试 1: 检查 API 端口监听${NC}"
if ss -lnt 2>/dev/null | grep -q ":10085 "; then
    echo -e "${GREEN}✓ API 端口 10085 正在监听${NC}"
else
    echo -e "${RED}✗ API 端口 10085 未监听${NC}"
    echo "请确保 Xray 服务正在运行且配置了 API inbound"
fi
echo ""

# 测试2: 检查 xray 命令
echo -e "${YELLOW}测试 2: 检查 xray 命令${NC}"
if command -v xray &>/dev/null; then
    echo -e "${GREEN}✓ xray 命令可用${NC}"
    xray version | head -1
else
    echo -e "${RED}✗ xray 命令不可用${NC}"
fi
echo ""

# 测试3: 查询所有统计数据
echo -e "${YELLOW}测试 3: 查询所有统计数据${NC}"
echo "执行: xray api statsquery --server=127.0.0.1:10085 --reset=false"
echo ""
xray api statsquery --server=127.0.0.1:10085 --reset=false 2>&1 | head -20
echo ""

# 测试4: 获取第一个用户并测试
if [[ -f "$USERS_FILE" ]]; then
    echo -e "${YELLOW}测试 4: 测试第一个用户的在线状态${NC}"

    first_user=$(jq -r '.users[0]' "$USERS_FILE" 2>/dev/null)
    if [[ -n "$first_user" && "$first_user" != "null" ]]; then
        username=$(echo "$first_user" | jq -r '.username')
        email=$(echo "$first_user" | jq -r '.email')
        uuid=$(echo "$first_user" | jq -r '.id')

        echo "用户名: $username"
        echo "邮箱: $email"
        echo "UUID: $uuid"
        echo ""

        # 获取端口
        echo "获取用户绑定的端口..."
        port=$(get_user_first_port "$uuid")
        if [[ -n "$port" ]]; then
            echo "端口: $port"
        else
            echo "未绑定端口"
        fi
        echo ""

        # 测试流量查询
        echo "查询流量统计..."
        debug_user_traffic "$email"
        echo ""

        # 测试在线状态
        if [[ -n "$port" ]]; then
            echo "检测在线状态..."
            status=$(get_user_online_status "$email" "$port")
            echo "状态: $status"

            case $status in
                online) echo -e "${GREEN}用户在线${NC}" ;;
                offline) echo -e "${YELLOW}用户离线${NC}" ;;
                unknown) echo -e "${GRAY}状态未知${NC}" ;;
                *) echo -e "${RED}未知状态: $status${NC}" ;;
            esac
        fi
    else
        echo "没有用户数据"
    fi
else
    echo "用户文件不存在: $USERS_FILE"
fi

echo ""
echo -e "${CYAN}========================================${NC}"
