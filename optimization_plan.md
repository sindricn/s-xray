# Xray 管理脚本优化方案

## 优化时间
2025-10-12

## 优化目标

### 1. 菜单结构精简
- 用户管理菜单过于复杂，需要重新组织
- 节点管理菜单选项过多，需要分类整理

### 2. 统一选择交互
- 当前：用户/节点/订阅选择方式不统一（序号/端口混用）
- 目标：统一使用序号选择，支持单选和多选

### 3. 域名自动优选
- 添加伪装域名时自动从优质域名列表中选择
- 支持手动输入或自动推荐

### 4. 出站规则管理
- 新增出站规则管理模块
- 支持直连、代理、拦截等规则配置

---

## 详细方案

### 📋 方案 1: 菜单结构精简

#### 当前问题分析

**用户管理菜单**（过于复杂）:
```
👥 全局用户管理：
1. 查看全局用户列表
2. 添加全局用户
3. 删除全局用户
4. 编辑全局用户
5. 刷新全局用户到所有节点

🔗 节点用户管理：
6. 添加用户到节点
7. 从节点移除用户
8. 查看节点的用户列表
9. 查看所有绑定关系

0. 返回主菜单
```

**节点管理菜单**（分类不清晰）:
```
⚡ 快速搭建：
1. 添加 VLESS Reality 节点
2. 添加 VLESS TLS 节点
3. 添加 VMess 节点
4. 添加 Trojan 节点
5. 添加 Shadowsocks 节点

🔧 节点管理：
6. 删除节点
7. 查看节点列表
8. 修改节点配置

👥 节点用户管理：
9. 查看节点的用户列表
10. 查看所有绑定关系
11. 添加用户到节点
12. 从节点移除用户
```

#### 优化后菜单结构

**用户管理菜单**（精简版）:
```
╔═══════════════════════════════════════╗
║          用户管理                    ║
╚═══════════════════════════════════════╝

1. 用户列表
2. 添加用户
3. 删除用户
4. 编辑用户
5. 绑定到节点

0. 返回主菜单
```

**节点管理菜单**（精简版）:
```
╔═══════════════════════════════════════╗
║          节点管理                    ║
╚═══════════════════════════════════════╝

⚡ 快速添加：
1. Reality 节点    2. TLS 节点
3. VMess 节点      4. Trojan 节点

📋 节点操作：
5. 节点列表        6. 删除节点
7. 编辑节点        8. 绑定用户

0. 返回主菜单
```

#### 实现策略
- 合并重复功能
- 将复杂操作简化为向导式流程
- 减少菜单层级

---

### 🎯 方案 2: 统一选择交互

#### 当前问题

**不统一的选择方式**:
- 用户选择：按序号
- 节点选择：有的用序号，有的用端口
- 订阅选择：按名称

#### 统一选择器设计

**功能特性**:
```bash
# 单选模式
select_item() {
    local items=("$@")
    # 显示带序号的列表
    # 返回选择的序号
}

# 多选模式
select_multiple_items() {
    local items=("$@")
    # 支持：1,3,5 或 1-5 或 all
    # 返回选中项的索引数组
}
```

**使用场景**:
1. **单选**: 编辑用户、编辑节点、查看详情
2. **多选**: 删除多个用户、删除多个节点、批量绑定

**交互示例**:
```
节点列表：
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
[1] VLESS-Reality-443   (启用)
[2] VLESS-TLS-8443      (启用)
[3] VMess-10086         (禁用)
[4] Trojan-443          (启用)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

请选择节点:
  单个: 输入序号 (如: 1)
  多个: 用逗号分隔 (如: 1,3,4)
  范围: 用连字符 (如: 1-3)
  全部: 输入 all

选择:
```

#### 实现步骤
1. 创建通用选择器函数库 (`modules/selector.sh`)
2. 统一列表显示格式
3. 更新所有模块使用统一选择器

---

### 🌐 方案 3: 域名自动优选

#### 功能设计

**优质域名列表**:
```bash
# 高信誉度域名（按分类）
PREMIUM_DOMAINS=(
    # 科技公司
    "www.microsoft.com"
    "www.apple.com"
    "www.cisco.com"
    "www.ibm.com"

    # 新闻媒体
    "www.bbc.com"
    "www.reuters.com"
    "www.bloomberg.com"

    # 电商平台
    "www.amazon.com"
    "www.ebay.com"

    # 云服务
    "aws.amazon.com"
    "cloud.google.com"
    "azure.microsoft.com"
)
```

**交互流程**:
```
设置伪装域名：
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

1. 使用推荐域名（自动优选）
2. 手动输入域名

请选择 [1-2, 默认: 1]: 1

正在从 15 个优质域名中随机选择...

推荐域名: www.microsoft.com

  ✓ 域名解析正常
  ✓ SSL 证书有效
  ✓ 响应速度: 45ms

确认使用该域名? [Y/n]:
```

#### 域名验证
- DNS 解析测试
- SSL 证书验证
- 响应速度测试
- HTTPS 可用性

#### 实现位置
`modules/domain.sh` - 添加 `auto_select_domain()` 函数

---

### 🚀 方案 4: 出站规则管理

#### 功能需求

基于 `docs/outbound.md` 实现出站规则管理。

**核心功能**:
1. 出站配置管理
2. 路由规则配置
3. 分流策略设置
4. Mux 多路复用配置

#### 出站类型

**支持的出站协议**:
- `freedom` - 直连
- `blackhole` - 拦截
- `socks` - SOCKS5 代理
- `http` - HTTP 代理
- `vmess` - VMess 出站
- `vless` - VLESS 出站
- `trojan` - Trojan 出站
- `shadowsocks` - SS 出站

#### 菜单设计

```
╔═══════════════════════════════════════╗
║        出站规则管理                  ║
╚═══════════════════════════════════════╝

📤 出站配置：
1. 查看出站列表
2. 添加出站规则
3. 删除出站规则
4. 编辑出站规则

🔀 路由规则：
5. 配置直连规则
6. 配置代理规则
7. 配置拦截规则

⚙️ 高级配置：
8. Mux 多路复用设置
9. 域名分流配置

0. 返回主菜单
```

#### 预设规则模板

**模板 1: 国内直连**
```json
{
  "tag": "direct-cn",
  "protocol": "freedom",
  "settings": {
    "domainStrategy": "UseIP"
  }
}
```

**模板 2: 广告拦截**
```json
{
  "tag": "block-ads",
  "protocol": "blackhole",
  "settings": {
    "response": {
      "type": "http"
    }
  }
}
```

**模板 3: 代理出站**
```json
{
  "tag": "proxy",
  "protocol": "freedom",
  "settings": {},
  "streamSettings": {},
  "mux": {
    "enabled": true,
    "concurrency": 8
  }
}
```

#### 路由规则配置

**规则类型**:
- 域名规则（domain）
- IP 规则（ip）
- 端口规则（port）
- 协议规则（protocol）
- 用户规则（user）

**示例配置**:
```json
{
  "routing": {
    "rules": [
      {
        "type": "field",
        "domain": [
          "geosite:cn"
        ],
        "outboundTag": "direct-cn"
      },
      {
        "type": "field",
        "domain": [
          "geosite:category-ads"
        ],
        "outboundTag": "block-ads"
      },
      {
        "type": "field",
        "ip": [
          "geoip:cn",
          "geoip:private"
        ],
        "outboundTag": "direct-cn"
      }
    ]
  }
}
```

#### 实现文件
- `modules/outbound.sh` - 出站规则管理
- `modules/routing.sh` - 路由规则配置

---

## 实施计划

### 阶段 1: 基础组件 (1-2天)

#### 1.1 统一选择器
- [ ] 创建 `modules/selector.sh`
- [ ] 实现单选函数 `select_single()`
- [ ] 实现多选函数 `select_multiple()`
- [ ] 添加输入验证和错误处理

#### 1.2 列表显示优化
- [ ] 统一列表格式（序号、状态、主要信息）
- [ ] 添加颜色和图标标识
- [ ] 实现分页显示（超过10项时）

### 阶段 2: 菜单重构 (2-3天)

#### 2.1 用户管理重构
- [ ] 精简菜单选项（9项→5项）
- [ ] 整合绑定功能
- [ ] 统一选择交互

#### 2.2 节点管理重构
- [ ] 精简菜单选项（12项→8项）
- [ ] 优化快速添加流程
- [ ] 统一选择交互

#### 2.3 订阅管理优化
- [ ] 统一订阅选择方式
- [ ] 支持多选删除

### 阶段 3: 新功能开发 (3-4天)

#### 3.1 域名自动优选
- [ ] 构建优质域名库
- [ ] 实现域名验证功能
- [ ] 集成到节点创建流程

#### 3.2 出站规则管理
- [ ] 创建出站管理模块
- [ ] 实现规则模板
- [ ] 集成路由配置

### 阶段 4: 测试和文档 (1-2天)

#### 4.1 功能测试
- [ ] 单元测试各模块
- [ ] 集成测试完整流程
- [ ] 用户体验测试

#### 4.2 文档更新
- [ ] 更新使用指南
- [ ] 编写功能说明
- [ ] 创建示例配置

---

## 技术实现

### 统一选择器实现

```bash
# modules/selector.sh

# 单选函数
select_single() {
    local prompt="$1"
    shift
    local items=("$@")

    # 显示列表
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    for i in "${!items[@]}"; do
        echo "[$((i+1))] ${items[$i]}"
    done
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    # 获取选择
    while true; do
        read -p "$prompt [1-${#items[@]}]: " choice
        if [[ "$choice" =~ ^[0-9]+$ ]] && [[ $choice -ge 1 ]] && [[ $choice -le ${#items[@]} ]]; then
            echo $((choice-1))
            return 0
        fi
        echo "无效选择，请重新输入"
    done
}

# 多选函数
select_multiple() {
    local prompt="$1"
    shift
    local items=("$@")

    # 显示列表
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    for i in "${!items[@]}"; do
        echo "[$((i+1))] ${items[$i]}"
    done
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "支持格式："
    echo "  单个: 1"
    echo "  多个: 1,3,5"
    echo "  范围: 1-3"
    echo "  全部: all"
    echo ""

    while true; do
        read -p "$prompt: " input

        if [[ "$input" == "all" ]]; then
            # 返回所有索引
            local all_indices=()
            for i in "${!items[@]}"; do
                all_indices+=("$i")
            done
            echo "${all_indices[@]}"
            return 0
        fi

        # 解析选择
        local selected_indices=()
        IFS=',' read -ra parts <<< "$input"

        for part in "${parts[@]}"; do
            if [[ "$part" =~ ^([0-9]+)-([0-9]+)$ ]]; then
                # 范围选择
                local start=${BASH_REMATCH[1]}
                local end=${BASH_REMATCH[2]}
                for ((i=start; i<=end; i++)); do
                    if [[ $i -ge 1 ]] && [[ $i -le ${#items[@]} ]]; then
                        selected_indices+=($((i-1)))
                    fi
                done
            elif [[ "$part" =~ ^[0-9]+$ ]]; then
                # 单个选择
                if [[ $part -ge 1 ]] && [[ $part -le ${#items[@]} ]]; then
                    selected_indices+=($((part-1)))
                fi
            fi
        done

        if [[ ${#selected_indices[@]} -gt 0 ]]; then
            echo "${selected_indices[@]}"
            return 0
        fi

        echo "无效选择，请重新输入"
    done
}
```

### 域名自动优选实现

```bash
# modules/domain.sh

# 优质域名库
PREMIUM_DOMAINS=(
    "www.microsoft.com"
    "www.apple.com"
    "www.cisco.com"
    "www.ibm.com"
    "www.intel.com"
    "www.bbc.com"
    "www.reuters.com"
    "www.bloomberg.com"
    "www.amazon.com"
    "www.ebay.com"
    "aws.amazon.com"
    "cloud.google.com"
    "azure.microsoft.com"
    "www.cloudflare.com"
    "www.nginx.com"
)

# 自动选择域名
auto_select_domain() {
    echo ""
    echo "正在从 ${#PREMIUM_DOMAINS[@]} 个优质域名中随机选择..."
    echo ""

    # 随机选择
    local random_index=$((RANDOM % ${#PREMIUM_DOMAINS[@]}))
    local selected_domain="${PREMIUM_DOMAINS[$random_index]}"

    echo "推荐域名: ${selected_domain}"
    echo ""

    # 验证域名
    echo "正在验证域名..."

    # DNS 解析测试
    if host "$selected_domain" >/dev/null 2>&1; then
        echo -e "  ${GREEN}✓${NC} 域名解析正常"
    else
        echo -e "  ${RED}✗${NC} 域名解析失败"
        return 1
    fi

    # SSL 测试
    if timeout 3 openssl s_client -connect "${selected_domain}:443" </dev/null >/dev/null 2>&1; then
        echo -e "  ${GREEN}✓${NC} SSL 证书有效"
    else
        echo -e "  ${YELLOW}⚠${NC} SSL 证书检查超时"
    fi

    # 响应速度测试
    local start_time=$(date +%s%3N)
    if curl -s -o /dev/null -w "%{http_code}" --connect-timeout 3 "https://${selected_domain}" >/dev/null 2>&1; then
        local end_time=$(date +%s%3N)
        local response_time=$((end_time - start_time))
        echo -e "  ${GREEN}✓${NC} 响应速度: ${response_time}ms"
    fi

    echo ""
    read -p "确认使用该域名? [Y/n]: " confirm
    confirm=${confirm:-Y}

    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        echo "$selected_domain"
        return 0
    else
        return 1
    fi
}
```

---

## 预期效果

### 用户体验改进
- ✅ 菜单更简洁，操作更直观
- ✅ 选择方式统一，学习成本降低
- ✅ 批量操作支持，效率提升
- ✅ 自动优选减少错误配置

### 功能增强
- ✅ 出站规则管理
- ✅ 域名自动优选
- ✅ 批量操作支持
- ✅ 多选功能

### 代码质量
- ✅ 模块化程度更高
- ✅ 代码复用性提升
- ✅ 维护性增强

---

## 兼容性

### 向后兼容
- 保留所有现有功能
- 数据格式不变
- 配置文件兼容

### 迁移说明
- 无需手动迁移
- 自动适配新交互方式
- 提供使用文档

---

**优化方案编写完成时间**: 2025-10-12
**预计实施周期**: 7-10 天
**优先级**: 高
