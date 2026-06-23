# 安装指南

这份文档按“第一次使用者照着做”的顺序写。目标是先跑通低延迟远程，再按需启用代理、排除规则和中转。

## 目录导航

- [整体流程](#整体流程)
- [第 0 步：准备 ZeroTier 网络](#第-0-步准备-zerotier-网络)
- [第 1 步：获取项目](#第-1-步获取项目)
- [第 2 步：填写配置文件](#第-2-步填写配置文件)
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

网络编号会填到 `.env`：

```text
ZEROTIER_NETWORK_ID=这里填你的网络编号
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

## 第 2 步：填写配置文件

复制配置样例：

```bash
cp config/example.env .env
```

Windows PowerShell：

```powershell
Copy-Item .\config\example.env .\.env
```

打开 `.env`，先填最关键的几项：

```text
ZEROTIER_NETWORK_ID=你的 ZeroTier 网络编号
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

## 第 3 步：安装 Ubuntu 节点

先预览，不改系统：

```bash
sudo bash scripts/ubuntu/install.sh --dry-run
```

确认计划没问题后安装：

```bash
sudo bash scripts/ubuntu/install.sh
```

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

## 第 4 步：配置两台 Windows

以管理员身份打开 PowerShell。

家里电脑：

```powershell
.\scripts\windows\setup.ps1 -Role Home
```

公司电脑：

```powershell
.\scripts\windows\setup.ps1 -Role Work
```

到 ZeroTier Central：

1. 授权家里电脑和公司电脑。
2. 家里电脑固定为 `10.246.77.10`。
3. 公司电脑固定为 `10.246.77.20`。

先测试网络：

```powershell
.\scripts\windows\test-network.ps1
```

如果需要让脚本写入 Windows 防火墙规则，分别在对应电脑上执行：

```powershell
.\scripts\windows\setup.ps1 -Role Home -ApplyFirewall
.\scripts\windows\setup.ps1 -Role Work -ApplyFirewall
```

成功标准：

- 家里电脑能访问 `10.246.77.20`。
- 公司电脑能访问 `10.246.77.10`。
- `test-network.ps1` 没有关键失败项。

## 第 5 步：远程访问

远程工具里填对方的 ZeroTier IP：

| 方向 | 地址 |
|---|---|
| 公司访问家里 | `10.246.77.10` |
| 家里访问公司 | `10.246.77.20` |

远程访问优先走 ZeroTier 直连。不要把远程工具强制走 Ubuntu 代理，否则会多绕一层，延迟通常更高。

如果远程工具本身有多个进程，排除代理时不要只排除一个主程序。应按安装目录、路径正则或完整进程名清单一起处理。

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

安装：

```bash
sudo bash scripts/ubuntu/install-relay.sh
```

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
| 直连延迟高 | 先排查授权、防火墙和网络质量，再考虑中转 |

更多排查命令见 [故障排查](troubleshooting.md)。
