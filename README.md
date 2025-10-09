# Xray-Core 一键管理脚本

基于 Xray-Core 的全功能一键搭建和管理脚本，支持多协议、多用户、订阅管理等企业级特性。

## 功能特性

### ✨ 核心功能

- 🚀 **内核管理**：一键安装、卸载、更新、启动、停止 Xray-Core
- 🔧 **节点管理**：支持 VLESS、VMess、Trojan、Shadowsocks 四大协议
- 👥 **用户管理**：多用户管理、UUID 自动生成、用户配置修改
- 📱 **订阅管理**：自动生成订阅链接、支持多订阅、内置订阅服务器
- 📊 **状态监控**：实时监控、流量统计、连接状态、日志查看
- 🔥 **防火墙管理**：自动识别防火墙类型、批量开放端口
- ⚙️ **配置管理**：配置验证、备份恢复、导入导出

### 🎯 协议支持

| 协议 | 传输方式 | TLS/XTLS | 特性 |
|------|---------|----------|------|
| VLESS | TCP/WS/gRPC/H2 | ✅ | XTLS Vision、零加密 |
| VMess | TCP/WS/mKCP | ✅ | 多种加密方式 |
| Trojan | TCP | ✅ | 回落配置 |
| Shadowsocks | TCP/UDP | ❌ | 2022版加密 |

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
   主菜单 -> 2. 节点管理 -> 选择协议类型
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

#### VLESS 节点

**特点**：
- 支持 XTLS Vision 流控
- 零加密开销
- 多种传输协议

**配置选项**：
- 端口：自定义监听端口
- UUID：自动生成或手动指定
- 传输：TCP、WebSocket、gRPC、HTTP/2
- TLS：支持自签名或自有证书

**示例**：
```bash
端口: 443
UUID: 自动生成
传输: WebSocket
路径: /ws
TLS: 启用
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

```bash
# 使用脚本卸载
./xray-manager.sh
选择：1 -> 2

# 手动卸载
systemctl stop xray
systemctl disable xray
rm -rf /usr/local/xray
rm -f /etc/systemd/system/xray.service
systemctl daemon-reload
```

## 更新日志

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
