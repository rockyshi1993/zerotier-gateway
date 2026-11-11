---
pageType: home
hero:
  name: ZeroTier Gateway
  text: 给已有 ZeroTier 私有网络增加网关能力
  tagline: 自托管 Ubuntu 代理、IPv4 Exit Node、指定 TCP 转发和内网站点发布。按需部署，不强制让所有设备流量经过网关。
  actions:
    - theme: brand
      text: 部署私有网关
      link: /quick-start.html
    - theme: alt
      text: 先选择场景
      link: /install.html
    - theme: alt
      text: GitHub
      link: https://github.com/rockyshi1993/zerotier-gateway
features:
  - title: 只想远程访问设备
    details: 设备加入同一 ZeroTier 网络即可互访，通常无需 Ubuntu 网关。
    link: /remote.html
  - title: 指定软件使用代理
    details: 在 Ubuntu 部署私有 HTTP/SOCKS5，客户端软件自主选择是否使用。
    link: /quick-start.html
  - title: Android 整机 IPv4 出口
    details: Ubuntu NAT、Central 默认路由及 Android Allow Default 三方协作。
    link: /exit-node.html
  - title: 公网发布内网站点
    details: 使用已有公网 Ubuntu 映射指定 TCP 服务或提供 HTTPS 反代。
    link: /publish-site.html
  - title: 多节点健康切换
    details: Windows 本地稳定入口，健康检查后对新连接进行故障转移。
    link: /proxy-multi-server.html
  - title: 安全与故障排查
    details: 私网授权、IPv6/DNS 边界、公网暴露及资源级回退。
    link: /security.html
---

## 先分清三种连接方式

| 用户行为 | 流量经过哪里 | 还需要做什么 |
|---|---|---|
| 访问另一台设备的 ZeroTier IP | ZeroTier 私网路径 | 成员授权、目标服务与防火墙；**无需 Ubuntu** |
| 为浏览器或软件设置私有代理 | 软件 → Ubuntu `10.246.77.1:10808` → 互联网 | 安装代理，并在软件中主动启用 |
| 让手机 IPv4 整机经 Ubuntu 出口 | 手机 → ZeroTier → Ubuntu NAT → 互联网 | Ubuntu 启用 Exit Node、Central 路由、手机 Allow Default |

**加入 ZeroTier ≠ 自动启用应用代理 ≠ 自动改变整机默认路由。** 访问私有 HTTP/SOCKS5 代理不需要开启 Allow Default；IPv4 Exit Node 也不是 HTTP/SOCKS5 服务。

## 一张图看懂流量

```text
  Windows / Android / 其他已授权成员
                  │
                  ├── ZeroTier IP ──→ 其他成员的私有服务
                  │
                  ├── HTTP/SOCKS5 ─→ Ubuntu 私有代理 ─→ 公网
                  │
                  └── Allow Default → Ubuntu IPv4 Exit Node ─→ 公网

  互联网用户 ─→ 公网 Ubuntu ─→ ZeroTier 内指定 TCP / HTTPS 目标
                  （只在显式启用发布功能后成立）
```

这张图表达**互不依赖的可选路径**，不是一条必须经过 Ubuntu 的固定网络链路。示例 `10.246.77.0/24` 可以调整，需避开已有路由网段。

## 能力和限制

| 功能 | 当前实现 | 生效前提 / 限制 |
|---|---|---|
| 私有代理 | sing-box mixed HTTP/SOCKS5 | 客户端显式配置；默认私网监听 |
| 私有 Exit Node | IPv4 forwarding + NAT | 仅 IPv4；IPv6/DNS 需分别检查 |
| 指定 TCP 中转 | systemd socket-proxyd | 不等于 ZeroTier 底层 DIRECT/RELAY 中继 |
| 公网服务发布 | IP+端口 / Caddy HTTPS | 必须已有公网可达 Ubuntu |
| Windows 多代理节点池 | 故障自动切换 | 仅新连接切换，不能做负载均衡 |
| 分流 / 限速 | PAC、本地 sing-box、tc | 仅覆盖实际经过相应入口的流量 |

## 使用前的重要提醒

- 对互联网开放代理端口并不是常规提速步骤；当前公网 mixed 代理未提供 TLS，认证不代表传输加密。参见[公网代理风险](proxy-public.md)。
- `--dry-run` 是系统操作预览，但部分脚本仍可能生成工作目录中的配置文件；不要把含密码的产物上传或提交。
- `VERSION` 当前标记 `1.4.0-dev`，站点内容基于 `main` 的开发中源码，不应直接当成 `v1.3.0` tag 的发布承诺。
- 安装命令和验证结果以目标 Ubuntu/Windows/Android 实际环境为准。静态文档通过不等于真实网络已经验收。

从 [部署第一个私有网关](quick-start.md) 开始，或者先读 [环境与路径选择](install.md)。
