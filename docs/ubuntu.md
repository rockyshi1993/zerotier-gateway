# Ubuntu 节点

Ubuntu 节点负责提供：

- 加入 ZeroTier 私有网络。
- 通过 sing-box 提供私有 HTTP/SOCKS5 代理。
- 在直连质量较差时提供可选中转兜底。

## 常用命令

```bash
bash scripts/ubuntu/init-config.sh
sudo bash scripts/ubuntu/install.sh --dry-run
sudo bash scripts/ubuntu/install.sh
sudo bash scripts/ubuntu/health-check.sh
```

`install.sh` 会同时安装 ZeroTier 和代理服务。`scripts/ubuntu/install-proxy.sh` 是单独修代理时用的子脚本，普通安装不用直接运行。

如果 Ubuntu 默认源里没有 `sing-box` 包，脚本会自动添加官方 SagerNet apt 源后再安装。

## 代理监听

默认情况下，代理监听 Ubuntu 的 ZeroTier IP：

```text
PROXY_BIND_IP=10.246.77.1
PROXY_PUBLIC_ACCESS=false
PROXY_CONNECT_HOST=10.246.77.1
PROXY_PORT=10808
```

这时客户端代理入口是 `10.246.77.1:10808`，只供 ZeroTier 私有网络内访问。

如果代理测速慢，而服务器公网 IP 入口更快，可以显式开启公网入口：

```text
PROXY_BIND_IP=0.0.0.0
PROXY_PUBLIC_ACCESS=true
PROXY_CONNECT_HOST=Ubuntu服务器公网IP
PROXY_ALLOWED_CLIENT_CIDRS=
PROXY_PORT=10808
```

开启公网入口后，`PROXY_BIND_IP=0.0.0.0` 表示 Ubuntu 同时在公网网卡和 ZeroTier 网卡上监听代理。客户端不一定都要改成公网 IP：已经加入 ZeroTier 的电脑可以继续用 `10.246.77.1:10808`，没加入 ZeroTier 或实测公网路径更快的设备再用 `PROXY_CONNECT_HOST:10808`。账号密码仍然可选，`PROXY_ALLOWED_CLIENT_CIDRS` 也可留空；留空表示全部来源可访问公网入口的 `10808`。长期使用建议填写来源 IP 白名单或启用代理账号密码。

## 系统服务

代理服务文件由以下模板生成：

```text
templates/systemd/sing-box-zt-proxy.service.tmpl
```

生成后的运行配置默认写入：

```text
/etc/zerotier-gateway/sing-box-server.json
```
