#!/bin/bash

#================================================================
# 数据迁移脚本：节点-用户架构分离
# 功能：将绑定式架构迁移到分离式架构
# 版本：v1.0
# 日期：2025-10-10
#================================================================

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# 目录定义
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
DATA_DIR="$PROJECT_DIR/data"

# 文件路径
OLD_USERS_FILE="$DATA_DIR/users.json"
NEW_USERS_FILE="$DATA_DIR/users.json.new"
NODE_USERS_FILE="$DATA_DIR/node_users.json"
BACKUP_DIR="$DATA_DIR/backup_$(date +%Y%m%d_%H%M%S)"

# 打印函数
print_info() {
    echo -e "${CYAN}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 检查依赖
check_dependencies() {
    if ! command -v jq &>/dev/null; then
        print_error "jq 未安装，请先安装 jq"
        exit 1
    fi
}

# 备份数据
backup_data() {
    print_info "创建备份目录: $BACKUP_DIR"
    mkdir -p "$BACKUP_DIR"

    if [[ -f "$OLD_USERS_FILE" ]]; then
        cp "$OLD_USERS_FILE" "$BACKUP_DIR/users.json"
        print_success "已备份 users.json"
    fi

    if [[ -f "$DATA_DIR/nodes.json" ]]; then
        cp "$DATA_DIR/nodes.json" "$BACKUP_DIR/nodes.json"
        print_success "已备份 nodes.json"
    fi
}

# 迁移用户数据
migrate_users() {
    print_info "开始迁移用户数据..."

    if [[ ! -f "$OLD_USERS_FILE" ]]; then
        print_warning "users.json 不存在，创建空文件"
        echo '{"users":[]}' > "$OLD_USERS_FILE"
    fi

    # 提取全局用户（去重、去除port字段）
    print_info "提取全局用户列表..."
    jq '{users: [.users[] | {
        id: .id,
        email: .email,
        level: (.level // 0),
        created: (.created // (now|todate)),
        enabled: true
    }] | unique_by(.id)}' "$OLD_USERS_FILE" > "$NEW_USERS_FILE"

    if [[ $? -eq 0 ]]; then
        local user_count=$(jq '.users | length' "$NEW_USERS_FILE")
        print_success "全局用户提取成功，共 $user_count 个用户"
    else
        print_error "用户数据提取失败"
        exit 1
    fi
}

# 生成节点-用户绑定关系
generate_node_user_bindings() {
    print_info "生成节点-用户绑定关系..."

    # 按port分组，生成绑定关系
    jq '{bindings: [
        .users
        | group_by(.port)
        | map(select(length > 0))
        | .[]
        | {
            port: (.[0].port | tostring),
            protocol: .[0].protocol,
            users: [.[].id]
        }
    ]}' "$OLD_USERS_FILE" > "$NODE_USERS_FILE"

    if [[ $? -eq 0 ]]; then
        local binding_count=$(jq '.bindings | length' "$NODE_USERS_FILE")
        print_success "节点-用户绑定关系生成成功，共 $binding_count 个绑定"
    else
        print_error "绑定关系生成失败"
        exit 1
    fi
}

# 验证数据完整性
validate_migration() {
    print_info "验证数据完整性..."

    # 检查UUID唯一性
    local uuid_count=$(jq '.users | length' "$NEW_USERS_FILE")
    local unique_uuid_count=$(jq '[.users[].id] | unique | length' "$NEW_USERS_FILE")

    if [[ $uuid_count -ne $unique_uuid_count ]]; then
        print_error "UUID不唯一！原始: $uuid_count, 唯一: $unique_uuid_count"
        return 1
    fi
    print_success "UUID唯一性验证通过"

    # 检查email唯一性
    local email_count=$(jq '.users | length' "$NEW_USERS_FILE")
    local unique_email_count=$(jq '[.users[].email] | unique | length' "$NEW_USERS_FILE")

    if [[ $email_count -ne $unique_email_count ]]; then
        print_warning "Email不唯一！原始: $email_count, 唯一: $unique_email_count"
        print_info "将自动去重，保留第一个出现的email"

        # 按email去重
        jq '{users: [.users | unique_by(.email)[]]}' "$NEW_USERS_FILE" > "${NEW_USERS_FILE}.tmp"
        mv "${NEW_USERS_FILE}.tmp" "$NEW_USERS_FILE"

        local new_count=$(jq '.users | length' "$NEW_USERS_FILE")
        print_success "Email去重完成，保留 $new_count 个用户"
    else
        print_success "Email唯一性验证通过"
    fi

    # 检查绑定关系中的用户是否都存在
    local binding_users=$(jq -r '.bindings[].users[]' "$NODE_USERS_FILE" | sort -u)
    local all_users=$(jq -r '.users[].id' "$NEW_USERS_FILE" | sort -u)

    local missing_users=$(comm -13 <(echo "$all_users") <(echo "$binding_users"))
    if [[ -n "$missing_users" ]]; then
        print_warning "发现绑定关系中的用户在用户列表中不存在："
        echo "$missing_users"
    else
        print_success "绑定关系验证通过"
    fi
}

# 应用迁移
apply_migration() {
    print_info "应用迁移..."

    # 替换users.json
    mv "$OLD_USERS_FILE" "${OLD_USERS_FILE}.old"
    mv "$NEW_USERS_FILE" "$OLD_USERS_FILE"

    print_success "用户文件已更新"
    print_info "  - 旧文件: ${OLD_USERS_FILE}.old"
    print_info "  - 新文件: $OLD_USERS_FILE"
    print_info "  - 绑定文件: $NODE_USERS_FILE"
}

# 生成迁移报告
generate_report() {
    local report_file="$BACKUP_DIR/migration_report.txt"

    cat > "$report_file" <<EOF
========================================
架构迁移报告
========================================
迁移时间: $(date '+%Y-%m-%d %H:%M:%S')
备份目录: $BACKUP_DIR

数据统计:
--------
全局用户数: $(jq '.users | length' "$OLD_USERS_FILE")
节点绑定数: $(jq '.bindings | length' "$NODE_USERS_FILE")

用户列表:
--------
$(jq -r '.users[] | "- \(.email) (\(.id))"' "$OLD_USERS_FILE")

节点绑定关系:
------------
$(jq -r '.bindings[] | "端口 \(.port) (\(.protocol)): \(.users | length) 个用户"' "$NODE_USERS_FILE")

文件路径:
--------
- 用户文件: $OLD_USERS_FILE
- 绑定文件: $NODE_USERS_FILE
- 旧文件备份: ${OLD_USERS_FILE}.old

迁移状态: ✅ 成功
========================================
EOF

    print_success "迁移报告已生成: $report_file"
    echo ""
    cat "$report_file"
}

# 主函数
main() {
    clear
    echo -e "${CYAN}========================================${NC}"
    echo -e "${CYAN}   节点-用户架构分离数据迁移工具${NC}"
    echo -e "${CYAN}========================================${NC}"
    echo ""

    # 检查依赖
    check_dependencies

    # 确认迁移
    echo -e "${YELLOW}警告：此操作将修改用户数据结构！${NC}"
    echo -e "${YELLOW}请确保已经阅读重构方案文档。${NC}"
    echo ""
    read -p "是否继续? [y/N]: " confirm

    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
        print_info "取消迁移"
        exit 0
    fi

    echo ""

    # 执行迁移步骤
    backup_data
    echo ""

    migrate_users
    echo ""

    generate_node_user_bindings
    echo ""

    validate_migration
    echo ""

    apply_migration
    echo ""

    generate_report
    echo ""

    print_success "架构迁移完成！"
    echo ""
    print_info "后续步骤："
    echo "  1. 检查迁移报告: $BACKUP_DIR/migration_report.txt"
    echo "  2. 测试新架构功能"
    echo "  3. 如有问题，可从备份恢复: $BACKUP_DIR"
    echo ""
}

# 运行主函数
main "$@"
