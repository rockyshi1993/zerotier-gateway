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

写入防火墙规则必须使用管理员 PowerShell。下面以 `E:\Worker\zerotier-gateway` 为例，如果你的仓库在别的位置，把路径换成自己的仓库目录。

确认当前窗口是不是管理员：

```powershell
cd E:\Worker\zerotier-gateway
([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
```

返回 `True` 后再应用规则；`Set-ExecutionPolicy` 只放行当前窗口运行脚本，不会提升管理员权限。

家里电脑预览：

```powershell
.\scripts\windows\set-firewall-rules.ps1 -Role Home
```

家里电脑应用：

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
.\scripts\windows\set-firewall-rules.ps1 -Role Home -Apply
```

公司电脑把 `Home` 改成 `Work`。

如果看到 `New-NetFirewallRule : 拒绝访问。` 或 `Windows System Error 5`，请关闭当前窗口，右键 PowerShell 选择“以管理员身份运行”，进入项目目录后重新执行。

不要把远程桌面或远程控制端口暴露到公网。
