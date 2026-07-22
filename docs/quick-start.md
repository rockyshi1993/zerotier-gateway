# 5 分钟快速开始

这条路径只使用项目现有脚本。你无需接触 `.env`、修改脚本或理解全部参数；初始化脚本会逐项询问必要信息。

这里的 5 分钟指脚本路径本身；软件下载、ZeroTier Central 授权等待和远程工具账号调试可能需要额外时间。

## 1. 准备 ZeroTier 网络

1. 在 [ZeroTier Central](https://my.zerotier.com) 创建一个私有网络。
2. 记下 16 位网络编号。
3. 准备一台可使用 `sudo` 的 Ubuntu，以及家里、公司两台已安装 ZeroTier 的 Windows。

推荐地址：Ubuntu `10.246.77.1`、家里电脑 `10.246.77.10`、公司电脑 `10.246.77.20`。

## 2. 获取项目

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

后面的命令都在仓库根目录执行。

## 3. 配置并安装 Ubuntu

先运行初始化脚本。除网络编号外，其余问题可以直接回车使用推荐值：

```bash
bash scripts/ubuntu/init-config.sh
sudo bash scripts/ubuntu/install.sh --dry-run
sudo bash scripts/ubuntu/install.sh
```

安装完成后，在 ZeroTier Central 授权 Ubuntu 节点，并把它的 Managed IP 固定为 `10.246.77.1`。然后检查：

```bash
sudo bash scripts/ubuntu/health-check.sh
```

成功时应看到 Ubuntu 已加入网络，代理监听在 `10.246.77.1:10808`。

## 4. 让两台 Windows 加入网络

在家里和公司电脑的 ZeroTier 客户端中加入同一个网络，再到 ZeroTier Central：

- 授权两台 Windows。
- 家里电脑固定为 `10.246.77.10`。
- 公司电脑固定为 `10.246.77.20`。

Windows 只加入网络但不需要被远程访问时，可以跳过下一步的防火墙脚本。

## 5. 配置两台 Windows

两台电脑都用“管理员身份运行”打开 PowerShell，并临时允许当前窗口执行脚本：

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
.\scripts\windows\init-config.ps1
```

家里电脑执行：

```powershell
.\scripts\windows\setup.ps1 -Role Home -ApplyFirewall
.\scripts\windows\test-network.ps1
```

公司电脑执行：

```powershell
.\scripts\windows\setup.ps1 -Role Work -ApplyFirewall
.\scripts\windows\test-network.ps1
```

`Home` 和 `Work` 表示当前电脑的身份，不要在同一台电脑上混用。看到“拒绝访问”或 `Windows System Error 5` 时，说明当前窗口不是管理员 PowerShell。

## 6. 验证远程访问

不要只看脚本有没有报错。请打开[安装与互访验证](verification.md)，依次检查 Ubuntu 服务、三台设备入网、家里/公司双向访问、远程端口和代理出口。

如果使用微软远程桌面，还需要在被访问的 Windows 上完成[远程主机启用与 3389 验证](verification.md#4-windows-远程主机已开启)。Windows Home 不能作为微软远程桌面主机，但仍可使用其他远程控制工具。

| 方向 | 远程工具填写 |
|---|---|
| 公司访问家里 | `10.246.77.10` |
| 家里访问公司 | `10.246.77.20` |

远程工具优先直连对方的 ZeroTier IP，不要把远程流量强制送进 Ubuntu 代理。两边实际连接成功后再进入代理配置。

## 7. 按需使用代理

只给需要代理的软件填写：

```text
地址：10.246.77.1
端口：10808
协议：HTTP 或 SOCKS5
用户名/密码：初始化时未启用认证就留空
```

加入 ZeroTier 不会自动启用代理；没有填写代理的软件仍走本机网络。Windows 可以用下面的脚本检查入口：

```powershell
.\scripts\windows\test-proxy.ps1
```

Pixel/Android 在移动网络下想整机走 Ubuntu 出口时，不要把 `10808` 开到公网；基础安装成功后按[私有 Exit Node](exit-node.md)启用，Windows 默认不会因此全局走 VPN。

## 完成标准

- 三台设备都已授权，且 ZeroTier IP 不冲突。
- 家里和公司能访问对方的 ZeroTier IP。
- 两台 Windows 的 `test-network.ps1` 没有关键失败。
- Ubuntu `health-check.sh` 能看到代理监听。
- 需要代理的软件能通过 `10.246.77.1:10808` 上网。

完成标准必须以[安装与互访验证](verification.md)中的实际命令结果为准，不以“安装脚本执行结束”代替。遇到问题先停在失败的那一层，再看[故障排查](troubleshooting.md)。
