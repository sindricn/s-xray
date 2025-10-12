#!/bin/bash

#================================================================
# Clash 配置生成测试脚本
# 用于验证 generate_clash_config() 函数的修复效果
#================================================================

# 设置测试环境
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/modules/subscription.sh"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "================================================================"
echo "Clash 配置生成测试"
echo "================================================================"
echo ""

# 测试用例 1: VLESS TLS 节点
echo -e "${YELLOW}测试 1: VLESS TLS 节点${NC}"
test_nodes_1='[
  {
    "protocol": "vless",
    "port": "443",
    "security": "tls",
    "transport": "ws",
    "extra": {
      "tls_domain": "example.com",
      "ws_path": "/vless"
    }
  }
]'

test_user_id="12345678-1234-1234-1234-123456789abc"
test_password=""

echo "生成配置..."
clash_config=$(generate_clash_config "$test_nodes_1" "$test_user_id" "$test_password")
if [[ $? -eq 0 ]]; then
    echo -e "${GREEN}✓ 配置生成成功${NC}"
    echo "$clash_config" | head -20
else
    echo -e "${RED}✗ 配置生成失败${NC}"
fi
echo ""

# 测试用例 2: VMess 节点
echo -e "${YELLOW}测试 2: VMess 节点${NC}"
test_nodes_2='[
  {
    "protocol": "vmess",
    "port": "8080",
    "security": "none",
    "transport": "ws",
    "extra": {
      "alter_id": 0,
      "cipher": "auto",
      "ws_path": "/vmess"
    }
  }
]'

clash_config=$(generate_clash_config "$test_nodes_2" "$test_user_id" "$test_password")
if [[ $? -eq 0 ]]; then
    echo -e "${GREEN}✓ 配置生成成功${NC}"
    echo "$clash_config" | grep -A 10 "proxies:"
else
    echo -e "${RED}✗ 配置生成失败${NC}"
fi
echo ""

# 测试用例 3: Trojan 节点（无 password - 应该跳过）
echo -e "${YELLOW}测试 3: Trojan 节点（无 password - 应该跳过）${NC}"
test_nodes_3='[
  {
    "protocol": "trojan",
    "port": "443",
    "security": "tls",
    "transport": "tcp",
    "extra": {
      "tls_domain": "example.com"
    }
  }
]'

clash_config=$(generate_clash_config "$test_nodes_3" "$test_user_id" "")
if [[ $? -eq 0 ]]; then
    echo -e "${YELLOW}⚠ 配置生成（但应该跳过 Trojan）${NC}"
else
    echo -e "${GREEN}✓ 正确处理：无 password 时无法生成 Trojan 配置${NC}"
fi
echo ""

# 测试用例 4: Trojan 节点（有 password）
echo -e "${YELLOW}测试 4: Trojan 节点（有 password）${NC}"
clash_config=$(generate_clash_config "$test_nodes_3" "$test_user_id" "test-password-123")
if [[ $? -eq 0 ]]; then
    echo -e "${GREEN}✓ 配置生成成功${NC}"
    echo "$clash_config" | grep -A 8 "Trojan"
else
    echo -e "${RED}✗ 配置生成失败${NC}"
fi
echo ""

# 测试用例 5: 混合节点（VLESS + VMess）
echo -e "${YELLOW}测试 5: 混合节点（VLESS + VMess）${NC}"
test_nodes_5='[
  {
    "protocol": "vless",
    "port": "443",
    "security": "tls",
    "transport": "tcp",
    "extra": {
      "tls_domain": "vless.example.com"
    }
  },
  {
    "protocol": "vmess",
    "port": "8080",
    "security": "none",
    "transport": "ws",
    "extra": {
      "alter_id": 0,
      "cipher": "auto",
      "ws_path": "/vmess"
    }
  }
]'

clash_config=$(generate_clash_config "$test_nodes_5" "$test_user_id" "$test_password")
if [[ $? -eq 0 ]]; then
    echo -e "${GREEN}✓ 配置生成成功${NC}"
    node_count=$(echo "$clash_config" | grep -c "  - name:")
    echo "生成节点数: $node_count"

    if [[ $node_count -eq 2 ]]; then
        echo -e "${GREEN}✓ 节点数量正确${NC}"
    else
        echo -e "${RED}✗ 节点数量错误（期望 2，实际 $node_count）${NC}"
    fi
else
    echo -e "${RED}✗ 配置生成失败${NC}"
fi
echo ""

# 测试用例 6: Reality 节点（应该跳过）
echo -e "${YELLOW}测试 6: Reality 节点（Clash 不支持，应该跳过）${NC}"
test_nodes_6='[
  {
    "protocol": "vless",
    "port": "443",
    "security": "reality",
    "transport": "tcp",
    "extra": {
      "dest": "www.microsoft.com:443",
      "server_names": ["www.microsoft.com"],
      "public_key": "test-public-key",
      "short_ids": [""]
    }
  }
]'

clash_config=$(generate_clash_config "$test_nodes_6" "$test_user_id" "$test_password")
if [[ $? -eq 0 ]]; then
    echo -e "${YELLOW}⚠ 配置生成（但 Reality 节点应该被跳过）${NC}"
    node_count=$(echo "$clash_config" | grep -c "  - name:")
    if [[ $node_count -eq 0 ]]; then
        echo -e "${GREEN}✓ Reality 节点正确跳过${NC}"
    else
        echo -e "${RED}✗ Reality 节点未被跳过${NC}"
    fi
else
    echo -e "${GREEN}✓ 正确处理：无有效节点时返回错误${NC}"
fi
echo ""

echo "================================================================"
echo "测试完成"
echo "================================================================"
