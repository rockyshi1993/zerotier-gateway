# Windows 客户端

涉及防火墙规则写入时，请以管理员身份运行 PowerShell。

打开方式：

1. 关闭普通 PowerShell 窗口。
2. 开始菜单搜索 `PowerShell` 或 `Windows Terminal`。
3. 右键选择“以管理员身份运行”。
4. 进入项目目录；下面以 `E:\Worker\zerotier-gateway` 为例，如果你的仓库在别的位置，把路径换成自己的仓库目录。

确认当前窗口是不是管理员：

```powershell
([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
```

返回 `True` 才能写入防火墙规则；如果返回 `False`，先关闭窗口，重新用“以管理员身份运行”打开。

如果 PowerShell 提示“无法加载文件”或 `PSSecurityException`，先在当前窗口执行：

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
```

这只会放行当前 PowerShell 窗口，关掉窗口后会恢复。它不会提升管理员权限。

## 初始化

第一次使用前，先生成配置：

```powershell
.\scripts\windows\init-config.ps1
```

两台 Windows 都加入同一个 ZeroTier 网络后，分别在对应电脑执行一次：

家里电脑：

```powershell
cd E:\Worker\zerotier-gateway
.\scripts\windows\setup.ps1 -Role Home
```

公司电脑：

```powershell
cd E:\Worker\zerotier-gateway
.\scripts\windows\setup.ps1 -Role Work
```

脚本会先打印防火墙计划。确认计划正确后，再追加 `-ApplyFirewall` 真正写入规则。

防火墙计划会包含两类入站规则：

| 规则 | 用途 |
|---|---|
| 对端 Windows IP | 家里和公司通过 ZeroTier 直连远程 |
| `UBUNTU_ZT_IP` | 直连不稳定时，允许 Ubuntu 中转服务器转发到这台 Windows |

`-Role Home` 只在家里电脑执行，`-Role Work` 只在公司电脑执行。如果某台 Windows 只加入 ZeroTier 网络，但不需要被另一台电脑远程访问，也不需要本项目生成规则，可以不执行 `setup.ps1`。

如果你有多台 Ubuntu 中转服务器，目标 Windows 只需要允许“当前要用的中转服务器”访问远程端口。同步 Windows `.env` 里的 `UBUNTU_ZT_IP` 后，重跑对应角色的 `setup.ps1 -ApplyFirewall` 即可自动更新规则。手动 `New-NetFirewallRule` 只适合旧脚本或临时补救。

查看脚本写入的规则：

```powershell
# 家里电脑查看 Home 规则；公司电脑把 Home 改成 Work
Get-NetFirewallRule -DisplayName "ZT Gateway * Inbound Home 3389" |
  Select-Object DisplayName,Enabled,Direction,Action,Profile

Get-NetFirewallRule -DisplayName "ZT Gateway * Inbound Home 3389" |
  Get-NetFirewallAddressFilter |
  Format-List RemoteAddress
```

脚本自动生成的中转规则名是 `ZT Gateway Relay Inbound Home 3389` 或 `ZT Gateway Relay Inbound Work 3389`。如果你手动创建了自定义规则名，查询时要使用实际创建过的名字。

## 更多 Windows 电脑

ZeroTier 网络可以加入两台以上 Windows。默认脚本只内置两个角色：

| 角色 | 默认 IP |
|---|---|
| Home | `10.246.77.10` |
| Work | `10.246.77.20` |

额外电脑可以固定为 `10.246.77.30`、`10.246.77.31` 等地址。只使用代理或只访问别人的电脑，不需要执行 `setup.ps1`。

如果额外电脑也加入了 ZeroTier，软件代理仍然优先填 `10.246.77.1:10808`。只有额外电脑没有加入 ZeroTier，或你特意想让它走服务器公网路径测速时，才填 `.env` 里的 `PROXY_CONNECT_HOST:10808`。

如果额外电脑也要被远程访问，请在那台电脑上用管理员 PowerShell 手动放行允许访问它的对端 ZeroTier IP。例如只允许公司电脑访问第三台电脑的 `3389`：

```powershell
New-NetFirewallRule -DisplayName "ZT Extra Remote 3389" -Direction Inbound -Action Allow -Protocol TCP -LocalPort 3389 -RemoteAddress 10.246.77.20 -Profile Any
```

如果信任整个 ZeroTier 私有网络，可以把 `-RemoteAddress` 改成 `10.246.77.0/24`。不要把远程端口放行到公网。

家里电脑：

```powershell
cd E:\Worker\zerotier-gateway
.\scripts\windows\setup.ps1 -Role Home -ApplyFirewall
```

公司电脑：

```powershell
cd E:\Worker\zerotier-gateway
.\scripts\windows\setup.ps1 -Role Work -ApplyFirewall
```

不要在同一台电脑上把 `-Role Home` 和 `-Role Work` 都执行一遍。`Role` 表示“当前这台电脑是谁”，不是你要连接的目标。

如果看到 `New-NetFirewallRule : 拒绝访问。` 或 `Windows System Error 5`，说明当前窗口没有足够权限，或系统策略拒绝写入防火墙。请用“以管理员身份运行”的 PowerShell 重新执行，并先运行：

```powershell
cd E:\Worker\zerotier-gateway
([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
```

## 诊断

```powershell
.\scripts\windows\test-network.ps1
.\scripts\windows\test-proxy.ps1
.\scripts\windows\show-diagnostics.ps1 -FindProcess "远程"
```

## 配置路径

默认配置路径是项目根目录下的 `.env`。

只有配置文件不在默认位置时，才需要显式指定路径：

```powershell
.\scripts\windows\test-network.ps1 -Env .\profiles\office.env
```
