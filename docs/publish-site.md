# 从公网访问 ZeroTier 内的服务

本项目支持两种静态发布方式：

| 需求 | 使用方式 |
|---|---|
| 没有域名，通过“服务器公网 IP + 端口”访问 TCP 服务 | 独立 systemd socket 映射 |
| 有域名，希望自动 HTTPS、HTTP 跳转和 WebSocket | 项目专属 Caddy |

这不是 ngrok 式随机域名或全球隧道平台。公网入口必须在一台有公网可达地址的 Ubuntu 上创建，目标必须是项目 ZeroTier 网段内的固定 IP。不要默认发布 RDP、SSH、数据库或管理后台。

## A. 公网 IP + 端口

先确认目标服务在 Ubuntu 上可达：

```bash
nc -vz 10.246.77.30 3000
```

预览并按提示输入映射名、公开端口、目标 IP 和目标端口：

```bash
sudo bash scripts/ubuntu/manage-publish.sh add-ip
```

确认摘要后应用：

```bash
sudo bash scripts/ubuntu/manage-publish.sh add-ip --apply
```

每条映射使用独立的 `zerotier-gateway-publish-<名称>.socket/.service`，最多 64 条，首期只支持 TCP。UFW 已启用时，脚本只添加带项目标记的对应端口规则；UFW 未启用时不会写入休眠规则。云安全组、路由器端口转发和运营商 NAT 仍需在各自平台完成。

只允许一个公网来源时可显式加 CIDR：

```bash
sudo bash scripts/ubuntu/manage-publish.sh add-ip --source-cidr 198.51.100.25/32
sudo bash scripts/ubuntu/manage-publish.sh add-ip --source-cidr 198.51.100.25/32 --apply
```

### 验证四层

```bash
sudo bash scripts/ubuntu/manage-publish.sh status --name mysite
sudo bash scripts/ubuntu/manage-publish.sh test --name mysite
```

脚本依次检查目标 TCP、本机 socket 和本机转发。最后必须换一台不在该 ZeroTier 网络里的设备，从外部网络访问：

```text
服务器公网IP:公开端口
```

本机三层通过但外部失败时，问题通常在云安全组、路由器 NAT、运营商入站限制或公网 IP 归属，不要重装目标站点。

更新或删除单条映射：

```bash
sudo bash scripts/ubuntu/manage-publish.sh update-ip --name mysite --target-port 8080
sudo bash scripts/ubuntu/manage-publish.sh update-ip --name mysite --target-port 8080 --apply
sudo bash scripts/ubuntu/manage-publish.sh remove --name mysite
sudo bash scripts/ubuntu/manage-publish.sh remove --name mysite --apply
```

删除后从外部重测，项目不应再监听该端口；其他映射和 relay 不受影响。

## B. 域名 + 自动 HTTPS

开始前完成：

1. 为域名创建 A 记录，指向 Ubuntu 的公网 IP。
2. 在云安全组、路由器和主机入口允许 TCP `80`、`443`。
3. 确认目标是 HTTP 服务，且 Ubuntu 能访问目标 ZeroTier IP 和端口。
4. 确认 `80`、`443`、本机 `2019` 没有被第三方服务占用。

推荐先使用 Let's Encrypt staging 验证流程：

```bash
sudo bash scripts/ubuntu/manage-publish.sh add-domain --staging
sudo bash scripts/ubuntu/manage-publish.sh add-domain --staging --apply
```

脚本会询问名称、域名、目标 IP 和端口，下载项目固定版本的官方 Caddy 静态二进制并校验摘要，然后生成、验证并启动项目专属 unit。它不会修改发行版默认 `caddy.service`，也不会接管已有 Caddy、nginx 或 Apache。

检查状态：

```bash
sudo bash scripts/ubuntu/manage-publish.sh status-domain --name mysite
sudo bash scripts/ubuntu/manage-publish.sh test-domain --name mysite
```

staging 证书不受浏览器信任是正常现象。目标、DNS、HTTP、HTTPS 和页面路径均通过后，切换到生产证书：

```bash
sudo bash scripts/ubuntu/manage-publish.sh update-domain --name mysite --production
sudo bash scripts/ubuntu/manage-publish.sh update-domain --name mysite --production --apply
```

再用浏览器打开 `https://你的域名`，确认证书有效、HTTP 自动跳转、真实页面可用；使用 WebSocket 的站点还要测试实际 WebSocket 功能。

### 可选访问限制

限制来源 CIDR：

```bash
sudo bash scripts/ubuntu/manage-publish.sh add-domain --source-cidr 198.51.100.0/24
sudo bash scripts/ubuntu/manage-publish.sh add-domain --source-cidr 198.51.100.0/24 --apply
```

启用基础认证时，脚本会在 Apply 阶段安全询问密码并生成 Caddy hash：

```bash
sudo bash scripts/ubuntu/manage-publish.sh add-domain --basic-auth-user visitor
sudo bash scripts/ubuntu/manage-publish.sh add-domain --basic-auth-user visitor --apply
```

多个域名可以共用项目 Caddy；更新或删除一条不会改其他域名：

```bash
sudo bash scripts/ubuntu/manage-publish.sh list-domains
sudo bash scripts/ubuntu/manage-publish.sh remove-domain --name mysite
sudo bash scripts/ubuntu/manage-publish.sh remove-domain --name mysite --apply
```

删除最后一个域名会停止项目 Caddy，并移除可验证归属的项目 UFW `80/443` 规则，但保留已校验二进制和证书数据，便于恢复。第三方反向代理和共享 Caddy 始终不在删除范围；UFW 所有权无法验证时，删除会安全停止并保留原服务与状态。

## 安全判断

- 公开端口意味着互联网上的请求能到达该服务；先确认应用自身认证、更新和日志。
- 来源限制只能识别网络出口，同一 NAT 后的设备无法按设备区分。
- 域名发布只反代明确目标，不会自动公开整个 ZeroTier 网段。
- 项目无法自动修改未知云厂商安全组，也不会把外部失败误报成内部目标失败。
