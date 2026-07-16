# ZeroTier Gateway

用现有脚本搭建 ZeroTier 私有远程访问、Ubuntu HTTP/SOCKS5 代理和可选中转。

> 普通流程只需要运行脚本并按提示操作，不需要编辑脚本或手工填写整页参数。

- [5 分钟快速开始](docs/quick-start.md)
- [完整用户文档](docs/index.md)
- 在线站点：`https://rockyshi1993.github.io/zerotier-gateway/`（合并到 `main` 并启用 GitHub Pages 后发布）

## 适合什么场景

- 家里和公司两台 Windows 需要通过 ZeroTier 互相远程。
- 浏览器或指定软件需要使用 Ubuntu 节点代理，但不想改成全局代理。
- 需要排除指定域名、IP 或进程不走代理。
- ZeroTier 直连长期不稳定，需要 Ubuntu 作为备用中转。
- 有多台代理服务器，希望 Windows 只配置一个自动切换入口。
- 需要按客户端限制代理速度，或从公网发布一个明确的本地站点。

## 最简网络

| 设备 | 作用 | 推荐 ZeroTier IP |
|---|---|---|
| Ubuntu 节点 | 私有 HTTP/SOCKS5 代理，可选中转 | `10.246.77.1` |
| 家里 Windows | 被公司电脑远程访问，也可以使用代理 | `10.246.77.10` |
| 公司 Windows | 被家里电脑远程访问，也可以使用代理 | `10.246.77.20` |

远程工具填写对方 Windows 的 ZeroTier IP。代理默认填写 `10.246.77.1:10808`。

> 加入 ZeroTier 只表示设备进入同一个私有网络，**不会自动让 Windows 代理上网**。只有主动配置代理的软件才会走 Ubuntu 出口。

## 开始前准备

1. 在 [ZeroTier Central](https://my.zerotier.com) 创建私有网络，并记下 16 位网络编号。
2. 准备一台可使用 `sudo` 的 Ubuntu。
3. 家里和公司两台 Windows 已安装 ZeroTier，并能使用管理员 PowerShell。
4. 两台 Windows 已安装你平时使用的远程工具。

## 最快开始

先克隆项目：

```bash
git clone https://github.com/rockyshi1993/zerotier-gateway.git
cd zerotier-gateway
```

Ubuntu 运行：

```bash
bash scripts/ubuntu/init-config.sh
sudo bash scripts/ubuntu/install.sh --dry-run
sudo bash scripts/ubuntu/install.sh
sudo bash scripts/ubuntu/health-check.sh
```

然后在 ZeroTier Central 授权 Ubuntu，并固定为 `10.246.77.1`。

两台 Windows 都加入同一个 ZeroTier 网络并在 Central 授权、固定地址后，用管理员 PowerShell 运行初始化脚本：

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
.\scripts\windows\init-config.ps1
```

家里电脑运行：

```powershell
.\scripts\windows\setup.ps1 -Role Home -ApplyFirewall
.\scripts\windows\test-network.ps1
```

公司电脑运行：

```powershell
.\scripts\windows\setup.ps1 -Role Work -ApplyFirewall
.\scripts\windows\test-network.ps1
```

`Home` 和 `Work` 表示当前电脑的身份，不要在同一台电脑上混用。

使用微软远程桌面时，还要在被访问电脑运行 `enable-remote-desktop.ps1 -Apply`；完整顺序见[5 分钟快速开始](docs/quick-start.md)，实际成功以[安装与互访验证](docs/verification.md)为准。

## 常用任务

| 你想做什么 | 直接查看 |
|---|---|
| 第一次完整配置 | [快速开始](docs/quick-start.md) |
| 检查是否安装成功、两台电脑是否互相访问 | [安装与互访验证](docs/verification.md) |
| 分别配置 Ubuntu 或 Windows | [Ubuntu 节点](docs/ubuntu.md) · [Windows 客户端](docs/windows.md) |
| 公司访问家里或家里访问公司 | [远程访问](docs/remote.md) |
| 给浏览器、v2rayN 或指定软件配置代理 | [代理上网](docs/proxy.md) |
| 不经过 ZeroTier，直接使用公网代理 | [公网代理](docs/proxy-public.md) |
| 添加多台代理服务器并切换 | [多台代理服务器](docs/proxy-multi-server.md) |
| 排除域名、IP 或进程 | [代理排除规则](docs/proxy-rules.md) |
| 正在使用旧版本，需要安全升级 | [安全升级](docs/upgrade.md) |
| 给指定代理客户端限制速度 | [按客户端限速](docs/rate-limit.md) |
| 通过公网 IP+端口或域名访问站点 | [公网站点发布](docs/publish-site.md) |
| 直连不稳定时启用中转 | [中转兜底](docs/relay.md) |
| 安装失败、权限报错或连不通 | [故障排查](docs/troubleshooting.md) |
| 卸载或恢复 | [回滚与卸载](docs/rollback.md) |

## 代理怎么用

已加入 ZeroTier 的设备优先使用私有入口：

```text
地址：10.246.77.1
端口：10808
协议：HTTP 或 SOCKS5
```

没有配置代理的软件继续使用本机网络。公网代理入口、认证、PAC、进程排除和 TUN 使用判断都属于进阶场景，请看[代理上网](docs/proxy.md)。

多台 Ubuntu 自动切换时，软件日常只使用 `127.0.0.1:20808`；公网访问本地站点使用独立发布命令，不要把 SOCKS 代理端口当作 Web 站点入口。

## 成功标准

- Ubuntu、家里电脑和公司电脑都已在 ZeroTier Central 授权，地址不冲突。
- Ubuntu `health-check.sh` 能看到代理监听。
- 两台 Windows 的 `test-network.ps1` 没有关键失败。
- 远程工具使用对方 ZeroTier IP 可以连接。
- 需要代理的软件能通过 `10.246.77.1:10808` 上网。

这些结论不能只凭脚本“没有报错”判断。请按[安装与互访验证](docs/verification.md)运行服务、双向 ping、3389、实际远程登录和代理出口命令。

## 出错时先做什么

Ubuntu：

```bash
sudo bash scripts/ubuntu/health-check.sh
```

Windows：

```powershell
.\scripts\windows\show-diagnostics.ps1
.\scripts\windows\test-network.ps1
.\scripts\windows\test-proxy.ps1
```

仍未解决时，按症状查看[故障排查](docs/troubleshooting.md)。看到“拒绝访问”或 `Windows System Error 5` 时，请确认当前窗口是管理员 PowerShell。

## 文档

- [文档首页](docs/index.md)
- [安装总览](docs/install.md)
- [安装与互访验证](docs/verification.md)
- [安全说明](docs/security.md)
- [发布验证（维护者）](docs/release.md)

## License

[MIT](LICENSE)
