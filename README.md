# ZeroTier Gateway

这份文档教你完成三件事：让家里电脑和公司电脑互相远程、在 Ubuntu 上搭一个只给指定软件使用的私有代理、按需设置哪些流量不走代理。

## 目录导航

- [适合什么场景](#适合什么场景)
- [最终会得到什么](#最终会得到什么)
- [开始前准备](#开始前准备)
- [完整流程](#完整流程)
- [常见选择](#常见选择)
- [文档入口](#文档入口)

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

远程访问走两台 Windows 的 ZeroTier IP。代理上网只给需要的软件单独配置 `10.246.77.1:10808`，不改整台电脑的全局网络。

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
PROXY_USERNAME=
PROXY_PASSWORD=
```

`PROXY_USERNAME` 和 `PROXY_PASSWORD` 默认可以留空。两项都留空时，代理不启用认证；如果要启用认证，必须两项都填写。

如果已经有 `.env`，再次运行初始化脚本时，直接回车会沿用旧值。

默认配置行为：

- Ubuntu 脚本默认读取项目根目录 `.env`。
- Windows 脚本默认读取项目根目录 `.env`。
- 只有多配置或非默认路径时，才需要使用 `--env <path>` 或 `-Env <path>`。

### 3. 配置 Ubuntu 节点

```bash
sudo bash scripts/ubuntu/install.sh --dry-run
sudo bash scripts/ubuntu/install.sh
sudo bash scripts/ubuntu/health-check.sh
```

`install.sh` 会同时安装 ZeroTier 和代理服务。普通安装只需要跑这一条；如果 `health-check.sh` 提示 `sing-box-zt-proxy.service could not be found`，说明代理服务没有装上，先重新执行 `sudo bash scripts/ubuntu/install.sh`。

然后到 ZeroTier Central：

1. 找到刚加入网络的 Ubuntu 节点。
2. 勾选授权。
3. 把它的 ZeroTier IP 固定为 `.env` 里的 `10.246.77.1`。

成功标准：

- `health-check.sh` 能看到代理监听在 `10.246.77.1:10808`。
- Ubuntu 节点在 ZeroTier Central 里显示在线。

### 4. 配置两台 Windows

家里电脑用管理员 PowerShell：

```powershell
.\scripts\windows\setup.ps1 -Role Home
.\scripts\windows\test-network.ps1
```

公司电脑用管理员 PowerShell：

```powershell
.\scripts\windows\setup.ps1 -Role Work
.\scripts\windows\test-network.ps1
```

然后到 ZeroTier Central：

1. 授权家里电脑和公司电脑。
2. 把家里电脑固定为 `10.246.77.10`。
3. 把公司电脑固定为 `10.246.77.20`。

如果要让脚本写入 Windows 防火墙规则，分别在对应电脑上执行：

```powershell
.\scripts\windows\setup.ps1 -Role Home -ApplyFirewall
.\scripts\windows\setup.ps1 -Role Work -ApplyFirewall
```

成功标准：

- 家里电脑能 `ping 10.246.77.20`。
- 公司电脑能 `ping 10.246.77.10`。
- `test-network.ps1` 没有关键失败项。

### 5. 远程访问

远程工具里填写对方的 ZeroTier IP：

| 方向 | 填写地址 |
|---|---|
| 公司访问家里 | `10.246.77.10` |
| 家里访问公司 | `10.246.77.20` |

远程工具本身建议走 ZeroTier 直连，不要强行走 Ubuntu 代理。这样延迟最低，也少一层转发。

### 6. 给需要的软件配置代理

代理入口：

```text
地址：10.246.77.1
端口：10808
协议：HTTP 或 SOCKS5
用户名：默认不填；启用认证时填 PROXY_USERNAME
密码：默认不填；启用认证时填 PROXY_PASSWORD
```

如果 `.env` 里没有填写 `PROXY_USERNAME` 和 `PROXY_PASSWORD`，软件里也不要填用户名和密码。只在需要代理上网的软件里填这个代理；没有配置代理的软件继续走本机原网络。

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

Ubuntu 上执行：

```bash
sudo bash scripts/ubuntu/install-relay.sh --dry-run
sudo bash scripts/ubuntu/install-relay.sh
```

停用中转：

```bash
sudo bash scripts/ubuntu/disable-relay.sh
```

### 9. 最终验收

全部完成后，至少确认这几项：

- Ubuntu、家里电脑、公司电脑都在同一个 ZeroTier 网络里，并且已授权。
- 三台机器的 ZeroTier IP 分别是 `10.246.77.1`、`10.246.77.10`、`10.246.77.20`。
- 家里和公司能互相访问对方的 ZeroTier IP。
- 远程工具使用对方 ZeroTier IP 能连上。
- 需要代理的软件使用 `10.246.77.1:10808` 能上网。
- 不需要代理的软件仍然走本机原网络。
- 如果配置了排除规则，PAC 或本地客户端规则已经重新生成。

## 常见选择

| 你想做什么 | 看这里 |
|---|---|
| 只想先跑通远程 | 先完成第 1 到第 5 步 |
| 只给浏览器或某个软件代理 | 完成第 6 步 |
| 排除公司内网、局域网或指定域名 | 做第 7 步里的 PAC |
| 排除某个软件或多进程软件 | 做第 7 步里的本地规则客户端配置 |
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
