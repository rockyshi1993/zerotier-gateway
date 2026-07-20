# 代理上网

Ubuntu 节点通过 sing-box 提供私有 HTTP/SOCKS5 混合代理。

默认私有代理入口：

```text
10.246.77.1:10808
```

默认不需要用户名和密码。需要启用或修改认证时，重新运行初始化脚本并按提示选择即可。

加入 ZeroTier 只代表 Windows 能访问这个入口，不代表会自动代理上网。只有在软件、系统代理、PAC 或本地规则客户端里主动配置代理后，对应流量才会走代理。没有配置代理的软件会继续使用原本网络。

## 代理什么时候生效

| 使用方式 | 生效范围 | 排除规则支持 |
|---|---|---|
| 在某个软件里手动填 `10.246.77.1:10808` | 只影响这个软件 | 由软件自己决定，本项目生成的排除规则不会自动生效 |
| 使用 `artifacts/proxy.pac` | 只影响配置了这个 PAC 的浏览器、系统代理或软件 | 支持域名、域名后缀、IP 网段；不支持进程 |
| 使用 `artifacts/windows-local-client.json` | 只影响导入并接管流量的本地规则客户端 | 支持域名、IP、进程；仅生成文件不会生效 |
| 使用[私有 Exit Node](exit-node.md) | 只影响开启 Allow Default 的客户端整机流量 | 不是 HTTP/SOCKS 代理，不使用本页排除规则 |

运行初始化或规则配置脚本只会更新本项目配置，不会自动修改 Windows 系统代理；只有软件、PAC 或本地规则客户端实际启用后才会接管流量。

## v2rayN 如何配置

如果你已经在用 v2rayN，可以把本仓库的 Ubuntu 代理作为 v2rayN 里的一个 `SOCKS` 节点。推荐优先添加 SOCKS，不需要再单独添加 HTTP 节点。

已加入 ZeroTier 的 Windows，节点这样填：

```text
类型：SOCKS
地址：10.246.77.1
端口：10808
用户名/密码：初始化时未启用认证就留空；启用时填写当时设置的账号
传输：tcp
伪装：none
TLS：关闭
```

如果启用了代理公网入口，并且这台设备没有加入 ZeroTier，或者实测服务器公网路径更快，可以把地址改成 Ubuntu 服务器公网 IP，端口仍然是 `10808`。

添加后，在 v2rayN 主界面把这个节点设为活动节点，再开启 v2rayN 的“系统代理”。这时 Windows 系统代理会指向 v2rayN 的本地监听地址；下面以本地监听 `127.0.0.1:10808` 为例，如果你改过 v2rayN 本地端口，以实际设置为准：

```text
127.0.0.1:10808
```

链路会变成：

```text
浏览器/软件 -> 127.0.0.1:10808 -> v2rayN -> 10.246.77.1:10808 -> Ubuntu 出口
```

验证：

```powershell
curl.exe --ssl-no-revoke -x socks5h://127.0.0.1:10808 https://api.ipify.org
curl.exe --ssl-no-revoke -x socks5h://127.0.0.1:10808 https://www.google.com/generate_204 -I
```

第一条能返回 IP，第二条返回 `204`，说明 v2rayN 的本地代理已经能通过 Ubuntu 出口访问网络。

## 已配置 127.0.0.1:10808，还需要开启 TUN 吗？

一般不需要。

如果 v2rayN 已经开启“系统代理”，并且 Windows 系统代理已经指向 v2rayN 本地监听地址，例如 `127.0.0.1:10808`，浏览器、Git、npm 和大多数遵守系统代理的软件通常已经会走 v2rayN。此时再开启 TUN，反而可能把 ZeroTier 网段、远程工具或代理服务器连接本身也接管进去，造成远程变慢、ZeroTier 不稳定或代理绕路。

只有下面情况才考虑开启 TUN：

- 某些软件完全不支持系统代理。
- 游戏、命令行或特殊客户端需要强制代理。
- 你明确希望几乎所有流量都由 v2rayN 接管。

如果必须开启 TUN，建议先这样设置：

```text
自动路由：开启
严格路由：先关闭
协议栈：gvisor
MTU：1500；如果仍不稳定再改 1400
IPv6：没有公网 IPv6 时关闭
```

同时在 v2rayN 的直连或绕过规则里保留：

```text
10.246.77.0/24
10.246.77.1
服务器公网IP
127.0.0.1
localhost
```

这样可以避免访问 Ubuntu 代理入口和远程电脑的流量被 TUN 再次代理。

## 其他代理任务

- ZeroTier 私有入口慢，或客户端没有加入 ZeroTier：[公网代理：不经过 ZeroTier](proxy-public.md)。
- Pixel/Android 移动网络整机走 Ubuntu 且不暴露公网代理：[私有 Exit Node](exit-node.md)。
- 要部署多个地区并在客户端切换：[多台代理服务器](proxy-multi-server.md)。
- 要让域名、IP 或进程直连：[代理排除规则](proxy-rules.md)。
- 要让多个 Ubuntu 在一个本地入口后自动切换：[多台代理服务器](proxy-multi-server.md)。
- 要限制某个客户端经代理的最高速度：[按客户端限速](rate-limit.md)。

## 后续启用或修改账号密码

可以后续重新配置，不需要重新加入 ZeroTier，也不需要从头安装整套网络。

在 Ubuntu 节点的仓库目录重新运行初始化脚本：

```bash
cd ~/zerotier-gateway
bash scripts/ubuntu/init-config.sh
```

脚本检测到已有配置时，直接回车会沿用旧值；走到“是否启用代理用户名和密码”时按需要选择：

- 想启用或修改账号密码：选择启用，然后输入新的用户名和密码。
- 想关闭账号密码：选择不启用即可。

然后只刷新 Ubuntu 代理服务：

```bash
sudo bash scripts/ubuntu/install-proxy.sh
sudo bash scripts/ubuntu/health-check.sh
```

客户端也要同步：

- 手动给软件填代理的：在软件代理设置里填新的用户名和密码；如果已经关闭认证，就把软件里的用户名和密码也清空。
- 使用 `artifacts/windows-local-client.json` 的：在 Windows 重新运行初始化脚本输入同一套代理账号，然后重新生成本地规则：

```powershell
.\scripts\windows\init-config.ps1
.\scripts\windows\generate-client-rules.ps1
```

## 测试

```powershell
.\scripts\windows\test-proxy.ps1
```

## 生成 PAC

```powershell
.\scripts\windows\generate-proxy-pac.ps1
```

输出文件：

```text
artifacts/proxy.pac
```

## 生成本地客户端规则

```powershell
.\scripts\windows\generate-client-rules.ps1
```

输出文件：

```text
artifacts/windows-local-client.json
```
