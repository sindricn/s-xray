#!/bin/bash

# 简单的 API 调试脚本

echo "========== Xray Stats API 调试 =========="
echo ""

# 1. 检查 API 端口
echo "1. 检查 API 端口 10085"
if ss -lnt 2>/dev/null | grep -q ":10085 "; then
    echo "✓ API 端口正在监听"
    ss -lnt | grep ":10085"
else
    echo "✗ API 端口未监听"
fi
echo ""

# 2. 检查 xray 二进制
echo "2. 检查 xray 二进制文件"
XRAY_BIN="/usr/local/xray/xray"
if [[ -x "$XRAY_BIN" ]]; then
    echo "✓ xray 可执行: $XRAY_BIN"
    $XRAY_BIN version | head -1
else
    echo "✗ xray 不可执行: $XRAY_BIN"
fi
echo ""

# 3. 测试 API 查询
echo "3. 测试 Stats API 查询"
echo "执行: $XRAY_BIN api statsquery --server=127.0.0.1:10085 --reset=false"
echo ""
OUTPUT=$($XRAY_BIN api statsquery --server=127.0.0.1:10085 --reset=false 2>&1)
if [[ -n "$OUTPUT" ]]; then
    echo "API 返回:"
    echo "$OUTPUT" | head -30
else
    echo "✗ API 无返回数据"
fi
echo ""

# 4. 解析测试
echo "4. 测试流量值解析"
if [[ -n "$OUTPUT" ]]; then
    # 获取第一个用户统计
    FIRST_STAT=$(echo "$OUTPUT" | grep -A1 "user>>>" | head -2)
    echo "第一条用户统计:"
    echo "$FIRST_STAT"
    echo ""

    # 提取 value
    VALUE=$(echo "$FIRST_STAT" | grep "value" | awk '{print $2}' | tr -d '\r')
    echo "提取的 value: $VALUE"

    if [[ -n "$VALUE" && "$VALUE" =~ ^[0-9]+$ ]]; then
        echo "✓ 解析成功,流量值: $VALUE 字节"
        MB=$((VALUE / 1048576))
        echo "  转换为 MB: $MB MB"
    else
        echo "✗ 解析失败或值为空"
    fi
fi
echo ""

# 5. 查询特定用户 (如果提供了参数)
if [[ -n "$1" ]]; then
    echo "5. 查询指定用户: $1"
    echo "上行流量:"
    $XRAY_BIN api statsquery --server=127.0.0.1:10085 --name "user>>>$1>>>traffic>>>uplink" 2>&1
    echo ""
    echo "下行流量:"
    $XRAY_BIN api statsquery --server=127.0.0.1:10085 --name "user>>>$1>>>traffic>>>downlink" 2>&1
fi

echo ""
echo "========================================"
echo "使用方法: $0 [用户邮箱]"
echo "示例: $0 user@example.com"
