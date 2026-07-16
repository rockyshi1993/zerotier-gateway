---
pageType: home
hero:
  name: ZeroTier Gateway
  text: 用脚本搭建私有远程访问与代理
  tagline: Ubuntu 提供私有代理和可选中转，Windows 通过 ZeroTier 互相远程；普通流程不需要编辑脚本或配置文件。
  actions:
    - theme: brand
      text: 5 分钟快速开始
      link: /quick-start.html
    - theme: alt
      text: 只看远程访问
      link: /remote.html
    - theme: alt
      text: 配置代理上网
      link: /proxy.html
features:
  - title: 第一次配置
    details: 依次完成 Ubuntu、两台 Windows 和 ZeroTier Central 授权。
    link: /quick-start.html
  - title: 安装与互访验证
    details: 检查服务、双向访问、远程端口和真实代理出口。
    link: /verification.html
  - title: 远程访问
    details: 开启被访问电脑，并使用对方 ZeroTier IP 连接。
    link: /remote.html
  - title: 代理与自动切换
    details: 配置单台代理，或把多台服务器收敛成一个本地入口。
    link: /proxy-multi-server.html
  - title: 按客户端限速
    details: 只限制指定客户端经过项目代理端口的上下行速度。
    link: /rate-limit.html
  - title: 公网站点发布
    details: 使用公网 IP+端口或显式域名 HTTPS 访问 ZT 内服务。
    link: /publish-site.html
---

## 先选择你要完成的任务

| 你的目标 | 从这里开始 |
|---|---|
| 第一次搭建 Ubuntu、家里电脑和公司电脑 | [5 分钟快速开始](quick-start.md) |
| 检查是否安装成功、互相访问是否正常 | [安装与互访验证](verification.md) |
| 只想让家里和公司互相远程 | [远程访问](remote.md) |
| 只想给浏览器或指定软件配置代理 | [代理上网](proxy.md) |
| 不加入 ZeroTier，直接使用公网代理 | [公网代理](proxy-public.md) |
| 添加多台代理服务器并切换 | [多台代理服务器](proxy-multi-server.md) |
| 需要排除域名、IP 或进程 | [代理排除规则](proxy-rules.md) |
| 正在使用旧版本，需要安全升级 | [安全升级](upgrade.md) |
| 限制某个代理客户端的最高速度 | [按客户端限速](rate-limit.md) |
| 用公网 IP+端口或域名访问本地站点 | [公网站点发布](publish-site.md) |
| ZeroTier 直连不稳定 | [中转兜底](relay.md) |
| 安装失败、连不通或权限报错 | [故障排查](troubleshooting.md) |

## 你会得到什么

| 设备 | 作用 | 推荐 ZeroTier IP |
|---|---|---|
| Ubuntu 节点 | 私有 HTTP/SOCKS5 代理，可选 TCP 中转 | `10.246.77.1` |
| 家里 Windows | 被公司电脑远程访问，也可以使用代理 | `10.246.77.10` |
| 公司 Windows | 被家里电脑远程访问，也可以使用代理 | `10.246.77.20` |

加入 ZeroTier 只表示设备进入同一个私有网络，**不会自动让 Windows 代理上网**。需要代理的软件还要主动填写 `10.246.77.1:10808`，或使用 PAC/本地规则客户端。

## 使用边界

- 远程优先连接对方 Windows 的 ZeroTier IP，延迟最低。
- 代理默认只监听 ZeroTier 私有入口；公网入口是可选高级功能。
- 中转只在直连长期不稳定时启用，不是默认路径。
- 不要把 Windows 远程端口直接暴露到公网。
- 公网站点发布只开放明确目标，不等于公开整个 ZeroTier 网络。

下一步：[开始第一次配置](quick-start.md)。
