# 公网代理：不经过 ZeroTier

这个任务适合两种情况：设备没有加入 ZeroTier，或设备到 Ubuntu 的 ZeroTier 路径明显慢于公网直连。它只改变代理入口，远程访问仍优先使用 Windows 的 ZeroTier IP。

如果你的目标是 Pixel/Android 在移动网络下使用 Ubuntu 出口，同时不暴露服务器公网代理端口，请优先看[私有 Exit Node](exit-node.md)。公网代理需要开放 `10808/tcp`，和“只经 ZeroTier 私有入口”不是同一条路径。

## 1. 在 Ubuntu 开启公网入口

在 Ubuntu 仓库根目录重新运行初始化脚本：

```bash
bash scripts/ubuntu/init-config.sh
```

已有值直接回车保留；在“是否启用代理公网入口提速”选择 `y`，确认服务器公网 IP，并按需设置来源公网 IP/CIDR与账号密码。然后只刷新代理服务：

```bash
sudo bash scripts/ubuntu/install-proxy.sh --dry-run
sudo bash scripts/ubuntu/install-proxy.sh
sudo bash scripts/ubuntu/health-check.sh
```

健康检查应看到 `0.0.0.0:10808` 监听。还要在云厂商安全组中允许需要的来源访问 `10808/tcp`；没有这一步，Ubuntu 本机正常也无法从公网连接。

## 2. 客户端连接

未加入 ZeroTier 的客户端在软件中填写：

```text
类型：SOCKS5 或 HTTP
地址：Ubuntu 服务器公网 IP
端口：10808
用户名/密码：初始化时未启用认证就留空
```

已加入 ZeroTier 的设备仍可继续使用 `10.246.77.1:10808`；只有实测公网路径更快时才改用公网地址。

## 3. 从 Windows 验证

将 `<服务器公网IP>` 替换为实际地址：

```powershell
Test-NetConnection <服务器公网IP> -Port 10808
curl.exe --ssl-no-revoke -x socks5h://<服务器公网IP>:10808 https://api.ipify.org
```

启用了认证时，在第二条命令中增加 `--proxy-user 用户名:密码`。通过标准是 `TcpTestSucceeded : True` 且返回出口 IP。

## 4. 关闭公网入口

重新执行初始化脚本，在公网入口问题选择 `n`，然后刷新代理服务：

```bash
bash scripts/ubuntu/init-config.sh
sudo bash scripts/ubuntu/install-proxy.sh
sudo bash scripts/ubuntu/health-check.sh
```

关闭后应恢复为仅在 Ubuntu ZeroTier IP 上监听。云安全组中的 `10808/tcp` 公网规则也应一并关闭。
