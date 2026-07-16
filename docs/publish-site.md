# 从公网访问 ZeroTier 内的服务

这页解决一个具体问题：把 ZeroTier 内网站电脑上的服务，通过一台公网 Ubuntu 提供给外网访问。开始前无需编辑 `.env` 或脚本文件，全部配置都由命令完成。

## 先判断是否适用

你需要同时满足：

1. 有一台公网可达的 Ubuntu，并已按本项目接入 ZeroTier。
2. 网站电脑也在同一个 ZeroTier 网络中，并使用固定的 ZeroTier IP。
3. 网站服务已经启动，且公网 Ubuntu 能访问它的 ZeroTier IP 和端口。

> 没有公网可达的 Ubuntu 时，这种发布方式不适用。它不会像 ngrok 一样自动提供公网入口或随机域名。

全部管理命令都在公网 Ubuntu 的仓库目录执行，不是在网站电脑上执行。

## 看懂连接方向

```text
外网浏览器
    ↓
公网 Ubuntu（在这里执行发布命令）
    ↓ ZeroTier
网站电脑（运行你的网站）
```

本文用同一套示例贯穿全部步骤：

| 要替换的值 | 示例 | 从哪里获得 |
|---|---|---|
| 公网 Ubuntu 的公网 IP | `203.0.113.10` | 云主机控制台或公网出口信息 |
| 网站电脑的 ZeroTier IP | `10.246.77.30` | 网站电脑的 ZeroTier 客户端或网络控制台 |
| 网站当前监听端口 | `3000` | 网站启动日志或应用设置 |
| 希望外网使用的端口 | `18080` | 自选一个未占用并允许入站的 TCP 端口 |
| 映射名称 | `mysite` | 自定义；每个站点使用不同的名称 |
| 域名 | `site.example.com` | 你拥有并能设置 DNS 的域名 |

`203.0.113.10` 和 `site.example.com` 只是文档示例，执行时必须换成你自己的值。

## A. 公网 IP + 端口

适合没有域名，或要发布普通 TCP 服务的情况。成功后，HTTP 网站的完整地址是 `http://203.0.113.10:18080`。

### 1. 确认网站电脑可达

在公网 Ubuntu 执行：

```bash
nc -vz 10.246.77.30 3000
```

失败时先修复网站监听、网站电脑防火墙或 ZeroTier 互访，不要继续创建公网映射。

### 2. 预览将要创建的映射

把示例值换成自己的值：

```bash
sudo bash scripts/ubuntu/manage-publish.sh add-ip \
  --name mysite \
  --listen-port 18080 \
  --target-ip 10.246.77.30 \
  --target-port 3000
```

preview 只显示计划，不修改系统。摘要中的名称、端口和目标都正确后，再执行下一步。

### 3. 应用同一组参数

```bash
sudo bash scripts/ubuntu/manage-publish.sh add-ip \
  --name mysite \
  --listen-port 18080 \
  --target-ip 10.246.77.30 \
  --target-port 3000 \
  --apply
```

### 4. 验证并从外网打开

```bash
sudo bash scripts/ubuntu/manage-publish.sh status --name mysite
sudo bash scripts/ubuntu/manage-publish.sh test --name mysite
```

这两条命令会确认项目 unit、目标 TCP 和本机转发；它们不能代替外网入口测试。

然后换一台不在该 ZeroTier 网络里的设备：

- HTTP 网站：浏览器打开 `http://203.0.113.10:18080`。
- 其他 TCP 服务：使用对应客户端连接 `203.0.113.10:18080`，不要用浏览器代替协议客户端。

`test` 通过但外网仍打不开时，检查云安全组、路由器端口转发、运营商入站限制和公网 IP 是否正确；不要重装网站或 ZeroTier。

## B. 域名 + 自动 HTTPS

适合已有域名的 HTTP 网站。成功后的完整地址是 `https://site.example.com`。

### 1. 准备 DNS 和入口

1. 为 `site.example.com` 创建 A 记录，指向公网 Ubuntu 的公网 IP。
2. 在云安全组、路由器和主机入口允许 TCP `80`、`443`。
3. 用 `nc -vz 10.246.77.30 3000` 确认公网 Ubuntu 能访问目标 HTTP 服务。

### 2. 使用 staging 预览

staging 用测试证书先验证 DNS、端口和反向代理流程，避免反复申请生产证书。

```bash
sudo bash scripts/ubuntu/manage-publish.sh add-domain \
  --name mysite \
  --domain site.example.com \
  --target-ip 10.246.77.30 \
  --target-port 3000 \
  --staging
```

### 3. 应用同一组参数

```bash
sudo bash scripts/ubuntu/manage-publish.sh add-domain \
  --name mysite \
  --domain site.example.com \
  --target-ip 10.246.77.30 \
  --target-port 3000 \
  --staging \
  --apply
```

### 4. 验证 staging

```bash
sudo bash scripts/ubuntu/manage-publish.sh status-domain --name mysite
sudo bash scripts/ubuntu/manage-publish.sh test-domain --name mysite
```

`test-domain` 检查目标 TCP、HTTP、HTTPS 和证书；DNS 解析失败会在 HTTP/HTTPS 步骤暴露。

staging 证书不受浏览器信任是正常现象。命令检查全部通过后，再切换生产证书：

```bash
sudo bash scripts/ubuntu/manage-publish.sh update-domain --name mysite --production
sudo bash scripts/ubuntu/manage-publish.sh update-domain --name mysite --production --apply
```

最后从外网浏览器打开 `https://site.example.com`，确认证书有效、HTTP 自动跳转且真实页面可用；使用 WebSocket 的站点还要测试实际 WebSocket 功能。

失败时按现象处理：

- `nc` 失败：先修网站监听、目标防火墙或 ZeroTier 互访。
- DNS 不正确：修正 A 记录并等待解析生效。
- 本机检查通过但外网失败：检查 80/443、安全组、路由器 NAT 和公网 IP。
- 80/443 或项目管理端口被占用：脚本会停止，不会接管已有 Caddy、nginx 或 Apache；先处理端口归属。

## 添加多个站点

每个站点使用不同的 `--name`，然后再次运行对应的 `add-ip` 或 `add-domain` 命令：

| 模式 | 还必须不同 | 示例 |
|---|---|---|
| IP+端口 | 公网端口 | 第二个站点可用名称 `blog`、端口 `18081` |
| 域名 | 完整域名 | 第二个站点可用名称 `blog`、域名 `blog.example.com` |

IP+端口模式还必须使用不同的公网端口；域名模式使用不同的域名，多个域名可以共用项目 Caddy。

## 更新、删除和高级配置

更新或删除 IP+端口映射：

```bash
sudo bash scripts/ubuntu/manage-publish.sh update-ip --name mysite --target-port 8080
sudo bash scripts/ubuntu/manage-publish.sh update-ip --name mysite --target-port 8080 --apply
sudo bash scripts/ubuntu/manage-publish.sh remove --name mysite
sudo bash scripts/ubuntu/manage-publish.sh remove --name mysite --apply
```

查看或删除域名映射：

```bash
sudo bash scripts/ubuntu/manage-publish.sh list-domains
sudo bash scripts/ubuntu/manage-publish.sh remove-domain --name mysite
sudo bash scripts/ubuntu/manage-publish.sh remove-domain --name mysite --apply
```

删除后从外网重测；被删除的端口或域名应不可达，其他映射和 relay 不受影响。

需要限制访问来源时，把下面选项同时加入对应的 preview 和 `--apply` 命令：

- 单个公网来源：`--source-cidr 198.51.100.25/32`
- 一个公网网段：`--source-cidr 198.51.100.0/24`

域名站点还可以加入 `--basic-auth-user visitor`。执行带 `--apply` 的命令时，脚本会询问密码并生成 Caddy hash，不需要把密码写进文档或配置文件。

## 实现与安全边界

- IP+端口模式为每条映射创建独立的 `zerotier-gateway-publish-<名称>.socket/.service`，最多 64 条，首期只支持 TCP。
- 域名模式使用项目专属 Caddy，支持自动 HTTPS、HTTP 跳转和 WebSocket。脚本下载固定版本的官方二进制并校验摘要。
- 脚本不会修改发行版默认 `caddy.service`，也不会接管已有 Caddy、nginx、Apache 或共享反向代理。
- UFW 已启用时，脚本只管理带项目标记的规则；UFW 未启用时不会预写休眠规则。云安全组、路由器 NAT 和运营商入口仍需在各自平台配置。
- 删除最后一个域名会停止项目 Caddy，并只移除可验证归属的项目 UFW `80/443` 规则；已校验二进制和证书数据会保留以便恢复，所有权无法验证时会安全停止删除。
- 这不是 ngrok 式随机域名或全球隧道平台，也不提供 UDP 映射、负载均衡或代理节点自动故障转移。

## 安全判断

- 不要直接公开 RDP、SSH、数据库或管理后台；如确需发布，先启用应用认证并限制来源。
- 公开端口意味着互联网上的请求能到达该服务；先确认应用自身认证、更新和日志。
- 来源限制只能识别网络出口，同一 NAT 后的设备无法按设备区分。
- 域名发布只反代明确目标，不会自动公开整个 ZeroTier 网段。
- 项目无法自动修改未知云厂商安全组，也不会把外部失败误报成内部目标失败。
