# 代理排除规则

当部分流量不应该走 Ubuntu 代理时，使用排除规则。

排除规则的生效点在客户端，不在 Ubuntu 代理服务本身。Ubuntu 代理只能处理“已经发到代理端口的请求”，不会知道 Windows 上哪个软件发起了请求，也不会自动读取 Windows 里的 `.env`。

| 规则类型 | 生成文件 | 生效条件 |
|---|---|---|
| 域名、域名后缀、IP 网段 | `artifacts/proxy.pac` | 浏览器、系统代理或软件配置了这个 PAC |
| 域名、IP、进程 | `artifacts/windows-local-client.json` | 本地规则客户端导入这个文件并接管流量 |
| 手动给某个软件填代理 | 无 | 只影响这个软件；本仓库排除规则不会自动套进去 |

## 域名和 IP 规则

编辑 `.env`：

```text
DIRECT_DOMAINS=localhost,*.local,*.company.com
DIRECT_DOMAIN_SUFFIXES=.local
DIRECT_IP_CIDRS=10.246.77.0/24,10.0.0.0/8,172.16.0.0/12,192.168.0.0/16
```

生成 PAC：

```powershell
.\scripts\windows\generate-proxy-pac.ps1
```

把 `artifacts/proxy.pac` 配到浏览器、系统代理或支持 PAC 的软件里后才会生效。PAC 不能识别 Windows 进程。

## 进程规则

进程规则需要在 Windows 本机使用本地规则客户端。Ubuntu 代理只能看到网络请求，无法知道请求来自 Windows 上的哪个进程。

编辑 `.env`：

```text
PROXY_MODE=local-rule-client
DIRECT_PROCESS_GROUPS=remote-tools,chat-tools,game-tools
DIRECT_PROCESS_NAMES=
DIRECT_PROCESS_PATHS=
DIRECT_PROCESS_PATH_REGEX=
```

生成本地客户端规则：

```powershell
.\scripts\windows\generate-client-rules.ps1
```

把 `artifacts/windows-local-client.json` 导入你使用的本地规则客户端，并确认它正在接管流量后，进程规则才会生效。只生成文件不会改变系统代理，也不会自动接管任何软件。

## 多进程软件

多进程软件不要只填一个主程序名，推荐按下面顺序收集规则：

1. 软件分类组。
2. 安装目录。
3. 路径正则。
4. 完整进程名清单。

如果软件会启动服务进程、辅助进程或更新进程，请把这些进程一并纳入规则。
