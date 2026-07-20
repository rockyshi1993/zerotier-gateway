# 手机移动网络：私有 Exit Node

这个任务解决的是：Pixel/Android 不连 Wi‑Fi、只用移动数据时，仍然希望整机流量通过 Ubuntu 出口上网，同时不把 `10808/tcp` 代理端口开放到公网。

先完成[快速开始](quick-start.md)，确认 Ubuntu 已加入 ZeroTier 并固定为 `10.246.77.1`。Exit Node 是按需功能，默认关闭；不开启时不会影响现有代理、远程、中转、限速或公网站点发布。

## 先看懂它和代理的区别

| 方式 | 入口 | 适合什么 |
|---|---|---|
| 私有代理 | 软件填写 `10.246.77.1:10808` | 浏览器、v2rayN、PAC 或指定软件走 Ubuntu 出口 |
| 私有 Exit Node | 客户端允许默认路由 | Pixel 移动网络下整机走 Ubuntu 出口 |
| 公网代理 | 软件填写服务器公网 IP:`10808` | 设备没有加入 ZeroTier，或明确要走公网代理 |

Exit Node 不是 HTTP/SOCKS 代理，不需要开放公网 `10808/tcp`。外网站点看到的出口仍是 Ubuntu 的公网出口 IP；“只走 ZeroTier IP”指手机到 Ubuntu 的入口路径在 ZeroTier 私有网络里，不是隐藏 Ubuntu 的公网出口身份。

## 1. Ubuntu 预览并启用

在 Ubuntu 仓库根目录执行。第一条只预览，不改系统：

```bash
sudo bash scripts/ubuntu/manage-exit-node.sh enable
```

确认 ZeroTier 网段、Ubuntu ZeroTier IP、ZeroTier 网卡和公网出口网卡都对，再执行：

```bash
sudo bash scripts/ubuntu/manage-exit-node.sh enable --apply
sudo bash scripts/ubuntu/manage-exit-node.sh status
```

脚本会启用 IPv4 forwarding，添加只匹配 ZeroTier 网段的 NAT/forward 规则，并创建项目自己的开机恢复服务。它不会重启现有代理服务，也不会修改公网代理开关。

如果你的 Ubuntu 地址不是默认 `10.246.77.1`，直接在命令里传值即可：

```bash
sudo bash scripts/ubuntu/manage-exit-node.sh enable --ubuntu-zt-ip 10.246.77.2 --zerotier-subnet 10.246.77.0/24
```

仍然先预览；确认后再追加 `--apply`。

## 2. ZeroTier Central 添加默认路由

到 ZeroTier Central 的网络页面，在 Managed Routes 增加：

```text
Destination: 0.0.0.0/0
Via: 10.246.77.1
```

这只是让网络里“存在一个默认出口”。它不会强制所有设备马上全局走 VPN；每台客户端还必须自己允许默认路由。

## 3. Pixel / Android 开启默认路由

在 Pixel 上：

1. 关闭 Outline、sing-box SFA、其他 VPN 或加速器。
2. 打开 ZeroTier One，确认已加入并连接同一个网络。
3. 进入这个网络的设置，打开 `Allow Default`、`Allow Default Route` 或类似“允许默认路由”的选项。
4. 关闭 Wi‑Fi，只保留移动数据。

Android 的文案会随 ZeroTier One 版本变化；核心判断是：这个 ZeroTier 网络必须允许默认路由。

## 4. 验证是否真的生效

Ubuntu 上先看状态：

```bash
sudo bash scripts/ubuntu/manage-exit-node.sh test
```

Pixel 上用移动数据打开：

```text
https://api.ipify.org
```

通过标准：返回的是 Ubuntu 服务器的公网出口 IP。

再打开：

```text
https://api64.ipify.org
```

本功能首期只做 IPv4。如果这里显示的是手机运营商 IPv6，说明 IPv6 仍可能绕过 Exit Node；这不是脚本安装失败，而是当前范围没有接管 IPv6。需要严格 IPv6 也走 Ubuntu 时，应作为后续需求单独实现。

## Windows 会不会也默认走 VPN？

不会自动走。

ZeroTier Central 的默认路由只是网络能力；Windows 还要在客户端自己开启 `Allow Default / Allow Default Route` 才会全局走 Exit Node。当前项目 Windows 模板默认是 `allowDefault=0`，所以 Windows 默认不会因此全局走 VPN，你电脑继续使用现有 v2rayN/私有代理方式，不会因为手机 Exit Node 自动切过去。

如果你未来想让某台 Windows 也整机走 Ubuntu 出口，再只在那台 Windows 的 ZeroTier 客户端里开启允许默认路由。

## 关闭 Exit Node

先预览：

```bash
sudo bash scripts/ubuntu/manage-exit-node.sh disable
```

确认后执行：

```bash
sudo bash scripts/ubuntu/manage-exit-node.sh disable --apply
```

关闭只清理项目创建的 sysctl 文件、开机恢复服务和三条带项目标记的 iptables 规则；不会关闭现有 `10.246.77.1:10808` 代理，也不会删除 ZeroTier 网络。

## 常见失败分层

| 现象 | 优先检查 |
|---|---|
| Pixel 仍显示手机运营商 IPv4 | Central 是否有 `0.0.0.0/0 via 10.246.77.1`；Pixel 是否开启允许默认路由 |
| Pixel 打不开网页 | Ubuntu `manage-exit-node.sh status` 是否显示 forwarding 和三条规则存在 |
| Windows 突然也全局走 VPN | 检查那台 Windows 的 ZeroTier 客户端是否开启了 Allow Default |
| IPv4 成功但 IPv6 是运营商地址 | 当前首期是 IPv4-only；不要把它宣称为严格全流量无泄漏 |
| 想继续只给浏览器代理 | 不用 Exit Node，仍按[代理上网](proxy.md)配置 `10.246.77.1:10808` |
