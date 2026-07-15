# 代理排除规则

当部分流量不应该走 Ubuntu 代理时，使用排除规则。

排除规则的生效点在客户端，不在 Ubuntu 代理服务本身。Ubuntu 代理只能处理“已经发到代理端口的请求”，不能替 Windows 决定哪些域名、IP 或进程应直连。

| 规则类型 | 生成文件 | 生效条件 |
|---|---|---|
| 域名、域名后缀、IP 网段 | `artifacts/proxy.pac` | 浏览器、系统代理或软件配置了这个 PAC |
| 域名、IP、进程 | `artifacts/windows-local-client.json` | 本地规则客户端导入这个文件并接管流量 |
| 手动给某个软件填代理 | 无 | 只影响这个软件；本仓库排除规则不会自动套进去 |

## 域名和 IP 规则

运行专项配置命令。以下示例让公司域名、ZeroTier 和常见局域网地址直连：

```powershell
.\scripts\windows\configure-proxy-rules.ps1 `
  -DirectDomains 'localhost,*.local,*.company.com' `
  -DirectDomainSuffixes '.local' `
  -DirectIpCidrs '10.246.77.0/24,10.0.0.0/8,172.16.0.0/12,192.168.0.0/16' `
  -Generate
```

不带参数运行会逐项询问，并显示当前值；直接回车可保留：

```powershell
.\scripts\windows\configure-proxy-rules.ps1
```

`-Generate` 会同时生成 `artifacts/proxy.pac` 和 `artifacts/windows-local-client.json`。把 PAC 配到浏览器、系统代理或支持 PAC 的软件后才会生效；PAC 不能识别 Windows 进程。

## 进程规则

进程规则需要在 Windows 本机使用本地规则客户端。Ubuntu 代理只能看到网络请求，无法知道请求来自 Windows 上的哪个进程。

使用内置软件组时直接运行：

```powershell
.\scripts\windows\configure-proxy-rules.ps1 -DirectProcessGroups 'remote-tools,chat-tools,game-tools' -Generate
```

也可以指定实际进程名或路径：

```powershell
.\scripts\windows\configure-proxy-rules.ps1 `
  -DirectProcessNames 'mstsc.exe,RemoteTool.exe' `
  -DirectProcessPaths 'C:\Program Files\RemoteTool\RemoteTool.exe' `
  -Generate
```

## 运行本地规则客户端

生成文件不会自动接管流量。项目生成的是 sing-box 配置，可在管理员 PowerShell 中安装并检查：

```powershell
winget install sing-box
sing-box check -c .\artifacts\windows-local-client.json
sing-box run -c .\artifacts\windows-local-client.json
```

Windows 安装命令可在 [sing-box 官方 Package Manager 文档](https://sing-box.sagernet.org/installation/package-manager/)核对。

保持这个窗口运行，并把要接管的软件或 Windows 系统代理指向：

```text
HTTP/SOCKS5：127.0.0.1:20808
```

这时链路是“软件 → 本地 sing-box → 按域名/IP/进程决定直连或 Ubuntu 代理”。结束时按 `Ctrl+C` 停止 sing-box，并在软件或系统代理中关闭 `127.0.0.1:20808`。

当前生成配置是本地 mixed 代理，不是 TUN。完全不遵守系统/软件代理的程序不会被它接管；这种情况才需要另行配置 TUN 客户端。

## 多进程软件

多进程软件不要只填一个主程序名，推荐按下面顺序收集规则：

1. 软件分类组。
2. 安装目录。
3. 路径正则。
4. 完整进程名清单。

如果软件会启动服务进程、辅助进程或更新进程，请把这些进程一并纳入规则。

配置后可用下面命令观察相关进程的实际名称和路径：

```powershell
Get-Process | Where-Object { $_.ProcessName -match 'Remote|ZeroTier|mstsc' } | Select-Object ProcessName,Path
```
