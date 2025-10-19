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
echo "执行命令: $XRAY_BIN api statsquery --server=$API_ADDR -pattern \"\""

# 使用临时文件捕获输出和错误
temp_output=$(mktemp)
temp_error=$(mktemp)

set +e  # 临时关闭错误退出
$XRAY_BIN api statsquery --server=$API_ADDR -pattern "" > "$temp_output" 2> "$temp_error"
stats_exit_code=$?
set -e  # 恢复错误退出

stats_output=$(cat "$temp_output")
stats_error=$(cat "$temp_error")
rm -f "$temp_output" "$temp_error"

echo "命令退出码: $stats_exit_code"

if [[ $stats_exit_code -ne 0 ]]; then
    echo -e "${RED}✗ Stats API 查询失败${NC}"
    if [[ -n "$stats_error" ]]; then
        echo "错误信息："
        echo "$stats_error"
    fi
fi

if [[ -n "$stats_output" ]]; then
    echo -e "${GREEN}✓ Stats API 有响应${NC}"

    # 统计行数
    line_count=$(echo "$stats_output" | wc -l)
    echo "返回了 $line_count 行数据"
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
        echo -e "${YELLOW}⚠ 没有发现用户流量统计${NC}"
        echo "可能原因："
        echo "  1. 用户还没有产生任何流量（最常见）"
        echo "  2. 用户配置缺少 email 字段"
        echo "  3. policy 中的统计未正确启用"
        echo ""
        echo "建议："
        echo "  - 让用户连接节点并产生一些流量"
        echo "  - 然后重新运行此诊断脚本"
    fi
else
    echo -e "${YELLOW}⚠ Stats API 返回空数据${NC}"
    echo "这通常表示："
    echo "  1. Xray 刚启动，还没有任何统计数据"
    echo "  2. 用户还没有连接或产生流量"
    echo ""
    echo "这是正常的！请让用户连接并使用一段时间后再检查。"
fi
echo ""

# 8. 测试查询特定用户
echo -e "${YELLOW}[8/8] 测试查询特定用户流量${NC}"
# 获取第一个有 email 的用户
first_email=$(jq -r '[.inbounds[].settings.clients[]? | select(.email != null) | .email] | first // ""' "$XRAY_CONFIG" 2>/dev/null)

if [[ -n "$first_email" && "$first_email" != "null" && "$first_email" != "" ]]; then
    echo "测试用户: $first_email"
    echo "查询命令: $XRAY_BIN api statsquery --server=$API_ADDR --name \"user>>>${first_email}>>>traffic>>>uplink\""

    set +e  # 临时关闭错误退出

    # 查询上行流量
    uplink_raw=$($XRAY_BIN api statsquery --server=$API_ADDR --name "user>>>${first_email}>>>traffic>>>uplink" 2>/dev/null)
    uplink=$(echo "$uplink_raw" | grep "value" | awk '{print $2}' | tr -d '\r' | head -1)
    uplink=${uplink:-0}
    [[ ! "$uplink" =~ ^[0-9]+$ ]] && uplink=0

    # 查询下行流量
    downlink_raw=$($XRAY_BIN api statsquery --server=$API_ADDR --name "user>>>${first_email}>>>traffic>>>downlink" 2>/dev/null)
    downlink=$(echo "$downlink_raw" | grep "value" | awk '{print $2}' | tr -d '\r' | head -1)
    downlink=${downlink:-0}
    [[ ! "$downlink" =~ ^[0-9]+$ ]] && downlink=0

    set -e  # 恢复错误退出

    echo "  API 原始响应（uplink）:"
    if [[ -n "$uplink_raw" ]]; then
        echo "$uplink_raw" | head -3
    else
        echo "    (无响应)"
    fi

    echo ""
    echo "  解析结果："
    echo "    上行流量: $uplink 字节 ($(awk "BEGIN {printf \"%.2f\", $uplink/1048576}") MB)"
    echo "    下行流量: $downlink 字节 ($(awk "BEGIN {printf \"%.2f\", $downlink/1048576}") MB)"
    echo ""

    if [[ "$uplink" -gt 0 ]] || [[ "$downlink" -gt 0 ]]; then
        echo -e "${GREEN}✓ 该用户有流量记录${NC}"
        echo -e "${GREEN}  Stats API 工作正常！${NC}"
    else
        echo -e "${YELLOW}⚠ 该用户流量为 0${NC}"
        echo ""
        echo "  可能的原因："
        echo "  1. 用户还没有连接并产生流量（最常见原因）"
        echo "  2. Xray 刚重启，统计数据被清空"
        echo "  3. 用户连接了但没有实际传输数据"
        echo ""
        echo "  建议操作："
        echo "  1. 使用该用户的订阅链接连接节点"
        echo "  2. 打开网页或进行一些网络活动"
        echo "  3. 等待 10-30 秒后重新运行此诊断脚本"
        echo "  4. 如果仍然为 0，可能需要检查客户端配置或重启 Xray"
    fi
else
    echo -e "${YELLOW}⚠ 未找到有 email 的用户，跳过测试${NC}"
    echo "请先添加用户或检查用户配置中的 email 字段"
fi
echo ""

echo -e "${CYAN}=== 诊断完成 ===${NC}"
echo ""
echo -e "${YELLOW}建议：${NC}"
echo "1. 如果所有检查都通过但流量仍为0，尝试重启 Xray: systemctl restart xray"
echo "2. 让用户连接并产生一些流量后再检查"
echo "3. 检查 Xray 日志: journalctl -u xray -n 50"
