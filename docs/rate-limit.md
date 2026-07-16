# 按客户端限制代理速度

限速只匹配“指定客户端 IP + 项目代理端口”的流量，不限制整台客户端、ZeroTier 控制流量、远程桌面、relay、公网站点或 Ubuntu 其他服务。首期以固定 ZeroTier Managed IP 作为客户端身份；公网来源也可以使用一个 IP/CIDR，但同一 NAT 后的设备会共享上限。

## 开始前

- Ubuntu 代理已经通过[安装与互访验证](verification.md)。
- 客户端已有固定 IP，例如 `10.246.77.30`。
- Ubuntu 安装了 `iproute2`，并能运行 `tc`。
- 先确认代理端口；默认是 `10808`。

## 添加规则

先预览，脚本会询问规则名、客户端地址、上传和下载上限：

```bash
sudo bash scripts/ubuntu/manage-rate-limit.sh add
```

确认计划只出现目标客户端和代理端口后再应用：

```bash
sudo bash scripts/ubuntu/manage-rate-limit.sh add --apply
```

例如客户端 `10.246.77.30` 可设置上传 `5mbit`、下载 `20mbit`。支持 `kbit`、`mbit` 和 `gbit`。每条规则会生成 TCP/UDP 各两个方向的精确 filter。

如果要按公网来源限制共享上限，使用：

```bash
sudo bash scripts/ubuntu/manage-rate-limit.sh add --source-mode public
sudo bash scripts/ubuntu/manage-rate-limit.sh add --source-mode public --apply
```

## 查看和修改

列出全部规则：

```bash
sudo bash scripts/ubuntu/manage-rate-limit.sh list
```

查看某条规则和内核计数：

```bash
sudo bash scripts/ubuntu/manage-rate-limit.sh status --name laptop
sudo bash scripts/ubuntu/manage-rate-limit.sh test --name laptop
```

修改上限时只给出要变化的值，先预览再应用：

```bash
sudo bash scripts/ubuntu/manage-rate-limit.sh update --name laptop --upload 8mbit --download 30mbit
sudo bash scripts/ubuntu/manage-rate-limit.sh update --name laptop --upload 8mbit --download 30mbit --apply
```

规则状态会在重启后由 `zerotier-gateway-rate-limit.service` 精确重放。脚本不会替换或删除根 qdisc；已有 `clsact` 可以共用，项目 preference/handle 与未知规则冲突时会停止。

恢复服务会记录当前仓库中管理脚本的绝对路径。存在限速规则时不要移动或删除仓库目录；确需移动时，先移除规则，移动后再从新目录重新添加。

## 验证限速没有扩大范围

1. 在受限客户端通过项目代理连续测速至少 30 秒，分别观察上传和下载。
2. 结果不应持续超过目标上限的 15%；瞬时抖动不作为失败。
3. 用另一台未配置规则的客户端重复测速，确认它没有继承该上限。
4. 同时验证远程桌面和 relay，不应因为代理限速明显变慢。
5. 在 Ubuntu 查看 filter 计数，确认命中的是目标客户端与代理端口。

```bash
sudo tc -s filter show dev <接口名> ingress
sudo tc -s filter show dev <接口名> egress
```

接口名可从 `status` 输出取得。文档中的 `<接口名>` 是命令参数，不需要打开任何配置文件。

## 临时停用或删除

临时停用会保留设置：

```bash
sudo bash scripts/ubuntu/manage-rate-limit.sh disable --name laptop
sudo bash scripts/ubuntu/manage-rate-limit.sh disable --name laptop --apply
```

再次执行 `update --name laptop --apply` 可恢复该规则。

永久删除：

```bash
sudo bash scripts/ubuntu/manage-rate-limit.sh remove --name laptop
sudo bash scripts/ubuntu/manage-rate-limit.sh remove --name laptop --apply
```

删除只处理该规则的四个 project-owned filter。`clsact` 会保留，以免误删第三方 filter。

## 常见失败

| 现象 | 处理 |
|---|---|
| 客户端不在 ZeroTier 网段 | 先在 Central 固定正确 Managed IP；公网来源需显式使用 `--source-mode public` |
| preference/handle 冲突 | 不要 flush；按错误输出确认第三方流控后再换接口或处理冲突 |
| 重启后规则缺失 | 查看 `systemctl status zerotier-gateway-rate-limit.service` 和 `journalctl -u zerotier-gateway-rate-limit.service` |
| 远程桌面也变慢 | 立即停用该规则并核对代理端口；这通常说明现场流量路径与预期不一致 |
