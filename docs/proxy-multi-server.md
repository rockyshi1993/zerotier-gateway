# 多台代理服务器

多台 Ubuntu 可以各自提供一个独立代理入口。最直观的使用方式是：每台服务器单独安装和验证，在 v2rayN 等客户端中添加多个 SOCKS 节点，按需要手动切换。

## 1. 为每台 Ubuntu 分配地址

示例：

| 节点 | ZeroTier IP | 私有代理入口 |
|---|---|---|
| 新加坡 | `10.246.77.1` | `10.246.77.1:10808` |
| 日本 | `10.246.77.2` | `10.246.77.2:10808` |
| 美国 | `10.246.77.3` | `10.246.77.3:10808` |

在 ZeroTier Central 中授权每台服务器并固定不同的 Managed IP，不能重复。

## 2. 每台服务器独立安装

在每台 Ubuntu 的仓库根目录分别执行：

```bash
bash scripts/ubuntu/init-config.sh
sudo bash scripts/ubuntu/install.sh --dry-run
sudo bash scripts/ubuntu/install.sh
sudo bash scripts/ubuntu/health-check.sh
```

初始化时只把当前服务器的 Ubuntu ZeroTier IP 填成它自己的地址。每台服务器都必须单独通过[Ubuntu 安装成功验证](verification.md#1-ubuntu-安装成功)。

如果客户端不加入 ZeroTier，则在每台服务器按[公网代理](proxy-public.md)分别开启公网入口。

## 3. 在客户端添加多个节点

以 v2rayN 为例，为每台服务器分别添加一个 SOCKS 节点：

```text
新加坡：10.246.77.1:10808
日本：  10.246.77.2:10808
美国：  10.246.77.3:10808
```

节点的用户名和密码以各台服务器初始化时的选择为准。给节点使用清楚的地区或用途名称，切换时把目标节点设为活动节点。

## 4. 逐台验证和切换

在 Windows 分别测试：

```powershell
curl.exe --ssl-no-revoke -x socks5h://10.246.77.1:10808 https://api.ipify.org
curl.exe --ssl-no-revoke -x socks5h://10.246.77.2:10808 https://api.ipify.org
curl.exe --ssl-no-revoke -x socks5h://10.246.77.3:10808 https://api.ipify.org
```

每条命令都应返回对应服务器的出口 IP。某一台失败时只检查该节点，不要重装其他服务器。

## 当前自动化边界

- `generate-proxy-pac.ps1` 和 `generate-client-rules.ps1` 当前一次只生成一个上游代理。
- v2rayN 多节点可以手动切换，但项目当前不承诺自动测速、负载均衡或故障转移。
- 需要切换生成的 PAC/本地客户端配置时，在 Windows 重新运行 `init-config.ps1` 选择目标代理入口，再重新生成产物。

这一边界避免文档把“多节点可添加”误写成“已经支持自动多上游”。
