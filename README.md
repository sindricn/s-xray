# S-Xray

基于 Xray-Core 的全功能管理脚本，支持多协议、多用户、订阅管理的一键部署方案。

## ✨ 核心特性

- 🚀 **一键部署** - VLESS + Reality 节点，无需域名和证书
- 🔧 **多协议支持** - 6 种入站协议 + 6 种出站协议，支持代理链
- 👥 **用户管理** - 全局用户系统，流量限制，有效期管理
- 🔗 **订阅管理** - 支持通用订阅（Base64）、原始订阅、Clash 订阅
- 📊 **状态监控** - 实时流量统计、连接信息、资源使用监控
- 🔥 **智能防火墙** - 自动识别系统防火墙（UFW/Firewalld/iptables）
- ⚙️ **配置管理** - 自动生成配置、备份恢复、验证修复
- 🌐 **域名优选** - Reality 域名延迟测试与优选
- 🛡️ **安全增强** - 输入验证框架、防注入保护

## 📦 快速开始

### 一键安装

```bash
curl -fsSL https://raw.githubusercontent.com/sindricn/s-xray/main/install.sh | sudo bash
```

安装完成后启动：

```bash
s-xray
```

## 🎯 协议支持

### 入站协议（客户端接入）

| 协议 | 传输方式 | 加密层 | 特性 |
|------|---------|-------|------|
| **VLESS** | TCP/WebSocket/gRPC/HTTP/2 | TLS/Reality | XTLS Vision、零加密、Reality 抗审查 |
| **VMess** | TCP/WebSocket/mKCP | TLS/无 | 多种加密方式、经典稳定 |
| **Trojan** | TCP | TLS | 强制 TLS、回落功能 |
| **Shadowsocks** | TCP/UDP | 无 | 2022 版加密、轻量级 |
| **HTTP** | HTTP 代理 | 无 | 本地代理入站 |
| **SOCKS** | SOCKS5 代理 | 无 | 本地代理入站 |

### 出站协议（上游代理）

| 协议 | 用途 | 特性 |
|------|------|------|
| **VLESS** | VLESS 上游代理 | 支持代理链 |
| **VMess** | VMess 上游代理 | 支持代理链 |
| **Trojan** | Trojan 上游代理 | 支持代理链 |
| **Shadowsocks** | Shadowsocks 上游代理 | 支持代理链 |
| **HTTP** | HTTP 上游代理 | 标准 HTTP 代理 |
| **SOCKS** | SOCKS5 上游代理 | 标准 SOCKS 代理 |

## 🛠️ 系统要求

- **操作系统**: Ubuntu 18+、Debian 10+、CentOS 7+
- **架构**: x86_64、ARM64、ARMv7
- **权限**: Root
- **依赖**: curl、wget、unzip、jq


## 🤝 贡献

欢迎提交 Issue 和 Pull Request！

1. Fork 本仓库
2. 创建特性分支 (`git checkout -b feature/amazing-feature`)
3. 提交更改 (`git commit -m 'Add some amazing feature'`)
4. 推送到分支 (`git push origin feature/amazing-feature`)
5. 提交 Pull Request

## 📝 更新日志

### v1.0.0 (2025-10-18) - 首次发布

**核心功能**
- ✅ 6 种入站协议：VLESS、VMess、Trojan、Shadowsocks、HTTP、SOCKS
- ✅ 6 种出站协议：VLESS、VMess、Trojan、Shadowsocks、HTTP、SOCKS
- ✅ 三层架构设计（协议-传输-加密）
- ✅ Reality 完整支持，无需域名和证书
- ✅ 支持代理链和上游代理配置

**用户与订阅**
- ✅ 全局用户系统，用户与节点分离管理
- ✅ 用户节点灵活绑定/解绑
- ✅ 流量限制和有效期管理
- ✅ 支持三种订阅格式（通用/原始/Clash）

**管理功能**
- ✅ 配置自动生成器
- ✅ 智能防火墙管理
- ✅ 状态监控和流量统计
- ✅ 配置备份恢复
- ✅ Reality 域名优选

**安全增强**
- ✅ 输入验证框架
- ✅ 防注入保护
- ✅ 统一日志系统
- ✅ 错误处理机制


## 📄 许可证

本项目基于 [MIT 许可证](LICENSE) 开源。

## 🙏 致谢

- [Xray-Core](https://github.com/XTLS/Xray-core) - 强大的代理工具

## ⚠️ 免责声明

本项目仅供学习和研究使用，请遵守当地法律法规。使用本项目所产生的一切后果由使用者自行承担。

---

⭐ 如果这个项目对你有帮助，欢迎点个 Star！

📮 问题反馈: [GitHub Issues](https://github.com/sindricn/s-xray/issues)
