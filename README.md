# Xray-Core 一键管理脚本

基于 Xray-Core 的全功能一键搭建和管理脚本，支持多协议、多用户、订阅管理等企业级特性。

> **版本：v1.2.0** | 基于 S-Hy2 最佳实践优化 | 增强的错误处理和日志系统

## 功能特性

### ✨ 核心功能

- 🚀 **内核管理**：一键安装、卸载、更新、启动、停止 Xray-Core
- 🔧 **节点管理**：支持 VLESS、VMess、Trojan、Shadowsocks 四大协议
- 👥 **用户管理**：多用户管理、UUID 自动生成、用户配置修改
- 📱 **订阅管理**：自动生成订阅链接、支持多订阅、内置订阅服务器
- 📊 **状态监控**：实时监控、流量统计、连接状态、日志查看
- 🔥 **防火墙管理**：自动识别防火墙类型、批量开放端口
- ⚙️ **配置管理**：配置验证、备份恢复、导入导出
- 🌐 **域名管理**：Reality 域名优选、自定义域名管理
- 🔐 **证书管理**：自动生成、手动导入、证书验证

### 🎯 协议支持

| 协议 | 传输方式 | 加密层 | 特性 |
|------|---------|-------|------|
| VLESS | TCP/WS/gRPC/H2 | TLS/Reality | XTLS Vision、零加密、Reality 抗审查 |
| VMess | TCP/WS/mKCP | TLS | 多种加密方式 |
| Trojan | TCP | TLS | 回落配置 |
| Shadowsocks | TCP/UDP | 无 | 2022版加密 |

### ⚡ 一键搭建

**VLESS + Reality 节点**（推荐）
- 协议层：VLESS (零加密，性能最优)
- 传输层：TCP (稳定可靠)
- 加密层：Reality (最新抗审查技术)
- 特点：无需域名和证书，自动生成密钥对

## 系统要求

- 操作系统：Ubuntu 18+、Debian 10+、CentOS 7+
- 架构：x86_64、ARM64、ARMv7
- 权限：Root
- 依赖：curl、wget、unzip、jq

## 快速开始

### 一键安装（推荐）

```bash
# 从 GitHub 一键安装（默认安装到 /opt/s-xray）
curl -fsSL https://raw.githubusercontent.com/sindricn/s-xray/main/install.sh | sudo bash

# 或使用 wget
wget -qO- https://raw.githubusercontent.com/sindricn/s-xray/main/install.sh | sudo bash
```

安装完成后，直接使用快捷命令启动：
```bash
s-xray
```

**说明：**
- 安装脚本会自动下载完整项目到 `/opt/s-xray`
- 自动创建全局命令 `s-xray`
- 支持 Git、wget、curl 多种下载方式

### 手动安装

```bash
# 克隆仓库
git clone https://github.com/sindricn/s-xray.git
cd s-xray

# 运行安装脚本
sudo bash install.sh

# 或直接运行主脚本
chmod +x xray-manager.sh
sudo ./xray-manager.sh
```

### 首次使用

1. **安装 Xray 内核**
   ```
   主菜单 -> 1. 内核管理 -> 1. 安装 Xray
   ```

2. **添加节点**
   ```
   主菜单 -> 2. 节点管理 -> 1. 一键搭建 VLESS + Reality 节点（推荐）

   或选择其他协议类型自定义配置
   ```

3. **添加用户**
   ```
   主菜单 -> 3. 用户管理 -> 1. 添加用户
   ```

4. **生成订阅**
   ```
   主菜单 -> 4. 订阅管理 -> 1. 生成订阅链接
   ```

5. **开放防火墙端口**
   ```
   主菜单 -> 6. 防火墙管理 -> 1. 开放端口
   ```

## 详细功能说明

### 1. 内核管理

#### 安装 Xray
- 自动检测系统架构
- 从 GitHub 获取最新版本
- 自动创建 systemd 服务
- 生成默认配置文件

```bash
# 手动安装
./xray-manager.sh
选择：1 -> 1
```

#### 更新 Xray
- 检测当前版本和最新版本
- 自动备份配置
- 无缝更新到最新版

### 2. 节点管理

#### 🚀 一键搭建 VLESS + Reality（推荐）

**三层架构**：
- **协议层**：VLESS (零加密，性能最优)
- **传输层**：TCP (稳定可靠)
- **加密层**：Reality (最新抗审查技术)

**特点**：
- 无需域名和证书
- 自动生成密钥对和 ShortId
- 自动生成分享链接
- 抗主动探测和审查

**配置流程**：
```bash
主菜单 -> 2. 节点管理 -> 1. 一键搭建 VLESS + Reality 节点

配置项：
- 监听端口 [默认: 443]
- 用户 UUID [自动生成]
- 用户备注 [默认: user@reality]
- 目标网站 (SNI) [默认: www.microsoft.com]
- 伪装域名 [默认: 同目标网站]

自动生成：
- Reality 密钥对（公钥/私钥）
- ShortId (8-16位)
- 分享链接
```

**输出信息**：
```
节点信息：
  端口: 443
  UUID: xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
  Flow: xtls-rprx-vision

Reality 配置：
  目标网站: www.microsoft.com
  伪装域名: www.microsoft.com
  公钥: xxxxxxxxxxxxxxxxxxxxxxxxxx
  ShortId: xxxxxxxxxxxxxxxx

分享链接：vless://...
```

#### VLESS 节点（自定义）

**特点**：
- 支持 XTLS Vision 流控
- 零加密开销
- 多种传输协议
- 支持 TLS/Reality 加密

**配置选项**：
- 端口：自定义监听端口
- UUID：自动生成或手动指定
- 传输：TCP、WebSocket、gRPC、HTTP/2
- 加密：TLS 或 Reality

**示例**：
```bash
端口: 443
UUID: 自动生成
传输: WebSocket
路径: /ws
加密: TLS
域名: example.com
```

#### VMess 节点

**特点**：
- 经典稳定协议
- 多种加密方式
- 广泛客户端支持

**配置选项**：
- 加密：auto、aes-128-gcm、chacha20-poly1305
- AlterID：建议使用 0
- 传输：TCP、WebSocket、mKCP

#### Trojan 节点

**特点**：
- 强制 TLS 加密
- 回落功能
- 伪装能力强

**配置选项**：
- 密码：自定义密码
- 证书：必须配置 TLS
- 回落：可配置回落地址

#### Shadowsocks 节点

**特点**：
- 轻量级协议
- UDP 支持
- 简单易用

**配置选项**：
- 加密：aes-256-gcm、chacha20-poly1305
- 网络：TCP+UDP

### 3. 用户管理

#### 添加用户
- 支持添加到现有节点
- 自动生成 UUID
- 多用户隔离

#### 用户配置修改
- 修改邮箱/备注
- 重置 UUID/密码
- 调整用户等级

#### 用户等级系统
```
等级 0-10，数字越大优先级越高
- 等级 0：普通用户
- 等级 5：VIP 用户
- 等级 10：管理员
```

### 4. 订阅管理

#### 生成订阅
- 自动收集所有节点和用户
- 生成 Base64 编码订阅
- 内置 HTTP 订阅服务器

#### 订阅链接格式
```
http://your-server-ip:8080/sub/default
```

#### 订阅配置
- 自定义订阅域名
- 自定义订阅端口
- 订阅加密选项

### 5. 状态监控

#### 运行状态
- 服务状态
- 版本信息
- 运行时长
- 资源使用（CPU、内存）
- 端口监听
- 节点统计

#### 流量统计
- 入站流量统计
- 用户流量统计
- 上行/下行流量分离

**前提条件**：
配置文件中需包含以下内容：
```json
{
  "api": {
    "tag": "api",
    "services": ["HandlerService", "StatsService"]
  },
  "stats": {},
  "policy": {
    "system": {
      "statsInboundUplink": true,
      "statsInboundDownlink": true
    }
  }
}
```

#### 连接信息
- 活动连接数
- 连接详情
- 按端口分组统计

#### 实时监控
- 刷新间隔：3秒
- 监控内容：
  - 服务状态
  - 资源使用
  - 连接统计
  - 网络流量
  - 最新日志

### 6. 防火墙管理

#### 支持的防火墙
- UFW (Ubuntu)
- Firewalld (CentOS/RHEL)
- iptables (通用)

#### 功能
- 自动检测防火墙类型
- 开放/关闭端口
- 支持 TCP/UDP/both
- 批量开放节点端口
- 查看防火墙规则

#### 批量开放端口
自动读取所有节点端口并批量开放，一键完成防火墙配置。

### 7. 配置管理

#### 查看配置
使用 jq 格式化显示当前配置

#### 编辑配置
- 自动备份
- 自动验证
- 失败回滚

#### 备份配置
- 自动命名（时间戳）
- 保留最近 10 个备份
- 支持手动备份

#### 恢复配置
- 列出所有备份
- 选择性恢复
- 验证后生效

#### 验证配置
- JSON 语法检查
- Xray 内置验证
- 详细错误信息

#### 导入/导出
- 支持 JSON 配置文件
- 支持 tar.gz 压缩包
- 包含节点和用户数据

## 目录结构

```
s-xray/
├── xray-manager.sh          # 主脚本入口
├── modules/                 # 功能模块目录
│   ├── core.sh             # 内核管理
│   ├── node.sh             # 节点管理
│   ├── user.sh             # 用户管理
│   ├── subscription.sh     # 订阅管理
│   ├── monitor.sh          # 状态监控
│   ├── firewall.sh         # 防火墙管理
│   └── config.sh           # 配置管理
├── docs/                    # Xray 官方配置文档
└── README.md               # 使用说明
```

## 数据文件

脚本运行后会在 `/usr/local/xray/data/` 目录下创建以下文件：

```
/usr/local/xray/
├── xray                    # Xray 可执行文件
├── config.json            # 主配置文件
├── access.log             # 访问日志
├── error.log              # 错误日志
├── data/                  # 数据目录
│   ├── users.json         # 用户数据库
│   ├── nodes.json         # 节点数据库
│   ├── subscriptions/     # 订阅文件
│   ├── backups/          # 配置备份
│   └── exports/          # 配置导出
└── certs/                # 证书目录
```

## 常见问题

### 1. 安装失败

**问题**：下载超时或失败

**解决**：
```bash
# 检查网络连接
ping github.com

# 手动下载安装包
wget https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-64.zip
```

### 2. 无法获取流量统计

**原因**：API 服务未配置

**解决**：确保配置文件包含 API 和 Stats 配置（安装时自动添加）

### 3. 防火墙端口未开放

**问题**：节点无法连接

**解决**：
```bash
# 使用脚本开放端口
主菜单 -> 6 -> 1

# 或手动开放
ufw allow 443/tcp
firewall-cmd --permanent --add-port=443/tcp && firewall-cmd --reload
```

### 4. 订阅服务无法访问

**问题**：订阅链接无法打开

**解决**：
```bash
# 检查订阅服务状态
ps aux | grep subscription_server

# 重启订阅服务
主菜单 -> 4 -> 5 -> 3

# 检查端口是否开放
netstat -tlnp | grep 8080
```

### 5. 配置验证失败

**问题**：JSON 格式错误

**解决**：
```bash
# 使用 jq 验证
jq . /usr/local/xray/config.json

# 恢复备份
主菜单 -> 7 -> 4
```

### 6. Reality 密钥生成失败

**问题**：提示"密钥生成失败，请检查 Xray 是否正确安装"

**原因**：
- Xray 未安装或路径不正确
- Xray 版本过低，不支持 x25519 命令
- 执行权限问题

**解决步骤**：

1. **检查 Xray 是否已安装**
   ```bash
   ls -l /usr/local/xray/xray
   /usr/local/xray/xray version
   ```

2. **安装或更新 Xray**
   ```bash
   # 通过脚本安装
   主菜单 -> 1. 内核管理 -> 1. 安装 Xray

   # 或更新到最新版本
   主菜单 -> 1. 内核管理 -> 3. 更新 Xray
   ```

3. **测试 x25519 命令**
   ```bash
   /usr/local/xray/xray x25519

   # 正常输出应该类似：
   # Private key: xxx...
   # Public key: xxx...
   ```

4. **检查执行权限**
   ```bash
   chmod +x /usr/local/xray/xray
   ```

5. **使用调试工具**

   在脚本中可以调用测试函数：
   ```bash
   # 在节点管理模块中调用
   test_reality_keygen
   ```

**最低版本要求**：
- Xray-core 1.8.0+ (推荐使用最新版本)

## 安全建议

### 1. 定期更新
定期更新 Xray 内核到最新版本，修复安全漏洞。

### 2. 证书配置
生产环境建议使用正规证书（Let's Encrypt），避免使用自签名证书。

### 3. 密码强度
Trojan 和 Shadowsocks 使用强密码，建议 16 位以上随机字符。

### 4. 防火墙规则
只开放必要端口，定期检查防火墙规则。

### 5. 日志管理
定期清理日志文件，生产环境使用 warning 级别。

### 6. 备份配置
重要操作前备份配置，避免数据丢失。

## 性能优化

### 1. 传输协议选择
- **最快**：VLESS + TCP + XTLS
- **平衡**：VLESS + WebSocket + TLS
- **伪装**：VMess + WebSocket + TLS

### 2. 加密方式
- VLESS：使用 none（零加密）
- VMess：使用 aes-128-gcm
- Shadowsocks：使用 aes-256-gcm

### 3. 系统优化
```bash
# 调整文件描述符限制
ulimit -n 1000000

# 调整内核参数
echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf
echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf
sysctl -p
```

## 卸载

### 一键卸载（推荐）

```bash
# 在线卸载（从 GitHub 下载卸载脚本）
curl -fsSL https://raw.githubusercontent.com/sindricn/s-xray/main/uninstall.sh | sudo bash

# 或使用本地脚本卸载
sudo bash /opt/s-xray/uninstall.sh
```

**卸载选项：**
- 自动停止并删除 Xray 服务
- 删除管理脚本和全局命令
- 可选保留用户数据和配置备份
- 可选清理防火墙规则

### 使用脚本卸载

```bash
./xray-manager.sh
选择：1 -> 2
```

### 手动卸载

```bash
# 完全卸载
systemctl stop xray
systemctl disable xray
rm -rf /usr/local/xray
rm -rf /opt/s-xray
rm -f /etc/systemd/system/xray.service
rm -f /usr/local/bin/s-xray
rm -f /usr/local/bin/xray-manager
systemctl daemon-reload
```

## 代码质量优化

### v1.2.0 架构改进

基于 [S-Hy2](https://github.com/your-org/s-hy2) 项目最佳实践，本版本进行了全面的代码质量优化：

#### 1. 统一公共库 (`modules/common.sh`)

**日志系统**：
- 分级日志：DEBUG/INFO/WARN/ERROR/FATAL
- 彩色终端输出和文件持久化
- 时间戳和进程 ID 标记
- 日志文件：`/var/log/xray-manager.log`

```bash
# 使用示例
log_info "安装 Xray 内核..."
log_error "配置文件验证失败"
log_warn "端口已被占用"
```

**错误处理**：
- 统一错误退出函数
- 信号捕获（ERR/INT/TERM）
- 自动清理机制
- 调用栈跟踪

**工具函数**：
- `require_command()` - 命令依赖检查
- `require_root()` - 权限验证
- `confirm()` - 用户确认
- `get_public_ip()` - 获取公网 IP
- `retry_with_backoff()` - 重试机制
- `wait_for_condition()` - 条件等待

#### 2. 输入验证框架 (`modules/input-validation.sh`)

**基础验证**：
- `validate_port()` - 端口验证（1-65535）
- `validate_domain()` - 域名格式验证
- `validate_email()` - 邮箱验证
- `validate_uuid()` - UUID 格式验证
- `validate_ip()` - IP 地址验证

**协议验证**：
- `validate_vless_config()` - VLESS 配置验证
- `validate_vmess_config()` - VMess 配置验证
- `validate_trojan_config()` - Trojan 配置验证
- `validate_shadowsocks_config()` - Shadowsocks 配置验证
- `validate_reality_config()` - Reality 配置完整性验证

**安全增强**：
- `sanitize_input()` - 输入清理（防注入）
- `validate_path()` - 路径安全验证（防目录遍历）
- `protect_production()` - 生产环境保护

**交互式输入**：
- `read_port()` - 端口输入（自动验证）
- `read_uuid()` - UUID 输入（可自动生成）
- `read_domain()` - 域名输入（可验证 DNS）
- `read_password()` - 密码输入（强度检查）

#### 3. 代码规范统一

**严格模式**：
```bash
#!/bin/bash
set -uo pipefail
# -u: 使用未定义变量报错
# -o pipefail: 管道任意命令失败返回失败
# 不用 -e: 避免意外退出，保持错误处理可控
```

**变量命名规范**：
```bash
# 常量：readonly + 全大写
readonly MAX_RETRY=3
readonly CONFIG_DIR="/etc/xray"

# 全局变量：大写
XRAY_DIR="/usr/local/xray"

# 局部变量：local + 小写
local user_input=""
```

**引号规范**：
```bash
# ✅ 正确 - 始终使用引号
echo "$variable"
rm -rf "$directory"

# ❌ 错误 - 缺少引号
echo $variable
rm -rf $directory
```

#### 4. 安全加固

**临时文件安全**：
```bash
temp_file=$(mktemp)
chmod 600 "$temp_file"
trap "rm -f '$temp_file'" EXIT
```

**命令注入防护**：
```bash
# ❌ 危险
eval "cat $user_input"

# ✅ 安全
cat "$user_input"
```

**密码管理**：
- 日志中隐藏敏感信息
- 使用安全随机生成器
- 最小长度和复杂度要求

#### 5. 性能优化

**错误处理模式**：
```bash
# 早期返回模式
function_with_validation() {
    [[ ! -f "$file" ]] && {
        log_error "文件不存在"
        return 1
    }
    process_file "$file"
}
```

**重试机制**：
```bash
# 指数退避重试
retry_with_backoff 3 1 "curl -s example.com"
```

## 更新日志

### v1.2.0 (2025-10-09) - 代码质量大幅提升
- 🎯 **架构优化**：基于 S-Hy2 最佳实践全面重构
- 📝 **统一日志系统**：分级日志、文件持久化、调用栈跟踪
- 🔒 **增强输入验证**：完整的验证框架，防注入保护
- 🛡️ **安全加固**：临时文件安全、命令注入防护
- 📐 **代码规范**：严格模式、统一命名、引号规范
- ⚡ **错误处理**：信号捕获、自动清理、早期返回
- 🔧 **工具函数**：重试机制、条件等待、IP 获取
- 📊 **性能优化**：减少重复代码、优化执行流程

### v1.1.0 (2025-10-09)
- ✅ **新增 Reality 支持**：三层架构（协议-传输-加密）
- ✅ **一键搭建 VLESS + Reality 节点**：无需域名，自动生成密钥
- ✅ **节点序号选择**：支持序号和端口两种方式
- ✅ **域名管理**：Reality 域名优选、延迟测试
- ✅ **证书管理**：自动生成、手动导入
- ✅ 自动生成 Reality 分享链接
- ✅ 优化节点菜单结构和用户体验
- ✅ 修复软链接模块目录解析问题
- ✅ 修复重复安装逻辑，支持更新模式

### v1.0.1 (2025-10-09)
- ✅ 新增一键安装/卸载脚本
- ✅ 添加 `s-xray` 快捷命令
- ✅ 优化依赖安装过程，显示详细日志
- ✅ 修复在线安装时的交互问题
- ✅ 支持保留用户数据的卸载选项

### v1.0.0 (2025-10-07)
- ✅ 初始版本发布
- ✅ 支持 VLESS/VMess/Trojan/Shadowsocks
- ✅ 多用户管理
- ✅ 订阅管理
- ✅ 状态监控
- ✅ 防火墙管理
- ✅ 配置管理

## 贡献

欢迎提交 Issue 和 Pull Request！

## 许可证

本项目基于 MIT 许可证开源。

## 致谢

- [Xray-Core](https://github.com/XTLS/Xray-core) - 强大的代理工具
- 社区贡献者

## 联系方式

- Issues: [GitHub Issues](https://github.com/sindricn/s-xray/issues)
- GitHub: [https://github.com/sindricn/s-xray](https://github.com/sindricn/s-xray)

## 免责声明

本脚本仅供学习和研究使用，请遵守当地法律法规。使用本脚本所产生的一切后果由使用者自行承担。

---

⭐ 如果这个项目对你有帮助，请给个 Star！
