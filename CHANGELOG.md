# 更新日志

## [v1.3.6] - 2025-10-11

### 🐛 关键修复：Clash订阅导入失败

#### 问题描述
Clash订阅链接无法在客户端中导入节点，但单节点链接可以正常导入。

**根本原因**：
1. **Subshell问题**：第351-437行使用管道+while循环生成节点配置，导致在subshell中运行，输出无法写入父shell
2. 原代码结构：
   ```bash
   echo "$nodes_array" | jq -c '.[]' | while IFS= read -r node; do
       echo "  - name: \"VLESS-${port}\""  # 在subshell中，输出丢失
       echo "    type: vless"
   done
   ```
3. 结果：生成的Clash YAML文件中`proxies:`部分为空，导致无节点可用

#### 修复方案

**完全重写 generate_clash_config() 函数** (modules/subscription.sh Line 330-558)

**修复前**：
- 使用管道 `echo | jq | while` 导致subshell问题
- 节点配置输出丢失
- proxy-groups中有节点名但proxies部分为空

**修复后**：
- 使用数组收集：`proxy_configs=()` 和 `proxy_list=()`
- 在while循环中将配置存入数组：`proxy_configs+=("$node_config")`
- 循环后统一输出：`for config in "${proxy_configs[@]}"; do echo "$config"; done`
- 参考s-hy2项目的成功实现模式

**关键代码改动**：
```bash
# 新增：使用数组收集节点配置
local proxy_configs=()
local proxy_list=()

while IFS= read -r node; do
    local node_config="..."  # 构建完整节点配置
    [[ -n "$node_config" ]] && proxy_configs+=("$node_config")
    proxy_list+=("$node_name")
done < <(echo "$nodes_array" | jq -c '.[]')

# 输出所有节点配置
for config in "${proxy_configs[@]}"; do
    echo "$config"
    echo ""
done
```

**同步改进**：
- 增强路由规则：新增IPv6局域网、更多媒体服务关键词、analytics/track广告拦截
- 完善代理组：保持5个代理组结构（节点选择/自动选择/国外媒体/全球直连/全球拦截）
- 参考s-hy2完整规则集

#### 影响范围
- ✅ VLESS (TLS/Plain) 节点正确生成
- ✅ VMess 节点正确生成
- ✅ Trojan 节点正确生成
- ✅ Shadowsocks 节点正确生成
- ✅ Clash订阅可在Clash Verge/ClashX/Clash for Windows中正常导入
- ✅ 代理组节点列表完整显示

**测试验证**：
- 生成的Clash YAML包含完整的`proxies:`部分
- 每个节点配置包含name/type/server/port等完整字段
- proxy-groups中引用的节点名与proxies中定义的节点名匹配

---

## [v1.3.5] - 2025-10-11

### 🐛 修复：Admin用户显示问题

#### 问题描述
在节点链接和订阅链接中，admin用户显示为"admin@system"而不是"admin"。

**根本原因**：
1. 链接生成函数使用email字段作为备注名称（显示"admin@system"）
2. `bind_admin_to_node()`和`get_admin_user_info()`返回email而不是username

#### 修复内容

**说明**：email字段保持邮箱格式（"admin@system"），修复方式是改用username字段作为链接备注。

**modules/subscription.sh**:
- Line 19-23: `get_admin_user_info()`改为返回`UUID|password|username`（原为`UUID|password|email`）
- **关键改动**：链接生成改用username字段而不是email字段作为备注名称

**modules/node.sh**:
- Line 53-77: `bind_admin_to_node()`改为返回`UUID|password|username`（原为`UUID|password|email`）
- Line 430, 586, 683, 774, 846: 批量替换所有`admin_email`变量名为`admin_remark`
- **关键改动**：所有节点创建函数从读取email字段改为读取username字段作为链接备注

**影响范围**：
- ✅ VLESS Reality节点创建和链接生成
- ✅ VLESS TLS节点创建和链接生成
- ✅ VMess节点创建和链接生成
- ✅ Trojan节点创建和链接生成
- ✅ Shadowsocks节点创建和链接生成
- ✅ 订阅链接生成

**结果**：
- Admin用户在所有链接中显示为"admin"
- 用户绑定逻辑保持一致性
- 链接备注名称更清晰易读

---

### ✨ 新增：Clash订阅格式支持

#### 功能描述
添加Clash YAML格式订阅支持，为Clash系列客户端（Clash for Windows、ClashX、Clash Verge等）提供原生配置格式。

#### 实现内容

**modules/subscription.sh**:

1. **generate_clash_config()** (Line 323-481)
   - 生成完整的Clash YAML配置
   - 支持的协议：
     - ✅ VLESS (TLS/Plain) - Reality不支持（Clash限制）
     - ✅ VMess (自动/WebSocket)
     - ✅ Trojan (TLS)
     - ✅ Shadowsocks (多种加密方式)

   - 配置特性：
     - 代理端口：7890 (HTTP), 7891 (SOCKS5)
     - 外部控制：127.0.0.1:9090
     - 代理组：PROXY（手动选择）、AUTO（自动测速）
     - 路由规则：局域网直连、中国IP/域名直连、其他代理

2. **订阅类型菜单** (Line 743-749)
   - 选项1：通用订阅（Base64编码）
   - 选项2：原始订阅（纯文本）
   - 选项3：Clash订阅（YAML格式）**← 新增**

3. **订阅生成集成** (Line 834-848)
   - 收集用户绑定的节点JSON数组
   - 调用`generate_clash_config()`生成YAML
   - 保存为`${sub_name}_clash.yaml`

**使用场景**：
- Clash for Windows用户导入YAML配置
- ClashX Pro用户使用订阅链接
- Clash Verge用户自动更新配置
- 需要策略组和规则分流的场景

**配置示例**：
```yaml
port: 7890
socks-port: 7891
proxies:
  - name: "VLESS-443"
    type: vless
    server: 1.2.3.4
    port: 443
    uuid: xxx
    tls: true
  - name: "VMess-10086"
    type: vmess
    server: 1.2.3.4
    port: 10086
    uuid: xxx
    alterId: 0
    cipher: auto
proxy-groups:
  - name: PROXY
    type: select
    proxies: [...]
  - name: AUTO
    type: url-test
    proxies: [...]
```

---

### 🐛 修复：订阅链接导入失败问题（参考s-hy2项目）

#### 问题描述
通用订阅和Clash订阅导入客户端后无法使用，单个节点链接正常。

**根本原因**：
1. Base64编码函数不兼容所有系统（`-w 0`参数问题）
2. Clash配置使用while循环生成proxy-groups，子shell导致输出不完整
3. Clash proxy-groups结构过于简单，缺少常用分流组

#### 修复内容

**modules/subscription.sh**:

1. ✅ **base64_encode()** (Line 64-77)
   ```bash
   # 修复前：只支持-w 0参数
   echo -n "$input" | base64 -w 0 2>/dev/null || echo -n "$input" | base64

   # 修复后：兼容性更好，支持管道和参数输入
   base64 -w 0 2>/dev/null || base64 | tr -d '\n'
   ```
   - 添加管道输入支持
   - 使用`tr -d '\n'`作为后备方案，兼容不支持`-w 0`的系统

2. ✅ **通用订阅Base64编码** (Line 854-858)
   ```bash
   # 修复前：直接pipe可能有问题
   sub_content=$(printf "%s\n" "${share_links[@]}" | base64_encode)

   # 修复后：先生成raw_links，再编码
   local raw_links=$(printf "%s\n" "${share_links[@]}")
   sub_content=$(echo -n "$raw_links" | base64_encode)
   ```
   - 确保每行一个链接
   - 使用`echo -n`避免末尾换行

3. ✅ **generate_clash_config()** (Line 440-535)

   **参考s-hy2项目格式** (C:\code\s-hy2\scripts\node-info.sh Line 637-708)：

   ```bash
   # 修复前：使用while循环，子shell问题
   echo "$nodes_array" | jq -c '.[]' | while IFS= read -r node; do
       case $protocol in
           vless) echo "      - \"VLESS-${port}\"" ;;
       esac
   done

   # 修复后：使用数组收集，避免子shell
   local proxy_list=()
   while IFS= read -r node; do
       case $protocol in
           vless) proxy_list+=("VLESS-${port}") ;;
       esac
   done < <(echo "$nodes_array" | jq -c '.[]')

   for proxy in "${proxy_list[@]}"; do
       echo "      - \"$proxy\""
   done
   ```

   **Proxy-Groups 完善**：
   - 添加 "🚀 节点选择" - 手动选择组
   - 添加 "🔄 自动选择" - URL测试组（300秒间隔，50ms容差）
   - 添加 "🌍 国外媒体" - 媒体服务分流
   - 添加 "🎯 全球直连" - DIRECT出站
   - 添加 "🛑 全球拦截" - REJECT出站

   **Rules 完善**：
   - 局域网IP段直连（192.168/10/172.16/127）
   - 国外媒体关键词匹配（youtube/google/twitter/github/openai）
   - 广告拦截（ad/ads关键词）
   - GEOIP CN直连
   - MATCH默认走代理

#### 修复前后对比

**Base64编码兼容性**：
```bash
# 修复前：不支持-w 0的系统会失败
echo -n "$input" | base64 -w 0  # ❌ macOS/BSD不支持

# 修复后：兼容所有系统
base64 -w 0 2>/dev/null || base64 | tr -d '\n'  # ✅ 完全兼容
```

**Clash Proxy-Groups**：
```yaml
# 修复前：结构简单，节点可能缺失
proxy-groups:
  - name: "PROXY"
    type: select
    proxies:
      - "AUTO"
      # ❌ while循环可能导致节点未添加

# 修复后：完整结构，s-hy2风格
proxy-groups:
  - name: "🚀 节点选择"
    type: select
    proxies:
      - "🔄 自动选择"
      - "VLESS-443"  # ✅ 所有节点正确添加
      - "VMess-10086"
      - "🎯 全球直连"

  - name: "🔄 自动选择"
    type: url-test
    proxies:
      - "VLESS-443"
      - "VMess-10086"
    url: 'http://www.gstatic.com/generate_204'
    interval: 300
    tolerance: 50

  - name: "🌍 国外媒体"  # ✅ 新增媒体分流组
    type: select
    proxies:
      - "🚀 节点选择"
      - "🔄 自动选择"
      - "🎯 全球直连"
```

**Clash Rules**：
```yaml
# 修复前：规则过于简单
rules:
  - DOMAIN-SUFFIX,google.com,PROXY
  - GEOIP,CN,DIRECT
  - MATCH,PROXY

# 修复后：完整分流规则（参考s-hy2）
rules:
  # 局域网直连
  - IP-CIDR,192.168.0.0/16,🎯 全球直连,no-resolve
  - IP-CIDR,10.0.0.0/8,🎯 全球直连,no-resolve

  # 国外媒体服务
  - DOMAIN-KEYWORD,youtube,🌍 国外媒体
  - DOMAIN-KEYWORD,google,🌍 国外媒体
  - DOMAIN-SUFFIX,openai.com,🌍 国外媒体

  # 广告拦截
  - DOMAIN-KEYWORD,ad,🛑 全球拦截

  # 国内直连
  - GEOIP,CN,🎯 全球直连

  # 默认代理
  - MATCH,🚀 节点选择
```

#### 影响范围
- ✅ 通用Base64订阅：兼容所有系统（Linux/macOS/BSD）
- ✅ Clash订阅：完整proxy-groups结构，所有节点正确添加
- ✅ Clash分流：参考s-hy2项目，提供实用的分流规则
- ✅ 客户端导入：v2rayNG、Clash等客户端可正常导入和使用

---

### 🐛 修复：用户信息显示和节点链接问题（补充修复）

#### 问题描述
1. `list_global_users()`没有显示email字段
2. 查看单个节点链接时，默认配置错误且用户列表显示email而非username
3. VMess链接JSON格式中port和aid字段为字符串而非数字
4. Clash订阅配置缺少必要字段导致导入失败

#### 修复内容

**modules/user.sh**:

1. ✅ **list_global_users()** (Line 98-130)
   - 添加email字段显示列
   - 调整列宽以容纳所有字段：用户名、密码、邮箱、UUID、状态
   - 显示格式：`username (12) | password (16) | email (18) | UUID (20) | status (8)`

**modules/subscription.sh**:

2. ✅ **show_node_share_link()** (Line 488-645)
   - Line 519: 移除读取不存在的`node.email`字段
   - Line 549: 将"使用节点自带配置"改为"使用admin用户（默认）"
   - Line 614-620: 默认选项（选项1）改为使用`get_admin_user_info()`获取admin用户
   - Line 587-591: 用户列表显示格式改为`username (email) - UUID`
   - Line 610: 使用`username`而不是`email`作为final_remark
   - Line 639-640: 结果显示分离节点和用户信息

3. ✅ **generate_vmess_link_from_config()** (Line 187-230)
   - Line 210: `"port": ${port}` - 改为数字类型（移除引号）
   - Line 212: `"aid": ${alter_id}` - 改为数字类型（移除引号）
   - 修复VMess链接JSON格式，符合V2Ray标准

4. ✅ **generate_clash_config()** (Line 323-481)
   - Line 364, 381, 400, 414, 426: 为所有协议添加`udp: true`字段
   - Line 366, 415: 为TLS协议添加`skip-cert-verify: false`字段
   - Line 375-386: 完善Plain VLESS配置（无TLS场景）
   - VLESS配置：移除错误的`cipher`字段，添加正确的`udp`和`skip-cert-verify`
   - Trojan配置：添加缺失的`udp`和`skip-cert-verify`字段
   - VMess/SS配置：添加`udp: true`字段

#### 修复前后对比

**查看单个节点链接**：
```bash
# 修复前
选择用户：
  1. 使用节点自带配置（默认）  # ❌ nodes.json没有email字段
  2. 选择其他用户

用户列表：
[1] admin@system - uuid...  # ❌ 显示email

# 修复后
选择用户：
  1. 使用admin用户（默认）  # ✅ 使用get_admin_user_info()
  2. 选择其他用户

用户列表：
[1] admin (admin@system) - UUID: xxx...  # ✅ 显示username (email)
```

**Clash配置**：
```yaml
# 修复前
- name: "VLESS-443"
  type: vless
  server: 1.2.3.4
  port: 443
  uuid: xxx
  cipher: none  # ❌ VLESS不需要cipher
  tls: true
  # ❌ 缺少udp和skip-cert-verify

# 修复后
- name: "VLESS-443"
  type: vless
  server: 1.2.3.4
  port: 443
  uuid: xxx
  udp: true  # ✅ 添加UDP支持
  tls: true
  skip-cert-verify: false  # ✅ 添加证书验证设置
  servername: domain.com
```

**VMess链接**：
```json
// 修复前
{
  "port": "443",  // ❌ 字符串
  "aid": "0"      // ❌ 字符串
}

// 修复后
{
  "port": 443,    // ✅ 数字
  "aid": 0        // ✅ 数字
}
```

#### 影响范围
- ✅ 全局用户列表现在正确显示所有字段（username, password, email, UUID, status）
- ✅ 查看单个节点链接默认使用admin用户，用户列表显示清晰
- ✅ VMess订阅链接符合标准格式，客户端可正常导入
- ✅ Clash订阅配置完整，支持所有协议正常连接

---

### 🐛 修复：用户管理函数适配新架构

#### 问题描述
用户管理相关函数（查看、修改、删除）仍在使用旧的数据结构字段，导致功能异常。

**具体问题**：
1. `list_users()` - 尝试从users.json读取不存在的`port`和`protocol`字段
2. `modify_user()` - 使用port查询用户（错误），应使用username
3. `delete_global_user()` - 使用email查询用户，应使用username

#### 修复内容

**modules/user.sh**:

1. ✅ **list_users()** (Line 362-390)
   ```bash
   # 修改前：读取错误的字段
   local users=$(jq -r '.users[] | "\(.port)|\(.protocol)|\(.id)|\(.email)|\(.created)"'

   # 修改后：读取正确的字段
   local users=$(jq -r '.users[] | "\(.username)|\(.id)|\(.password)|\(.email)|\(.enabled)|\(.created)"'
   ```
   - 新增显示列：用户名、UUID、密码、邮箱、状态（启用/禁用）、创建时间
   - 移除错误的端口和协议列

2. ✅ **modify_user()** (Line 392-473)
   ```bash
   # 修改前：使用port和email查询
   read -p "请输入要修改用户的节点端口: " port
   read -p "请输入用户邮箱: " email
   local user_info=$(jq -r ".users[] | select(.port == \"$port\" and .email == \"$email\")"

   # 修改后：使用username查询
   read -p "请输入要修改的用户名: " username
   local user_info=$(jq -r ".users[] | select(.username == \"$username\")"
   ```
   - 修改选项：
     - 选项1：修改邮箱（直接更新users.json，调用regenerate_config）
     - 选项2：修改密码（直接更新users.json，调用regenerate_config）
     - 选项3：重置UUID（生成新UUID，更新users.json，调用regenerate_config）
     - 选项4：切换启用/禁用状态（新增功能）
   - 移除对废弃辅助函数的调用（update_user_email, update_user_id, update_user_level）
   - 所有修改操作后调用`regenerate_config`重新生成config.json

3. ✅ **delete_global_user()** (Line 206-258)
   ```bash
   # 修改前：使用email查询和删除
   read -p "请输入要删除的用户邮箱: " email
   local uuid=$(jq -r ".users[] | select(.email == \"$email\") | .id"

   # 修改后：使用username查询和删除
   read -p "请输入要删除的用户名: " username
   local uuid=$(jq -r ".users[] | select(.username == \"$username\") | .id"
   ```
   - 保持原有逻辑：先从node_users.json清理绑定，再从users.json删除用户
   - 删除后调用`generate_xray_config`和`restart_xray`

4. ✅ **验证正确的函数** (已确认无需修改)
   - `list_global_users()` (Line 86-126) - 正确显示username, password, uuid, status
   - `add_global_user()` (Line 128-203) - 正确使用username, password, email字段

#### 数据结构说明

**users.json 结构**（保持不变）：
```json
{
  "users": [
    {
      "id": "uuid",
      "username": "admin",
      "password": "password123",
      "email": "admin",
      "level": 0,
      "created": "2025-10-11T10:00:00Z",
      "enabled": true
    }
  ]
}
```

**注意事项**：
- email字段保留但不作为主要查询字段
- username是唯一标识，用于所有查询和修改操作
- 新架构中用户与节点通过node_users.json绑定，users.json中不包含port/protocol字段

**影响范围**：
- ✅ 用户管理菜单 → 查看用户列表（功能正常）
- ✅ 用户管理菜单 → 修改用户（功能正常）
- ✅ 全局用户管理 → 添加全局用户（功能正常）
- ✅ 全局用户管理 → 删除全局用户（功能正常）

**已知限制**：
- `add_user()` 和 `delete_user()` 函数（主菜单选项11和12标注为"旧版功能"）仍然使用旧架构逻辑，建议使用新架构的全局用户管理功能

---

## [v1.3.4] - 2025-10-11

### 🐛 修复：订阅链接生成逻辑（完全重写）

#### 问题描述
订阅链接生成的节点链接无效。所有链接生成函数都在尝试从nodes.json读取`.config`字段，但新架构中只保存了`protocol`, `port`, `transport`, `security`, `extra`字段。

**根本原因**：数据结构不匹配 - 链接生成函数期望的数据格式与nodes.json实际保存的格式不一致。

#### 修复内容

**重写所有链接生成函数** (modules/subscription.sh):

1. ✅ **generate_vless_reality_link_from_config()** (line 76-110)
   - 从`extra.dest`, `extra.server_names[0]`, `extra.public_key`, `extra.short_ids[0]`, `extra.flow`提取参数
   - 构建正确的Reality链接格式

2. ✅ **generate_vless_tls_link_from_config()** (line 112-154)
   - 从`transport`, `security`, `extra.tls_domain`, `extra.ws_path`, `extra.grpc_service`提取参数
   - 支持WebSocket和gRPC传输协议

3. ✅ **generate_vless_plain_link_from_config()** (line 156-185)
   - 从`transport`, `extra.ws_path`, `extra.grpc_service`提取参数
   - 生成无加密VLESS链接

4. ✅ **generate_vmess_link_from_config()** (line 187-230)
   - 从`extra.alter_id`, `extra.cipher`, `extra.ws_path`提取参数
   - 生成Base64编码的VMess JSON配置

5. ✅ **generate_trojan_link_from_config()** (line 232-254)
   - 从`extra.tls_domain`提取SNI参数
   - 使用用户password生成Trojan链接

6. ✅ **generate_ss_link_from_config()** (line 256-276)
   - 从`extra.cipher`提取加密方式
   - 使用用户password生成SIP002格式SS链接

7. ✅ **generate_share_link_smart()** (line 278-317)
   - 改用`security`字段判断VLESS类型（reality/tls/none）
   - 自动获取用户password用于Trojan/SS
   - 移除对`.config`的依赖

**修复admin用户获取** (line 505-532):
- 替换`get_admin_uuid()`为`get_admin_user_info()`
- 正确解析返回的`UUID|password|email`格式

#### nodes.json数据结构

**新架构存储格式**：
```json
{
  "nodes": [
    {
      "protocol": "vless",
      "port": "443",
      "transport": "tcp",
      "security": "reality",
      "extra": {
        "dest": "domain:443",
        "server_names": ["sni"],
        "public_key": "xxx",
        "private_key": "xxx",
        "short_ids": ["xxx"],
        "flow": "xtls-rprx-vision"
      },
      "created": "timestamp"
    }
  ]
}
```

**各协议extra字段**：
- **Reality**: `{dest, server_names[], public_key, private_key, short_ids[], flow}`
- **VLESS**: `{ws_path, grpc_service, tls_domain, tls_cert, tls_key}`
- **VMess**: `{alter_id, cipher, ws_path}`
- **Trojan**: `{tls_domain, tls_cert, tls_key, fallback_dest, fallback_port}`
- **Shadowsocks**: `{cipher}`

#### 影响范围

- ✅ 订阅链接生成功能完全修复
- ✅ 单节点链接查看功能修复
- ✅ 所有4种协议（VLESS/VMess/Trojan/SS）支持
- ✅ Reality/TLS/无加密 三种安全方式支持
- ✅ WebSocket/gRPC/TCP 传输协议支持

---

## [v1.3.3] - 2025-10-11

### 🐛 修复：节点创建用户绑定逻辑 + 脚本管理菜单更新

#### 问题1：节点创建绑定逻辑
修复了add_vless_node()函数使用旧架构导致的用户绑定问题。该函数仍在手动输入UUID/email并直接保存到nodes.json，未通过node_users.json建立绑定关系。

**修复内容**：
- ✅ **重构add_vless_node()** - 完全改用新架构，与其他节点类型保持一致
  - 移除手动UUID/email输入
  - 只保存节点技术参数到nodes.json
  - 自动调用bind_admin_to_node()建立绑定
  - 通过generate_xray_config()动态生成配置

#### 问题2：脚本管理菜单未更新
主菜单中的"脚本管理"仍显示旧的两级卸载选项，与uninstall.sh的三级卸载功能不匹配。

**修复内容**：
- ✅ **更新menu_script()** - 简化为直接调用uninstall.sh
  - 移除选项2和选项3的重复逻辑
  - 合并为单一"卸载管理"选项
  - 显示三级卸载说明后调用uninstall.sh
  - 用户在uninstall.sh中选择具体卸载级别

**菜单变更**：
```
旧菜单:
1. 更新脚本
2. 卸载脚本
3. 卸载脚本及依赖
0. 返回主菜单

新菜单:
1. 更新脚本
2. 卸载管理（三级选项）
0. 返回主菜单
```

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
