# Windows 客户端

涉及防火墙规则写入时，请以管理员身份运行 PowerShell。

如果 PowerShell 提示“无法加载文件”或 `PSSecurityException`，先在当前窗口执行：

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
```

这只会放行当前 PowerShell 窗口，关掉窗口后会恢复。

## 初始化

第一次使用前，先生成配置：

```powershell
.\scripts\windows\init-config.ps1
```

家里电脑：

```powershell
.\scripts\windows\setup.ps1 -Role Home
```

公司电脑：

```powershell
.\scripts\windows\setup.ps1 -Role Work
```

脚本会先打印防火墙计划。确认计划正确后，再追加 `-ApplyFirewall` 真正写入规则。

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
