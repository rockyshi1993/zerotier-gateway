# 故障排查

## 目录导航

- [找不到配置文件](#找不到配置文件)
- [Windows 脚本无法运行](#windows-脚本无法运行)
- [Windows 防火墙规则写入失败](#windows-防火墙规则写入失败)
- [ZeroTier 无法连通](#zerotier-无法连通)
- [ZeroTier Central 网段或地址池配置不干净](#zerotier-central-网段或地址池配置不干净)
- [开启 TUN 或全局代理后远程不通](#开启-tun-或全局代理后远程不通)
- [代理无法连通](#代理无法连通)
- [进程排除没有命中](#进程排除没有命中)

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

最新脚本会同时写入两类规则：对端 Windows 的 ZeroTier IP 用于直连，`.env` 里的 `UBUNTU_ZT_IP` 用于中转。如果公司电脑或安全软件禁止修改防火墙，请在系统防火墙里手动允许对应来源访问远程端口。默认示例里，家里电脑放行公司电脑 `10.246.77.20` 和 Ubuntu `10.246.77.1`；公司电脑放行家里电脑 `10.246.77.10` 和 Ubuntu `10.246.77.1`。

如果是第三台或更多 Windows 加入 ZeroTier，`setup.ps1 -Role Home/Work` 不会自动管理这些额外电脑。额外电脑只用代理或只访问别人时不需要执行 `setup.ps1`；如果它也要被远程访问，请在额外电脑上手动放行允许访问它的对端 ZeroTier IP，或放行可信的 `10.246.77.0/24`。

如果你新增了另一台 Ubuntu 中转服务器，Windows 不需要安装中转服务；但目标 Windows 必须允许新服务器的 ZeroTier IP 访问远程端口。比如新服务器是 `10.246.77.2`，目标 Windows 只放行过旧服务器或对方电脑 IP，就需要同步 Windows `.env` 里的 `UBUNTU_ZT_IP=10.246.77.2`，再重跑对应角色的 `setup.ps1 -ApplyFirewall`。如果已经放行可信的 `10.246.77.0/24`，通常不用再加规则。

旧脚本或临时补救时，也可以在目标 Windows 的管理员 PowerShell 手动添加：

```powershell
New-NetFirewallRule -DisplayName "ZT Relay Server 10.246.77.2 Inbound 3389" -Direction Inbound -Action Allow -Protocol TCP -LocalPort 3389 -RemoteAddress 10.246.77.2 -Profile Any
```

手动规则的 `DisplayName` 可以自己定，但后续查询必须使用实际创建过的名字。脚本自动生成的中转规则名是 `ZT Gateway Relay Inbound Home 3389` 或 `ZT Gateway Relay Inbound Work 3389`；如果你没有创建过 `ZT Relay Singapore Inbound 3389`，用这个名字查询会提示找不到对象。

## ZeroTier 无法连通

检查：

1. 设备已经在 ZeroTier Central 授权。
2. 基础三台机器的 ZeroTier IP 已按预期固定；更多设备也已固定为不冲突的 IP。
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

基础三台机器只保留：

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

如果已经用 v2rayN 或其他工具把 Windows 系统代理配置为本地监听地址，例如 `127.0.0.1:10808`，通常不需要再开启 TUN。系统代理已经能覆盖浏览器、Git、npm 和大多数遵守系统代理的软件；TUN 只在软件不支持系统代理、需要强制接管流量时再考虑。

如果开启 TUN、全局代理、加速器或其他接管系统流量的软件后远程不通，先让 ZeroTier 网段直连：

```text
10.246.77.0/24
```

如果当前代理节点就是 Ubuntu 私有入口，也把代理服务器地址和本机地址直连，避免代理连接本身被再次接管：

```text
10.246.77.1
服务器公网IP
127.0.0.1
localhost
```

v2rayN 的 TUN 模式建议先用：

```text
自动路由：开启
严格路由：先关闭
协议栈：gvisor
MTU：1500；如果仍不稳定再改 1400
IPv6：没有公网 IPv6 时关闭
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
4. 已加入 ZeroTier 的 Windows 优先测试 `10.246.77.1:10808`；如果这条能通，就不需要为了代理改成公网 IP。
5. 如果启用了公网入口，且客户端要走公网路径，`PROXY_PUBLIC_ACCESS=true`，并且 `PROXY_CONNECT_HOST` 是 Ubuntu 服务器公网 IP。
6. 如果启用了公网入口，且客户端要走公网路径，云防火墙和 Ubuntu 防火墙允许客户端访问 `10808/tcp`。
7. 如果启用了公网入口，`PROXY_ALLOWED_CLIENT_CIDRS` 可以留空；留空表示允许全部来源访问代理端口。填写后只允许指定来源。
8. 如果启用了代理认证，用户名和密码正确；如果没启用认证，客户端里不要填写用户名和密码。
9. 如果刚修改过代理账号密码、代理入口或白名单，Ubuntu 上已经重新执行 `sudo bash scripts/ubuntu/install-proxy.sh`，客户端软件、PAC 或本地规则也已经同步。

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

`test-proxy.ps1` 会连接 `.env` 里的 `PROXY_CONNECT_HOST:PROXY_PORT`。如果你已经启用公网入口，但输出里仍然测试 `10.246.77.1:10808`，说明 Windows 这边仍在测试 ZeroTier 私有入口；这对已经加入 ZeroTier 的 Windows 是正常且更安全的。只有你想测试公网路径，或这台设备没有加入 ZeroTier，才需要把 Windows `.env` 的 `PROXY_CONNECT_HOST` 改成服务器公网 IP。

如果默认私有入口慢，但公网代理工具很快，按下面方式优化：

```text
PROXY_PUBLIC_ACCESS=true
PROXY_BIND_IP=0.0.0.0
PROXY_CONNECT_HOST=Ubuntu服务器公网IP
PROXY_ALLOWED_CLIENT_CIDRS=
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
