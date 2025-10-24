#!/bin/bash

#================================================================
# Admin用户恢复脚本
# 用于重新创建admin用户
#================================================================

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# 全局变量
XRAY_DIR="/usr/local/xray"
DATA_DIR="${XRAY_DIR}/data"
USERS_FILE="${DATA_DIR}/users.json"

# 脚本目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo -e "${CYAN}╔═══════════════════════════════════════╗${NC}"
echo -e "${CYAN}║      Admin用户恢复工具               ║${NC}"
echo -e "${CYAN}╚═══════════════════════════════════════╝${NC}"
echo ""

# 检查用户文件
if [[ ! -f "$USERS_FILE" ]]; then
    echo -e "${YELLOW}用户文件不存在，创建新文件...${NC}"
    mkdir -p "$DATA_DIR"
    echo '{"users":[]}' > "$USERS_FILE"
fi

# 检查admin用户是否存在
admin_exists=$(python3 -c "
import json
import sys

try:
    with open('$USERS_FILE', 'r') as f:
        data = json.load(f)

    for user in data.get('users', []):
        if user.get('username') == 'admin':
            print('exists')
            sys.exit(0)

    print('not_found')
except:
    print('error')
    sys.exit(1)
")

if [[ "$admin_exists" == "exists" ]]; then
    echo -e "${GREEN}Admin用户已存在${NC}"
    echo ""
    python3 -c "
import json

with open('$USERS_FILE', 'r') as f:
    data = json.load(f)

for user in data.get('users', []):
    if user.get('username') == 'admin':
        print(f'  用户名: admin')
        print(f'  UUID: {user.get(\"id\")}')
        print(f'  邮箱: {user.get(\"email\")}')
        print(f'  状态: {\"启用\" if user.get(\"enabled\") else \"禁用\"}')
        break
"
    echo ""
    read -p "是否要重置admin用户? [y/N]: " confirm
    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
        echo "取消操作"
        exit 0
    fi

    # 删除旧的admin用户
    python3 "$SCRIPT_DIR/modules/json_helper.py" delete_user "$USERS_FILE" "admin"
    echo -e "${GREEN}已删除旧的admin用户${NC}"
fi

# 生成新的admin用户
admin_uuid=$(cat /proc/sys/kernel/random/uuid 2>/dev/null || uuidgen 2>/dev/null || python3 -c "import uuid; print(uuid.uuid4())")
admin_password=$(openssl rand -base64 16 | tr -d '/+=' | cut -c1-16)
admin_email="admin@system"

echo ""
echo -e "${YELLOW}正在创建admin用户...${NC}"

if python3 "$SCRIPT_DIR/modules/json_helper.py" add_user "$USERS_FILE" \
    "$admin_uuid" "admin" "$admin_password" "$admin_email" 0 "unlimited" "unlimited"; then

    echo ""
    echo -e "${GREEN}╔═══════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║  Admin用户创建成功！                 ║${NC}"
    echo -e "${GREEN}╚═══════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${CYAN}Admin用户信息：${NC}"
    echo -e "  用户名: ${YELLOW}admin${NC}"
    echo -e "  密码: ${YELLOW}$admin_password${NC}"
    echo -e "  UUID: ${YELLOW}$admin_uuid${NC}"
    echo -e "  邮箱: ${YELLOW}$admin_email${NC}"
    echo ""
    echo -e "${RED}请妥善保存以上信息！${NC}"
    echo ""
else
    echo -e "${RED}创建admin用户失败${NC}"
    exit 1
fi
