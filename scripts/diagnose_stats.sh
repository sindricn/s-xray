#!/bin/bash

#================================================================
# Xray Stats API 诊断脚本
# 用于排查流量统计不工作的问题
#================================================================

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

XRAY_BIN="/usr/local/xray/xray"
XRAY_CONFIG="/usr/local/xray/config.json"
API_ADDR="127.0.0.1:10085"

echo -e "${CYAN}=== Xray Stats API 诊断工具 ===${NC}\n"

# 1. 检查 Xray 是否运行
echo -e "${YELLOW}[1/8] 检查 Xray 服务状态${NC}"
if systemctl is-active --quiet xray; then
    echo -e "${GREEN}✓ Xray 服务正在运行${NC}"
else
    echo -e "${RED}✗ Xray 服务未运行${NC}"
    echo "请先启动 Xray: systemctl start xray"
    exit 1
fi
echo ""

# 2. 检查 API 端口监听
echo -e "${YELLOW}[2/8] 检查 API 端口 10085${NC}"
if ss -lnt 2>/dev/null | grep -q ":10085 " || netstat -lnt 2>/dev/null | grep -q ":10085 "; then
    echo -e "${GREEN}✓ API 端口 10085 正在监听${NC}"
else
    echo -e "${RED}✗ API 端口 10085 未监听${NC}"
    echo "API 配置可能有问题"
    exit 1
fi
echo ""

# 3. 检查配置文件中的 stats 模块
echo -e "${YELLOW}[3/8] 检查配置文件中的 stats 模块${NC}"
if [[ -f "$XRAY_CONFIG" ]]; then
    if jq -e '.stats' "$XRAY_CONFIG" >/dev/null 2>&1; then
        echo -e "${GREEN}✓ stats 模块已启用${NC}"
        jq '.stats' "$XRAY_CONFIG"
    else
        echo -e "${RED}✗ stats 模块未启用${NC}"
        echo "需要在配置中添加 \"stats\": {}"
        exit 1
    fi
else
    echo -e "${RED}✗ 配置文件不存在: $XRAY_CONFIG${NC}"
    exit 1
fi
echo ""

# 4. 检查 API 服务配置
echo -e "${YELLOW}[4/8] 检查 API 服务配置${NC}"
if jq -e '.api.services[] | select(. == "StatsService")' "$XRAY_CONFIG" >/dev/null 2>&1; then
    echo -e "${GREEN}✓ StatsService 已启用${NC}"
    jq '.api' "$XRAY_CONFIG"
else
    echo -e "${RED}✗ StatsService 未启用${NC}"
    echo "需要在 api.services 中添加 \"StatsService\""
    exit 1
fi
echo ""

# 5. 检查 policy 中的统计配置
echo -e "${YELLOW}[5/8] 检查 policy 统计配置${NC}"
if jq -e '.policy.levels."0".statsUserUplink' "$XRAY_CONFIG" >/dev/null 2>&1; then
    echo -e "${GREEN}✓ statsUserUplink 已启用${NC}"
    jq '.policy.levels."0"' "$XRAY_CONFIG"
else
    echo -e "${YELLOW}⚠ statsUserUplink 未启用${NC}"
    echo "建议在 policy.levels.0 中添加统计配置"
fi
echo ""

# 6. 检查 inbound 用户配置（检查前3个用户）
echo -e "${YELLOW}[6/8] 检查 inbound 用户配置${NC}"
echo "检查用户是否有 email 字段..."

user_count=0
inbound_count=$(jq '.inbounds | length' "$XRAY_CONFIG")
echo "总共 $inbound_count 个 inbound"

for ((i=0; i<inbound_count && i<3; i++)); do
    inbound_tag=$(jq -r ".inbounds[$i].tag" "$XRAY_CONFIG")
    inbound_protocol=$(jq -r ".inbounds[$i].protocol" "$XRAY_CONFIG")

    # 跳过 API inbound
    if [[ "$inbound_tag" == "api" ]]; then
        continue
    fi

    echo -e "\n${CYAN}Inbound: $inbound_tag ($inbound_protocol)${NC}"

    clients=$(jq -c ".inbounds[$i].settings.clients // []" "$XRAY_CONFIG")
    client_count=$(echo "$clients" | jq 'length')

    if [[ "$client_count" -gt 0 ]]; then
        for ((j=0; j<client_count && j<3; j++)); do
            email=$(echo "$clients" | jq -r ".[$j].email // \"无\"")
            level=$(echo "$clients" | jq -r ".[$j].level // \"无\"")

            if [[ "$email" != "无" && "$email" != "null" ]]; then
                echo -e "  ${GREEN}✓ 用户 $((j+1)): email=$email, level=$level${NC}"
                ((user_count++))
            else
                echo -e "  ${RED}✗ 用户 $((j+1)): 缺少 email${NC}"
            fi
        done
    else
        echo -e "  ${YELLOW}该 inbound 没有用户${NC}"
    fi
done

if [[ $user_count -eq 0 ]]; then
    echo -e "\n${RED}✗ 没有找到包含 email 的用户${NC}"
    echo "Stats 需要每个用户都有 email 字段"
    exit 1
else
    echo -e "\n${GREEN}✓ 找到 $user_count 个有效用户${NC}"
fi
echo ""

# 7. 测试 Stats API 查询
echo -e "${YELLOW}[7/8] 测试 Stats API 查询${NC}"
if [[ ! -x "$XRAY_BIN" ]]; then
    echo -e "${RED}✗ Xray 二进制文件不存在或不可执行: $XRAY_BIN${NC}"
    exit 1
fi

echo "尝试查询所有统计数据..."
stats_output=$($XRAY_BIN api statsquery --server=$API_ADDR -pattern "" 2>&1 || true)

if [[ -n "$stats_output" ]]; then
    echo -e "${GREEN}✓ Stats API 响应成功${NC}"
    echo ""
    echo "统计数据示例（前20行）:"
    echo "$stats_output" | head -20
    echo ""

    # 检查是否有用户流量数据
    if echo "$stats_output" | grep -q "user>>>.*>>>traffic"; then
        echo -e "${GREEN}✓ 发现用户流量统计${NC}"
        echo ""
        echo "用户流量统计："
        echo "$stats_output" | grep "user>>>.*>>>traffic" | head -10
    else
        echo -e "${RED}✗ 没有发现用户流量统计${NC}"
        echo "可能原因："
        echo "  1. 用户还没有产生任何流量"
        echo "  2. 用户配置缺少 email 字段"
        echo "  3. policy 中的统计未正确启用"
    fi
else
    echo -e "${RED}✗ Stats API 无响应${NC}"
    echo "可能原因："
    echo "  1. API 端口未正确监听"
    echo "  2. StatsService 未启用"
    echo "  3. Xray 版本不支持 stats"
fi
echo ""

# 8. 测试查询特定用户
echo -e "${YELLOW}[8/8] 测试查询特定用户流量${NC}"
# 获取第一个有 email 的用户
first_email=$(jq -r '[.inbounds[].settings.clients[]? | select(.email != null) | .email] | first // ""' "$XRAY_CONFIG")

if [[ -n "$first_email" && "$first_email" != "null" ]]; then
    echo "测试用户: $first_email"

    uplink=$($XRAY_BIN api statsquery --server=$API_ADDR --name "user>>>${first_email}>>>traffic>>>uplink" 2>/dev/null | grep "value" | awk '{print $2}' | tr -d '\r' || echo "0")
    downlink=$($XRAY_BIN api statsquery --server=$API_ADDR --name "user>>>${first_email}>>>traffic>>>downlink" 2>/dev/null | grep "value" | awk '{print $2}' | tr -d '\r' || echo "0")

    uplink=${uplink:-0}
    downlink=${downlink:-0}

    echo "  上行流量: $uplink 字节"
    echo "  下行流量: $downlink 字节"

    if [[ "$uplink" -gt 0 ]] || [[ "$downlink" -gt 0 ]]; then
        echo -e "${GREEN}✓ 该用户有流量记录${NC}"
    else
        echo -e "${YELLOW}⚠ 该用户流量为 0${NC}"
        echo "  如果用户已经连接，可能需要："
        echo "  1. 确认用户确实产生了流量"
        echo "  2. 检查 policy 配置是否正确"
        echo "  3. 重启 Xray 服务使配置生效"
    fi
else
    echo -e "${YELLOW}⚠ 未找到有 email 的用户，跳过测试${NC}"
fi
echo ""

echo -e "${CYAN}=== 诊断完成 ===${NC}"
echo ""
echo -e "${YELLOW}建议：${NC}"
echo "1. 如果所有检查都通过但流量仍为0，尝试重启 Xray: systemctl restart xray"
echo "2. 让用户连接并产生一些流量后再检查"
echo "3. 检查 Xray 日志: journalctl -u xray -n 50"
