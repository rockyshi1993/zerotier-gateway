# 代理排除规则

当部分流量不应该走 Ubuntu 代理时，使用排除规则。

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

## 多进程软件

多进程软件不要只填一个主程序名，推荐按下面顺序收集规则：

1. 软件分类组。
2. 安装目录。
3. 路径正则。
4. 完整进程名清单。

如果软件会启动服务进程、辅助进程或更新进程，请把这些进程一并纳入规则。
