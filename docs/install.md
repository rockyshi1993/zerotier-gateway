# 开始使用：选择接入方式

本项目提供的是 **ZeroTier 私网之上的可选网关能力**。先决定你希望哪部分流量经过 Ubuntu，再选择最小步骤；无需默认安装家里/公司两台 Windows 的完整脚本链。

## 哪种方式最适合你？

| 目标 | 设备与前置 | 正确入口 | 不需要做的事 |
|---|---|---|---|
| 只访问另一台电脑或内网服务 | 两台设备能加入同一私有 ZeroTier 网络 | [仅成员互访](remote.md) | 不必安装 Ubuntu、代理、Exit Node |
| 指定浏览器/软件换成 Ubuntu 出口 | Ubuntu + 至少一台已授权客户端 | [部署私有网关](quick-start.md) | 不必启用 RDP / Allow Default |
| Android 移动数据时整机 IPv4 走 Ubuntu | 已入网 Ubuntu + Android ZeroTier 客户端 | [IPv4 Exit Node](exit-node.md) | 不必配置 Windows Home/Work 或公开 10808 |
| 把内网 Web/TCP 服务发布到公网 | 公网可达 Ubuntu + ZeroTier 内目标服务 | [公网站点发布](publish-site.md) | 不必使用 Exit Node |
| 多节点代理自动故障转移 | 两台以上已验证可用的代理 + Windows | [多代理节点池](proxy-multi-server.md) | 不需要全局负载均衡控制器 |

## 部署网关前的核对清单

- 有自己管理的 **私有 ZeroTier 网络**和 16 位 Network ID；已了解成员需要授权。
- Ubuntu 可使用 `sudo`、`systemd`、`ip`、`iptables` 等工具；准备可安装 ZeroTier 和 sing-box 的网络环境。
- 选择一个与家里 LAN、公司网络、云 VPC、其他 VPN **不冲突**的 IPv4 网段。`10.246.77.0/24` 只是示例。
- 在 ZeroTier Central 确认 Ubuntu 将使用的 Managed IP；这必须与本地 `.env` 里的 Ubuntu ZT IP 一致。
- 客户端能够安装 ZeroTier，并能够访问目标 IP；需要 RDP 时目标 Windows 版本和账号须满足条件。
- 正在升级旧版时先读 [安全升级](upgrade.md)，不要把首次安装当成升级手段。

## 两阶段安装为何重要

`install.sh` 是现有的一体化入口，会先安装并加入 ZeroTier，再部署代理。如果 Ubuntu 在 Central 尚未授权、尚未获得计划 IP，sing-box 绑定该 IP 的启动可能失败。

新手推荐：[第一阶段安装 ZeroTier 并授权](quick-start.md#2-安装并授权-zerotier) → [第二阶段安装代理](quick-start.md#3-安装私有代理)。

只有**已经具备正确 ZT IP**的现有 Ubuntu 节点，才可根据自己的需要使用一体化 `install.sh`。本轮没有改变其源码行为。

## 安装会修改哪些内容

| 操作 | 主要作用 | 是否默认执行 |
|---|---|---|
| ZeroTier 安装/入网 | 安装 `zerotier-one` 并设置客户端网络标志 | 网关首次安装 |
| 私有代理安装 | 安装 sing-box、写入配置和 systemd 服务、可能配置 UFW | 主路径 |
| IPv4 Exit Node | 修改 IP forwarding、NAT/forward、恢复服务 | 仅选择时 |
| TCP 中转 | 创建指定 systemd socket/service | 可选 |
| 公网发布 | 创建项目转发或 Caddy 服务，并配置入口 | 可选 |
| Windows 代理节点池 | 本地运行文件和登录计划任务 | 可选 |

高级变更的退出步骤统一从 [回滚与卸载](rollback.md) 进入。第一次安装完成后按 [分层验证](verification.md) 检查真实出口，不以脚本退出零作为唯一成功标准。
