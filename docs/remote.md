# 仅设备互访与远程访问（无需网关）

**若只是让两台 ZeroTier 成员通过私有 IP 互访，不需要 Ubuntu 网关、不需要 sing-box，也不需要部署本项目的代理服务。** ZeroTier 负责组网；你只需保证目标服务确实运行，并允许正确的访问来源。

## 最短路径

1. 在 [ZeroTier Central](https://my.zerotier.com) 创建 **Private** Network。
2. 两台 Windows 或其他设备安装 ZeroTier、加入同一 Network，并在 Central 授权。
3. 给设备分配互不冲突的 Managed IP，确认本机确实拥有地址；例如家里 `10.246.77.10`，公司 `10.246.77.20`。
4. 在被访问设备启用对应服务、账号与防火墙允许规则。
5. 从另一设备连接目标 ZeroTier IP，确认真实功能可用。

```text
公司 Windows ── ZeroTier 私网 ── 家里 Windows
10.246.77.20                  10.246.77.10
```

这里的 IP 是示例，不需要强行使用 `10.246.77.0/24`；但需避开家里/公司和其他 VPN 的已有网段。

## 如果使用微软远程桌面

如需运行本项目的 Windows PowerShell 脚本，请先按 [Windows 获取脚本步骤](windows.md#0-获取脚本只在需要本项目辅助功能时) 在**被访问的电脑**下载仓库并进入根目录；只使用 ZeroTier 客户端互访的用户无需下载本项目。

Windows Pro、Enterprise、Education 等可按系统支持范围作为远程桌面主机；**Windows Home 通常不能作为内置 RDP 主机**，但可以作为客户端，或使用其他远程工具。被访问设备需要保持开机、允许运行 RDP 和账户登录，推荐保持网络级别身份验证（NLA）。

在**被访问的 Windows** 仓库目录，用管理员 PowerShell 预览并启用：

```powershell
.\scripts\windows\enable-remote-desktop.ps1
.\scripts\windows\enable-remote-desktop.ps1 -Apply
```

该脚本仅在实际需要 RDP 主机功能时使用。不要开放公网 `3389/tcp`。

## 可选：用项目脚本管理 Home/Work 防火墙

**只限计划采用默认 Home/Work 配置的设备。** 先在对应 Windows 执行：

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
.\scripts\windows\init-config.ps1
```

家里设备预览、确认后应用：

```powershell
.\scripts\windows\setup.ps1 -Role Home
.\scripts\windows\setup.ps1 -Role Home -ApplyFirewall
```

公司设备使用 `-Role Work`，不要在同一台设备混用两个角色。该脚本会放行对端 IP 和配置中的 Ubuntu 中转来源；如果根本没有 Ubuntu 中转需求，请确认预览中的范围是否符合安全要求。脚本默认只支持 Home/Work 两种角色，**不会自动覆盖第三台及更多电脑**。

不希望使用这组固定角色时，可以使用系统原生防火墙规则，精确放行需要的对端 ZeroTier IP 和服务端口；无需为了使用 ZeroTier 而安装本项目 Windows 配置。

## 验证目标服务

从访问发起端执行：

```powershell
Test-NetConnection 10.246.77.10 -Port 3389
mstsc /v:10.246.77.10
```

如果目标不是 RDP，改成实际服务的端口和客户端。只有**真实连接成功**才能证明需求满足；`ping` 可能受防火墙 ICMP 规则影响，ping 失败不一定等于 TCP 失败。

## 中转不是默认路径

只有指定 TCP 远程服务在直接访问不稳定、且已排除基本网络问题时，才考虑[指定 TCP 中转](relay.md)。它使用 Ubuntu 代理指定端口，不是 ZeroTier 底层 DIRECT/RELAY 机制，也不能自动改善所有流量。

关闭远程访问时应在目标 Windows 系统设置中关闭不再需要的 RDP 主机功能，并撤销对应的允许规则；项目 `enable-remote-desktop.ps1` 目前没有对称的 `-Disable` 参数，不能将 `setup.ps1 -Rollback` 误作关闭 RDP 主机。

无法连接时按[验证](verification.md#5-远程端口与实际连接)和[排障](troubleshooting.md)逐层定位。
