# 安装与功能验收：按你使用的能力验证

**不必让所有用户完成全部验证。** 先验收自己启用的能力：仅成员互访不需要通过 Ubuntu 代理/Exit Node；仅私有代理不需要设置 RDP；手机 Exit Node 必须在 Android 端实际验证。

## 验收层级

| 层级 | 证明什么 | 不能证明什么 |
|---|---|---|
| ZeroTier `ONLINE` / `OK` | 客户端和网络控制面状态 | 到特定服务 TCP 可达 |
| Ubuntu 服务 `active` / 端口监听 | 进程已启动并监听端口 | 客户端能连接、代理能出公网 |
| `Test-NetConnection` | 目标 TCP 入口可达 | 代理协议、账号、DNS 或外网访问正常 |
| 经代理的实际公网 IP | 某一请求确实经网关出口 | 所有软件/IPv6/DNS 都经网关 |
| Android IPv4 出口 | IPv4 默认路由链有效 | IPv6/所有 DNS 都无泄漏 |

`health-check.sh` 当前主要输出诊断信息，部分内部命令失败会被忽略；**不能只看退出码 0 就宣布安装成功**。

## 1. Ubuntu 安装成功

**适用：** 你部署了 Ubuntu 网关。在 Ubuntu 仓库目录检查：

```bash
sudo bash scripts/ubuntu/health-check.sh
sudo systemctl is-active zerotier-one
sudo systemctl is-active sing-box-zt-proxy
sudo zerotier-cli info
sudo zerotier-cli listnetworks
ip -4 -br addr
sudo ss -lntp | grep ':10808'
```

通过标准：ZeroTier 网络为 `OK`；ZeroTier 网卡的地址与 Central 管理的 IP 一致；使用代理时 `sing-box-zt-proxy` 为 `active`，并在配置的 ZeroTier IP/代理端口上监听。`10.246.77.1:10808` 只是示例。

如果刚在 Central 授权 Ubuntu 或改变 Managed IP，先等 Ubuntu 取得该 IP，再核对/重启需要绑定地址的代理服务：

```bash
sudo systemctl restart sing-box-zt-proxy
sudo systemctl status sing-box-zt-proxy --no-pager
sudo ss -lntp | grep ':10808'
```

这一步会重启现有代理并影响当前连接；仅在绑定地址不正确或服务未正常运行时执行。代理安装不成功先定位原因，不要盲目重装 ZeroTier。

## 2. 三台设备都已加入 ZeroTier（仅使用 Home/Work 场景）

本节是对旧 Home/Work 示例的兼容验收；**只有你确实配置了三台成员时才执行**。仅一个 Ubuntu 和一台客户端时，不需要通过这一节的三设备数量要求。

在 Windows 查看：

```powershell
zerotier-cli info
zerotier-cli listnetworks
.\scripts\windows\test-network.ps1
```

示例地址为 Ubuntu `10.246.77.1`、家里 `10.246.77.10`、公司 `10.246.77.20`；实际以 Central 授权和本机网卡地址为准。相同 ZT 网段的其他 LAN/VPN 冲突也应排除。

## 3. 家里与公司双向互访（可选）

确实使用两台 Windows 时，分别进行双向访问。ICMP 只是辅助：

```powershell
# 家里设备
ping -n 20 10.246.77.20
```

```powershell
# 公司设备
ping -n 20 10.246.77.10
```

如果 ICMP 被安全策略拦截，可以直接验证目标 TCP 服务，不能仅凭 ping 失败断言所有连接都失败。

## 4. Windows 远程主机已开启（仅使用 RDP）

在**被访问的 Windows**（需要支持 RDP 主机的版本）执行：

```powershell
.\scripts\windows\enable-remote-desktop.ps1
.\scripts\windows\enable-remote-desktop.ps1 -Apply
Get-Service TermService
Get-NetTCPConnection -State Listen -LocalPort 3389
```

需要在管理员 PowerShell 下进行服务配置和防火墙操作。Windows Home 不能作为原生微软 RDP 主机，可改用其他远程工具。还要保持目标设备开机、账号可登录并启用 NLA。

## 5. 远程端口与实际连接

在连接发起端测试实际目标：

```powershell
# 公司访问家里（示例）
Test-NetConnection 10.246.77.10 -Port 3389
mstsc /v:10.246.77.10
```

需要双向 RDP 时再从家里电脑测试公司 `10.246.77.20:3389`。`TcpTestSucceeded: True` 之后，还须验证实际登录；如果其他远程软件走非 3389 端口，应使用其真实端口与客户端。

## 6. 私有代理入口与真实出口

在已入网 Windows（如使用了初始化器）运行：

```powershell
.\scripts\windows\test-proxy.ps1
```

如果只是手工设置代理，也可以不运行 Windows 项目脚本而直接测试：

```powershell
Test-NetConnection 10.246.77.1 -Port 10808
curl.exe --ssl-no-revoke -x socks5h://10.246.77.1:10808 https://api.ipify.org
```

预期：TCP 入口可达，真实返回 Ubuntu 公网出口 IP。启用认证时须使用对应代理软件的安全凭据输入；不要把口令直接提交到仓库。然后验证实际需要走代理的软件。

已通过端口检查但出口失败时优先核对代理协议、密码、Ubuntu 本机公网访问和防火墙。

## 7. 中转只在需要时验证

指定 TCP 中转是可选功能。需要时参见 [TCP 中转](relay.md) 中的 systemd socket、Ubuntu TCP 目标与 Windows 到中转入口的专项检查。不能将它描述为 ZeroTier P2P DIRECT/RELAY 的通用中继。

## 按需功能的专项验收

| 已启用功能 | 必须单独检查 |
|---|---|
| Android IPv4 Exit Node | Ubuntu 状态 + Central `0.0.0.0/0` + Android Allow Default + 移动数据 `https://api.ipify.org` + `https://api64.ipify.org` IPv6 边界 |
| 多节点代理 | 真实备用节点出口、故障切换只影响新连接、所有节点故障时 fail-closed，见[节点池](proxy-multi-server.md#7-验证自动切换) |
| 公网 IP+端口发布 | 目标 TCP、本机转发、云安全组、真实外部 TCP/HTTP 访问 |
| 公网域名发布 | DNS、80/443、证书信任、HTTP/HTTPS、必要的 WebSocket |
| 指定客户端代理限速 | 受限客户端与未受限对照、仅代理端口命中，见[限速](rate-limit.md#验证限速没有扩大范围) |
| 升级 | 原服务、监听、配置及真实出口不变量，见[升级](upgrade.md#通过标准) |

本页是验收操作手册，不记录“已在你的真实网络通过”的假结果；实际设备测试需由可访问该网络的人在目标环境执行。
