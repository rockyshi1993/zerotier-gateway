# Android 移动数据通过 Ubuntu IPv4 Exit Node 上网

这一功能用于让**主动选择该出口的客户端**通过 Ubuntu 的公网 IPv4 出口上网，同时不需要将 HTTP/SOCKS5 代理端口 `10808/tcp` 暴露到互联网。

与“在浏览器中配置私有代理”不同，Exit Node 操作的是 **IPv4 默认路由和 NAT**。它不意味着所有 ZeroTier 成员都自动改变出口，也**不提供 IPv6 或 DNS 绝对无泄漏保证**。

## 先看懂三端职责

| 配置位置 | 负责什么 |
|---|---|
| Ubuntu | ZeroTier 已入网；IPv4 forwarding / NAT 与转发规则生效 |
| ZeroTier Central | 将 `0.0.0.0/0` 指向 Ubuntu 的 ZeroTier IP |
| Android 客户端 | 加入 Network、授权并显式允许 Default Route |

```text
Android (Allow Default) ── ZeroTier ── Ubuntu IPv4 NAT ── 互联网
Android IPv6 / DNS ── 需要另行检查实际走向，不能假设被接管
```

只希望访问 `10.246.77.1:10808` 的 Android 代理客户端，不需要本页默认路由配置；请看 [私有代理](proxy.md)。

## 前置条件

- Ubuntu 已加入私有 ZeroTier Network，已获 Central 授权，ZeroTier 网卡拥有计划 IPv4。
- Ubuntu 可以访问公网，且使用 `systemd`、`iptables`、`ip`、`sysctl`。
- Android 端已安装可用的 ZeroTier 客户端并加入同一个网络；预先检查设备上的其他 VPN/TUN 应用，因为 Android 通常对同时运行多个 VPN 有限制。
- 网段不与手机、Wi-Fi、已有 VPN 或云网络冲突。
- 使用者已评估把移动端流量改由 Ubuntu 出口带来的隐私与可用性影响。

**本页不需要两台 Windows、RDP 或公网 HTTP/SOCKS5 服务。**

## 1. 在 Ubuntu 预览并启用

**执行设备：已加入 ZeroTier 的 Ubuntu。**

```bash
sudo bash scripts/ubuntu/manage-exit-node.sh enable
sudo bash scripts/ubuntu/manage-exit-node.sh enable --apply
sudo bash scripts/ubuntu/manage-exit-node.sh status
```

第一条仅预览规则计划，第二条应用：启用 IPv4 forwarding、添加来源为 ZeroTier 子网的 NAT/forward 规则，并建立恢复服务。请在执行 `--apply` 前确认 ZeroTier 网卡、公网出口网卡和目标网段完全正确。它不会修改 Central 或 Android 设置，也不会开放公网代理端口。

Ubuntu 的 ZeroTier IP 不是默认例子时，可使用 `--ubuntu-zt-ip` 与 `--zerotier-subnet` 参数明确传入；先预览再应用。执行成功之后还必须进行下面两端配置。

## 2. 在 ZeroTier Central 添加路由

**执行位置：ZeroTier Central 中对应 Network 的 Managed Routes。**

```text
Destination: 0.0.0.0/0
Via: 10.246.77.1
```

把示例 `10.246.77.1` 改成 Ubuntu 的实际 ZeroTier IP。默认路由会提供给网络成员，但成员是否使用它取决于各设备的 ZeroTier 客户端路由设置；**不要将这一步误写成强制让所有客户端全局代理**。

## 3. 在 Android 上选择这条默认路由

1. 关闭可能冲突的其他 VPN/TUN 应用，连接并授权本项目 Network。
2. 在该 ZeroTier Network 设置中找到 **Allow Default / Allow Default Route**，明确开启。
3. 关闭 Wi-Fi，使用移动数据做首次验收，避免出口判断被 Wi-Fi 条件影响。
4. 必要时重新连接 ZeroTier 网络并查看设备实际路由行为。

不同 ZeroTier Android 客户端版本的 UI 名称、路由兼容性可能不同；以客户端显示和网络实测为准。Windows 也需按设备检查 Allow Default，不能仅因仓库里存在 `allowDefault=0` 模板就认定电脑不会受默认路由影响；当前 Windows 脚本没有证明模板会自动应用。

## 4. 验证是否真的生效

在 Ubuntu：

```bash
sudo bash scripts/ubuntu/manage-exit-node.sh status
sudo bash scripts/ubuntu/manage-exit-node.sh test
```

这些命令能显示规则状态和客户端检查清单，**不会代替在手机发起真实公网请求**。

在 Android 关闭 Wi-Fi、保留移动数据、保持 ZeroTier 连接后，访问：

```text
https://api.ipify.org
https://api64.ipify.org
```

验收：`api.ipify.org` 返回 Ubuntu 实际公网 IPv4；`api64.ipify.org` 是单独的 IPv6 边界检查。若 IPv6 返回运营商地址，当前 IPv4-only 实现并未接管它。还要按需测试域名解析路径，不得宣称严格“无泄漏”。

## 5. 安全关闭：必须处理三端

**不能只执行 Ubuntu `disable --apply` 就宣称客户端已恢复。** 服务端脚本不会自动删除 Central 的 `0.0.0.0/0`，也不会改变 Android 或 Windows 上的 Allow Default 设置。

按以下顺序操作，避免客户端仍将默认流量指向已关闭的 Ubuntu 转发节点：

1. **客户端：** 先在所有正在使用该 Ubuntu 出口的手机/电脑上关闭 Allow Default，或停用对应 ZeroTier VPN；确认它们已改回正常网络出口。
2. **Central：** 如果该默认路由就是为本 Exit Node 专门创建，且没有其他正在依赖它的成员，删除 `0.0.0.0/0 via <Ubuntu ZT IP>`；不要误删其他业务路由。
3. **Ubuntu：** 预览并应用项目规则停用：

```bash
sudo bash scripts/ubuntu/manage-exit-node.sh disable
sudo bash scripts/ubuntu/manage-exit-node.sh disable --apply
```

4. **复验：** Android 重新使用移动数据访问公网，Windows/其他成员确认无错误默认路由，Ubuntu 检查项目 Exit Node 状态。原有应用级私有代理不应被这一操作关闭。

## 6. 常见异常

| 现象 | 首要判断 |
|---|---|
| 手机连不上 ZeroTier 私网 IP | 成员授权、网络状态、目标网卡和路由冲突；与 Exit Node 是否开启不同 |
| 手机能访问 Ubuntu 私网，但 IPv4 出口还是运营商 | Central 默认路由与 Android Allow Default 是否确实生效 |
| Android 开启后网页全打不开 | Ubuntu 转发/NAT、错误出口网卡、其他 VPN/TUN 冲突、DNS 解析 |
| IPv4 成功，IPv6 仍是运营商 | 当前项目 **IPv4-only**，不得视为完整双栈出口 |
| Windows 意外改变出口 | 在该 Windows 实际检查 Allow Default 与路由表，模板存在并不等于已应用 |
| 显示 RELAY / 很慢 | 先排查网络与 UDP 连通性，见[故障排查](troubleshooting.md)；9993 放行不保证 DIRECT |

公网入口风险见[安全说明](security.md)。本方案不承诺客户端版本之间自动兼容，也不代替真实 Android 网络验收。
