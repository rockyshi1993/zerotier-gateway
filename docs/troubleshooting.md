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

## Windows 防火墙规则写入失败

如果执行：

```powershell
.\scripts\windows\setup.ps1 -Role Home -ApplyFirewall
```

或：

```powershell
.\scripts\windows\setup.ps1 -Role Work -ApplyFirewall
```

看到类似报错：

```text
New-NetFirewallRule : 拒绝访问。
Windows System Error 5
```

通常是当前 PowerShell 不是管理员权限，或系统策略拒绝写入防火墙。处理方式：

1. 关闭当前 PowerShell。
2. 右键 PowerShell，选择“以管理员身份运行”。
3. 进入项目目录。
4. 确认管理员状态返回 `True`：

```powershell
cd E:\Worker\zerotier-gateway
([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
```

5. 先执行 `Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass`。这条命令只放行当前窗口运行脚本，不会提升管理员权限。
6. 家里电脑重新执行 `.\scripts\windows\setup.ps1 -Role Home -ApplyFirewall`。
7. 公司电脑重新执行 `.\scripts\windows\setup.ps1 -Role Work -ApplyFirewall`。

如果公司电脑或安全软件禁止修改防火墙，请在系统防火墙里手动允许对端 ZeroTier IP 访问远程端口。默认示例里，家里电脑放行 `10.246.77.20`，公司电脑放行 `10.246.77.10`。

## ZeroTier 无法连通

检查：

1. 设备已经在 ZeroTier Central 授权。
2. 三台机器的 ZeroTier IP 已按预期固定。
3. Windows 防火墙允许对端 ZeroTier IP 访问远程端口。
4. `10.246.77.0/24` 的路由走 ZeroTier。
5. ZeroTier Central 里没有残留 `172.27.x.x` 地址池或成员 IP。

运行：

```powershell
.\scripts\windows\test-network.ps1
```

## ZeroTier Central 网段或地址池配置不干净

到 ZeroTier Central 的网络详情页，打开 `Advanced`，建议保持：

| 位置 | 应该保留 |
|---|---|
| `Managed Routes` | `10.246.77.0/24 (LAN)` |
| `IPv4 Auto-Assign` | 可以关闭自动分配，改为手动固定 IP |
| `Auto-Assign Pools` | 如果保留自动分配，只用 `10.246.77.100` 到 `10.246.77.254` |

不要把 `10.246.77.0/24` 填到 `Via`。如果还有 `172.27.0.1` 到 `172.27.255.254` 的自动分配地址池、成员机器上的 `172.27.x.x`，或误填的 `192.168.x.x` 地址池，建议删掉。

三台机器只保留：

| 设备 | Managed IP |
|---|---|
| Ubuntu 节点 | `10.246.77.1` |
| 家里 Windows 电脑 | `10.246.77.10` |
| 公司 Windows 电脑 | `10.246.77.20` |

调整后，在 Windows 上执行：

```powershell
Restart-Service ZeroTierOneService
zerotier-cli listnetworks
```

`listnetworks` 里应该只看到本机的 `10.246.77.x/24`，不应该再看到 `172.27.x.x`。

## 开启 TUN 或全局代理后远程不通

如果开启 TUN、全局代理、加速器或其他接管系统流量的软件后远程不通，先让 ZeroTier 网段直连：

```text
10.246.77.0/24
```

如果代理工具支持按进程直连，把 ZeroTier 进程也加入直连。可用下面命令查看实际进程名和路径：

```powershell
Get-Process | Where-Object { $_.ProcessName -like "*ZeroTier*" } | Select-Object ProcessName,Path
```

远程工具本身也建议走直连；如果代理工具支持按进程规则，把远程工具的主进程、服务进程和辅助进程一起加入直连。

改完后，两台 Windows 都执行：

```powershell
Restart-Service ZeroTierOneService
zerotier-cli peers
```

公司访问家里时测 `ping -n 20 10.246.77.10`；家里访问公司时测 `ping -n 20 10.246.77.20`。

如果 `peers` 里对方节点的 `path` 仍然显示为代理出口 IP，说明 ZeroTier 进程还在被 TUN 接管，需要继续检查代理工具的直连规则。

## 代理无法连通

检查：

1. Ubuntu 节点已经拿到 `10.246.77.1`。
2. sing-box 服务正在运行。
3. 默认私有入口时，代理监听在 `10.246.77.1:10808`。
4. 如果启用了公网入口，`PROXY_PUBLIC_ACCESS=true`，并且 `PROXY_CONNECT_HOST` 是 Ubuntu 服务器公网 IP。
5. 如果启用了公网入口，云防火墙和 Ubuntu 防火墙允许你的来源公网 IP 访问 `10808/tcp`。
6. 如果启用了公网入口，`PROXY_ALLOWED_CLIENT_CIDRS` 已填写公司或家里的公网 IP/CIDR；没有白名单时脚本不会添加宽泛公网放行规则。
7. 如果启用了代理认证，用户名和密码正确；如果没启用认证，客户端里不要填写用户名和密码。
8. 如果刚修改过代理账号密码、代理入口或白名单，Ubuntu 上已经重新执行 `sudo bash scripts/ubuntu/install-proxy.sh`，客户端软件、PAC 或本地规则也已经同步。

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

`test-proxy.ps1` 会连接 `.env` 里的 `PROXY_CONNECT_HOST:PROXY_PORT`。如果你已经启用公网入口，但输出里仍然测试 `10.246.77.1:10808`，说明 Windows 这边的 `.env` 还没有同步 `PROXY_CONNECT_HOST`。

如果默认私有入口慢，但公网代理工具很快，按下面方式优化：

```text
PROXY_PUBLIC_ACCESS=true
PROXY_BIND_IP=0.0.0.0
PROXY_CONNECT_HOST=Ubuntu服务器公网IP
PROXY_ALLOWED_CLIENT_CIDRS=公司公网IP/32,家里公网IP/32
```

然后在 Ubuntu 上执行：

```bash
sudo bash scripts/ubuntu/install-proxy.sh --dry-run
sudo bash scripts/ubuntu/install-proxy.sh
```

## 进程排除没有命中

多进程软件可能会启动服务进程、辅助进程或更新进程。

查找候选进程：

```powershell
.\scripts\windows\show-diagnostics.ps1 -FindProcess "远程"
.\scripts\windows\show-diagnostics.ps1 -FindProcessPath "C:\Program Files\远程工具"
```
