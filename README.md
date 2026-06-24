# ZeroTier Gateway

这份文档教你完成三件事：让家里电脑和公司电脑互相远程、在 Ubuntu 上搭一个只给指定软件使用的私有代理、按需设置哪些流量不走代理。

## 目录导航

| 想做什么 | 直接跳到 |
|---|---|
| 先确认这个项目是不是适合你 | [适合什么场景](#适合什么场景)、[最终会得到什么](#最终会得到什么) |
| 第一次安装前准备 | [开始前准备](#开始前准备)、[1. 获取项目](#1-获取项目)、[2. 生成配置](#2-生成配置) |
| 配置 Ubuntu 代理节点 | [3. 配置 Ubuntu 节点](#3-配置-ubuntu-节点) |
| 检查 ZeroTier Central 网段和地址池 | [ZeroTier Central 网段和地址池检查](#zerotier-central-网段和地址池检查) |
| 配置家里和公司 Windows | [4. 配置两台 Windows](#4-配置两台-windows)、[打开管理员 PowerShell](#打开管理员-powershell)、[执行 Windows 脚本](#执行-windows-脚本) |
| 写入或修复 Windows 防火墙 | [写入防火墙规则](#写入防火墙规则)、[防火墙写入失败](#防火墙写入失败) |
| 开始远程访问 | [5. 远程访问](#5-远程访问) |
| 开启 TUN 或全局代理后远程不通 | [TUN 或全局代理开启后远程不通](#tun-或全局代理开启后远程不通) |
| 家庭宽带没有公网 IPv4 | [常见问题](#常见问题) |
| 只让指定软件走代理 | [6. 给需要的软件配置代理](#6-给需要的软件配置代理)、[7. 排除 IP、域名或进程](#7-排除-ip域名或进程) |
| 代理测速慢，想走服务器公网入口 | [代理上网提速：可选公网入口](#代理上网提速可选公网入口) |
| 后续启用、修改或关闭代理账号密码 | [后续启用或修改代理账号密码](#后续启用或修改代理账号密码) |
| 直连不稳定时处理 | [8. 远程直连不稳定时，再开启中转](#8-远程直连不稳定时再开启中转)、[验证中转是否成功](#验证中转是否成功) |
| 检查是否配置成功 | [9. 最终验收](#9-最终验收) |
| 查看常见问题、常见选择和更多文档 | [常见问题](#常见问题)、[常见选择](#常见选择)、[文档入口](#文档入口) |

## 适合什么场景

- 家里电脑和公司电脑需要互相远程，目标是低延迟、少折腾。
- 某些软件需要通过 Ubuntu 节点代理上网，但不想把整台电脑都改成全局代理。
- 需要排除指定 IP、域名或进程不走代理。
- ZeroTier 直连效果不好时，希望有一个备用中转方案。

## 最终会得到什么

完成后，你会有一个这样的网络：

| 设备 | 作用 | 推荐 ZeroTier IP |
|---|---|---|
| Ubuntu 节点 | 私有 HTTP/SOCKS5 代理，可选中转 | `10.246.77.1` |
| 家里 Windows 电脑 | 被公司电脑远程访问，也可以使用代理 | `10.246.77.10` |
| 公司 Windows 电脑 | 被家里电脑远程访问，也可以使用代理 | `10.246.77.20` |

远程访问走两台 Windows 的 ZeroTier IP。代理上网只给需要的软件单独配置代理，不改整台电脑的全局网络。默认代理入口是 `10.246.77.1:10808`；如果这个入口测速慢，可以按后文开启可选公网入口，让客户端直接连 Ubuntu 服务器公网 IP。

## 开始前准备

你需要准备：

1. 一个 ZeroTier 账号，并在 [ZeroTier Central](https://my.zerotier.com) 创建一个私有网络。
2. 复制这个网络的 16 位网络编号，初始化脚本会问你这个编号。
3. 一台 Ubuntu 机器，能使用 `sudo`。
4. 家里和公司两台 Windows 电脑，能用管理员身份打开 PowerShell。
5. 两台 Windows 上已经安装好你平时使用的远程工具，远程地址改填对方的 ZeroTier IP。
6. 如果你想给代理加认证，再准备一个代理用户名和密码；默认可以不填。

## 完整流程

### 1. 获取项目

在 Ubuntu 或 Windows 上都可以先获取仓库：

```bash
git clone https://github.com/rockyshi1993/zerotier-gateway.git
cd zerotier-gateway
```

Windows PowerShell：

```powershell
git clone https://github.com/rockyshi1993/zerotier-gateway.git
cd .\zerotier-gateway
```

### 2. 生成配置

运行初始化脚本，按提示输入 ZeroTier 网络编号和三台机器的 IP。一路回车会使用推荐默认值。

Ubuntu：

```bash
bash scripts/ubuntu/init-config.sh
```

Windows PowerShell：

```powershell
.\scripts\windows\init-config.ps1
```

脚本会在项目根目录生成 `.env`。最关键的几项会是这样：

```text
ZEROTIER_NETWORK_ID=你输入的 ZeroTier 网络编号
UBUNTU_ZT_IP=10.246.77.1
HOME_PC_ZT_IP=10.246.77.10
WORK_PC_ZT_IP=10.246.77.20
PROXY_PUBLIC_ACCESS=false
PROXY_CONNECT_HOST=10.246.77.1
PROXY_ALLOWED_CLIENT_CIDRS=
PROXY_USERNAME=
PROXY_PASSWORD=
```

`PROXY_USERNAME` 和 `PROXY_PASSWORD` 默认可以留空。两项都留空时，代理不启用认证；如果要启用认证，必须两项都填写。

`PROXY_PUBLIC_ACCESS=false` 表示默认只走 ZeroTier 私有入口。后续如果想优化代理测速，可以重新运行初始化脚本，选择启用代理公网入口；账号密码仍然可选，但公网入口必须认真配置来源 IP 白名单。

如果已经有 `.env`，再次运行初始化脚本时，直接回车会沿用旧值。

默认配置行为：

- Ubuntu 脚本默认读取项目根目录 `.env`。
- Windows 脚本默认读取项目根目录 `.env`。
- 只有多配置或非默认路径时，才需要使用 `--env <path>` 或 `-Env <path>`。

#### ZeroTier Central 网段和地址池检查

到 ZeroTier Central 的网络详情页，打开 `Advanced`，建议保持下面这种简单配置：

| 位置 | 应该保留 |
|---|---|
| `Managed Routes` | `10.246.77.0/24 (LAN)` |
| `IPv4 Auto-Assign` | 可以关闭自动分配，改为给三台机器手动固定 IP |
| `Auto-Assign Pools` | 如果保留自动分配，只用 `10.246.77.100` 到 `10.246.77.254` |

不要把 `10.246.77.0/24` 填到 `Add Routes` 下面的 `Via` 里。`Via` 是“让某个节点转发某个网段”时才用；本项目默认只需要 `10.246.77.0/24 (LAN)`。

如果页面里还有下面这些内容，建议删掉：

- `172.27.0.1` 到 `172.27.255.254` 的自动分配地址池。
- 成员机器上的 `172.27.x.x` Managed IP。
- 误填到地址池里的 `192.168.x.x`。

三台机器最终只需要这些 ZeroTier IP：

| 设备 | Managed IP |
|---|---|
| Ubuntu 节点 | `10.246.77.1` |
| 家里 Windows 电脑 | `10.246.77.10` |
| 公司 Windows 电脑 | `10.246.77.20` |

调整后，在家里和公司两台 Windows 上重启 ZeroTier 并检查：

```powershell
Restart-Service ZeroTierOneService
zerotier-cli listnetworks
```

`listnetworks` 里应该只看到本机的 `10.246.77.x/24`，不应该再看到 `172.27.x.x`。

### 3. 配置 Ubuntu 节点

```bash
sudo bash scripts/ubuntu/install.sh --dry-run
sudo bash scripts/ubuntu/install.sh
sudo bash scripts/ubuntu/health-check.sh
```

`install.sh` 会同时安装 ZeroTier 和代理服务。普通安装只需要跑这一条；如果 `health-check.sh` 提示 `sing-box-zt-proxy.service could not be found`，说明代理服务没有装上，先重新执行 `sudo bash scripts/ubuntu/install.sh`。

如果安装时看到 `Unable to locate package sing-box`，说明当前 Ubuntu 源里没有 sing-box 包。更新到最新脚本后重新执行 `sudo bash scripts/ubuntu/install.sh`，脚本会自动添加官方 SagerNet apt 源后继续安装。

然后到 ZeroTier Central：

1. 找到刚加入网络的 Ubuntu 节点。
2. 勾选授权。
3. 把它的 ZeroTier IP 固定为 `.env` 里的 `10.246.77.1`。

成功标准：

- `health-check.sh` 能看到代理监听在 `10.246.77.1:10808`；如果你启用了公网入口，也可能看到 `0.0.0.0:10808`。
- Ubuntu 节点在 ZeroTier Central 里显示在线。

### 4. 配置两台 Windows

两台 Windows 都已经加入同一个 ZeroTier 网络后，还需要分别在本机执行一次 Windows 脚本。脚本会读取 `.env`，告诉你这台电脑应该放行哪一个对端 ZeroTier IP。

只加入 ZeroTier 网络、并且不需要被远程访问的电脑，可以不执行 `setup.ps1`；需要被另一台电脑远程访问，或需要本项目帮你检查网络和生成代理规则的 Windows，建议执行。

#### 打开管理员 PowerShell

先在 Windows 上打开管理员 PowerShell：

1. 关闭普通 PowerShell 窗口。
2. 开始菜单搜索 `PowerShell` 或 `Windows Terminal`。
3. 右键选择“以管理员身份运行”。
4. 进入项目目录；下面以 `E:\Worker\zerotier-gateway` 为例，如果你的仓库在别的位置，把路径换成自己的仓库目录。

确认当前窗口是不是管理员：

```powershell
([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
```

返回 `True` 才能写入防火墙规则；如果返回 `False`，先关闭窗口，重新用“以管理员身份运行”打开。

再临时允许当前窗口运行本仓库脚本：

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
```

这条命令只解决“脚本被 Windows 阻止运行”的问题，不会提升管理员权限。关掉当前 PowerShell 窗口后会恢复。

#### 执行 Windows 脚本

家里电脑执行：

```powershell
cd E:\Worker\zerotier-gateway
.\scripts\windows\setup.ps1 -Role Home
.\scripts\windows\test-network.ps1
```

公司电脑执行：

```powershell
cd E:\Worker\zerotier-gateway
.\scripts\windows\setup.ps1 -Role Work
.\scripts\windows\test-network.ps1
```

不要在同一台电脑上把 `-Role Home` 和 `-Role Work` 都执行一遍。`Role` 表示“当前这台电脑是谁”，不是你要连接的目标。

#### 授权并固定 IP

然后到 ZeroTier Central：

1. 授权家里电脑和公司电脑。
2. 把家里电脑固定为 `10.246.77.10`。
3. 把公司电脑固定为 `10.246.77.20`。

#### 写入防火墙规则

如果要让脚本写入 Windows 防火墙规则，分别在对应电脑上执行：

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

`-Role Home` 只在家里电脑执行，`-Role Work` 只在公司电脑执行。家里电脑的规则会放行公司电脑的 ZeroTier IP，公司电脑的规则会放行家里电脑的 ZeroTier IP。

#### 防火墙写入失败

如果写入防火墙时看到红色报错：

```text
New-NetFirewallRule : 拒绝访问。
Windows System Error 5
```

说明当前 PowerShell 没有管理员权限，或系统策略拒绝写入防火墙。先关闭当前窗口，重新用“以管理员身份运行”打开 PowerShell，进入项目目录后确认管理员状态：

```powershell
cd E:\Worker\zerotier-gateway
([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
```

返回 `True` 后再执行：

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
.\scripts\windows\setup.ps1 -Role Home -ApplyFirewall
```

公司电脑把最后一行改成：

```powershell
.\scripts\windows\setup.ps1 -Role Work -ApplyFirewall
```

成功标准：

- 家里电脑能 `ping 10.246.77.20`。
- 公司电脑能 `ping 10.246.77.10`。
- `test-network.ps1` 没有关键失败项。
- 执行 `-ApplyFirewall` 时没有红色报错，并看到 `Firewall rules applied.`。

### 5. 远程访问

远程工具里填写对方的 ZeroTier IP：

| 方向 | 填写地址 |
|---|---|
| 公司访问家里 | `10.246.77.10` |
| 家里访问公司 | `10.246.77.20` |

远程工具本身建议走 ZeroTier 直连，不要强行走 Ubuntu 代理。这样延迟最低，也少一层转发。

#### TUN 或全局代理开启后远程不通

如果家里或公司电脑开启了 TUN、全局代理、加速器或其他接管系统流量的软件，远程可能变慢，甚至直接连不上。处理原则是：代理可以开，但 ZeroTier 网段和 ZeroTier 进程必须直连。

在代理工具的直连或绕过规则里加入：

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

### 6. 给需要的软件配置代理

默认代理入口：

```text
地址：10.246.77.1
端口：10808
协议：HTTP 或 SOCKS5
用户名：默认不填；启用认证时填 PROXY_USERNAME
密码：默认不填；启用认证时填 PROXY_PASSWORD
```

如果 `.env` 里没有填写 `PROXY_USERNAME` 和 `PROXY_PASSWORD`，软件里也不要填用户名和密码。只在需要代理上网的软件里填这个代理；没有配置代理的软件继续走本机原网络。

#### 代理上网提速：可选公网入口

如果你发现 `10.246.77.1:10808` 代理测速慢，但同一台 Ubuntu 服务器上的 Outline、v2rayN 或其他公网入口很快，通常原因是：本仓库默认代理入口走 ZeroTier 私有网络，客户端到 Ubuntu 的这段链路可能绕路；Outline/v2rayN 往往是直接连服务器公网 IP。

这种情况下可以开启代理公网入口。它只优化“代理上网”，不改变远程控制路径。远程控制仍然优先走两台 Windows 的 ZeroTier IP。

在 Ubuntu 节点重新运行初始化脚本：

```bash
cd ~/zerotier-gateway
bash scripts/ubuntu/init-config.sh
```

走到“是否启用代理公网入口提速”时选择启用，按下面填写：

```text
代理监听地址：0.0.0.0
客户端连接代理地址：你的 Ubuntu 服务器公网 IP
允许访问公网代理的公网 IP/CIDR：公司公网IP/32,家里公网IP/32
```

生成后的 `.env` 会类似这样：

```text
PROXY_BIND_IP=0.0.0.0
PROXY_PUBLIC_ACCESS=true
PROXY_CONNECT_HOST=服务器公网IP
PROXY_ALLOWED_CLIENT_CIDRS=公司公网IP/32,家里公网IP/32
PROXY_PORT=10808
PROXY_USERNAME=
PROXY_PASSWORD=
```

账号密码仍然可以不填；两项都留空时不启用认证。如果公网入口没有配置账号密码，至少要保证云防火墙或系统防火墙只允许你的公司、家里公网 IP 访问 `10808`，不要把代理端口对全网开放。

让配置生效：

```bash
sudo bash scripts/ubuntu/install-proxy.sh --dry-run
sudo bash scripts/ubuntu/install-proxy.sh
sudo bash scripts/ubuntu/health-check.sh
```

然后在 Windows 上更新代理配置：

如果 Windows 仓库里也有一份 `.env`，先把下面这些代理字段同步成 Ubuntu 节点上的值；也可以在 Windows 重新运行 `.\scripts\windows\init-config.ps1`，输入同一套代理配置：

```text
PROXY_PUBLIC_ACCESS
PROXY_CONNECT_HOST
PROXY_ALLOWED_CLIENT_CIDRS
PROXY_PORT
PROXY_USERNAME
PROXY_PASSWORD
```

否则 `test-proxy.ps1`、PAC 和本地规则客户端仍会使用旧的 `10.246.77.1:10808`。

```powershell
.\scripts\windows\test-proxy.ps1
.\scripts\windows\generate-proxy-pac.ps1
.\scripts\windows\generate-client-rules.ps1
```

手动给软件填代理时，地址改成 `.env` 里的 `PROXY_CONNECT_HOST`，端口仍然是 `10808`。例如：

```text
地址：服务器公网IP
端口：10808
协议：HTTP 或 SOCKS5
```

如果 `test-proxy.ps1` 仍然连不上，先检查三处：

1. `PROXY_CONNECT_HOST` 是服务器公网 IP，不是 `10.246.77.1`。
2. DigitalOcean 或其他云厂商防火墙允许你的来源公网 IP 访问 `10808/tcp`。
3. Ubuntu 的 `ufw` 已允许 `PROXY_ALLOWED_CLIENT_CIDRS` 访问 `10808/tcp`。

#### 后续启用或修改代理账号密码

可以后续重新配置，不需要重新加入 ZeroTier，也不需要从头安装整套网络。代理服务跑在 Ubuntu 节点上，所以最终以 Ubuntu 节点项目根目录里的 `.env` 为准。

在 Ubuntu 节点的仓库目录重新运行初始化脚本：

```bash
cd ~/zerotier-gateway
bash scripts/ubuntu/init-config.sh
```

脚本检测到已有 `.env` 时，直接回车会沿用旧值；走到“是否启用代理用户名和密码”时按需要选择：

- 想启用或修改账号密码：选择启用，然后输入新的用户名和密码。
- 想关闭账号密码：选择不启用，脚本会把 `PROXY_USERNAME` 和 `PROXY_PASSWORD` 清空。

然后只刷新 Ubuntu 代理服务：

```bash
sudo bash scripts/ubuntu/install-proxy.sh
sudo bash scripts/ubuntu/health-check.sh
```

刷新后同步客户端：

- 手动给软件填代理的：在软件代理设置里填新的用户名和密码；如果已经关闭认证，就把软件里的用户名和密码也清空。
- 使用 `artifacts/windows-local-client.json` 的：把 Windows 仓库里的 `.env` 也改成同一套账号密码，然后重新生成本地规则：

```powershell
.\scripts\windows\generate-client-rules.ps1
```

测试代理：

```powershell
.\scripts\windows\test-proxy.ps1
```

### 7. 排除 IP、域名或进程

如果只是排除域名或 IP，编辑 `.env`：

```text
DIRECT_DOMAINS=localhost,*.local,*.company.com
DIRECT_DOMAIN_SUFFIXES=.local
DIRECT_IP_CIDRS=10.246.77.0/24,10.0.0.0/8,172.16.0.0/12,192.168.0.0/16
```

生成 PAC：

```powershell
.\scripts\windows\generate-proxy-pac.ps1
```

输出文件在 `artifacts/proxy.pac`。

如果要按进程排除，编辑 `.env`：

```text
PROXY_MODE=local-rule-client
DIRECT_PROCESS_GROUPS=remote-tools,chat-tools,game-tools
DIRECT_PROCESS_NAMES=
DIRECT_PROCESS_PATHS=
DIRECT_PROCESS_PATH_REGEX=
```

生成本地规则客户端配置：

```powershell
.\scripts\windows\generate-client-rules.ps1
```

输出文件在 `artifacts/windows-local-client.json`。本仓库负责生成规则文件，实际接管进程流量需要导入你正在使用的本地规则客户端。

### 8. 远程直连不稳定时，再开启中转

只有家里和公司长期无法直连，或者远程延迟明显不稳定时，再考虑中转。

默认配置下，Ubuntu 会用 `systemd-socket-proxyd` 创建 TCP 中转入口：

| 远程方向 | 连接地址 | 实际转发到 |
|---|---|---|
| 公司访问家里 | `10.246.77.1:443` | `10.246.77.10:3389` |
| 家里访问公司 | `10.246.77.1:444` | `10.246.77.20:3389` |

`RELAY_PORT=443` 表示第一个中转入口从 `443` 开始；如果 `REMOTE_PORTS` 有多个端口，脚本会继续使用后续端口。Ubuntu 只监听自己的 ZeroTier IP，不把远程端口暴露到公网。

Ubuntu 上先预览：

```bash
sudo bash scripts/ubuntu/install-relay.sh --dry-run
```

确认输出里的转发方向正确后再安装：

```bash
sudo bash scripts/ubuntu/install-relay.sh
```

看到下面这类输出，只代表中转 socket 已经安装并启用，还需要继续按下一节验证链路：

```text
created symlink ...
[INFO] Relay sockets installed.
```

#### 验证中转是否成功

先在 Ubuntu 上确认两个中转入口已经监听：

```bash
systemctl is-active zerotier-gateway-relay-home-3389.socket
systemctl is-active zerotier-gateway-relay-work-3389.socket
ss -lntp | grep -E '10.246.77.1:(443|444)'
```

成功时应看到两个 `active`，并且 `ss` 输出里有 `10.246.77.1:443` 和 `10.246.77.1:444`。如果没有监听，先确认 Ubuntu 的 ZeroTier IP 是 `10.246.77.1`：

```bash
zerotier-cli listnetworks
```

再从两台 Windows 测 Ubuntu 中转端口：

公司电脑测“公司访问家里”的入口：

```powershell
Test-NetConnection 10.246.77.1 -Port 443
```

家里电脑测“家里访问公司”的入口：

```powershell
Test-NetConnection 10.246.77.1 -Port 444
```

成功时应看到：

```text
TcpTestSucceeded : True
```

如果这里是 `False`，说明 Windows 到 Ubuntu 中转入口不通。先确认三台机器都在同一个 ZeroTier 网络；如果 Ubuntu 开了 `ufw`，放行 ZeroTier 网段访问中转端口：

```bash
sudo ufw allow from 10.246.77.0/24 to any port 443 proto tcp comment ztg-relay-home
sudo ufw allow from 10.246.77.0/24 to any port 444 proto tcp comment ztg-relay-work
sudo ufw status
```

再确认 Ubuntu 能访问两台 Windows 的远程端口：

```bash
nc -vz 10.246.77.10 3389
nc -vz 10.246.77.20 3389
```

如果提示没有 `nc`，先安装：

```bash
sudo apt-get update
sudo apt-get install -y netcat-openbsd
```

`nc` 成功时应看到 `succeeded`。如果 Ubuntu 访问某台 Windows 的 `3389` 失败，去对应 Windows 上重新写入防火墙规则：

家里电脑：

```powershell
.\scripts\windows\setup.ps1 -Role Home -ApplyFirewall
```

公司电脑：

```powershell
.\scripts\windows\setup.ps1 -Role Work -ApplyFirewall
```

全部验证通过后，远程工具里不再填对方 Windows 的 ZeroTier IP，而是按下面填写 Ubuntu 的中转地址：

| 远程方向 | 远程工具里填写 |
|---|---|
| 公司访问家里 | `10.246.77.1:443` |
| 家里访问公司 | `10.246.77.1:444` |

直连恢复稳定后，建议切回对方 Windows 的 ZeroTier IP。

停用中转：

```bash
sudo bash scripts/ubuntu/disable-relay.sh
```

停用脚本会关闭并移除本项目生成的 `zerotier-gateway-relay-*.socket` 和 `zerotier-gateway-relay-*.service`。如果你以后改过 `RELAY_PORT` 或 `REMOTE_PORTS`，它也会清理历史残留的中转单元，不会影响 ZeroTier 本身和代理服务。

### 9. 最终验收

全部完成后，至少确认这几项：

- Ubuntu、家里电脑、公司电脑都在同一个 ZeroTier 网络里，并且已授权。
- 三台机器的 ZeroTier IP 分别是 `10.246.77.1`、`10.246.77.10`、`10.246.77.20`。
- `zerotier-cli listnetworks` 里没有残留 `172.27.x.x`。
- 家里和公司能互相访问对方的 ZeroTier IP。
- 远程工具使用对方 ZeroTier IP 能连上。
- 需要代理的软件使用代理入口能上网：默认是 `10.246.77.1:10808`，启用公网入口后是 `PROXY_CONNECT_HOST:10808`。
- 不需要代理的软件仍然走本机原网络。
- 如果配置了排除规则，PAC 或本地客户端规则已经重新生成。

## 常见问题

### 家庭宽带不提供公网 IPv4，会影响远程吗？

会。你仍然可以正常用 IPv4 上网，但家里路由器拿到的是运营商大内网地址，不是别人能直接访问的公网 IPv4。常见判断方式：

- 路由器里的 `WAN IP` 是 `100.64.0.0` 到 `100.127.255.255` 之间的地址，例如 `100.68.x.x`。
- 运营商明确说家庭宽带不提供公网 IPv4，只有企业宽带提供。
- `zerotier-cli peers` 里公司到家里长期显示 `RELAY`，或者远程 ping 延迟高、丢包明显。

这种情况下，在家里路由器里做端口映射通常解决不了问题，因为流量还要先经过运营商 NAT。ZeroTier Central 只保留 `10.246.77.0/24 (LAN)` 即可，不需要继续给 `Via` 或地址池加复杂路由。

处理建议：

1. 先向运营商申请公网 IPv4 或动态公网 IPv4。如果运营商明确拒绝，就不要继续反复改家里路由器端口映射。
2. 改用离家里和公司更近的 VPS 做中转或反向连接。国内、香港、日本或新加坡节点通常比美国节点更适合低延迟远程。
3. 如果家里和公司两边都有可用 IPv6，可以尝试让 ZeroTier 走 IPv6 直连；但这依赖两边网络和防火墙，不保证一定成功。

不要把远程桌面或远程控制端口直接暴露到公网。推荐路径仍然是优先 ZeroTier 直连；直连长期不稳定时，再使用可信的中转节点。

## 常见选择

| 你想做什么 | 看这里 |
|---|---|
| 只想先跑通远程 | 先完成第 1 到第 5 步 |
| 只给浏览器或某个软件代理 | 完成第 6 步 |
| 默认代理入口慢，但服务器公网代理很快 | 看 [代理上网提速：可选公网入口](#代理上网提速可选公网入口) |
| 排除公司内网、局域网或指定域名 | 做第 7 步里的 PAC |
| 排除某个软件或多进程软件 | 做第 7 步里的本地规则客户端配置 |
| 家庭宽带没有公网 IPv4 | 看 [常见问题](#常见问题) |
| 远程延迟高、直连不稳定 | 再看第 8 步 |
| 安装失败或连不通 | 看 [故障排查](docs/troubleshooting.md) |

## 文档入口

- [安装指南](docs/install.md)
- [Ubuntu 节点](docs/ubuntu.md)
- [Windows 客户端](docs/windows.md)
- [远程访问](docs/remote.md)
- [代理上网](docs/proxy.md)
- [代理排除规则](docs/proxy-rules.md)
- [中转](docs/relay.md)
- [故障排查](docs/troubleshooting.md)
- [安全说明](docs/security.md)
- [回滚与卸载](docs/rollback.md)
