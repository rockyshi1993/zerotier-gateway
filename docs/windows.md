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

`-Role Home` 只在家里电脑执行，`-Role Work` 只在公司电脑执行。如果某台 Windows 只加入 ZeroTier 网络，但不需要被另一台电脑远程访问，也不需要本项目生成规则，可以不执行 `setup.ps1`。

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
