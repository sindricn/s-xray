#!/bin/bash

#================================================================
# jq 版本和功能检查脚本
#================================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

print_success() { echo -e "${GREEN}[✓]${NC} $1"; }
print_error() { echo -e "${RED}[✗]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[!]${NC} $1"; }

echo "=== jq 版本和功能检查 ==="
echo ""

# 检查jq是否安装
if ! command -v jq >/dev/null 2>&1; then
    print_error "jq 未安装"
    echo ""
    echo "请安装jq:"
    echo "  Ubuntu/Debian: apt-get install -y jq"
    echo "  CentOS/RHEL:   yum install -y jq"
    exit 1
fi

# 显示版本
JQ_VERSION=$(jq --version 2>&1)
echo "jq 版本: $JQ_VERSION"
echo "jq 路径: $(which jq)"
echo ""

# 最低版本要求
REQUIRED_VERSION="1.5"
CURRENT_VERSION=$(echo "$JQ_VERSION" | grep -oP '\d+\.\d+' | head -1)

if [[ -z "$CURRENT_VERSION" ]]; then
    print_warning "无法解析jq版本号"
else
    echo "检测到版本: $CURRENT_VERSION"
    echo "最低要求: $REQUIRED_VERSION"

    # 简单的版本比较
    if awk "BEGIN {exit !($CURRENT_VERSION >= $REQUIRED_VERSION)}"; then
        print_success "版本满足要求"
    else
        print_error "版本过低，建议升级"
        echo ""
        echo "升级命令:"
        echo "  Ubuntu/Debian: apt-get update && apt-get install --only-upgrade jq"
        echo "  CentOS/RHEL:   yum update jq"
    fi
fi

echo ""
echo "=== 测试关键功能 ==="
echo ""

ALL_OK=true

# 测试1: 基本JSON解析
echo "测试1: 基本JSON解析"
if echo '{"test":"value"}' | jq . >/dev/null 2>&1; then
    print_success "基本解析正常"
else
    print_error "基本解析失败"
    ALL_OK=false
fi

# 测试2: jq -n (构造模式)
echo "测试2: jq -n 构造JSON"
if result=$(jq -n '{test: "value"}' 2>&1) && [[ "$result" == '{"test":"value"}' ]]; then
    print_success "jq -n 正常"
else
    print_error "jq -n 失败: $result"
    ALL_OK=false
fi

# 测试3: --arg 参数
echo "测试3: --arg 参数传递"
if result=$(jq -n --arg key "value" '{test: $key}' 2>&1) && echo "$result" | jq -e '.test == "value"' >/dev/null 2>&1; then
    print_success "--arg 正常"
else
    print_error "--arg 失败: $result"
    ALL_OK=false
fi

# 测试4: --argjson 参数（关键）
echo "测试4: --argjson 参数传递"
json_data='{"nested":"data"}'
if result=$(jq -n --argjson obj "$json_data" '{test: $obj}' 2>&1); then
    if echo "$result" | jq -e '.test.nested == "data"' >/dev/null 2>&1; then
        print_success "--argjson 正常"
    else
        print_error "--argjson 结果错误: $result"
        ALL_OK=false
    fi
else
    print_error "--argjson 失败: $result"
    ALL_OK=false
fi

# 测试5: 数组追加
echo "测试5: 数组追加操作"
if result=$(echo '{"arr":[]}' | jq '.arr += [{"id":"1"}]' 2>&1); then
    if echo "$result" | jq -e '.arr[0].id == "1"' >/dev/null 2>&1; then
        print_success "数组追加正常"
    else
        print_error "数组追加结果错误: $result"
        ALL_OK=false
    fi
else
    print_error "数组追加失败: $result"
    ALL_OK=false
fi

# 测试6: now|todate (时间函数)
echo "测试6: 时间函数 (now|todate)"
if result=$(jq -n 'now|todate' 2>&1) && [[ "$result" =~ ^\"[0-9]{4}-[0-9]{2}-[0-9]{2}T ]]; then
    print_success "时间函数正常"
else
    print_error "时间函数失败: $result"
    ALL_OK=false
fi

# 测试7: 复杂的map操作
echo "测试7: map 修改操作"
if result=$(echo '{"users":[{"name":"old"}]}' | jq '.users |= map(if .name == "old" then .name = "new" else . end)' 2>&1); then
    if echo "$result" | jq -e '.users[0].name == "new"' >/dev/null 2>&1; then
        print_success "map 操作正常"
    else
        print_error "map 操作结果错误: $result"
        ALL_OK=false
    fi
else
    print_error "map 操作失败: $result"
    ALL_OK=false
fi

# 测试8: 两步JSON构造（脚本实际使用的模式）
echo "测试8: 两步JSON构造（实际使用模式）"
user_data=$(jq -n --arg id "uuid-123" --arg name "test" '{id: $id, username: $name}' 2>&1)
if [[ $? -eq 0 ]]; then
    result=$(echo '{"users":[]}' | jq ".users += [$user_data]" 2>&1)
    if [[ $? -eq 0 ]] && echo "$result" | jq -e '.users[0].id == "uuid-123"' >/dev/null 2>&1; then
        print_success "两步构造正常"
    else
        print_error "第二步失败: $result"
        echo "  user_data: $user_data"
        ALL_OK=false
    fi
else
    print_error "第一步失败: $user_data"
    ALL_OK=false
fi

echo ""
echo "=== 检查结果 ==="
echo ""

if $ALL_OK; then
    print_success "所有测试通过，jq功能正常"
    exit 0
else
    print_error "部分测试失败"
    echo ""
    echo "建议操作:"
    echo "1. 升级jq到最新版本"
    echo "2. 如果是CentOS，可能需要启用EPEL源:"
    echo "   yum install -y epel-release"
    echo "   yum update jq"
    echo "3. 或者从源码编译安装最新版jq"
    exit 1
fi
