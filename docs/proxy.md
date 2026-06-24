# 代理上网

Ubuntu 节点通过 sing-box 提供私有 HTTP/SOCKS5 混合代理。

默认私有代理入口：

```text
10.246.77.1:10808
```

默认不需要用户名和密码。只有 `.env` 同时填写了 `PROXY_USERNAME` 和 `PROXY_PASSWORD` 时，代理才启用认证。

加入 ZeroTier 只代表 Windows 能访问这个入口，不代表会自动代理上网。只有在软件、系统代理、PAC 或本地规则客户端里主动配置代理后，对应流量才会走代理。没有配置代理的软件会继续使用原本网络。

## 代理什么时候生效

| 使用方式 | 生效范围 | 排除规则支持 |
|---|---|---|
| 在某个软件里手动填 `10.246.77.1:10808` | 只影响这个软件 | 由软件自己决定，本仓库 `.env` 排除规则不会自动生效 |
| 使用 `artifacts/proxy.pac` | 只影响配置了这个 PAC 的浏览器、系统代理或软件 | 支持域名、域名后缀、IP 网段；不支持进程 |
| 使用 `artifacts/windows-local-client.json` | 只影响导入并接管流量的本地规则客户端 | 支持域名、IP、进程；仅生成文件不会生效 |

Windows 仓库里的 `.env` 不会自动修改系统代理。它只给 `test-proxy.ps1`、`generate-proxy-pac.ps1` 和 `generate-client-rules.ps1` 读取。

## 代理测速慢时的优化

默认入口 `10.246.77.1:10808` 走 ZeroTier 私有网络。如果 Windows 到 Ubuntu 的 ZeroTier 链路绕路，代理测速会慢。你用 Outline、v2rayN 或其他工具直连服务器公网 IP 很快，但本仓库代理慢，通常就是这个原因。

可以开启可选公网入口，让没有加入 ZeroTier 的设备，或实测公网路径更快的设备，直接连接 Ubuntu 服务器公网 IP：

```text
PROXY_BIND_IP=0.0.0.0
PROXY_PUBLIC_ACCESS=true
PROXY_CONNECT_HOST=Ubuntu服务器公网IP
PROXY_ALLOWED_CLIENT_CIDRS=
PROXY_PORT=10808
```

字段区别：

| 字段 | 含义 |
|---|---|
| `PROXY_BIND_IP` | Ubuntu 上代理监听在哪个地址；私有入口填 `10.246.77.1`，公网入口由初始化脚本自动设为 `0.0.0.0` |
| `PROXY_CONNECT_HOST` | Windows 生成测试、PAC、本地规则时连接哪个地址；已加入 ZeroTier 的电脑可继续用 `10.246.77.1`，没加入 ZeroTier 或要走公网路径时填服务器公网 IP |
| `PROXY_ALLOWED_CLIENT_CIDRS` | 允许访问公网代理入口的来源公网 IP/CIDR；留空表示全部来源 |

账号密码仍然可选：`PROXY_USERNAME` 和 `PROXY_PASSWORD` 都留空就不启用认证；两项都填写才启用认证。`PROXY_ALLOWED_CLIENT_CIDRS` 留空时会允许全部来源访问公网代理端口，适合临时测试；长期使用建议填写来源 IP 白名单，或至少启用代理账号密码。

开启公网入口后，已经加入这个 ZeroTier 网络的 Windows 不需要强制改成公网 IP。它可以继续使用 `10.246.77.1:10808`，这条私有入口不暴露公网，更安全。

让公网入口生效：

```bash
bash scripts/ubuntu/init-config.sh
sudo bash scripts/ubuntu/install-proxy.sh --dry-run
sudo bash scripts/ubuntu/install-proxy.sh
sudo bash scripts/ubuntu/health-check.sh
```

Windows 侧测试：

如果 Windows 仓库里也有 `.env`，先决定 `PROXY_CONNECT_HOST` 要连接哪个入口，再同步 `PROXY_PUBLIC_ACCESS`、`PROXY_CONNECT_HOST`、`PROXY_ALLOWED_CLIENT_CIDRS`、`PROXY_PORT`、`PROXY_USERNAME`、`PROXY_PASSWORD`，或重新运行 Windows 初始化脚本输入同一套值。

| Windows 状态 | `PROXY_CONNECT_HOST` 推荐值 | 手动软件代理地址 |
|---|---|---|
| 已加入这个 ZeroTier 网络 | `10.246.77.1` | `10.246.77.1:10808` |
| 没加入 ZeroTier | `Ubuntu服务器公网IP` | `Ubuntu服务器公网IP:10808` |
| 已加入 ZeroTier，但实测公网路径更快 | `Ubuntu服务器公网IP` | `Ubuntu服务器公网IP:10808` |

```powershell
.\scripts\windows\test-proxy.ps1
```

如果开启公网入口后连不上，先检查：

1. 走私有入口时，Windows 能 ping 通 `10.246.77.1`，并且软件代理地址是 `10.246.77.1:10808`。
2. 走公网入口时，`PROXY_CONNECT_HOST` 是服务器公网 IP，云厂商防火墙允许你的来源公网 IP 访问 `10808/tcp`。
3. `PROXY_ALLOWED_CLIENT_CIDRS` 留空时，Ubuntu `ufw` 会放行全部来源；填写后只放行指定来源。
4. 如果启用了账号密码，客户端填写的用户名和密码与 Ubuntu `.env` 一致。

## 后续启用或修改账号密码

可以后续重新配置，不需要重新加入 ZeroTier，也不需要从头安装整套网络。代理服务跑在 Ubuntu 节点上，所以最终以 Ubuntu 节点项目根目录里的 `.env` 为准。

在 Ubuntu 节点的仓库目录重新运行初始化脚本：

```bash
cd ~/zerotier-gateway
bash scripts/ubuntu/init-config.sh
```

脚本检测到已有 `.env` 时，直接回车会沿用旧值；走到“是否启用代理用户名和密码”时按需要选择：

- 想启用或修改账号密码：选择启用，然后输入新的用户名和密码。
- 想关闭账号密码：选择不启用，脚本会把 `PROXY_USERNAME` 和 `PROXY_PASSWORD` 清空。

然后只刷新 Ubuntu 代理服务：

```bash
sudo bash scripts/ubuntu/install-proxy.sh
sudo bash scripts/ubuntu/health-check.sh
```

客户端也要同步：

- 手动给软件填代理的：在软件代理设置里填新的用户名和密码；如果已经关闭认证，就把软件里的用户名和密码也清空。
- 使用 `artifacts/windows-local-client.json` 的：把 Windows 仓库里的 `.env` 也改成同一套账号密码，然后重新生成本地规则：

```powershell
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
