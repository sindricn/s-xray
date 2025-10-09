# 快速开始指南

## 5 分钟快速部署

### 第一步：安装

```bash
# 克隆项目
git clone https://github.com/your-repo/s-xray.git
cd s-xray

# 运行安装脚本
chmod +x install.sh
sudo ./install.sh
```

### 第二步：安装 Xray 内核

启动管理脚本后：
```
主菜单 -> 1. 内核管理 -> 1. 安装 Xray
```

等待安装完成（约 1-2 分钟）

### 第三步：添加节点

#### 方案一：VLESS（推荐）

```
主菜单 -> 2. 节点管理 -> 1. 添加 VLESS 节点

配置示例：
- 端口: 443
- UUID: [自动生成]
- 邮箱: user@vless
- 传输: 2 (WebSocket)
- WebSocket 路径: /ws
- 启用 TLS: n (测试环境可不启用)
```

#### 方案二：Trojan（高伪装）

```
主菜单 -> 2. 节点管理 -> 3. 添加 Trojan 节点

配置示例：
- 端口: 443
- 密码: your-strong-password
- 邮箱: user@trojan
- 域名: your-domain.com
- 证书: [留空使用自签名]
- 回落: n
```

### 第四步：开放防火墙

```
主菜单 -> 6. 防火墙管理 -> 1. 开放端口

输入端口: 443
协议类型: tcp
```

### 第五步：生成分享链接

添加节点后，系统会自动生成分享链接，复制到客户端即可使用。

或者生成订阅：
```
主菜单 -> 4. 订阅管理 -> 1. 生成订阅链接

配置示例：
- 订阅名称: default
- 加密订阅: Y
- 订阅域名: [留空使用IP]
- 订阅端口: 8080
```

订阅链接：`http://your-ip:8080/sub/default`

## 常用命令速查

### 启动管理脚本
```bash
xray-manager
# 或
sudo ./xray-manager.sh
```

### 查看 Xray 状态
```bash
systemctl status xray
```

### 查看实时日志
```bash
journalctl -u xray -f
```

### 查看配置文件
```bash
cat /usr/local/xray/config.json | jq
```

### 测试配置
```bash
/usr/local/xray/xray test -config /usr/local/xray/config.json
```

## 快速故障排查

### 1. 节点无法连接

检查清单：
- [ ] Xray 服务是否运行：`systemctl status xray`
- [ ] 防火墙端口是否开放：`ss -tlnp | grep 443`
- [ ] 配置文件是否正确：`xray test -config /usr/local/xray/config.json`
- [ ] 客户端配置是否正确

### 2. 流量统计无数据

需要在配置中启用 stats 和 API：
```
主菜单 -> 1. 内核管理 -> 1. 安装 Xray
```
重新安装会自动添加必要配置

### 3. 订阅无法访问

检查清单：
- [ ] 订阅服务是否运行：`ps aux | grep subscription_server`
- [ ] 订阅端口是否开放：`ss -tlnp | grep 8080`
- [ ] 防火墙是否放行订阅端口

重启订阅服务：
```
主菜单 -> 4. 订阅管理 -> 5. 订阅配置 -> 3. 重启订阅服务
```

## 推荐配置方案

### 个人使用

**协议**：VLESS + WebSocket + TLS
**端口**：443
**传输**：WebSocket
**TLS**：启用（使用 Let's Encrypt）

### 多人使用

1. 创建节点（VLESS 或 VMess）
2. 为每个用户添加独立账号
3. 生成订阅链接分享
4. 定期查看流量统计

### 高性能场景

**协议**：VLESS + TCP + XTLS Vision
**端口**：443
**加密**：none
**流控**：xtls-rprx-vision

## 下一步

完成基础部署后，建议：

1. **配置域名和证书**
   - 购买域名
   - 申请 Let's Encrypt 免费证书
   - 配置 TLS

2. **优化性能**
   - 启用 BBR 加速
   - 调整内核参数
   - 使用 XTLS

3. **安全加固**
   - 使用强密码
   - 定期更新内核
   - 配置防火墙规则

4. **监控维护**
   - 定期查看流量统计
   - 监控系统资源
   - 备份配置文件

## 更多帮助

- 完整文档：[README.md](README.md)
- Xray 官方文档：[docs/](docs/)
- 问题反馈：[GitHub Issues](https://github.com/your-repo/s-xray/issues)
