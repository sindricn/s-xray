# 更新日志

## [v1.3.3] - 2025-10-11

### 🐛 修复：节点创建用户绑定逻辑

#### 问题描述
修复了add_vless_node()函数使用旧架构导致的用户绑定问题。该函数仍在手动输入UUID/email并直接保存到nodes.json，未通过node_users.json建立绑定关系。

#### 修复内容
- ✅ **重构add_vless_node()** - 完全改用新架构，与其他节点类型保持一致
  - 移除手动UUID/email输入
  - 只保存节点技术参数到nodes.json
  - 自动调用bind_admin_to_node()建立绑定
  - 通过generate_xray_config()动态生成配置

#### 验证结果
所有5个节点创建函数现在都使用统一的新架构：
1. ✅ `quick_add_vless_reality()` - Reality快速搭建
2. ✅ `add_vless_node()` - VLESS标准节点 **← 本次修复**
3. ✅ `add_vmess_node()` - VMess节点
4. ✅ `add_trojan_node()` - Trojan节点
5. ✅ `add_shadowsocks_node()` - Shadowsocks节点

#### 统一工作流程
```
1. 输入技术参数（端口、传输、加密等）
2. save_node_info() - 保存节点技术参数到nodes.json
3. bind_admin_to_node() - 创建节点-用户绑定关系到node_users.json
4. generate_xray_config() - 从三个JSON文件动态生成config.json
5. restart_xray - 重启服务
6. 显示分享链接 - 节点立即可用
```

---

## [v1.3.2] - 2025-10-11

### 🔧 用户管理优化和卸载功能增强

#### 核心改进
- ✅ **Username作为主键** - 用户名成为唯一标识符,不再依赖email
- ✅ **Email变为可选** - email不再是必填项,默认为username@local
- ✅ **显示优化** - 用户列表显示username/password而非UUID/email
- ✅ **三级卸载** - 提供脚本、脚本+配置、完全卸载三个选项

#### 用户管理改进（modules/user.sh）

**数据结构调整**：
```json
{
  "users": [
    {
      "id": "uuid",
      "username": "admin",        // ← 主键,唯一且必填
      "password": "password",     // ← 必填
      "email": "admin@local",     // ← 可选,默认username@local
      "level": 0,
      "enabled": true
    }
  ]
}
```

**函数修改**：
- `list_global_users()` - 显示username/password/UUID/状态
  - 表格宽度调整适应新字段
  - Password显示限制在16字符(超出显示...)
  - 移除email和level列

- `add_global_user()` - 用户名成为主键
  - username: 必填且唯一检查
  - password: 必填(留空自动生成)
  - email: 可选(默认username@local)
  - UUID: 自动生成(不再询问用户)

#### 用户关联修正（modules/user_node_binding.sh）

**所有函数改为username关联**：
- `bind_user_to_node()` - 输入username而非email
- `unbind_user_from_node()` - 通过username查找用户
- `show_user_nodes()` - 通过username显示节点
- `show_node_users()` - 显示username/password信息
- `batch_bind_user_to_nodes()` - 批量操作使用username

#### 订阅管理修正（modules/subscription.sh）

**get_admin_user_info()** - 修改admin查找逻辑:
```bash
# 旧: select(.email == "admin")
# 新: select(.username == "admin")
```

#### 卸载功能增强（uninstall.sh）

**三级卸载选项**：
1. **仅卸载脚本** - 删除/opt/s-xray,保留Xray核心和所有配置
2. **卸载脚本和配置** - 删除脚本+data目录+config.json,保留Xray核心
3. **完全卸载** - 停止服务+删除Xray核心+删除所有配置+可选清理防火墙

**实现逻辑**：
```bash
case $uninstall_level in
    1) UNINSTALL_LEVEL="script" ;;
    2) UNINSTALL_LEVEL="script_config" ;;
    3) UNINSTALL_LEVEL="full" ;;
esac

# 级别1执行后exit 0
# 级别2执行后exit 0
# 级别3执行完整卸载流程
```

#### 影响范围 📊

**数据兼容性**：
- ✅ 现有users.json需要确保有username字段
- ✅ Email可为空或任意值
- ✅ 所有用户查询改为username-based

**功能影响**：
- ✅ 用户绑定操作全部改为username输入
- ✅ 用户显示更直观(username/password优先)
- ✅ 卸载更灵活(三级选项)

---

## [v1.3.1] - 2025-10-11

### 🔧 重要修正：快速搭建流程优化

#### 修正内容 ⚠️
修正了v1.3.0中的快速搭建逻辑问题，实现了正确的用户管理架构。

**核心修正**：
- ✅ **默认admin用户** - 系统初始化时自动创建admin用户
- ✅ **快速搭建优化** - 节点创建时自动绑定admin用户，立即可用
- ✅ **用户表完善** - 增加username和password字段
- ✅ **配置生成修复** - config_generator.sh正确支持password字段
- ✅ **分享链接生成** - 节点创建完成后立即显示可用的分享链接

#### 数据结构调整 📊

**users.json（全局用户表）** - 新增字段：
```json
{
  "users": [
    {
      "id": "uuid",
      "username": "admin",        // ← 新增
      "password": "password",     // ← 新增
      "email": "admin@system",
      "level": 0,
      "enabled": true,
      "created": "2025-10-11T10:00:00Z"
    }
  ]
}
```

#### 修正的功能 🔧

**用户管理（modules/user.sh）**：
- `add_global_user()` - 增加username和password输入
  - 用户名必填且唯一
  - 密码可选（留空自动生成）
- `init_admin_user()` - 系统初始化admin用户 ✨ 新增
  - 脚本启动时自动调用
  - 检查admin是否存在，不存在则创建
  - 随机生成初始密码并显示

**节点管理（modules/node.sh）**：
- `bind_admin_to_node()` - 绑定admin用户到节点 ✨ 新增辅助函数
  - 自动获取admin用户信息
  - 在node_users.json中建立绑定关系
  - 返回用户信息供分享链接生成使用

- `quick_add_vless_reality()` - 修正快速搭建流程 ✅
  - 节点创建后自动绑定admin用户
  - 立即生成并显示分享链接
  - 节点创建完成即可使用

- `add_vmess_node()` - 修正VMess节点创建 ✅
  - 自动绑定admin用户
  - 显示admin用户信息和分享链接

- `add_trojan_node()` - 修正Trojan节点创建 ✅
  - 自动绑定admin用户
  - 使用admin密码生成Trojan链接

- `add_shadowsocks_node()` - 修正Shadowsocks节点创建 ✅
  - 自动绑定admin用户
  - 使用admin密码生成SS链接

**配置生成（modules/config_generator.sh）**：
- `generate_xray_config()` - 修正password字段支持 ✅
  - 从users.json正确读取password字段
  - Trojan协议使用用户password而非UUID
  - Shadowsocks协议使用用户password
  - VLESS/VMess协议继续使用UUID

#### 工作流程修正 🔄

**旧流程（v1.3.0 - 有问题）**：
```
创建节点（无用户） → 提示用户去绑定 → 节点无法使用
```

**新流程（v1.3.1 - 已修正）**：
```
1. 系统启动 → 自动初始化admin用户
2. 创建节点 → 自动绑定admin用户
3. 生成配置 → 重启Xray
4. 显示分享链接 → 节点立即可用 ✅
5. （可选）添加更多用户 → 绑定到节点
```

#### 用户体验提升 ✨

- **快速搭建更快**：节点创建后立即可用，无需额外步骤
- **分享链接立即显示**：创建完成后直接显示可用的分享链接
- **admin密码管理**：初始化时显示admin密码，可通过用户管理修改
- **向后兼容**：保留用户绑定功能，支持多用户管理

---

## [v1.3.0] - 2025-10-10

### 🏗️ 重大架构重构：节点用户分离

#### 架构变更 ⚡
从"节点绑定用户"重构为"节点用户分离"架构，实现真正的多对多关系。

**核心改进**：
- ✅ **节点独立性** - 节点创建时不再绑定用户，只定义技术参数
- ✅ **用户全局化** - 用户在全局管理，UUID和email全局唯一
- ✅ **灵活绑定** - 一个用户可访问多个节点，一个节点可服务多个用户
- ✅ **动态配置** - config.json根据绑定关系动态生成

#### 新数据结构 📊

**users.json（全局用户池）**：
```json
{
  "users": [
    {"id": "uuid", "email": "user@example.com", "level": 0, "enabled": true}
  ]
}
```

**node_users.json（绑定关系）- 新增**：
```json
{
  "bindings": [
    {"port": "443", "protocol": "vless", "users": ["uuid1", "uuid2"]}
  ]
}
```

#### 新增模块 🆕

1. **config_generator.sh** - 动态配置生成引擎
   - `generate_xray_config()` - 根据nodes.json + users.json + node_users.json生成config.json
   - `generate_inbound_config()` - 智能inbound配置生成
   - `generate_stream_settings()` - streamSettings动态生成
   - 支持协议：VLESS, VMess, Trojan
   - 支持安全：Reality, TLS, None

2. **user_node_binding.sh** - 用户节点绑定管理
   - `bind_user_to_node()` - 绑定用户到节点
   - `unbind_user_from_node()` - 解绑用户
   - `show_user_node_bindings()` - 显示所有绑定关系
   - `show_user_nodes()` - 查看用户可访问的节点
   - `show_node_users()` - 查看节点的用户列表
   - `batch_bind_user_to_nodes()` - 批量绑定用户到多个节点

3. **数据迁移工具**
   - `scripts/migrate_to_separated_architecture.sh` - 完整数据迁移脚本
   - 自动备份、转换数据结构、验证完整性、生成报告

#### 重构功能 🔧

**节点管理（modules/node.sh）**：
- `save_node_info()` - 完全重写，参数变更
  - 新签名：`(protocol, port, transport, security, extra_config)`
  - 只保存节点技术参数，不包含用户信息
- `quick_add_vless_reality()` - 去除UUID和email输入 ✅
  - 节点创建完成后提示用户绑定
  - 调用`generate_xray_config()`重新生成配置
- `add_vmess_node()` - 重构VMess节点创建 ✅
  - 去除UUID/email/password输入
  - 只保存端口、传输协议、加密方式等技术参数
- `add_trojan_node()` - 重构Trojan节点创建 ✅
  - 去除password/email输入
  - 保存TLS域名、证书、回落配置等技术参数
- `add_shadowsocks_node()` - 重构Shadowsocks节点创建 ✅
  - 去除password/email输入
  - 保存加密方式等技术参数

**用户管理（modules/user.sh）**：
- `list_global_users()` - 显示全局用户列表 ✨ 新增
- `add_global_user()` - 添加全局用户（可选绑定节点）✨ 新增
- `delete_global_user()` - 删除全局用户（自动清理绑定）✨ 新增
- `check_email_exists()` - 支持全局和节点级别查重

**订阅管理（modules/subscription.sh）**：
- `generate_subscription_with_user()` - 调整订阅生成逻辑 ✅
  - 只为用户已绑定的节点生成订阅链接
  - 无绑定节点时提示并可选择生成全部节点
  - 显示用户可访问节点数量

**菜单系统（xray-manager.sh）**：
- **用户管理菜单** - 完全重构 ✅
  - 新增"全局用户管理"分组（查看、添加、删除用户）
  - 新增"用户节点绑定"分组（绑定、解绑、查看关系、批量绑定）
  - 保留旧版功能（向后兼容）
- **节点管理菜单** - 新增功能 ✅
  - 新增"节点用户管理"分组
  - 查看节点的用户列表
  - 查看所有绑定关系

#### 使用流程变化 🔄

**旧流程**（已废弃）：
```
创建节点 → 输入UUID和email → 节点用户绑定在一起
```

**新流程**：
```
1. 创建节点（只定义端口、协议、域名等）
2. 添加用户（全局用户池，UUID自动生成）
3. 绑定用户到节点（灵活关联）
4. 生成配置（动态组合）
```

#### 迁移指南 📖

1. **备份数据**：
   ```bash
   cp -r /usr/local/xray/data /usr/local/xray/data.backup
   ```

2. **运行迁移脚本**：
   ```bash
   bash /usr/local/xray/scripts/migrate_to_separated_architecture.sh
   ```

3. **验证迁移**：
   - 检查 users.json（UUID和email唯一性）
   - 检查 node_users.json（绑定关系正确）
   - 查看迁移报告

#### 兼容性说明 ⚠️

- ✅ 旧函数暂时保留（向后兼容）
- ✅ 数据迁移脚本自动处理转换
- ⚠️ 新旧架构的config.json格式不同
- ⚠️ 建议在测试环境先测试

#### 技术优势 🚀

1. **灵活性提升**
   - 一个用户可使用多个节点（多地域、多协议）
   - 一个节点可服务多个用户（节省端口）

2. **管理简化**
   - 用户全局管理，不与节点耦合
   - 删除节点不影响用户数据
   - 修改用户信息一次生效全部节点

3. **扩展性增强**
   - 支持复杂的访问控制策略
   - 便于实现用户分组、权限管理
   - 为未来的流量统计、计费系统奠定基础

#### 文档更新 📚

- **架构设计**: `claudedocs/架构重构方案-节点用户分离.md`
- **完成总结**: `claudedocs/架构重构完成总结.md`
- **迁移脚本**: `scripts/migrate_to_separated_architecture.sh`

---

## [v1.2.2] - 2025-10-10

### 🐛 重要Bug修复

#### 数据完整性修复 ✅
- **端口查重逻辑** - 防止端口冲突导致服务不可用
  - 新增 `check_port_exists()` 函数（modules/node.sh:9-37）
  - 检查nodes.json中的端口记录
  - 检查系统端口占用状态（ss/netstat）
  - 节点创建前自动验证端口可用性

- **用户名查重逻辑** - 防止用户邮箱重复
  - 新增 `check_email_exists()` 函数（modules/user.sh:8-34）
  - 支持节点级别和全局级别查重
  - 用户添加前自动验证邮箱唯一性
  - 防止数据混乱和管理问题

#### 错误提示优化 ⚠️
- **端口冲突提示**：`端口 {port} 已被占用或已存在，请使用其他端口`
- **邮箱重复提示**：`用户邮箱 '{email}' 在端口 {port} 上已存在`
- 提前拦截错误，避免配置失败

### 🐛 订阅管理修复

#### 核心问题修复 ✅
- **修复base64_encode()函数** - 添加参数验证，防止"unbound variable"错误
  - 使用 `${1:-}` 安全参数展开
  - 添加空值检查和错误返回
  - 修复 subscription.sh:86 错误

- **完善订阅管理菜单** - 添加缺失的生成订阅功能
  - 新增独立"生成订阅链接"选项（选项2）
  - 优化菜单结构为5项（原4项）
  - 调整菜单编号顺序更符合逻辑

- **新增订阅更新功能** - regenerate_subscription()
  - 重新生成现有订阅内容
  - 保留订阅配置（用户绑定、订阅类型）
  - 自动更新订阅时间戳
  - 支持三种订阅格式（Base64/Clash/Raw）

#### 订阅管理新菜单结构
```
1. 查看节点链接        - 独立查看单个节点分享链接
2. 生成订阅链接 (新增) - 创建新的订阅（支持用户绑定）
3. 查看订阅链接        - 查看所有已创建订阅列表
4. 更新订阅            - 重新生成现有订阅内容
5. 删除订阅            - 删除指定订阅
```

#### 技术改进 🔧
- **参数安全性**: 所有接收参数的函数都添加了默认值处理
- **错误处理**: 完善订阅生成过程中的错误检查和用户提示
- **用户体验**: 重新生成订阅时显示详细配置信息

### 🎯 项目结构重构

#### 系统状态增强
- ✅ **在线节点统计** - 实时检测节点端口监听状态
- ✅ **状态显示优化** - 显示在线节点数/总节点数
- ✅ **智能检测** - 支持ss和netstat双重检测方式

#### 功能菜单重组
- ✅ **菜单重新编号** - 按照新结构系统化组织
- ✅ **Xray管理** - "内核管理"升级为"Xray管理"
  - 新增：查看日志功能（实时/完整/错误日志）
  - 优化：菜单项顺序调整（安装→启动→停止→重启→卸载→更新→日志）
- ✅ **订阅管理简化** - 精简为4个核心功能
  - 查看节点链接（单个节点分享链接）
  - 查看订阅链接（所有订阅列表）
  - 更新订阅（生成新订阅/重新生成）
  - 删除订阅
- ✅ **出站规则管理** - 全新功能模块（开发中）
  - 查看/添加/修改/删除/启用/禁用规则
  - 支持域名分流、IP分流、直连/代理/拦截设置
- ✅ **脚本管理** - "卸载脚本"扩展为"脚本管理"
  - 更新脚本（Git pull自动更新）
  - 卸载脚本（保留Xray核心）
  - 卸载脚本及依赖（完全清理）
- ❌ **移除配置管理** - 功能分散到其他模块

#### 新功能菜单结构
```
1. Xray管理     （原"内核管理"）
2. 用户管理     （保持）
3. 节点管理     （保持）
4. 订阅管理     （简化）
5. 域名管理     （保持）
6. 证书管理     （保持）
7. 出站规则     （新增）
8. 防火墙管理   （保持）
9. 脚本管理     （扩展）
```

#### 域名管理优化
- ✅ **菜单结构重组** - 按功能分类清晰
  - 服务器域名（TLS证书绑定、订阅地址）
  - SNI伪装域名（Reality/TLS协议）
  - Host伪装域名（WebSocket/HTTP传输）
  - 优选域名测试（智能延迟测试）
  - 校验DNS（域名解析验证）
- ✅ **服务器域名管理** - manage_server_domain()
  - 查看/设置服务器域名
  - 域名解析测试
- ✅ **SNI伪装域名** - manage_sni_domain()
  - 设置默认SNI域名
  - 查看推荐域名列表
  - TLS握手测试
- ✅ **Host伪装域名** - manage_host_domain()
  - Host域名配置
  - HTTP连接测试

#### 证书管理优化
- ✅ **菜单结构完善** - 符合用户需求
  - 查看证书（list_certificates）
  - 修改证书（modify_certificate）- 新增
  - 添加自定义证书（add_certificate）
  - 删除证书（delete_certificate）
  - 自动申请证书（auto_apply_certificate）- 新增
- ✅ **证书修改功能** - modify_certificate()
  - 更新证书文件路径
  - 更新密钥文件路径
  - 文件存在性验证
- ✅ **自动申请证书** - auto_apply_certificate()
  - acme.sh集成
  - 支持Let's Encrypt/ZeroSSL/Buypass
  - HTTP验证/DNS验证/独立模式
  - 自动续期支持
  - 证书自动安装到指定目录

#### 技术实现
- **在线节点检测函数**: get_online_nodes()
  - 遍历所有节点端口
  - 使用ss或netstat检查监听状态
  - 返回在线节点计数
- **日志查看功能**:
  - journalctl集成
  - 实时日志（-f -n 50）
  - 完整日志（--no-pager）
  - 错误日志（-p err）
- **域名管理新增函数**:
  - manage_server_domain() - 服务器域名管理
  - manage_sni_domain() - SNI伪装域名
  - manage_host_domain() - Host伪装域名
- **证书管理新增函数**:
  - modify_certificate() - 证书修改
  - auto_apply_certificate() - acme.sh自动申请

---

## [v1.2.1] - 2025-10-10

### 🔥 重大更新：订阅管理完全重构

#### 订阅链接修复 ✅
- **修复所有协议的分享链接格式**
  - ✅ VLESS Reality - 完整的Reality参数（pbk, sid, sni, flow）
  - ✅ VLESS TLS - 正确的TLS配置和传输层参数
  - ✅ VMess - 标准JSON格式 + Base64编码
  - ✅ Trojan - 完整的TLS参数
  - ✅ Shadowsocks - SIP002标准格式

#### 多客户端支持 📱
- **通用订阅（Base64编码）**
  - V2RayN / V2RayNG
  - Shadowrocket
  - Quantumult X
  - SagerNet
  - 其他兼容客户端

- **Clash订阅（YAML格式）**
  - Clash for Windows
  - Clash for Android
  - ClashX (macOS)

- **原始订阅（纯文本）**
  - 所有支持订阅的客户端
  - 手动导入支持

#### 订阅功能增强 🚀
- ✅ **三种订阅格式** - Base64/Clash/Raw
- ✅ **智能链接生成** - 自动识别节点类型
- ✅ **分享链接查看** - 独立查看所有节点链接
- ✅ **用户绑定功能** - 订阅链接支持用户绑定，默认绑定admin用户
- ✅ **Admin默认用户** - 自动初始化admin默认用户
- ✅ **单节点链接查看** - 支持查看单个节点的分享链接
- ✅ **订阅服务器** - Python HTTP服务器
- ✅ **订阅管理** - 创建/查看/更新/删除
- ✅ **详细文档** - 完整的使用指南

#### 技术改进 🔧
- **公网IP获取优化**
  - 多个API源备份
  - 超时控制（3秒）
  - 降级到本地IP

- **Base64编码优化**
  - 无换行编码
  - 兼容性处理

- **URL编码标准化**
  - RFC 3986标准
  - 特殊字符处理

- **订阅服务器增强**
  - 简化日志输出
  - CORS支持
  - 无缓存响应
  - 错误处理完善

- **DNS解析日志优化**
  - 简化域名测试输出
  - 使用 `>/dev/null 2>&1` 静默处理
  - 减少不必要的控制台输出

#### 文档完善 📖
- 创建《订阅管理使用指南》
  - 详细的使用流程
  - 客户端配置示例
  - 分享链接格式说明
  - 故障排除指南
  - 最佳实践建议

### 界面优化 🎨

#### 主菜单改进
- ✅ **修复显示格式**: 移除 `%-23s` 等格式化符号的显示问题
- ✅ **简化状态显示**: 直接显示状态信息，更清晰易读
- ✅ **菜单编号优化**: 将卸载选项从 `99` 改为 `9`，按顺序排列
- ✅ **标题高亮**: 使用黄色高亮"系统状态"和"功能菜单"标题
- ✅ **版本更新**: 显示版本号 v1.2.1

#### 卸载界面美化
- 🎨 统一使用框线样式
- ⚠️ 增加警告提示（包括配置文件和数据）
- 📝 优化退出提示信息

### 新增功能 ✨

#### 1. 主菜单状态显示增强
- ✅ **内核版本显示**: 实时显示当前 Xray-Core 版本
- ✅ **运行状态监控**: 实时显示 Xray 服务运行状态（运行中/已停止）
- ✅ **节点数量统计**: 显示当前配置的节点总数
- ✅ **用户数量统计**: 显示当前配置的用户总数
- 🎨 **美化界面**: 使用框线美化主菜单，提升用户体验

#### 2. Reality 节点快速搭建优化
- 🚀 **智能域名优选**: 默认启用自动优选最佳伪装域名
  - 实时显示测试进度和延迟
  - 支持测试 15+ 常用域名
  - 自动选择延迟最低的域名
  - 显示测试成功率统计

- 🎯 **三种配置模式**:
  1. 使用默认伪装域名（快速模式）
  2. **自动优选最佳域名（推荐，默认选项）**
  3. 手动输入自定义域名

- 📊 **详细测试反馈**:
  - 实时显示每个域名的测试结果
  - 颜色标识成功/失败状态
  - 显示延迟最低的前 5 个域名供参考
  - 允许用户选择其他优选域名

- 🔧 **智能交互优化**:
  - SNI (Server Name Indication) 自动设置
  - 伪装域名自动跟随选择
  - 支持测试后更改域名选择
  - 可选设置为默认伪装域名

#### 3. 域名管理增强
- 📈 **智能优选测试页面**:
  - 测试 20+ 常用域名
  - 显示延迟最低的前 10 个域名
  - 使用颜色区分域名质量：
    - 🟢 绿色 (<200ms): 优秀，强烈推荐
    - 🟡 黄色 (200-500ms): 良好，可以使用
    - 🔴 红色 (>500ms): 较慢，不推荐
  - 支持按序号选择推荐域名

- 💾 **推荐域名保存**: 自动保存测试结果到 `recommended_domains.txt`

### 改进 🔧

#### 性能优化
- ⚡ 域名测试超时时间优化（从 1 秒提升到 2 秒）
- 🔍 增强 DNS 解析验证逻辑
- 📝 优化测试进度显示

#### 用户体验
- 🎨 统一界面风格（使用框线和颜色）
- 💬 更清晰的提示信息
- 🎯 更智能的默认选项
- 📊 更详细的统计信息

### 技术细节 🔨

#### 主菜单状态获取 (xray-manager.sh:96-112)
```bash
get_xray_status() {
    local version="未安装"
    local status="${RED}未运行${NC}"

    if [[ -f "$XRAY_BIN" ]]; then
        version=$("$XRAY_BIN" version 2>/dev/null | head -1 | awk '{print $2}')

        if systemctl is-active xray &>/dev/null; then
            status="${GREEN}运行中${NC}"
        else
            status="${RED}已停止${NC}"
        fi
    fi

    echo "$version|$status"
}
```

#### 智能域名优选测试 (modules/node.sh:142-241)
- 测试域名列表：15 个精选常用域名
- 测试方法：OpenSSL TLS 握手 + DNS 解析验证
- 结果展示：实时进度、延迟统计、前 5 名推荐
- 交互选项：使用推荐、更改选择、设置默认

#### 域名管理优选测试 (modules/domain.sh:37-188)
- 测试域名列表：20 个扩展域名
- 结果分级：优秀/良好/较慢（颜色区分）
- 前 10 名显示：序号、域名、延迟
- 支持按序号选择

### 使用示例 📖

#### 快速搭建 Reality 节点
```bash
1. 进入脚本：xray
2. 选择：2. 节点管理
3. 选择：1. 一键搭建 VLESS + Reality 节点
4. 输入端口（默认 443）
5. 选择域名模式：2（自动优选，推荐）
6. 等待测试完成，查看推荐域名
7. 确认使用或更改选择
8. 完成配置
```

#### 域名优选测试
```bash
1. 进入脚本：xray
2. 选择：7. 域名管理
3. 选择：1. Reality 伪装域名优选测试
4. 查看测试结果和推荐域名
5. 选择序号或使用最佳域名
6. 设置为默认（可选）
```

### 配置文件说明 📁

- **默认域名存储**: `/usr/local/xray/data/default_domain.txt`
- **推荐域名列表**: `/usr/local/xray/data/recommended_domains.txt`
- **节点配置**: `/usr/local/xray/data/nodes.json`
- **用户配置**: `/usr/local/xray/data/users.json`

### 兼容性 ✅

- ✅ 完全向后兼容 v1.2.0
- ✅ 保留所有原有功能
- ✅ 新增功能为可选特性
- ✅ 不影响现有配置

### 下一步计划 🚀

- [ ] 添加节点性能监控
- [ ] 支持多用户管理增强
- [ ] 添加订阅链接生成优化
- [ ] 集成证书自动续期
- [ ] 添加流量统计功能

---

## [v1.2.0] - 2025-10-08

### 初始版本
- 基础内核管理功能
- 节点管理（VLESS/VMess/Trojan/Shadowsocks）
- 用户管理
- 订阅管理
- 防火墙管理
- 配置管理
- 域名管理
- 证书管理
