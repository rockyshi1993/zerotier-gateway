# 远程访问

远程访问请使用 ZeroTier IP。

默认 IP 规划：

| 设备 | ZeroTier IP |
|---|---|
| Ubuntu 节点 | `10.246.77.1` |
| 家里电脑 | `10.246.77.10` |
| 公司电脑 | `10.246.77.20` |

## 访问方向

公司电脑访问家里电脑：

```text
10.246.77.10
```

家里电脑访问公司电脑：

```text
10.246.77.20
```

## 防火墙

只允许对端 ZeroTier IP 访问远程端口。

如果使用微软远程桌面，先在被访问的 Windows 上检查版本并启用远程主机：

```powershell
.\scripts\windows\enable-remote-desktop.ps1
.\scripts\windows\enable-remote-desktop.ps1 -Apply
```

Windows Home 不能作为微软远程桌面主机，但可作为客户端；可以改用其他远程控制工具。微软远程桌面还要求目标电脑保持开机和唤醒，并使用有密码且被允许远程登录的账户。

版本与主机要求依据：[Microsoft Learn - Enable Remote Desktop on your PC](https://learn.microsoft.com/en-us/windows-server/remote/remote-desktop-services/remotepc/remote-desktop-allow-access)。

写入防火墙规则必须使用管理员 PowerShell。请直接在仓库根目录打开管理员 PowerShell。

确认当前窗口是不是管理员：

```powershell
# 在仓库根目录执行
([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
```

返回 `True` 后再应用规则；`Set-ExecutionPolicy` 只放行当前窗口运行脚本，不会提升管理员权限。

家里电脑预览：

```powershell
.\scripts\windows\setup.ps1 -Role Home
```

家里电脑应用：

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
.\scripts\windows\setup.ps1 -Role Home -ApplyFirewall
```

公司电脑把 `Home` 改成 `Work`。

规则预览里应该看到两类来源：对端 Windows 的 ZeroTier IP 用于直连，初始化脚本中选择的 Ubuntu IP 用于中转。默认第一台中转服务器是 `10.246.77.1`；如果改用新服务器，例如 `10.246.77.2`，重新运行 `init-config.ps1`，一路回车保留现值、只更新 Ubuntu IP，再重跑 `setup.ps1 -Role Home|Work -ApplyFirewall`。

如果看到 `New-NetFirewallRule : 拒绝访问。` 或 `Windows System Error 5`，请关闭当前窗口，右键 PowerShell 选择“以管理员身份运行”，进入项目目录后重新执行。

不要把远程桌面或远程控制端口暴露到公网。

安装后请按[Windows 远程主机验证](verification.md#4-windows-远程主机已开启)和[实际连接验证](verification.md#5-远程端口与实际连接)完成双向验收。
