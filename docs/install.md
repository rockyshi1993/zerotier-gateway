# 安装指南

这份文档按“第一次使用者照着做”的顺序写。目标是先跑通低延迟远程，再按需启用代理、排除规则和中转。

## 目录导航

- [整体流程](#整体流程)
- [第 0 步：准备 ZeroTier 网络](#第-0-步准备-zerotier-网络)
- [第 1 步：获取项目](#第-1-步获取项目)
- [第 2 步：生成配置文件](#第-2-步生成配置文件)
- [第 3 步：安装 Ubuntu 节点](#第-3-步安装-ubuntu-节点)
- [第 4 步：配置两台 Windows](#第-4-步配置两台-windows)
- [第 5 步：远程访问](#第-5-步远程访问)
- [第 6 步：代理上网](#第-6-步代理上网)
- [第 7 步：排除规则](#第-7-步排除规则)
- [第 8 步：中转兜底](#第-8-步中转兜底)
- [验收清单](#验收清单)
- [失败时先看什么](#失败时先看什么)

## 整体流程

推荐按下面顺序做，不要一开始就配置中转或复杂规则：

1. 创建一个 ZeroTier 私有网络。
2. 让 Ubuntu、家里电脑、公司电脑加入同一个 ZeroTier 网络。
3. 固定三台机器的 ZeroTier IP。
4. 用 ZeroTier IP 跑通家里和公司的双向远程。
5. 在 Ubuntu 上启动私有 HTTP/SOCKS5 代理。
6. 只给需要代理的软件配置代理。
7. 有排除需求时，再生成 PAC 或本地规则客户端配置。
8. 只有直连效果差时，再启用中转兜底。

推荐 IP 规划：

| 设备 | 作用 | ZeroTier IP |
|---|---|---|
| Ubuntu 节点 | 私有代理节点，可选中转节点 | `10.246.77.1` |
| 家里 Windows 电脑 | 家里远程端 | `10.246.77.10` |
| 公司 Windows 电脑 | 公司远程端 | `10.246.77.20` |

## 第 0 步：准备 ZeroTier 网络

1. 打开 [ZeroTier Central](https://my.zerotier.com)。
2. 创建一个网络。
3. 复制这个网络的 16 位网络编号。
4. 确认网络是私有网络。
5. 后面每台机器加入网络后，都要在这个页面勾选授权。

初始化脚本会问你这个网络编号：

```text
ZeroTier 网络编号，16 位: 这里输入你的网络编号
```

## 第 1 步：获取项目

Ubuntu：

```bash
git clone https://github.com/rockyshi1993/zerotier-gateway.git
cd zerotier-gateway
```

Windows PowerShell：

```powershell
git clone https://github.com/rockyshi1993/zerotier-gateway.git
cd .\zerotier-gateway
```

## 第 2 步：生成配置文件

运行初始化脚本，按提示回答问题。一路回车会使用推荐默认值。

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
ZEROTIER_SUBNET=10.246.77.0/24
UBUNTU_ZT_IP=10.246.77.1
HOME_PC_ZT_IP=10.246.77.10
WORK_PC_ZT_IP=10.246.77.20

PROXY_BIND_IP=10.246.77.1
PROXY_PORT=10808
PROXY_USERNAME=
PROXY_PASSWORD=
```

默认不需要代理用户名和密码。只有你想限制谁能使用这个代理时，才同时填写 `PROXY_USERNAME` 和 `PROXY_PASSWORD`。

如果已经有 `.env`，再次运行初始化脚本时，直接回车会沿用旧值。

字段含义：

| 字段 | 怎么填 |
|---|---|
| `ZEROTIER_NETWORK_ID` | ZeroTier Central 里复制的网络编号 |
| `UBUNTU_ZT_IP` | Ubuntu 节点固定 IP，推荐 `10.246.77.1` |
| `HOME_PC_ZT_IP` | 家里电脑固定 IP，推荐 `10.246.77.10` |
| `WORK_PC_ZT_IP` | 公司电脑固定 IP，推荐 `10.246.77.20` |
| `PROXY_BIND_IP` | 代理监听地址，通常和 Ubuntu 节点 IP 一样 |
| `PROXY_PORT` | 代理端口，默认 `10808` |
| `PROXY_USERNAME` | 可选代理用户名；留空表示不启用认证 |
| `PROXY_PASSWORD` | 可选代理密码；留空表示不启用认证 |

默认情况下，Ubuntu 和 Windows 脚本都会读取项目根目录的 `.env`。只有你把配置文件放到别的位置，才需要传 `--env <path>` 或 `-Env <path>`。

### ZeroTier Central 网段和地址池检查

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

## 第 3 步：安装 Ubuntu 节点

先预览，不改系统：

```bash
sudo bash scripts/ubuntu/install.sh --dry-run
```

确认计划没问题后安装：

```bash
sudo bash scripts/ubuntu/install.sh
```

`install.sh` 会同时安装 ZeroTier 和代理服务。普通安装只需要跑这一条，不需要手动找其他安装脚本。

如果安装时看到 `Unable to locate package sing-box`，说明当前 Ubuntu 源里没有 sing-box 包。更新到最新脚本后重新执行 `sudo bash scripts/ubuntu/install.sh`，脚本会自动添加官方 SagerNet apt 源后继续安装。

到 ZeroTier Central 完成三件事：

1. 找到 Ubuntu 节点。
2. 勾选授权。
3. 把它的 ZeroTier IP 固定为 `10.246.77.1`。

检查 Ubuntu 节点：

```bash
sudo bash scripts/ubuntu/health-check.sh
```

成功标准：

- Ubuntu 节点在 ZeroTier Central 显示在线。
- Ubuntu 节点 IP 是 `10.246.77.1`。
- 代理监听在 `10.246.77.1:10808`。
- 防火墙没有把 `10808` 暴露到公网。

如果 `health-check.sh` 提示 `sing-box-zt-proxy.service could not be found`，说明代理服务没有装上，先重新执行：

```bash
sudo bash scripts/ubuntu/install.sh
```

## 第 4 步：配置两台 Windows

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

先临时允许当前窗口运行本仓库脚本：

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
```

这条命令只解决“脚本被 Windows 阻止运行”的问题，不会提升管理员权限。关掉当前 PowerShell 窗口后会恢复。

两台 Windows 都已经加入同一个 ZeroTier 网络后，还需要分别在本机执行一次 Windows 脚本。脚本会读取 `.env`，告诉你这台电脑应该放行哪一个对端 ZeroTier IP。

只加入 ZeroTier 网络、并且不需要被远程访问的电脑，可以不执行 `setup.ps1`；需要被另一台电脑远程访问，或需要本项目帮你检查网络和生成代理规则的 Windows，建议执行。

家里电脑：

```powershell
cd E:\Worker\zerotier-gateway
.\scripts\windows\setup.ps1 -Role Home
.\scripts\windows\test-network.ps1
```

公司电脑：

```powershell
cd E:\Worker\zerotier-gateway
.\scripts\windows\setup.ps1 -Role Work
.\scripts\windows\test-network.ps1
```

不要在同一台电脑上把 `-Role Home` 和 `-Role Work` 都执行一遍。`Role` 表示“当前这台电脑是谁”，不是你要连接的目标。

到 ZeroTier Central：

1. 授权家里电脑和公司电脑。
2. 家里电脑固定为 `10.246.77.10`。
3. 公司电脑固定为 `10.246.77.20`。

如果需要让脚本写入 Windows 防火墙规则，分别在对应电脑上执行：

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

如果写入防火墙时看到：

```text
New-NetFirewallRule : 拒绝访问。
Windows System Error 5
```

先确认 PowerShell 是“以管理员身份运行”。如果不是，关闭窗口，右键 PowerShell 选择“以管理员身份运行”，进入项目目录后确认管理员状态：

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

- 家里电脑能访问 `10.246.77.20`。
- 公司电脑能访问 `10.246.77.10`。
- `test-network.ps1` 没有关键失败项。
- 执行 `-ApplyFirewall` 时没有红色报错，并看到 `Firewall rules applied.`。

## 第 5 步：远程访问

远程工具里填对方的 ZeroTier IP：

| 方向 | 地址 |
|---|---|
| 公司访问家里 | `10.246.77.10` |
| 家里访问公司 | `10.246.77.20` |

远程访问优先走 ZeroTier 直连。不要把远程工具强制走 Ubuntu 代理，否则会多绕一层，延迟通常更高。

如果远程工具本身有多个进程，排除代理时不要只排除一个主程序。应按安装目录、路径正则或完整进程名清单一起处理。

### TUN 或全局代理开启后远程不通

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

## 第 6 步：代理上网

代理入口：

```text
地址：10.246.77.1
端口：10808
协议：HTTP 或 SOCKS5
用户名：默认不填；启用认证时填 .env 里的 PROXY_USERNAME
密码：默认不填；启用认证时填 .env 里的 PROXY_PASSWORD
```

只在需要代理的软件里填这个代理。没有配置代理的软件继续走原网络。

### 后续启用或修改代理账号密码

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

成功标准：

- 需要代理的软件能通过 `10.246.77.1:10808` 访问网络。
- 不需要代理的软件不受影响。
- `test-proxy.ps1` 能连通代理入口。

## 第 7 步：排除规则

### 排除域名和 IP

编辑 `.env`：

```text
DIRECT_DOMAINS=localhost,*.local,*.company.com
DIRECT_DOMAIN_SUFFIXES=.local
DIRECT_IP_CIDRS=10.246.77.0/24,10.0.0.0/8,172.16.0.0/12,192.168.0.0/16
```

生成 PAC：

```powershell
.\scripts\windows\generate-proxy-pac.ps1
```

输出：

```text
artifacts/proxy.pac
```

把这个 PAC 配到浏览器、系统代理或你使用的代理工具里。

### 排除进程

进程规则只能在 Windows 本机通过本地规则客户端实现。Ubuntu 代理看不到 Windows 上的进程名。

编辑 `.env`：

```text
PROXY_MODE=local-rule-client
DIRECT_PROCESS_GROUPS=remote-tools,chat-tools,game-tools
DIRECT_PROCESS_NAMES=
DIRECT_PROCESS_PATHS=
DIRECT_PROCESS_PATH_REGEX=
```

生成规则：

```powershell
.\scripts\windows\generate-client-rules.ps1
```

输出：

```text
artifacts/windows-local-client.json
```

本仓库负责生成规则文件，实际按进程接管流量需要导入你正在使用的本地规则客户端。

多进程软件建议按下面顺序收集：

1. 软件所属分类组。
2. 安装目录。
3. 路径正则。
4. 主进程、服务进程、辅助进程、更新进程的完整进程名。

## 第 8 步：中转兜底

中转不是默认路径。只有下面情况才建议启用：

- 家里和公司长期无法直连。
- 远程延迟和丢包明显影响使用。
- 已确认不是 Windows 防火墙、ZeroTier 授权或 IP 配置问题。

Ubuntu 上预览：

```bash
sudo bash scripts/ubuntu/install-relay.sh --dry-run
```

默认 `REMOTE_PORTS=3389`、`RELAY_PORT=443` 时，预览里会看到：

| 远程方向 | 连接地址 | 实际转发到 |
|---|---|---|
| 公司访问家里 | `10.246.77.1:443` | `10.246.77.10:3389` |
| 家里访问公司 | `10.246.77.1:444` | `10.246.77.20:3389` |

确认方向正确后安装：

```bash
sudo bash scripts/ubuntu/install-relay.sh
```

安装后，把远程工具里的地址临时改成上表的 Ubuntu 中转地址。直连恢复稳定后，再切回对方 Windows 的 ZeroTier IP。

停用：

```bash
sudo bash scripts/ubuntu/disable-relay.sh
```

## 验收清单

完成后逐项确认：

| 检查项 | 期望结果 |
|---|---|
| ZeroTier 网络 | 三台机器都已加入同一个网络并授权 |
| Ubuntu IP | `10.246.77.1` |
| 家里电脑 IP | `10.246.77.10` |
| 公司电脑 IP | `10.246.77.20` |
| ZeroTier 地址 | `zerotier-cli listnetworks` 里没有残留 `172.27.x.x` |
| 远程访问 | 两台 Windows 能用对方 ZeroTier IP 远程 |
| 代理入口 | `10.246.77.1:10808` 可用 |
| 代理范围 | 只有配置了代理的软件走 Ubuntu |
| 排除规则 | PAC 或本地客户端规则重新生成并导入 |
| 中转 | 只有直连差时才启用 |

## 失败时先看什么

| 现象 | 先检查 |
|---|---|
| 三台机器互相 ping 不通 | ZeroTier 是否授权、IP 是否固定、是否在同一网络 |
| 远程工具连不上 | 是否填了对方 ZeroTier IP；Windows 防火墙是否允许远程端口 |
| 代理连不上 | Ubuntu 是否在线；`health-check.sh` 是否看到 `10.246.77.1:10808` |
| 代理认证失败 | 如果启用了认证，检查 `.env` 里的用户名密码是否和软件里填写一致；如果没启用认证，软件里不要填用户名密码 |
| 排除规则不生效 | 是否重新生成 PAC 或本地客户端规则；多进程软件是否只填了主进程 |
| 直连延迟高 | 先检查 ZeroTier Central 是否只保留 `10.246.77.0/24`，TUN 或全局代理是否让 `10.246.77.0/24` 和 ZeroTier 进程直连，再考虑中转 |

更多排查命令见 [故障排查](troubleshooting.md)。
