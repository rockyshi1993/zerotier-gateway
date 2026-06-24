# 代理上网

Ubuntu 节点通过 sing-box 提供私有 HTTP/SOCKS5 混合代理。

默认代理入口：

```text
10.246.77.1:10808
```

默认不需要用户名和密码。只有 `.env` 同时填写了 `PROXY_USERNAME` 和 `PROXY_PASSWORD` 时，代理才启用认证。

只在需要代理上网的软件里配置这个入口。没有配置代理的软件会继续使用原本网络。

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
