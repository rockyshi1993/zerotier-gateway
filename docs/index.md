---
pageType: home
hero:
  name: ZeroTier Gateway
  text: 用脚本搭建私有远程访问与代理
  tagline: Ubuntu 提供私有代理和可选中转，Windows 通过 ZeroTier 互相远程；普通流程不需要编辑脚本或配置文件。
  actions:
    - theme: brand
      text: 5 分钟快速开始
      link: /quick-start
    - theme: alt
      text: 只看远程访问
      link: /remote
    - theme: alt
      text: 配置代理上网
      link: /proxy
features:
  - title: 脚本优先
    details: 初始化、安装、检查和防火墙都从现有脚本进入，减少手工参数。
  - title: 默认私有
    details: 远程和代理默认使用 ZeroTier 私有地址，不要求暴露 Windows 远程端口。
  - title: 失败可恢复
    details: 健康检查、网络测试、中转、故障排查和回滚都有独立入口。
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

下一步：[开始第一次配置](quick-start.md)。
