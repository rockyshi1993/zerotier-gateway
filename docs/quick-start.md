# 快速开始：部署第一个私有 Ubuntu 网关

本教程实现一个明确目标：**让一台已加入 ZeroTier 的客户端，通过 Ubuntu 私有 HTTP/SOCKS5 代理访问互联网**。

不需要准备两台 Windows、不需要开启远程桌面、不需要公网代理，也不需要 Android Allow Default。仅希望成员互访时应直接阅读[仅设备互访](remote.md)。

## 0. 先确认条件

- 有自己管理的 ZeroTier 私有 Network，记下 **16 位 Network ID**。
- 一台可使用 `sudo` 的 Ubuntu，联网可安装 ZeroTier/sing-box；部署前确认源代码可信。
- 至少一台 Windows 或其他客户端可加入同一 ZeroTier 网络并获得授权。
- 选择不与现有 LAN、VPN 或云网络冲突的网段；以下以 `10.246.77.0/24`、Ubuntu `10.246.77.1` 为示例，而非固定要求。
- 如系统曾部署本项目，请先阅读[安全升级](upgrade.md)，不要直接按首次安装覆盖配置。

## 1. 下载并生成配置

**执行设备：Ubuntu。** 在普通用户终端进入仓库根目录：

```bash
git clone https://github.com/rockyshi1993/zerotier-gateway.git
cd zerotier-gateway
bash scripts/ubuntu/init-config.sh
```

初始化器会询问网络编号、网段、Ubuntu/Windows 示例地址、代理端口和可选公网设置。即使没有两台 Windows，Home/Work 的提示也只是保留配置字段，**不代表这两台 Windows 是主路径的前置**。

新手不要启用代理公网入口；如无需认证，私有网络内的成员仍应是你明确授权和信任的设备。初始化后的 `.env` 可能含密码，请避免提交、复制到共享位置。

## 2. 安装并授权 ZeroTier

**执行设备：Ubuntu。** 先预览，再安装 ZeroTier 并加入 Network：

```bash
sudo bash scripts/ubuntu/install-zerotier.sh --dry-run
sudo bash scripts/ubuntu/install-zerotier.sh
sudo zerotier-cli info
sudo zerotier-cli listnetworks
```

安装器在需要时会调用 ZeroTier 官方安装脚本并加入你提供的 Network ID。随后进入 [ZeroTier Central](https://my.zerotier.com)：

1. 打开对应 Network，授权 Ubuntu 成员。
2. 为它分配一个明确且未冲突的 Managed IP，例如 `10.246.77.1`。
3. 回到 Ubuntu 检查网络状态以及网卡上实际存在的地址：

```bash
sudo zerotier-cli listnetworks
ip -4 -br addr
```

**继续条件：** `listnetworks` 中该网络为 `OK`，并且 Ubuntu ZeroTier 网卡确实拥有预期 IPv4。未授权、地址不是预期值或网段冲突时，先修正 Central 与本机状态，再继续；不要尝试强行启动绑定不存在 IP 的代理服务。

## 3. 安装私有代理

**执行设备：同一台 Ubuntu，仓库根目录。**

```bash
sudo bash scripts/ubuntu/install-proxy.sh --dry-run
sudo bash scripts/ubuntu/install-proxy.sh
sudo bash scripts/ubuntu/health-check.sh
sudo systemctl is-active sing-box-zt-proxy
sudo ss -lntp | grep ':10808'
```

如果初始化时选了其他端口，最后一条命令应改成实际端口。代理默认监听 Ubuntu 的 ZeroTier IP，不需要开放公网 `10808/tcp`。

**预览边界：** `install-proxy.sh --dry-run` 不应改动系统服务，但其实现仍会在仓库 `artifacts/` 下生成配置产物；这些产物可能包含代理密码，**不是严格零文件写入**。

**通过标准：** 服务是 `active`，监听地址是实际 Ubuntu ZeroTier IP 和配置的代理端口。`health-check.sh` 主要显示信息，不能代替下面的真实客户端请求测试。

## 4. 让客户端接入 ZeroTier

在客户端安装 ZeroTier，加入**同一个** Network，在 Central 授权并分配不冲突的 Managed IP。

如果用 Windows，先检查它能访问 Ubuntu 私有地址：

```powershell
Test-NetConnection 10.246.77.1 -Port 10808
```

`TcpTestSucceeded` 应为 `True`。如果客户端只是使用代理，无需执行 `setup.ps1 -Role Home|Work`，也无需开启 RDP 或全局路由。

## 5. 让指定软件使用代理并验证出口

在浏览器、v2rayN 或支持 HTTP/SOCKS5 的软件中，手动设置：

```text
代理协议：HTTP 或 SOCKS5
代理服务器：10.246.77.1（替换为实际 Ubuntu ZeroTier IP）
端口：10808（替换为实际端口）
认证：仅在初始化时启用了账号密码才填写
```

Windows 上可用独立的命令验证未启用认证的 SOCKS5 出口：

```powershell
curl.exe --ssl-no-revoke --proxy socks5h://10.246.77.1:10808 https://api.ipify.org
```

如果启用了认证，请使用代理软件的安全凭据输入方式，避免把明文口令长期保留在终端历史中。命令返回的公网 IP 应是 Ubuntu 的实际出口 IP；再在你需要的业务软件中实际访问一个网页以完成验收。

**没有主动配置代理的其他软件仍用原来的网络。** 访问私有代理不需要启用 ZeroTier 的 Allow Default。

## 6. 出错与安全退出

| 失败层 | 先看什么 |
|---|---|
| ZeroTier 未 ONLINE / Network 非 OK | 服务、网络 ID、Central 成员授权 |
| Ubuntu 缺少预期 ZT IP | Central Managed IP、地址冲突、本机路由 |
| 代理没有监听 | `systemctl status sing-box-zt-proxy`、绑定地址、`ss` |
| Windows 到 Ubuntu TCP 不通 | 网络成员、服务监听、UFW、安全组（不要直接公开代理） |
| TCP 通但 SOCKS/HTTP 请求失败 | 代理协议/认证、服务器真实公网访问、错误日志 |
| 业务软件仍使用本机出口 | 软件是否真的启用代理、目标是否绕过系统代理 |

详细步骤见 [安装验证](verification.md)、[故障排查](troubleshooting.md) 和 [回滚与卸载](rollback.md)。

完成第一个私有网关后，如需手机移动数据**整机 IPv4** 走 Ubuntu，再单独按 [IPv4 Exit Node](exit-node.md) 开启。不要将全局路由与本页的软件代理混为一谈。
