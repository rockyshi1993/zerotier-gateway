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
systemctl status zerotier-gateway-relay-home-3389.socket
systemctl status zerotier-gateway-relay-work-3389.socket
ss -lntp | grep -E ':443|:444'
```

停用：

```bash
sudo bash scripts/ubuntu/disable-relay.sh
```

停用脚本会关闭并移除本项目生成的 `zerotier-gateway-relay-*.socket` 和 `zerotier-gateway-relay-*.service`。如果启用中转后改过端口，再执行停用脚本也会清理历史残留单元。它不会卸载 ZeroTier，也不会停用代理服务。

直连工作良好时，不要用中转替代正常直连。
