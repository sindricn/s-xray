# 出站规则管理模块

## 更新时间
2025-10-12

## 模块概述

新增出站规则管理模块,提供可视化的出站连接配置管理,支持 Freedom(直连)、Blackhole(黑洞)、代理链等多种出站类型。

---

## 功能特点

### 1. 多种出站类型
- **Freedom**: 直连出站,正常转发流量
- **Blackhole**: 黑洞出站,阻止访问(屏蔽广告/恶意网站)
- **Proxy**: 代理出站,使用现有节点作为代理

### 2. 高级配置
- **域名策略**: AsIs, UseIP, UseIPv4, UseIPv6等多种DNS解析策略
- **TCP分片**: 用于绕过SNI检测和审查
- **Mux多路复用**: 减少TCP握手延迟,提升连接效率
- **默认出站**: 设置路由不匹配时的默认出站

### 3. 可视化管理
- **列表展示**: 清晰显示所有出站规则
- **序号选择**: 统一使用序号管理,符合系统风格
- **交互友好**: 提供详细说明和默认值

### 4. 配置集成
- **导出到Xray**: 一键导出到Xray配置文件
- **自动备份**: 导出前自动备份现有配置
- **热重载**: 支持导出后立即重启Xray应用配置

---

## 出站类型详解

### Freedom (直连出站)

**用途**:
- 国内流量直连(不走代理)
- 白名单网站直接访问
- 提高国内网站访问速度

**配置选项**:
```bash
- 标签: 自定义标识(例如: direct, direct-cn)
- 域名策略:
  • AsIs: 使用系统DNS
  • UseIP: 使用内置DNS,IPv4优先
  • UseIPv4: 仅使用IPv4
  • UseIPv6: 仅使用IPv6
- TCP分片:
  • 分片包长度: 100-200 字节
  • 分片间隔: 10-20 毫秒
  • 用途: 绕过SNI黑名单检测
```

**示例配置**:
```json
{
  "protocol": "freedom",
  "tag": "direct",
  "settings": {
    "domainStrategy": "UseIP",
    "fragment": {
      "packets": "tlshello",
      "length": "100-200",
      "interval": "10-20"
    }
  }
}
```

**使用场景**:
- 配合路由规则,国内流量走direct
- 白名单网站不经过代理
- 提升国内CDN访问速度

---

### Blackhole (黑洞出站)

**用途**:
- 屏蔽广告域名
- 阻止恶意网站访问
- 过滤跟踪器和分析服务

**配置选项**:
```bash
- 标签: 自定义标识(例如: block, ad-block)
- 响应类型:
  • none: 直接关闭连接
  • http: 返回 HTTP 403 禁止访问
```

**示例配置**:
```json
{
  "protocol": "blackhole",
  "tag": "block",
  "settings": {
    "response": {
      "type": "http"
    }
  }
}
```

**使用场景**:
- 配合路由规则屏蔽广告域名列表
- 阻止已知的恶意网站
- 过滤telemetry和analytics域名

---

### Proxy (代理出站)

**用途**:
- 使用现有节点作为出站代理
- 实现代理链(多级跳转)
- 灵活切换不同代理节点

**配置选项**:
```bash
- 选择节点: 从现有节点列表中选择
- 标签: 自定义标识(例如: proxy-vless-443)
- Mux配置:
  • 启用/禁用多路复用
  • 并发数: 1-128 (默认: 8)
```

**示例配置**:
```json
{
  "protocol": "vless",
  "tag": "proxy-vless-443",
  "settings": {
    "vnext": [{
      "address": "1.2.3.4",
      "port": 443,
      "users": [{"id": "uuid-here", "flow": "xtls-rprx-vision"}]
    }]
  },
  "streamSettings": {
    "network": "tcp",
    "security": "reality"
  },
  "mux": {
    "enabled": true,
    "concurrency": 8
  }
}
```

**使用场景**:
- 指定某些流量走特定代理节点
- 实现地理位置跳转(如: 先日本再美国)
- 代理链增强隐私保护

---

## 使用指南

### 方法一: 通过主菜单

```bash
./xray-manager.sh
# → 9. 出站规则管理 (新增)
```

### 方法二: 直接运行模块

```bash
bash modules/outbound.sh
```

---

## 功能演示

### 1. 添加 Freedom 出站

```
╔═══════════════════════════════════════╗
║      添加 Freedom 直连出站          ║
╚═══════════════════════════════════════╝

Freedom 说明：
  • 直接向目标发送数据（正常转发）
  • 适用于国内流量、白名单网站
  • 支持域名策略、TCP分片等功能

请输入出站标签 (例如: direct): direct-cn

域名策略：
1. AsIs (默认，使用系统DNS)
2. UseIP (使用内置DNS，IPv4优先)
3. UseIPv4 (仅IPv4)
4. UseIPv6 (仅IPv6)

请选择 [1-4, 默认: 1]: 2

是否启用 TCP 分片（用于绕过 SNI 检测）? [y/N]: y

TCP 分片配置：
分片包长度范围 (默认: 100-200):
分片间隔(ms) (默认: 10-20):

✓ Freedom 出站添加成功！

出站信息：
  标签: direct-cn
  协议: Freedom (直连)
  域名策略: UseIP
  TCP分片: 已启用
```

### 2. 添加 Blackhole 出站

```
╔═══════════════════════════════════════╗
║      添加 Blackhole 黑洞出站        ║
╚═══════════════════════════════════════╝

Blackhole 说明：
  • 阻止所有数据出站（屏蔽访问）
  • 适用于广告域名、恶意网站
  • 配合路由规则使用

请输入出站标签 (例如: block): ad-block

响应类型：
1. none (直接关闭连接)
2. http (返回 HTTP 403)

请选择 [1-2, 默认: 1]: 2

✓ Blackhole 出站添加成功！

出站信息：
  标签: ad-block
  协议: Blackhole (黑洞)
  响应: http
```

### 3. 添加代理出站

```
╔═══════════════════════════════════════╗
║      添加代理出站                    ║
╚═══════════════════════════════════════╝

代理出站说明：
  • 使用现有节点作为出站代理
  • 适用于代理链、多级跳转
  • 支持 VLESS、VMess、Trojan、SS

现有节点列表：

[1] 协议: vless, 端口: 443, 加密: reality, 传输: tcp
[2] 协议: vmess, 端口: 10086, 加密: tls, 传输: ws
[3] 协议: trojan, 端口: 443, 加密: tls, 传输: tcp

请选择节点序号: 1

请输入出站标签 (例如: proxy-vless-443): proxy-us

是否启用 Mux 多路复用? [y/N]: y

Mux 并发数 (1-128, 默认: 8): 16

✓ 代理出站添加成功！

出站信息：
  标签: proxy-us
  协议: vless
  端口: 443
  Mux: 已启用 (并发: 16)
```

### 4. 查看出站规则列表

```
╔═══════════════════════════════════════╗
║          出站规则列表                ║
╚═══════════════════════════════════════╝

共 4 条出站规则

序号  标签                 协议                 类型            说明
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
1     direct-cn            freedom              直连出站        直连, 策略: UseIP
2     ad-block             blackhole            黑洞出站        黑洞屏蔽
3     proxy-us             vless                VLESS 代理      Mux: 是
4     proxy-jp             vmess                VMess 代理      Mux: 否

提示：
  • 第一条出站规则为默认出站
  • 路由不匹配时使用默认出站
```

### 5. 设置默认出站

```
请输入要设为默认的出站规则序号: 3

✓ 默认出站已设置为: proxy-us

说明: 路由规则不匹配时,流量将通过 proxy-us 出站
```

### 6. 导出到 Xray 配置

```
╔═══════════════════════════════════════╗
║      导出出站配置到 Xray            ║
╚═══════════════════════════════════════╝

即将导出 4 条出站规则到 Xray 配置

确认导出? [y/N]: y

✓ 已备份当前配置
✓ 出站配置导出成功！

是否重启 Xray 服务使配置生效? [y/N]: y

✓ Xray 服务重启成功
```

---

## Mux 多路复用说明

### 什么是 Mux?

Mux (Multiplexing) 在一条TCP连接上分发多个TCP连接的数据,减少TCP握手延迟。

### 优势

- ✅ **减少延迟**: 避免多次TCP三次握手
- ✅ **连接复用**: 节省服务器资源
- ✅ **突破限制**: 绕过某些连接数限制

### 注意事项

- ❌ **不适合大流量**: 看视频、下载、测速时反而降低速度
- ❌ **仅客户端启用**: 服务器自动适配
- ⚠️ **适用场景**: 网页浏览、API请求等小流量场景

### Mux 参数

```json
{
  "enabled": true,          // 是否启用
  "concurrency": 8,         // 最大并发数(1-128)
  "xudpConcurrency": 16,    // UDP并发数(可选)
  "xudpProxyUDP443": "reject" // UDP/443处理方式
}
```

**并发数建议**:
- 网页浏览: 8 (默认)
- API密集: 16
- 低延迟优先: 4
- 连接数多: 32

---

## 配合路由规则使用

出站规则需要配合路由规则才能生效:

### 示例路由配置

```json
{
  "routing": {
    "domainStrategy": "IPIfNonMatch",
    "rules": [
      {
        "type": "field",
        "domain": ["geosite:cn"],
        "outboundTag": "direct-cn"
      },
      {
        "type": "field",
        "domain": ["geosite:category-ads-all"],
        "outboundTag": "ad-block"
      },
      {
        "type": "field",
        "ip": ["geoip:cn"],
        "outboundTag": "direct-cn"
      },
      {
        "type": "field",
        "network": "tcp,udp",
        "outboundTag": "proxy-us"
      }
    ]
  }
}
```

**规则说明**:
1. 国内域名 → 直连 (direct-cn)
2. 广告域名 → 黑洞 (ad-block)
3. 国内IP → 直连 (direct-cn)
4. 其他流量 → 代理 (proxy-us)

---

## 文件结构

### 出站规则存储

**文件**: `/usr/local/xray/data/outbounds.json`

**格式**:
```json
{
  "outbounds": [
    {
      "protocol": "freedom",
      "tag": "direct-cn",
      "settings": {
        "domainStrategy": "UseIP"
      }
    },
    {
      "protocol": "blackhole",
      "tag": "ad-block",
      "settings": {
        "response": {"type": "http"}
      }
    },
    {
      "protocol": "vless",
      "tag": "proxy-us",
      "settings": {...},
      "streamSettings": {...},
      "mux": {"enabled": true, "concurrency": 8}
    }
  ]
}
```

### 配置导出

导出时会:
1. 备份当前 Xray 配置到 `config.json.backup.{timestamp}`
2. 合并出站规则到 `config.json` 的 `outbounds` 字段
3. 可选择是否重启 Xray 服务

---

## 核心函数

**文件**: `modules/outbound.sh`

### 主要函数

#### init_outbound_file()

初始化出站规则文件,如果不存在则创建空配置。

#### add_freedom_outbound()

添加 Freedom 直连出站,支持:
- 域名策略选择
- TCP分片配置
- 交互式参数输入

#### add_blackhole_outbound()

添加 Blackhole 黑洞出站,支持:
- 响应类型选择(none/http)
- 快速配置广告屏蔽

#### add_proxy_outbound()

从现有节点添加代理出站,支持:
- 节点列表选择
- Mux配置
- 自动生成配置

#### list_outbounds()

列表展示所有出站规则,显示:
- 序号、标签、协议
- 类型名称
- 配置摘要(域名策略/Mux状态)

#### set_default_outbound()

设置默认出站,将指定出站移动到列表第一位。

#### modify_outbound_mux()

修改出站的 Mux 配置,支持启用/禁用和并发数调整。

#### export_outbounds_to_xray()

导出出站配置到 Xray,自动备份并可选重启服务。

---

## 使用场景

### 场景一: 国内直连 + 国外代理

**目标**: 国内流量直连,国外流量代理

**配置步骤**:
1. 添加 Freedom 出站 (tag: direct-cn, 域名策略: UseIP)
2. 添加代理出站 (tag: proxy-us, 从节点选择US服务器)
3. 设置 proxy-us 为默认出站
4. 配置路由规则: geosite:cn → direct-cn, 其他 → proxy-us

### 场景二: 屏蔽广告 + 正常上网

**目标**: 屏蔽广告域名,其他正常访问

**配置步骤**:
1. 添加 Blackhole 出站 (tag: ad-block, 响应: http)
2. 添加 Freedom 出站 (tag: direct, 域名策略: AsIs)
3. 设置 direct 为默认出站
4. 配置路由规则: geosite:category-ads-all → ad-block

### 场景三: 代理链（多级跳转）

**目标**: 流量先经过日本节点,再到美国节点

**配置步骤**:
1. 添加代理出站 JP (tag: proxy-jp, 日本节点)
2. 添加代理出站 US (tag: proxy-us, 美国节点)
3. 在 Xray 配置中设置 proxy-us 的 proxySettings.tag 为 proxy-jp
4. 路由规则指向 proxy-us

---

## 高级用法

### TCP 分片绕过SNI检测

某些地区会检测TLS握手中的SNI字段并阻断连接。TCP分片可以欺骗审查系统:

**原理**: 将TLS Client Hello拆分成多个小包发送

**配置**:
```bash
- 分片包长度: 100-200字节 (随机长度更难被识别)
- 分片间隔: 10-20毫秒 (模拟正常网络延迟)
- 分片方式: tlshello (TLS握手包分片)
```

**适用场景**:
- SNI黑名单阻断
- TLS指纹识别规避
- 深度包检测(DPI)绕过

### 域名策略优化

不同网络环境选择不同策略:

| 环境 | 推荐策略 | 原因 |
|------|----------|------|
| 国内网络 | UseIPv4 | 国内IPv6不普及 |
| IPv6网络 | UseIPv6v4 | 优先IPv6,回落IPv4 |
| 纯IPv6 | ForceIPv6 | 强制IPv6,避免DNS泄露 |
| 防DNS污染 | AsIs + 内置DNS | 使用可信DNS服务器 |

---

## 故障排查

### 问题1: 出站规则不生效

**原因**: 没有配置路由规则或路由规则优先级问题

**解决**:
1. 检查是否配置了路由规则
2. 确认路由规则的 outboundTag 与出站标签一致
3. 查看 Xray 日志: `journalctl -u xray -f`

### 问题2: Mux 导致速度变慢

**原因**: Mux 不适合大流量场景

**解决**:
1. 对于视频、下载流量禁用 Mux
2. 将 concurrency 设为负数: -1 (仅对该出站禁用Mux)
3. 或在路由规则中将大流量域名指向无Mux的出站

### 问题3: TCP 分片导致连接失败

**原因**: 某些网络不支持过小的分片包

**解决**:
1. 增大分片包长度: 200-300
2. 减少分片间隔: 5-10ms
3. 或完全禁用TCP分片

---

## 最佳实践

### 出站配置建议

1. **至少配置3个出站**:
   - direct: 直连出站(默认)
   - block: 黑洞出站(广告屏蔽)
   - proxy: 代理出站(翻墙)

2. **合理使用Mux**:
   - 网页浏览: 启用
   - 视频流媒体: 禁用
   - 下载上传: 禁用

3. **域名策略选择**:
   - 国内环境: UseIPv4
   - 国外环境: UseIP
   - 隐私优先: ForceIP

4. **标签命名规范**:
   - direct-cn, direct-global
   - block-ads, block-malware
   - proxy-us, proxy-jp, proxy-hk

### 性能优化

1. **减少不必要的出站**: 只配置实际使用的出站
2. **Mux并发数**: 根据实际并发连接数调整(一般8-16即可)
3. **TCP分片**: 仅在必要时启用(有性能损耗)

---

## 后续优化计划

### 短期 (1-2周)
- [ ] 支持从节点批量生成代理出站
- [ ] 出站测试功能(延迟测试、连通性检查)
- [ ] 出站分组管理(按地区、用途分组)

### 中期 (1个月)
- [ ] 可视化路由规则配置
- [ ] 出站负载均衡配置
- [ ] 自动故障切换

### 长期 (2-3个月)
- [ ] 出站性能监控和统计
- [ ] 智能出站选择(基于延迟、负载)
- [ ] 图形化出站拓扑展示

---

## 集成到主菜单

在 `xray-manager.sh` 主菜单中添加:

```bash
echo -e "${GREEN}9.${NC} 出站规则管理"

case $choice in
    ...
    9) source "${MODULES_DIR}/outbound.sh" && outbound_management_menu ;;
    ...
esac
```

---

**模块完成时间**: 2025-10-12
**状态**: ✅ 已完成并测试
**依赖**: jq, 节点管理模块
**文件**: `modules/outbound.sh`, `data/outbounds.json`
