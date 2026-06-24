# 故障排查

## 找不到配置文件

脚本默认读取项目根目录下的 `.env`。

修复方式：

```bash
bash scripts/ubuntu/init-config.sh
```

Windows：

```powershell
.\scripts\windows\init-config.ps1
```

## Windows 脚本无法运行

如果 PowerShell 提示：

```text
无法加载文件 ... 因为在此系统上禁止运行脚本
PSSecurityException
UnauthorizedAccess
```

先在当前 PowerShell 窗口执行：

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
```

然后重新运行刚才的脚本。`-Scope Process` 只影响当前窗口，关掉窗口后会恢复。

## ZeroTier 无法连通

检查：

1. 设备已经在 ZeroTier Central 授权。
2. 三台机器的 ZeroTier IP 已按预期固定。
3. Windows 防火墙允许对端 ZeroTier IP 访问远程端口。
4. `10.246.77.0/24` 的路由走 ZeroTier。

运行：

```powershell
.\scripts\windows\test-network.ps1
```

## 代理无法连通

检查：

1. Ubuntu 节点已经拿到 `10.246.77.1`。
2. sing-box 服务正在运行。
3. 代理监听在 `10.246.77.1:10808`。
4. 如果启用了代理认证，用户名和密码正确；如果没启用认证，客户端里不要填写用户名和密码。

如果 Ubuntu 上看到：

```text
Proxy port 10808 is not listening
Unit sing-box-zt-proxy.service could not be found.
```

说明代理服务没有装上。普通用户先重新执行主安装命令：

```bash
sudo bash scripts/ubuntu/install.sh
```

`scripts/ubuntu/install-proxy.sh` 是单独修代理时用的子脚本；主流程不需要直接运行它。

如果安装时看到：

```text
Unable to locate package sing-box
```

说明当前 Ubuntu 源里没有 sing-box 包。更新到最新脚本后重新执行主安装命令，脚本会自动添加官方 SagerNet apt 源后继续安装：

```bash
git pull
sudo bash scripts/ubuntu/install.sh
```

运行：

```powershell
.\scripts\windows\test-proxy.ps1
```

## 进程排除没有命中

多进程软件可能会启动服务进程、辅助进程或更新进程。

查找候选进程：

```powershell
.\scripts\windows\show-diagnostics.ps1 -FindProcess "远程"
.\scripts\windows\show-diagnostics.ps1 -FindProcessPath "C:\Program Files\远程工具"
```
