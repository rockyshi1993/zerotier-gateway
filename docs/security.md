# 安全说明

## 必须保持的默认策略

- ZeroTier 网络应保持为私有网络。
- 新设备必须手动授权。
- 代理默认不启用账号密码认证；如果你的 ZeroTier 网络里有不可信设备，再同时填写 `PROXY_USERNAME` 和 `PROXY_PASSWORD` 启用认证。
- 代理默认监听 Ubuntu 的 ZeroTier IP，只供 ZeroTier 私有网络访问。
- 只有明确需要优化代理测速时，才启用代理公网入口。
- 远程控制端口不要暴露到公网。
- `.env` 不要提交到仓库。

## 默认私有入口

默认代理入口只供 ZeroTier 私有网络内访问：

```text
10.246.77.1:10808
```

这种模式下，云防火墙和系统防火墙都不要把 `10808` 开放到公网。

## 可选公网入口

如果默认入口测速慢，可以开启公网入口：

```text
PROXY_PUBLIC_ACCESS=true
PROXY_BIND_IP=0.0.0.0
PROXY_CONNECT_HOST=Ubuntu服务器公网IP
PROXY_ALLOWED_CLIENT_CIDRS=公司公网IP/32,家里公网IP/32
```

安全要求：

- `PROXY_ALLOWED_CLIENT_CIDRS` 至少填写公司、家里当前公网 IP 的 `/32`。
- 云厂商防火墙也要限制来源 IP，不要只依赖应用层配置。
- 代理账号密码仍然是可选项；如果来源 IP 不固定，建议同时填写 `PROXY_USERNAME` 和 `PROXY_PASSWORD`。
- 不要把远程控制端口暴露到公网；公网入口只用于代理上网。
