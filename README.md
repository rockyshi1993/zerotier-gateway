# ZeroTier Gateway

为已有的 **ZeroTier 私有网络**按需部署自托管网关能力：Ubuntu HTTP/SOCKS5 代理、IPv4 Exit Node、指定 TCP 转发、内网站点发布，以及 Windows 代理节点管理辅助工具。

- [在线文档](https://rockyshi1993.github.io/zerotier-gateway/)
- [部署第一个私有网关](docs/quick-start.md)
- [选择接入方式](docs/install.md)
- [故障排查](docs/troubleshooting.md)

> 当前 `main` 使用开发版本标识 `1.4.0-dev`。已存在 `v1.3.0` Git tag，但开发分支的功能、脚本及文档不可直接视为 v1.3.0 的正式交付内容。生产使用前应按所选择的提交或 tag 验证。

## 选择你的目标

| 目标 | 是否需要 Ubuntu 网关 | 起点 |
|---|---|---|
| 两台 ZeroTier 成员互访或远程桌面 | **不需要** | [仅设备互访](docs/remote.md) |
| 浏览器或指定软件走 Ubuntu 公网出口 | **需要** | [私有代理部署](docs/quick-start.md) |
| Android 移动网络 IPv4 整机走 Ubuntu 出口 | **需要** | [私有 Exit Node](docs/exit-node.md) |
| 通过公网 Ubuntu 发布 ZeroTier 内的服务 | **需要** | [内网站点发布](docs/publish-site.md) |
| 多台代理节点故障自动切换 | 需要可用代理节点 | [多代理节点池](docs/proxy-multi-server.md) |

## 先分清三类流量

1. **私网互访：** 加入同一个 ZeroTier 私有网络后，访问目标设备的 ZeroTier IP；不会自动改变默认互联网出口。
2. **指定软件代理：** 软件主动连接 Ubuntu 的 `10.246.77.1:10808`（示例地址）；未配置的软件继续走自己的网络。
3. **IPv4 Exit Node：** Ubuntu 启用 IPv4 转发与 NAT，Central 添加默认路由，且客户端显式允许默认路由后，客户端 IPv4 才经 Ubuntu 出口。

这些模式相互独立。单纯访问私有代理 **不需要**启用 Allow Default。IPv4 出口通过也不代表 IPv6 和 DNS 都不会绕行。

## 能力与边界

| 能力 | 实现 | 默认 |
|---|---|---|
| Ubuntu 私有 HTTP/SOCKS5 | sing-box mixed inbound，示例 `10.246.77.1:10808` | 基础代理安装启用 |
| IPv4 Exit Node | forwarding + iptables NAT，按客户端允许默认路由 | 关闭 |
| TCP 中转 | systemd socket/proxyd，指定服务端口 | 按需 |
| 公网站点发布 | systemd TCP 端口映射、独立 Caddy HTTPS | 关闭 |
| Windows 本地节点池 | sing-box + 登录计划任务，健康检查与新连接切换 | 按需 |
| 代理分流与限速 | PAC/本地 sing-box、Linux tc | 按需 |

此项目不是 ZeroTier 控制器、通用中继服务、VPN 协议实现或 Web 管理平台。TCP 中转不优化 ZeroTier 底层 P2P 链路；自动节点切换不迁移已有 TCP 连接，也不是负载均衡。

## 部署私有代理的最短路径

在一台支持 sudo 的 Ubuntu 上，先创建私人 ZeroTier Network 并获取 16 位 Network ID：

```bash
git clone https://github.com/rockyshi1993/zerotier-gateway.git
cd zerotier-gateway
bash scripts/ubuntu/init-config.sh
sudo bash scripts/ubuntu/install-zerotier.sh
```

**此时先到 ZeroTier Central 授权服务器，确认实际分配的 Managed IP 已出现在 Ubuntu 网卡上**，再安装代理：

```bash
sudo bash scripts/ubuntu/install-proxy.sh --dry-run
sudo bash scripts/ubuntu/install-proxy.sh
sudo bash scripts/ubuntu/health-check.sh
```

`--dry-run` 用于预览系统变更；其中代理脚本仍可能在项目 `artifacts/` 生成本地配置产物，并非完全无文件写入。完整前置、客户端设置与端到端验收参见 [快速开始](docs/quick-start.md)。

## 安全提醒

- 私有 ZeroTier 网络启用成员授权；不公开 RDP、SSH、数据库等管理端口。
- **不推荐将未加密的公网 HTTP/SOCKS5 mixed 代理直接暴露互联网。** 本项目公网 mixed 监听并不自动提供 TLS；账号密码认证不等于加密。
- 代理认证信息会进入 `.env` 和生成的 JSON 配置；当前版本的某些脚本未保证这些文件只允许所有者读取。请核对权限，并避免共享工作目录与提交凭据。
- `uninstall.sh` 主要移除代理服务，不代表自动清理所有可选功能、Central 路由及历史防火墙规则。参见 [安全边界](docs/security.md) 和 [回滚与卸载](docs/rollback.md)。

## 文档与维护

[Ubuntu](docs/ubuntu.md) · [Windows](docs/windows.md) · [私有代理](docs/proxy.md) · [Exit Node](docs/exit-node.md) · [服务发布](docs/publish-site.md) · [限速](docs/rate-limit.md) · [多节点](docs/proxy-multi-server.md) · [升级](docs/upgrade.md) · [版本发布流程](docs/release.md)

许可证：[MIT](LICENSE)。欢迎通过 [Issues](https://github.com/rockyshi1993/zerotier-gateway/issues) 反馈可复现的问题；涉及真实网络故障时请去除 Network ID、私有凭据和公网地址后再上传日志。
