# Windows 客户端：接入、远程与代理

Windows 上可以分别完成三件事：作为 ZeroTier 私网成员访问其他设备、提供 RDP/其他远程服务，以及主动使用 Ubuntu 代理。**这三者不要求同时启用。**

## 1. 普通 ZeroTier 成员

安装 ZeroTier，加入一个由你授权的 Private Network，并在 Central 给该电脑分配一个与现有网段不冲突的 Managed IP。此时即可尝试访问其他 ZeroTier 成员的服务，不需要部署 Ubuntu 网关，也不需要执行本项目 `setup.ps1`。

不要把“已加入 ZeroTier”理解成“Windows 全局使用 Ubuntu 出口”。Windows 自身的 ZeroTier **Allow Default** 必须单独查看；仓库虽有 `allowDefault=0` 模板，但当前 Windows 初始化/设置脚本并未证明会自动把它应用到已安装客户端。使用 Exit Node 前后务必在客户端实际核对。

## 2. 需要微软远程桌面时

被访问设备须使用支持 RDP 主机的 Windows 版本；Windows Home 不能作为内置 RDP 主机。管理员 PowerShell 在仓库根目录执行：

```powershell
([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
.\scripts\windows\enable-remote-desktop.ps1
.\scripts\windows\enable-remote-desktop.ps1 -Apply
```

权限检查应返回 `True`。`Set-ExecutionPolicy -Scope Process` 仅对当前 PowerShell 进程放宽执行策略，**不会提升权限**。在公司受管设备上，系统策略可能禁止此操作，请遵守管理员授权要求。

## 3. 可选的 Home/Work 防火墙辅助

下面脚本只适合你明确采用默认 Home/Work 两角色时使用。需要先完成 ZeroTier 授权、确认本机与对端 IP，然后分别在两台 Windows 上运行初始化器：

```powershell
.\scripts\windows\init-config.ps1
```

家里电脑在管理员终端预览并应用：

```powershell
.\scripts\windows\setup.ps1 -Role Home
.\scripts\windows\setup.ps1 -Role Home -ApplyFirewall
```

公司电脑使用 `-Role Work`。规则计划包含对端 Windows 的远程来源，以及所配置的 Ubuntu TCP 中转来源；若从未部署 Ubuntu 中转，应用前仍应审查来源列表，不要默认放行不需要的路径。

额外的第三台 Windows 可以直接加入 ZeroTier；现有 `setup.ps1` 不会自动覆盖新角色。需要在第三台提供远程服务时，按服务实际端口和允许来源配置 Windows 防火墙，或选择相应远程软件的官方配置方式。

## 4. Windows 软件使用私有代理

只使用 HTTP/SOCKS5 代理时，不需要执行 Home/Work 防火墙步骤。已入网的 Windows 软件主动配置 Ubuntu ZT IP 和代理端口（示例 `10.246.77.1:10808`），或使用 v2rayN 的 SOCKS 节点。

```powershell
Test-NetConnection 10.246.77.1 -Port 10808
curl.exe --ssl-no-revoke -x socks5h://10.246.77.1:10808 https://api.ipify.org
```

第一条验证 TCP 可达，第二条验证经过代理访问互联网。两种结果必须分别判断；如果软件本身没有接管系统流量，即使第二条成功也不能宣称整个 Windows 已切换网络出口。

更多规则与节点池见 [代理分流](proxy-rules.md) 和 [Windows 本地自动节点池](proxy-multi-server.md)。开启 v2rayN TUN 时需要自行防止将 ZeroTier 路由或远程流量错误纳入 TUN。

## 5. 诊断与恢复

```powershell
.\scripts\windows\show-diagnostics.ps1
.\scripts\windows\test-network.ps1
.\scripts\windows\test-proxy.ps1
```

`test-proxy.ps1` 使用 Windows 项目根目录 `.env` 里的目标代理配置。若你仅使用软件手动设置代理，也可以直接通过 `Test-NetConnection` 和 `curl.exe` 验证，不必运行配置初始化器。

如需移除项目生成的防火墙规则，管理员 PowerShell 执行 `setup.ps1 -Rollback`；它不会卸载 ZeroTier、关闭第三方代理客户端或还原全部 Windows 系统网络设置，详见 [回滚与卸载](rollback.md)。
