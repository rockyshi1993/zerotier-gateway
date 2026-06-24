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

`RELAY_PORT` 是第一个监听端口，`REMOTE_PORTS` 是 Windows 远程端口列表。脚本会按“家里、公司”的顺序为每个远程端口分配两个连续监听端口。

先预览：

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

如果没有 `nc`：

```bash
sudo apt-get update
sudo apt-get install -y netcat-openbsd
```

如果 Windows 到 Ubuntu 的 `Test-NetConnection` 失败，先确认三台机器都在同一个 ZeroTier 网络；如果 Ubuntu 开了 `ufw`，放行 ZeroTier 网段访问中转端口：

```bash
sudo ufw allow from 10.246.77.0/24 to any port 443 proto tcp comment ztg-relay-home
sudo ufw allow from 10.246.77.0/24 to any port 444 proto tcp comment ztg-relay-work
sudo ufw status
```

停用：

```bash
sudo bash scripts/ubuntu/disable-relay.sh
```

停用脚本会关闭并移除本项目生成的 `zerotier-gateway-relay-*.socket` 和 `zerotier-gateway-relay-*.service`。如果启用中转后改过端口，再执行停用脚本也会清理历史残留单元。它不会卸载 ZeroTier，也不会停用代理服务。

直连工作良好时，不要用中转替代正常直连。
