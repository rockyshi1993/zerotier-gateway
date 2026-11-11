# 安全边界与已知风险

ZeroTier 的 Private Network 和成员授权是接入控制的基础，但它们**不能自动保证**应用协议加密、凭据文件权限、双栈 DNS/IPv6 路由或公网发布服务本身的安全。本项目提供脚本和示例，运行时服务与所在主机的安全配置仍需你负责。

## 默认网络暴露面

| 功能 | 默认/可选入口 | 主要风险 |
|---|---|---|
| 私有 mixed HTTP/SOCKS5 | 仅 Ubuntu ZeroTier IP（示例 `10.246.77.1:10808`） | 同网络中不可信成员可能滥用代理；应限制成员 |
| 公网 mixed HTTP/SOCKS5 | 可选 `0.0.0.0:10808` | **无内建 TLS**，明文代理与密码暴露风险，可能形成开放代理 |
| ZeroTier UDP 9993 | 可选放行入站 `9993/udp` | 有助于 NAT/P2P 连通，但不保证 DIRECT；需审查云安全组 |
| IPv4 Exit Node | ZeroTier 内转发/NAT | 改变开启 Allow Default 的客户端 IPv4 出口；IPv6/DNS 边界独立 |
| 指定 TCP 中转 | Ubuntu ZeroTier IP 上的指定转发端口 | 可达性、转发目标权限和中转可用性依赖网关 |
| 公网站点发布 | 指定公网 TCP/HTTPS 入口 | 实际互联网暴露目标服务、认证和漏洞 |
| Windows 多代理节点池 | `127.0.0.1:20808` | 本地服务和计划任务；故障时新连接失败而非自动直连 |
| 代理限速 | 已有代理端口上的 tc 规则 | 不准确的 IP/CIDR 可能限错对象；不会自动管控所有流量 |

## 已知安全风险：含口令文件权限

Ubuntu 初始化器写出的 `.env` 可能包含 `PROXY_USERNAME` / `PROXY_PASSWORD`；模板渲染会生成 `artifacts/sing-box-server.json`，并复制到 `/etc/zerotier-gateway/sing-box-server.json`。当前源码没有在这些路径上统一实施“仅所有者可读”的严格权限策略；**权限风险尚未通过代码修复**。

部署者可先检查并临时限制这些文件的读取权限，但这不能消除文件生成瞬间可能采用过宽权限的风险：

```bash
stat -c '%a %U:%G %n' .env artifacts/sing-box-server.json 2>/dev/null
sudo stat -c '%a %U:%G %n' /etc/zerotier-gateway/sing-box-server.json 2>/dev/null
# 在核实所有权、服务所需权限后按需限制文件读取：
[ -f .env ] && chmod 600 .env
[ -f artifacts/sing-box-server.json ] && chmod 600 artifacts/sing-box-server.json
[ -f /etc/zerotier-gateway/sing-box-server.json ] && sudo chmod 600 /etc/zerotier-gateway/sing-box-server.json
```

若配置目录由多人共用，应特别注意目录和备份权限。**不要将 `.env`、生成 JSON、带口令的错误日志上传仓库或 Issues。** 源码修复需作为单独安全任务审批、实施和测试。

## 公网代理不等于 TLS

`templates/sing-box/server-mixed.json.tmpl` 的 mixed inbound 未配置 TLS。即使启用了账号密码，也不能宣称公网代理通信和凭据得到传输加密。

默认建议：优先使用私有 ZeroTier 入口；如确需互联网直接访问，必须独立评估加密传输、身份认证、来源限制、系统防火墙、云安全组和滥用日志，并参考 [公网代理](proxy-public.md)。**不要将“公网路径可能更快”写成无条件安全推荐。**

## IPv4 Exit Node 与 Windows 路由

ZeroTier Central 的 `0.0.0.0/0` 只是提供默认路由能力；客户端还需要显式允许。Windows 脚本没有证据证明会自动把仓库中的 `allowDefault=0` 模板应用到已安装客户端，因此**必须现场检查每台设备的 Allow Default 与路由状态**。

本 Exit Node 当前只接管 IPv4；访问 `https://api.ipify.org` 显示 Ubuntu IPv4 不代表 IPv6 及 DNS 一定同路。使用 `https://api64.ipify.org` 和实际 DNS 测试查明边界，必要时关闭使用该出口的业务。

## 防火墙与回退边界

`scripts/ubuntu/lib/firewall.sh` 含按端口删除 UFW allow 规则的逻辑，可能触及没有项目专属 marker 的历史规则。调整公网入口、重新安装代理前，建议记录 `sudo ufw status numbered`，预览变更并核实所有权，不要把所有受影响规则都视为“项目只管理自己创建的资源”。

`install-proxy.sh --allow-zerotier-udp` 除了 ZeroTier UDP UFW 放行，**还会刷新或重启 sing-box 代理**，请考虑已有会话的中断。若云厂商安全组拦截 UDP，单独修改 Ubuntu UFW 不一定足够。

## 公网站点发布

公开某一内网站点不等于公开整个 ZeroTier 网络；但公开的目标应用仍需自己的身份认证、限流、更新和日志。不要无保护地公开 RDP、SSH、数据库和管理后台。项目不能修改未知云厂商安全组、路由器入站 NAT 或上游 DNS。

## 退出与卸载

停用 IPv4 Exit Node 时先让使用它的客户端取消 Allow Default，再按需移除 Central 默认路由，最后停用 Ubuntu 项目 NAT。`uninstall.sh` 只覆盖基础代理服务，不会自动回收所有高级功能、Central 路由和主机历史规则。见[回滚与卸载](rollback.md)。

## 版本与验证等级

当前 `VERSION` 为 `1.4.0-dev`，已发布 v1.3.0 的 Git tag 与开发中的 `main` 不可混用。文档静态检查、脚本模拟测试与真实 Ubuntu/Windows/Android 网络验收是不同证据等级，不能互相替代。
