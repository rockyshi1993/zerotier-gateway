# ZeroTier Gateway

> 当前主线：用一个 ZeroTier 私有局域网打通家里电脑、公司电脑和 Ubuntu 节点；远程访问优先走 ZeroTier 直连，代理上网只让需要的软件走 Ubuntu 私有 HTTP/SOCKS5 代理，必要时再启用中转兜底。

## 适合什么场景

- 家里电脑和公司电脑需要互相远程，目标是低延迟、少折腾。
- 某些软件需要通过 Ubuntu 节点代理上网，但不想把整台电脑都改成全局代理。
- 需要排除指定 IP、域名或进程不走代理。
- ZeroTier 直连效果不好时，希望有一个可选的中转方案。

首版不做复杂 VPN 平台，不默认配置出口节点，不做自建控制器、Moon/私有根或多网络编排。

## 快速开始

推荐流程如下：

1. 获取仓库内容，进入项目目录。
2. 复制 `config/example.env` 为项目根目录下的 `.env`，并填写你的 ZeroTier 网络编号、三台机器的 ZeroTier IP、代理账号密码。
3. 把 Ubuntu 节点、家里电脑、公司电脑加入同一个 ZeroTier 私有网络。
4. 两台 Windows 电脑之间使用 ZeroTier IP 做远程访问。
5. 只给需要代理的软件配置 `10.246.77.1:10808`。
6. 需要排除流量时再生成 PAC 或本地客户端规则；直连质量差时再看中转文档。

默认配置行为：

- Ubuntu 脚本默认读取项目根目录 `.env`。
- Windows 脚本默认读取项目根目录 `.env`。
- 只有多配置或非默认路径时，才需要使用 `--env <path>` 或 `-Env <path>`。

获取仓库：

```bash
git clone https://github.com/rockyshi1993/zerotier-gateway.git
cd zerotier-gateway
```

Ubuntu 节点：

```bash
cp config/example.env .env
# 先编辑 .env。
sudo bash scripts/ubuntu/install.sh --dry-run
sudo bash scripts/ubuntu/install.sh
sudo bash scripts/ubuntu/health-check.sh
```

Windows PowerShell：

```powershell
Copy-Item .\config\example.env .\.env
# 先编辑 .env。
.\scripts\windows\setup.ps1 -Role Home
.\scripts\windows\test-network.ps1
.\scripts\windows\test-proxy.ps1
```

代理规则输出：

```powershell
.\scripts\windows\generate-proxy-pac.ps1
.\scripts\windows\generate-client-rules.ps1
```

## 文档入口

- [安装指南](docs/install.md)
- [Ubuntu 节点](docs/ubuntu.md)
- [Windows 客户端](docs/windows.md)
- [远程访问](docs/remote.md)
- [代理上网](docs/proxy.md)
- [代理排除规则](docs/proxy-rules.md)
- [中转兜底](docs/relay.md)
- [故障排查](docs/troubleshooting.md)
- [安全说明](docs/security.md)
- [回滚与卸载](docs/rollback.md)
- [发布验证](docs/release.md)

## 旧脚本说明

`zerotier-gateway-setup.sh` 仅保留为历史兼容入口，不是当前“低延迟远程 + 私有代理 + 可选中转”主流程。新用户请优先使用上面的 `config/`、`scripts/ubuntu/`、`scripts/windows/` 和 `docs/`。

---

<details>
<summary>旧版说明（历史参考，不作为当前主线）</summary>

旧版一键脚本 `zerotier-gateway-setup.sh` 仍保留在仓库中，主要用于历史兼容和回溯。当前新用户请优先阅读上方快速开始和 `docs/` 下的中文文档。

如需查看旧版完整说明，请通过 Git 历史回看本次中文化之前的 `README.md`。
</details>
