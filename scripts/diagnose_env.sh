#!/bin/bash

#================================================================
# 环境诊断脚本
# 检查系统依赖和JSON文件状态
#================================================================

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

print_header() {
    echo ""
    echo -e "${CYAN}╔═══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║  $1${NC}"
    echo -e "${CYAN}╚═══════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

print_info() { echo -e "${CYAN}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[✓]${NC} $1"; }
print_error() { echo -e "${RED}[✗]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[!]${NC} $1"; }

# 数据目录
DATA_DIR="/usr/local/xray/data"
USERS_FILE="${DATA_DIR}/users.json"
NODES_FILE="${DATA_DIR}/nodes.json"
NODE_USERS_FILE="${DATA_DIR}/node_users.json"

print_header "系统依赖检查"

# 检查关键命令
DEPS=(bash jq curl wget openssl)
ALL_OK=true

for cmd in "${DEPS[@]}"; do
    if command -v "$cmd" >/dev/null 2>&1; then
        version=$(
            case "$cmd" in
                bash) bash --version | head -1 ;;
                jq) jq --version ;;
                curl) curl --version | head -1 ;;
                wget) wget --version | head -1 ;;
                openssl) openssl version ;;
            esac
        )
        print_success "$cmd: $version"
    else
        print_error "$cmd: 未安装"
        ALL_OK=false
    fi
done

print_header "jq 详细检查"

if command -v jq >/dev/null 2>&1; then
    print_success "jq 已安装"
    echo "  版本: $(jq --version)"
    echo "  路径: $(which jq)"
    echo "  文件信息: $(ls -lh "$(which jq)")"

    # 测试jq功能
    echo ""
    print_info "测试jq基本功能..."

    if echo '{"test":"value"}' | jq . >/dev/null 2>&1; then
        print_success "jq 解析JSON: 正常"
    else
        print_error "jq 解析JSON: 失败"
        ALL_OK=false
    fi

    if jq -n --arg key "value" '{test: $key}' >/dev/null 2>&1; then
        print_success "jq --arg 参数: 正常"
    else
        print_error "jq --arg 参数: 失败"
        ALL_OK=false
    fi

    local test_json='{"field":"test"}'
    if result=$(jq -n --argjson obj "$test_json" '$obj') && [[ "$result" == "$test_json" ]]; then
        print_success "jq --argjson 参数: 正常"
    else
        print_error "jq --argjson 参数: 失败"
        echo "  输入: $test_json"
        echo "  输出: $result"
        ALL_OK=false
    fi
else
    print_error "jq 未安装 - 这是问题的根源！"
    echo ""
    print_warning "请安装jq:"
    echo "  Ubuntu/Debian: apt-get install -y jq"
    echo "  CentOS/RHEL:   yum install -y jq"
    ALL_OK=false
fi

print_header "JSON 文件检查"

for file in "$USERS_FILE" "$NODES_FILE" "$NODE_USERS_FILE"; do
    echo "检查: $file"

    if [[ ! -f "$file" ]]; then
        print_warning "文件不存在"
        continue
    fi

    echo "  大小: $(ls -lh "$file" | awk '{print $5}')"
    echo "  权限: $(ls -l "$file" | awk '{print $1}')"

    # 检查文件编码
    if command -v file >/dev/null 2>&1; then
        encoding=$(file -b "$file")
        echo "  编码: $encoding"
    fi

    # 检查JSON格式
    if command -v jq >/dev/null 2>&1; then
        if jq empty "$file" 2>/dev/null; then
            print_success "JSON 格式正确"

            # 显示内容摘要
            case "$file" in
                *users.json)
                    count=$(jq '.users | length' "$file" 2>/dev/null || echo "0")
                    echo "  用户数: $count"
                    if [[ $count -gt 0 ]]; then
                        echo "  用户列表:"
                        jq -r '.users[] | "    - \(.username) (UUID: \(.id[0:8])...)"' "$file" 2>/dev/null || echo "    解析失败"
                    fi
                    ;;
                *nodes.json)
                    count=$(jq '.nodes | length' "$file" 2>/dev/null || echo "0")
                    echo "  节点数: $count"
                    ;;
                *node_users.json)
                    count=$(jq '.bindings | length' "$file" 2>/dev/null || echo "0")
                    echo "  绑定数: $count"
                    ;;
            esac
        else
            print_error "JSON 格式错误"
            echo "  错误信息:"
            jq empty "$file" 2>&1 | head -5 | sed 's/^/    /'

            echo ""
            echo "  文件前10行:"
            head -10 "$file" | sed 's/^/    /'

            ALL_OK=false
        fi
    else
        print_warning "无法检查JSON格式 (jq未安装)"
    fi

    echo ""
done

print_header "系统环境"

echo "操作系统: $(cat /etc/os-release 2>/dev/null | grep PRETTY_NAME | cut -d= -f2 | tr -d '"')"
echo "内核版本: $(uname -r)"
echo "Bash版本: $BASH_VERSION"
echo "区域设置:"
echo "  LANG: ${LANG:-未设置}"
echo "  LC_ALL: ${LC_ALL:-未设置}"

print_header "诊断总结"

if [[ "$ALL_OK" == true ]]; then
    print_success "所有检查通过！环境正常。"
    echo ""
    print_info "如果仍然遇到JSON错误，问题可能在代码逻辑中。"
else
    print_error "发现问题！"
    echo ""
    print_warning "修复建议:"

    if ! command -v jq >/dev/null 2>&1; then
        echo "  1. 安装jq:"
        echo "     Ubuntu/Debian: apt-get install -y jq"
        echo "     CentOS/RHEL:   yum install -y jq"
    fi

    echo "  2. 重新运行安装脚本"
    echo "  3. 再次运行此诊断脚本验证"
fi

echo ""
