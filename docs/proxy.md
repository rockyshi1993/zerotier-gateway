# 私有 HTTP/SOCKS5 代理

Ubuntu 使用 sing-box 的 mixed inbound 提供 **HTTP 与 SOCKS5** 代理。默认示例入口 `10.246.77.1:10808` 只在你的 ZeroTier 网络里使用。它不是 ZeroTier 自身的功能；客户端**必须显式配置**要使用代理的软件。

## 先看懂流量

```text
浏览器 / 指定软件 ── HTTP/SOCKS5 ──→ Ubuntu ZT IP:10808 ──→ 互联网
其他未配置的软件 ──────────────────→ 客户端自己的默认网络
```

访问这个私有代理不需要启用 Allow Default。IPv4 Exit Node 是不同的全局路由能力，见 [手机出口](exit-node.md)。

## 前置和安装

首次 Ubuntu 网关按 [快速开始](quick-start.md) 的两段式流程部署：先让 Ubuntu 加入并获授权、取得正确 ZT IP，再运行 `install-proxy.sh`。可用以下命令确认服务和监听：

```bash
sudo systemctl is-active sing-box-zt-proxy
sudo ss -lntp | grep ':10808'
```

端口是示例值，实际以你的配置为准。代理默认不启用密码；ZeroTier Private Network 的成员授权仍然很重要。

## 让客户端软件使用代理

在支持代理的应用中设置：

```text
协议：HTTP 或 SOCKS5
服务器：10.246.77.1
端口：10808
账号密码：仅启用过代理认证才需要
```

### v2rayN 用户

在已加入 ZeroTier 的 Windows 中添加一个 SOCKS 节点，地址填写 Ubuntu 的私有 IP，端口为代理端口，账号密码与实际配置一致。选择该节点后，**还需在 v2rayN 或目标软件里实际启用代理**；添加节点本身不会改变其他应用的网络行为。

当 v2rayN 的系统代理入口为 `127.0.0.1:10808`（仅示例，可能与默认本地端口不同）时，链路是：

```text
应用 → 本地 v2rayN → Ubuntu ZeroTier IP:10808 → 公网
```

验证本地 SOCKS5 入口：

```powershell
curl.exe --ssl-no-revoke -x socks5h://127.0.0.1:10808 https://api.ipify.org
```

如果本地监听不是 `10808`，改用软件界面显示的真实端口。

## TUN 是否必须启用？

一般不必。使用系统代理的应用可以在不启用 TUN 的情况下通过 v2rayN；TUN 会接管更广的流量，存在将 ZeroTier 私网、远程软件和代理服务器路径再次代理导致环路或不可达的风险。

仅当某软件不遵守系统代理，且你已明确了解 TUN 路由范围时再考虑。应在 TUN 规则中排除 ZeroTier 网段、代理服务器本身和必要的远程设备 IP，并验证真实效果。**本项目生成的本地 sing-box mixed 配置不是 TUN 模式**。

## PAC / 本地规则 / 多节点池的边界

| 消费方式 | 实际接管范围 | 规则能力 |
|---|---|---|
| 软件手动 HTTP/SOCKS5 | 该软件的代理请求 | 由该软件决定直连策略 |
| PAC | 配置了 PAC 的软件请求 | 域名、域名后缀、IP，不能依赖进程识别 |
| Windows 本地 sing-box | 导入配置并主动将流量发送给本地入口的软件 | 域名/IP/进程规则（受客户端和 sing-box 版本影响） |
| 多节点池本地入口 `127.0.0.1:20808` | 使用该入口的软件的新请求 | 在节点故障时切换新连接，不迁移已有会话 |

参见 [代理排除规则](proxy-rules.md) 和 [多代理节点池](proxy-multi-server.md)。配置文件被生成，不代表流量已经被接管。

## 安全与账号密码

私有代理使用前应授权和信任 ZeroTier 成员。需要启用或变更认证时，在 Ubuntu 仓库目录重新运行初始化器选择密码，再运行 `install-proxy.sh` 使配置生效。**这会重启现有代理服务，可能影响当前连接。**

`.env` 和生成的 JSON 可能包含口令，当前脚本未保证严格文件权限；参见[安全说明](security.md)。若计划公开代理端口，必须先阅读[公网代理](proxy-public.md)的明文传输风险，公网账号密码不等于 TLS 加密。

## 实际验证

已加入 ZeroTier 的 Windows 上：

```powershell
Test-NetConnection 10.246.77.1 -Port 10808
curl.exe --ssl-no-revoke -x socks5h://10.246.77.1:10808 https://api.ipify.org
```

端口通不等于出口正确；返回 Ubuntu 的出口 IP 后，还应测试目标业务软件。失败时按[故障排查](troubleshooting.md)定位，不要直接重新安装所有服务。
