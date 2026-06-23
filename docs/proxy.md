# 代理上网

Ubuntu 节点通过 sing-box 提供私有 HTTP/SOCKS5 混合代理。

默认代理入口：

```text
10.246.77.1:10808
```

只在需要代理上网的软件里配置这个入口。没有配置代理的软件会继续使用原本网络。

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
