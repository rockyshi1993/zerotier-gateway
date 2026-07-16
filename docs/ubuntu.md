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

默认代理入口是 `10.246.77.1:10808`，只供 ZeroTier 私有网络内访问。代理测速慢或客户端未加入 ZeroTier 时，按[公网代理](proxy-public.md)重新运行初始化脚本开启公网入口，不需要编辑配置文件。

已有节点升级、按客户端限速和公网站点发布分别使用[安全升级](upgrade.md)、[按客户端限速](rate-limit.md)和[公网站点发布](publish-site.md)中的专项命令；它们默认关闭，不会随基础安装自动启用。

安装完成后使用[Ubuntu 安装成功验证](verification.md#1-ubuntu-安装成功)检查服务、网络和监听地址。

## 系统服务

代理服务文件由以下模板生成：

```text
templates/systemd/sing-box-zt-proxy.service.tmpl
```

生成后的运行配置默认写入：

```text
/etc/zerotier-gateway/sing-box-server.json
```
