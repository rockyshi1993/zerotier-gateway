# Ubuntu 网关节点

Ubuntu 是可选网关执行环境：它加入 ZeroTier 网络，使用 sing-box 提供私有 HTTP/SOCKS5 代理，之后可以按需启用 IPv4 Exit Node、指定 TCP 中转、限速或公网发布。

仅两台 ZeroTier 成员互访时，**不需要部署 Ubuntu**。首次部署请先看[快速开始](quick-start.md)，不要将下面的组件命令误认为全部必须执行。

## 安装依赖与部署阶段

- 准备可 `sudo` 的 Ubuntu，具备 `systemd` 和正常的软件包源；运行时工具包括 ZeroTier、sing-box 等。不得仅凭历史 `STATUS.md` 宣称其他发行版均已实测。
- Ubuntu 的 ZT IP 必须在 Central 授权后真实出现在网卡上，才能让代理绑定该 IP。
- 项目一体化 `install.sh` 会先加入网络、再安装代理；首次授权尚未完成时，推荐现有两段脚本，不把一体化入口写成必然即刻成功。

```bash
bash scripts/ubuntu/init-config.sh
sudo bash scripts/ubuntu/install-zerotier.sh --dry-run
sudo bash scripts/ubuntu/install-zerotier.sh
sudo zerotier-cli listnetworks
ip -4 -br addr
```

在 Central 授权 Ubuntu 并确认计划 Managed IP 已经生效后：

```bash
sudo bash scripts/ubuntu/install-proxy.sh --dry-run
sudo bash scripts/ubuntu/install-proxy.sh
sudo bash scripts/ubuntu/health-check.sh
```

## 服务与文件

| 资源 | 作用 |
|---|---|
| `zerotier-one` | ZeroTier 网络客户端 |
| `sing-box-zt-proxy.service` | 私有 mixed 代理服务 |
| `/etc/zerotier-gateway/sing-box-server.json` | 代理运行配置，可能含明文凭据 |
| 项目根目录 `.env` | 初始化器生成的本地参数，可能含明文凭据 |
| 项目 `artifacts/sing-box-server.json` | 模板渲染产物，也可能含凭据 |

**安全提醒：** 当前初始化和模板渲染流程不保证含凭据文件的严格所有者权限。请在可信工作目录部署、检查权限并限制其他用户读取；安全缺口作为独立源码修复项，不因文档提示视为已修复。

## 检查私有代理状态

```bash
sudo systemctl is-active zerotier-one
sudo systemctl is-active sing-box-zt-proxy
sudo zerotier-cli listnetworks
sudo ss -lntp | grep ':10808'
```

以上端口是示例；以实际初始化配置为准。`health-check.sh` 会显示多个信息块，但部分内部失败可能被忽略，不能用退出码 `0` 代替客户端端到端验证。

## ZeroTier UDP 9993 与 DIRECT

ZeroTier 连接长期显示 `RELAY` 时，先核实云防火墙、安全组和 UDP 网络条件。项目 `install-proxy.sh --allow-zerotier-udp` 可以选择在 UFW 放行入站 UDP 9993，但**也会重新安装/重启代理服务**，不应将其描述为纯防火墙单点修改。放行 UDP 9993 也不保证一定建立 DIRECT。

不影响其他代理配置的手工防火墙管理需在充分核对现有规则和权限后进行，建议先查看 [排障](troubleshooting.md) 和 [安全说明](security.md)。

## 可选能力

[IPv4 Exit Node](exit-node.md) · [TCP 中转](relay.md) · [按客户端代理限速](rate-limit.md) · [公网站点发布](publish-site.md) · [安全升级](upgrade.md) · [卸载与资源清理](rollback.md)
