#!/bin/bash

#================================================================
# Clash 节点配置诊断脚本
# 用于检查节点数据是否符合 Clash 订阅生成要求
#================================================================

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# 配置路径
NODES_FILE="/usr/local/xray/data/nodes.json"
USERS_FILE="/usr/local/xray/data/users.json"

echo "================================================================"
echo "Clash 节点配置诊断工具"
echo "================================================================"
echo ""

# 检查节点文件是否存在
if [[ ! -f "$NODES_FILE" ]]; then
    echo -e "${RED}✗ 节点文件不存在: $NODES_FILE${NC}"
    echo ""
    echo "请先添加节点后再使用此工具"
    exit 1
fi

echo -e "${GREEN}✓ 节点文件存在${NC}"
echo ""

# 读取节点数据
nodes_count=$(jq -r '.nodes | length' "$NODES_FILE" 2>/dev/null)

if [[ -z "$nodes_count" || "$nodes_count" == "null" ]]; then
    echo -e "${RED}✗ 无法解析节点文件（JSON格式错误）${NC}"
    exit 1
fi

echo -e "${CYAN}节点总数: ${YELLOW}$nodes_count${NC}"
echo ""

if [[ $nodes_count -eq 0 ]]; then
    echo -e "${YELLOW}⚠ 没有找到任何节点${NC}"
    exit 0
fi

# 分析每个节点
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "节点详细信息"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

clash_compatible=0
clash_incompatible=0
needs_password=0

index=1
while IFS= read -r node; do
    [[ -z "$node" || "$node" == "null" ]] && continue

    protocol=$(echo "$node" | jq -r '.protocol')
    port=$(echo "$node" | jq -r '.port')
    security=$(echo "$node" | jq -r '.security // "none"')
    transport=$(echo "$node" | jq -r '.transport // "tcp"')

    echo -e "${CYAN}节点 #$index${NC}"
    echo "  协议: $protocol"
    echo "  端口: $port"
    echo "  安全: $security"
    echo "  传输: $transport"

    # 检查 Clash 兼容性
    if [[ "$protocol" == "vless" && "$security" == "reality" ]]; then
        echo -e "  ${RED}✗ Clash 兼容性: 不支持（Reality 协议）${NC}"
        ((clash_incompatible++))
    else
        echo -e "  ${GREEN}✓ Clash 兼容性: 支持${NC}"
        ((clash_compatible++))

        # 检查是否需要 password
        if [[ "$protocol" == "trojan" || "$protocol" == "shadowsocks" ]]; then
            echo -e "  ${YELLOW}⚠ 需要 password 字段${NC}"
            ((needs_password++))
        fi
    fi

    echo ""
    ((index++))
done < <(jq -c '.nodes[]' "$NODES_FILE" 2>/dev/null)

# 统计信息
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "统计结果"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo -e "${GREEN}Clash 兼容节点: $clash_compatible${NC}"
echo -e "${RED}Clash 不兼容节点: $clash_incompatible${NC}"
echo -e "${YELLOW}需要 password 的节点: $needs_password${NC}"
echo ""

# 检查用户 password
if [[ $needs_password -gt 0 ]]; then
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "用户 Password 检查"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    if [[ ! -f "$USERS_FILE" ]]; then
        echo -e "${RED}✗ 用户文件不存在: $USERS_FILE${NC}"
    else
        users_count=$(jq -r '.users | length' "$USERS_FILE" 2>/dev/null)
        echo "用户总数: $users_count"
        echo ""

        while IFS= read -r user; do
            [[ -z "$user" || "$user" == "null" ]] && continue

            username=$(echo "$user" | jq -r '.username // .email')
            password=$(echo "$user" | jq -r '.password // ""')

            if [[ -n "$password" ]]; then
                echo -e "  ${GREEN}✓${NC} 用户 $username: 有 password"
            else
                echo -e "  ${RED}✗${NC} 用户 $username: 无 password ${YELLOW}(无法使用 Trojan/SS)${NC}"
            fi
        done < <(jq -c '.users[]' "$USERS_FILE" 2>/dev/null)

        echo ""
    fi
fi

# 建议
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "建议"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

if [[ $clash_compatible -eq 0 ]]; then
    echo -e "${RED}✗ 没有 Clash 兼容的节点${NC}"
    echo ""
    echo "建议："
    echo "  1. 添加 VLESS TLS、VMess 或 Trojan 节点"
    echo "  2. Reality 节点不被 Clash 支持，但可以使用通用订阅格式"
elif [[ $clash_incompatible -gt 0 ]]; then
    echo -e "${YELLOW}⚠ 部分节点不兼容 Clash${NC}"
    echo ""
    echo "说明："
    echo "  - Reality 节点会在 Clash 订阅中自动跳过"
    echo "  - 可以正常生成包含其他协议节点的 Clash 订阅"
else
    echo -e "${GREEN}✓ 所有节点都兼容 Clash${NC}"
fi

if [[ $needs_password -gt 0 ]]; then
    echo ""
    echo -e "${YELLOW}⚠ 有 Trojan/SS 节点需要 password${NC}"
    echo ""
    echo "确保用户数据中包含 password 字段："
    echo ""
    echo "  编辑用户文件:"
    echo "  vi $USERS_FILE"
    echo ""
    echo "  添加 password 字段:"
    echo '  {
    "users": [{
      "id": "uuid",
      "username": "admin",
      "password": "your-password-here"
    }]
  }'
fi

echo ""
echo "================================================================"
echo "诊断完成"
echo "================================================================"
