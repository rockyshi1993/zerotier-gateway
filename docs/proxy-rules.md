# 代理直连与排除规则

分流规则作用于**实际接管请求的客户端**，不在 Ubuntu 代理端自动识别 Windows 上的进程。项目生成 PAC 与 Windows 本地 sing-box 配置，但它们不是语义完全相同的消费者。

## 规则生效范围

| 场景 | 生成内容 | 生效前提 | 限制 |
|---|---|---|---|
| 域名和 IP 直连 | `artifacts/proxy.pac` | 浏览器/系统/软件显式使用 PAC | 不识别进程；部分 PAC 运行环境 DNS 行为不同 |
| 域名/IP/进程直连 | `artifacts/windows-local-client.json` | 本地 sing-box 运行且目标软件使用本地入口 | 不等于全机 TUN；进程识别依赖平台/版本 |
| 软件直接设置 Ubuntu SOCKS/HTTP | 无 | 软件主动把连接送到 Ubuntu | PAC 和本项目规则不会自动套用 |

## 正确区分精确域名和域名后缀

`DIRECT_DOMAINS` 对应 sing-box `domain` 的**精确匹配**，`DIRECT_DOMAIN_SUFFIXES` 对应 `domain_suffix`，不应把 `*.company.com` 当成通用的跨客户端通配语义。PAC 模板使用 `shExpMatch`，所以它对 `*.company.com` 的含义可能与 sing-box 不一致。

推荐对公司主域名和子域名分别写精确与后缀：

```powershell
.\scripts\windows\configure-proxy-rules.ps1 `
  -DirectDomains 'company.com,localhost' `
  -DirectDomainSuffixes '.company.com,.local' `
  -DirectIpCidrs '10.246.77.0/24,10.0.0.0/8,172.16.0.0/12,192.168.0.0/16' `
  -Generate
```

其中 IP 和域名均为示例。精确匹配 `company.com` 与后缀 `.company.com` 共同覆盖主域和子域；是否按预期命中还需要分别验证 PAC 和本地 sing-box，不能只看文件生成成功。

交互式查看/修改现有规则：

```powershell
.\scripts\windows\configure-proxy-rules.ps1
```

## 进程规则

进程规则只能在**本地规则客户端**上处理；Ubuntu 代理没有 Windows 的进程信息。可使用脚本内置的进程组，或显式指定进程名/路径：

```powershell
.\scripts\windows\configure-proxy-rules.ps1 -DirectProcessGroups 'remote-tools,chat-tools,game-tools' -Generate
```

多进程客户端需要覆盖真实的辅助进程，否则可能部分流量仍走代理。生成的 JSON 配置不会自行启动或接管流量。

## 使用生成的本地配置

在确认 Windows sing-box 已正确安装后：

```powershell
sing-box check -c .\artifacts\windows-local-client.json
sing-box run -c .\artifacts\windows-local-client.json
```

在目标软件中显式将代理地址指向配置生成的 `127.0.0.1:20808`（以你的实际 `LOCAL_PROXY_PORT` 为准）。停止 sing-box（运行终端内按 `Ctrl+C`）后，也应关闭软件的本地代理，否则请求可能失败。修改或取消分流规则时先停用该本地入口，再重新生成并验证配置，不能仅删除 JSON 就当作恢复了网络状态。

## 规则验证建议

- `company.com`、`sub.company.com` 应按自己的直连策略逐个验证；`unrelated-example.com` 不应意外命中。
- 零配置客户端和没有开启代理的软件不受本地 PAC/规则自动控制。
- 使用 `sing-box check` 验证 JSON 语法和版本适配，并使用真实请求确认命中行为；语法通过不等于流量命中正确。
- 客户端若使用 TUN、DoH 或特殊 DNS，应独立检查路由/DNS 行为，不能以一个浏览器结果推广到所有应用。

需要全局 IPv4 出口请看 [Exit Node](exit-node.md)，而不是把本地 mixed 规则误作系统路由。
