# 中转兜底

中转是可选能力，不是默认主路径。

只有满足下面情况时才考虑启用：

1. 家里电脑和公司电脑长期无法建立直连。
2. 远程访问体验明显较差。
3. UDP 或 NAT 条件无法继续优化。

中转使用 Ubuntu 节点的 ZeroTier IP 做 TCP 转发，不要求家里宽带有公网 IPv4。默认配置下：

| 远程方向 | 连接地址 | 实际转发到 |
|---|---|---|
| 公司访问家里 | `10.246.77.1:443` | `10.246.77.10:3389` |
| 家里访问公司 | `10.246.77.1:444` | `10.246.77.20:3389` |

当前脚本默认使用 `443/444 -> 3389`；普通使用无需理解或修改这些参数。

被中转访问的 Windows 必须允许当前 Ubuntu 中转服务器访问远程端口。Windows 初始化时选定 Ubuntu 地址后，`setup.ps1 -Role Home|Work -ApplyFirewall` 会自动写入对应规则。默认第一台中转服务器是 `10.246.77.1`，所以普通首次流程不需要额外手动加防火墙规则。

## 启用并验证默认中转

在 Ubuntu 仓库根目录先预览：

```bash
sudo bash scripts/ubuntu/install-relay.sh --dry-run
```

确认预览里的方向正确后安装：

```bash
sudo bash scripts/ubuntu/install-relay.sh
```

安装后检查：

```bash
systemctl is-active zerotier-gateway-relay-home-3389.socket
systemctl is-active zerotier-gateway-relay-work-3389.socket
systemctl status zerotier-gateway-relay-home-3389.socket
systemctl status zerotier-gateway-relay-work-3389.socket
ss -lntp | grep -E '10.246.77.1:(443|444)'
```

成功时应看到两个 `active`，并且 `ss` 输出里有 `10.246.77.1:443` 和 `10.246.77.1:444`。

从两台 Windows 测中转入口：

```powershell
# 公司电脑：访问家里电脑的中转入口
Test-NetConnection 10.246.77.1 -Port 443

# 家里电脑：访问公司电脑的中转入口
Test-NetConnection 10.246.77.1 -Port 444
```

成功时应看到：

```text
TcpTestSucceeded : True
```

再从 Ubuntu 测目标 Windows 远程端口：

```bash
nc -vz 10.246.77.10 3389
nc -vz 10.246.77.20 3389
```

如果没有 `nc` 或看到 `nc: command not found`：

```bash
sudo apt-get update
sudo apt-get install -y netcat-openbsd
```

安装后再执行 `nc -vz`。如果命令能运行但连接失败，优先回到目标 Windows，重新运行初始化脚本选择当前中转服务器，再执行 `setup.ps1 -ApplyFirewall`。

如果 Windows 到 Ubuntu 的 `Test-NetConnection` 失败，先确认发起端 Windows、目标 Windows 和当前中转 Ubuntu 都在同一个 ZeroTier 网络；如果 Ubuntu 开了 `ufw`，放行 ZeroTier 网段访问中转端口：

```bash
sudo ufw allow from 10.246.77.0/24 to any port 443 proto tcp comment ztg-relay-home
sudo ufw allow from 10.246.77.0/24 to any port 444 proto tcp comment ztg-relay-work
sudo ufw status
```

## 多台中转服务器

可以有多台 Ubuntu 服务器加入同一个 ZeroTier 网络。每台服务器必须使用不同的 ZeroTier IP，例如：

| 服务器 | ZeroTier IP |
|---|---|
| 旧中转服务器 | `10.246.77.1` |
| 新中转服务器 | `10.246.77.2` |

在哪台服务器上中转，就在那台服务器先运行初始化脚本；已有值直接回车保留，只把 Ubuntu ZeroTier IP 输入为该服务器自己的地址：

```bash
bash scripts/ubuntu/init-config.sh
```

然后在这台服务器上安装中转：

```bash
sudo bash scripts/ubuntu/install-relay.sh --dry-run
sudo bash scripts/ubuntu/install-relay.sh
```

切换服务器时，不需要在 Windows 上安装中转服务。把远程工具里的连接地址从旧服务器改成新服务器即可：

| 远程方向 | 旧服务器 | 新服务器 |
|---|---|---|
| 公司访问家里 | `10.246.77.1:443` | `10.246.77.2:443` |
| 家里访问公司 | `10.246.77.1:444` | `10.246.77.2:444` |

目标 Windows 需要允许新服务器访问远程端口。在目标 Windows 重新运行初始化脚本，直接回车保留其他值，只把 Ubuntu ZeroTier IP 输入为新服务器地址：

```powershell
.\scripts\windows\init-config.ps1
```

然后在目标 Windows 重跑对应角色的防火墙脚本。

目标是家里电脑，就在家里电脑执行：

```powershell
.\scripts\windows\setup.ps1 -Role Home -ApplyFirewall
```

目标是公司电脑，就在公司电脑执行：

```powershell
.\scripts\windows\setup.ps1 -Role Work -ApplyFirewall
```

切换后先从 Windows 验证新服务器入口：

```powershell
Test-NetConnection 10.246.77.2 -Port 443
Test-NetConnection 10.246.77.2 -Port 444
```

不用的旧中转可以停用。停用旧服务器不会影响新服务器，也不会影响 ZeroTier 本身。

## 很多台 Windows 电脑

很多台 Windows 可以加入同一个 ZeroTier 网络。只用代理或只访问其他电脑时，不需要执行 `setup.ps1`，也不需要中转配置。

当前中转脚本默认只为初始化时指定的家里电脑和公司电脑生成入口。

其他 Windows 如果也要被远程访问，优先使用它自己的 ZeroTier IP 直连；如果确实要经过中转，需要单独规划目标 IP 和中转端口，避免多个目标共用同一个入口端口。

## 停用中转

```bash
sudo bash scripts/ubuntu/disable-relay.sh
```

停用脚本会关闭并移除本项目生成的 `zerotier-gateway-relay-*.socket` 和 `zerotier-gateway-relay-*.service`。如果启用中转后改过端口，再执行停用脚本也会清理历史残留单元。它不会卸载 ZeroTier，也不会停用代理服务。

直连工作良好时，不要用中转替代正常直连。
