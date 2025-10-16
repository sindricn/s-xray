# 订阅列表同步问题诊断指南

## 问题描述
删除订阅后，订阅列表仍然显示已删除的订阅，但查看单个订阅时提示不存在。

## 已添加的诊断功能

### 1. 调试模式
在运行脚本前设置环境变量启用调试模式：
```bash
export DEBUG_MODE=1
./xray-manager.sh
```

启用后，查看订阅列表时会显示：
- 订阅数据库文件路径
- 文件最后修改时间

### 2. 删除订阅时的诊断信息
在删除订阅时，系统会自动显示：
- 删除前的订阅总数
- 删除后的订阅总数
- 如果数量没有变化，会显示警告并列出所有订阅名称

## 诊断步骤

### 步骤1：启用调试模式
```bash
export DEBUG_MODE=1
cd /usr/local/xray
./xray-manager.sh
```

### 步骤2：复现问题
1. 进入订阅管理菜单 (选项3)
2. 选择"查看订阅链接" (选项3)
3. 记录当前显示的订阅列表
4. 选择"删除订阅" (选项5)
5. 输入要删除的订阅名称
6. 观察删除过程中的输出信息
7. 返回并再次选择"查看订阅链接"
8. 对比删除前后的列表

### 步骤3：检查数据库文件
```bash
# 查看订阅数据库内容
cat /usr/local/xray/data/subscriptions.json | jq '.'

# 查看文件修改时间
ls -lh /usr/local/xray/data/subscriptions.json

# 检查是否有临时文件残留
ls -lh /usr/local/xray/data/subscriptions.json*
```

### 步骤4：手动验证删除
```bash
# 假设要删除的订阅名称是 "test-sub"
SUB_NAME="test-sub"

# 查看删除前
jq '.subscriptions | length' /usr/local/xray/data/subscriptions.json

# 手动执行删除命令
jq ".subscriptions = [.subscriptions[] | select(.name != \"$SUB_NAME\")]" \
  /usr/local/xray/data/subscriptions.json > /tmp/test.json

# 查看删除后
jq '.subscriptions | length' /tmp/test.json

# 对比内容
diff <(jq -S '.' /usr/local/xray/data/subscriptions.json) \
     <(jq -S '.' /tmp/test.json)
```

## 可能的问题原因

### 1. 订阅名称不匹配
**症状**: 删除时显示"订阅在数据库中未找到匹配项"

**原因**:
- 输入的名称包含额外的空格
- 数据库中存储的名称和显示的名称不一致
- 有不可见字符

**解决方案**:
```bash
# 查看数据库中实际的订阅名称（包括不可见字符）
jq -r '.subscriptions[].name' /usr/local/xray/data/subscriptions.json | od -c
```

### 2. 文件权限问题
**症状**: 删除操作没有错误提示，但文件内容没有变化

**原因**: 脚本没有写入权限

**检查方法**:
```bash
ls -l /usr/local/xray/data/subscriptions.json
# 应该显示类似: -rw-r--r-- root root
```

### 3. 并发操作问题
**症状**: 多个终端同时操作时，删除不生效

**原因**: 临时文件被覆盖

**解决方案**: 避免同时在多个终端操作

### 4. 缓存问题
**症状**: 文件内容已更新，但列表显示旧数据

**原因**: Shell变量或jq输出被缓存（理论上不应该发生）

**验证方法**:
```bash
# 在删除后立即检查文件
cat /usr/local/xray/data/subscriptions.json | jq -r '.subscriptions[].name'
```

## 收集诊断信息

如果问题仍然存在，请收集以下信息：

```bash
# 创建诊断报告
cat > /tmp/subscription-debug.log << 'EOF'
=== 系统信息 ===
$(uname -a)
$(bash --version | head -1)
$(jq --version)

=== 订阅数据库 ===
$(cat /usr/local/xray/data/subscriptions.json | jq '.')

=== 文件信息 ===
$(ls -lh /usr/local/xray/data/subscriptions.json*)

=== 临时文件 ===
$(ls -lh /usr/local/xray/data/*.tmp 2>/dev/null || echo "无临时文件")

=== 目录权限 ===
$(ls -ld /usr/local/xray/data/)
EOF

cat /tmp/subscription-debug.log
```

## 临时解决方案

如果问题持续且无法诊断，可以使用以下临时方案：

### 方案1：手动编辑JSON文件
```bash
# 备份文件
cp /usr/local/xray/data/subscriptions.json /usr/local/xray/data/subscriptions.json.bak

# 使用文本编辑器编辑
nano /usr/local/xray/data/subscriptions.json

# 或使用jq直接编辑
jq 'del(.subscriptions[] | select(.name == "要删除的订阅名"))' \
  /usr/local/xray/data/subscriptions.json > /tmp/new.json
mv /tmp/new.json /usr/local/xray/data/subscriptions.json
```

### 方案2：重建订阅数据库
```bash
# 备份现有数据
cp /usr/local/xray/data/subscriptions.json /usr/local/xray/data/subscriptions.json.bak

# 创建新的空数据库
echo '{"subscriptions":[]}' > /usr/local/xray/data/subscriptions.json

# 然后重新生成所有订阅
```

## 联系支持

如果以上方法都无法解决问题，请提供：
1. 调试模式下的完整操作日志
2. `/tmp/subscription-debug.log` 文件内容
3. 复现问题的详细步骤
