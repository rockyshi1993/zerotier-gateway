# 安装与互访验证

按本页从上到下验证。每一层通过后再继续；某一层失败时，先按该节的“失败时”处理，不要直接重装全部组件。

默认地址：Ubuntu `10.246.77.1`、家里电脑 `10.246.77.10`、公司电脑 `10.246.77.20`。如果初始化时使用了其他地址，以脚本输出为准。

## 1. Ubuntu 安装成功

在 Ubuntu 仓库根目录执行：

```bash
sudo bash scripts/ubuntu/health-check.sh
sudo systemctl is-active zerotier-one
sudo systemctl is-active sing-box-zt-proxy
sudo zerotier-cli info
sudo zerotier-cli listnetworks
sudo ss -lntp | grep ':10808'
```

通过标准：

- 两个服务都返回 `active`。
- `zerotier-cli info` 包含 `ONLINE`。
- `listnetworks` 中目标网络为 `OK`，并显示 Ubuntu 的 `10.246.77.1/24`。
- `ss` 能看到 `10.246.77.1:10808`；启用公网代理时也可能是 `0.0.0.0:10808`。

失败时：服务不存在就重新运行 `sudo bash scripts/ubuntu/install.sh`；网络显示 `ACCESS_DENIED` 就回到 ZeroTier Central 授权该节点；地址不是计划值就先修正 Central 的 Managed IP。

如果刚在 ZeroTier Central 授权 Ubuntu 节点，或刚把 Managed IP 修正为 `10.246.77.1`，回到 Ubuntu 执行：

```bash
sudo systemctl restart sing-box-zt-proxy
sudo systemctl status sing-box-zt-proxy --no-pager
sudo ss -lntp | grep ':10808'
sudo bash scripts/ubuntu/health-check.sh
```

这一步确认代理服务已经用新的 ZeroTier 地址重新监听。`install.sh --dry-run` 只预览计划，不会修复授权或重启服务。

## 2. 三台设备都已加入 ZeroTier

家里和公司电脑分别在管理员 PowerShell 中执行：

```powershell
zerotier-cli info
zerotier-cli listnetworks
.\scripts\windows\test-network.ps1
```

通过标准：

- 两台电脑的 `zerotier-cli info` 都显示 `ONLINE`。
- 家里电脑显示 `10.246.77.10/24`，公司电脑显示 `10.246.77.20/24`。
- `test-network.ps1` 对 Ubuntu、本机和对端地址的结果没有关键失败。

如果看到旧网段地址或 `REQUESTING_CONFIGURATION`，先确认只加入了正确的网络、三台设备均已授权且 Managed IP 没有冲突。

## 3. 家里与公司双向互访

家里电脑执行：

```powershell
ping -n 20 10.246.77.20
```

公司电脑执行：

```powershell
ping -n 20 10.246.77.10
```

通过标准：两边都能收到回复，且没有持续高丢包。偶发单包抖动不等于安装失败；连续超时则继续检查：

```powershell
zerotier-cli peers
Get-NetRoute -AddressFamily IPv4 | Where-Object DestinationPrefix -eq '10.246.77.0/24'
```

如果开启了 TUN、全局代理或加速器，请先按[代理排除规则](proxy-rules.md)让 ZeroTier 网段和远程工具直连，再重测。

## 4. Windows 远程主机已开启

只在“要被连接”的 Windows 上执行。Windows Pro、Enterprise、Education 和 Server 可作为微软远程桌面主机；Windows Home 只能作为客户端，可改用其他远程控制工具。

先预览当前状态，再启用：

```powershell
.\scripts\windows\enable-remote-desktop.ps1
.\scripts\windows\enable-remote-desktop.ps1 -Apply
```

然后按当前电脑角色写入仅允许 ZeroTier 对端和中转节点访问的防火墙规则：

```powershell
# 家里电脑
.\scripts\windows\setup.ps1 -Role Home -ApplyFirewall

# 公司电脑
.\scripts\windows\setup.ps1 -Role Work -ApplyFirewall
```

在目标电脑检查主机状态：

```powershell
Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server' -Name fDenyTSConnections
Get-Service TermService
Get-NetTCPConnection -State Listen -LocalPort 3389
```

通过标准：`fDenyTSConnections` 为 `0`、`TermService` 正在运行，并有 `3389` 监听。目标电脑必须保持开机和唤醒；台式机如需取消交流电待机，可按需执行：

```powershell
powercfg /change standby-timeout-ac 0
```

## 5. 远程端口与实际连接

公司电脑验证家里电脑：

```powershell
Test-NetConnection 10.246.77.10 -Port 3389
mstsc /v:10.246.77.10
```

家里电脑验证公司电脑：

```powershell
Test-NetConnection 10.246.77.20 -Port 3389
mstsc /v:10.246.77.20
```

通过标准：`TcpTestSucceeded : True`，并能看到登录界面。端口通但无法登录时，检查目标 Windows 账户是否有密码、是否属于管理员或“远程桌面用户”，以及输入的是否是目标电脑账户。

## 6. 私有代理入口与真实出口

在已加入 ZeroTier 的 Windows 执行：

```powershell
.\scripts\windows\test-proxy.ps1
```

该脚本先验证代理端口，再通过代理访问 `https://api.ipify.org`。通过标准是 `TcpTestSucceeded : True`，随后返回一个出口 IP，并显示两项检查通过。

如果使用 v2rayN，本地监听为 `127.0.0.1:10808`，再执行：

```powershell
curl.exe --ssl-no-revoke -x socks5h://127.0.0.1:10808 https://api.ipify.org
curl.exe --ssl-no-revoke -x socks5h://127.0.0.1:10808 https://www.google.com/generate_204 -I
```

第一条应返回出口 IP，第二条应返回 `204`。端口能通但出口测试失败时，先在 Ubuntu 重跑 `health-check.sh`，再看[代理无法连通](troubleshooting.md#代理无法连通)。

## 7. 中转只在需要时验证

ZeroTier 直连稳定时无需安装中转。直连长期高延迟或丢包时，按[中转兜底](relay.md)安装；该页保留 `systemctl is-active`、`ss`、`Test-NetConnection` 和 `nc -vz` 的完整专项验证，避免在这里复制两套命令。

## 最终验收

- Ubuntu 服务、ZeroTier 网络和代理监听均正常。
- 三台设备地址正确，家里与公司双向互访。
- 需要被访问的 Windows 已开启远程主机，3389 从对端可达并实际登录成功。
- 私有代理端口与真实出口测试通过。
- 若启用中转，中转页的四层验证全部通过。

全部通过后才算“安装成功”，而不只是脚本没有报错。

## 按需功能的专项验收

首次安装不需要启用下面功能。启用后按对应任务页验证，避免把公网、流控或故障注入命令混进基础安装路径：

- 两台以上代理与本地单入口：[多台代理服务器](proxy-multi-server.md#7-验证自动切换)。
- 指定客户端上下行上限和未限速对照：[按客户端限速](rate-limit.md#验证限速没有扩大范围)。
- 公网 IP+端口的目标、本机与外部四层检查：[公网站点发布](publish-site.md#a-公网-ip--端口)。
- 域名 DNS、HTTP、HTTPS、证书与 WebSocket：[公网站点发布](publish-site.md#b-域名--自动-https)。
- Pixel/Android 移动网络经 Ubuntu 出口：[私有 Exit Node](exit-node.md#4-验证是否真的生效)，包括 `manage-exit-node.sh test`、`https://api.ipify.org` 和 `https://api64.ipify.org`。
- 正在使用旧版本时的升级前后不变量：[安全升级](upgrade.md#通过标准)。
