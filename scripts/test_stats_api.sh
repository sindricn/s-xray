#!/bin/bash

# 快速测试 Stats API 的两种查询方式

XRAY_BIN="/usr/local/xray/xray"
API_ADDR="127.0.0.1:10085"
EMAIL="admin@system"

echo "=== 测试 Stats API 查询方式 ==="
echo ""

echo "1. 查询所有统计数据（JSON 格式）："
echo "命令: $XRAY_BIN api statsquery --server=$API_ADDR -pattern \"\""
echo "---"
$XRAY_BIN api statsquery --server=$API_ADDR -pattern "" | grep -A 1 "admin@system" | head -10
echo ""

echo "2. 查询特定用户下行流量（纯文本格式）："
echo "命令: $XRAY_BIN api statsquery --server=$API_ADDR --name \"user>>>$EMAIL>>>traffic>>>downlink\""
echo "---"
$XRAY_BIN api statsquery --server=$API_ADDR --name "user>>>$EMAIL>>>traffic>>>downlink"
echo ""

echo "3. 查询特定用户上行流量（纯文本格式）："
echo "命令: $XRAY_BIN api statsquery --server=$API_ADDR --name \"user>>>$EMAIL>>>traffic>>>uplink\""
echo "---"
$XRAY_BIN api statsquery --server=$API_ADDR --name "user>>>$EMAIL>>>traffic>>>uplink"
echo ""

echo "4. 解析测试："
echo "---"
downlink_raw=$($XRAY_BIN api statsquery --server=$API_ADDR --name "user>>>$EMAIL>>>traffic>>>downlink")
echo "原始输出:"
echo "$downlink_raw"
echo ""

downlink=$(echo "$downlink_raw" | grep "value" | awk '{print $2}' | tr -d '\r')
echo "解析后的值: $downlink"
echo ""

if [[ -n "$downlink" && "$downlink" =~ ^[0-9]+$ ]]; then
    echo "✓ 解析成功: $downlink 字节"
    mb=$(awk "BEGIN {printf \"%.2f\", $downlink/1048576}")
    echo "  等于: $mb MB"
else
    echo "✗ 解析失败"
fi
