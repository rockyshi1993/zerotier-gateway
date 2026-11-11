# 停用、回滚与卸载

**先确定要退出的是哪个能力。** 关闭软件代理、关闭 Android IPv4 Exit Node、移除 Ubuntu 代理服务、卸载 ZeroTier 是不同操作。现有 `uninstall.sh` **不是全功能一键恢复工具**。

在执行任何资源删除前，记录实际 IP、服务名、UFW 规则、Central 路由、Windows 任务以及需要保留的其他服务；旧版/开发版混用时先核对当前代码版本。

## 1. 手机/客户端不再使用 Exit Node

必须避免保留一条指向已失效网关的默认路由：

1. 在所有使用此出口的 Android/Windows 等客户端上，先关闭对应 ZeroTier Network 的 **Allow Default** 或停用该 VPN，检查它们能通过正常网络上网。
2. 在 ZeroTier Central 确认 `0.0.0.0/0 via <Ubuntu ZT IP>` 是否由本任务单独使用。若是且没有其他依赖，则删除；不要删除共享路由。
3. 在 Ubuntu 预览并应用停止：

```bash
sudo bash scripts/ubuntu/manage-exit-node.sh disable
sudo bash scripts/ubuntu/manage-exit-node.sh disable --apply
```

4. 复验客户端普通公网 IPv4、必要的 IPv6/DNS 访问以及 Ubuntu 项目 Exit Node 状态。此流程不会自动关闭原有应用级 HTTP/SOCKS5 代理。

## 2. 停止 Ubuntu 私有代理

在 Ubuntu 仓库根目录：

```bash
sudo bash scripts/ubuntu/uninstall.sh
```

脚本主要移除 `sing-box-zt-proxy.service`；默认不卸载 ZeroTier，也不清理全部可选资源或所有历史防火墙规则。代理软件端还应取消指向该服务的代理入口，否则应用请求可能持续失败。

在进行大范围卸载前，检查并记录：

```bash
sudo systemctl list-units 'zerotier-gateway-*' --all
sudo ufw status numbered
```

不要未经审查就删除未知归属的防火墙规则。生成的 `.env`、`artifacts/` 和 `/etc/zerotier-gateway/` 可能仍含凭据，需要按安全保留策略单独处置。

## 3. 单独关闭 TCP 中转

```bash
sudo bash scripts/ubuntu/disable-relay.sh
```

此操作关闭项目生成的中转 systemd 单元；检查 Windows 远程工具是否还在连接中转的 Ubuntu ZT IP/443、444 等端口。关闭中转不应影响设备通过 ZeroTier IP 直接互访。

## 4. 单独停用限速或服务发布

限速规则：

```bash
sudo bash scripts/ubuntu/manage-rate-limit.sh disable --name laptop
sudo bash scripts/ubuntu/manage-rate-limit.sh disable --name laptop --apply
sudo bash scripts/ubuntu/manage-rate-limit.sh remove --name laptop --apply
```

公网 IP+端口映射：

```bash
sudo bash scripts/ubuntu/manage-publish.sh remove --name mysite
sudo bash scripts/ubuntu/manage-publish.sh remove --name mysite --apply
```

域名发布：

```bash
sudo bash scripts/ubuntu/manage-publish.sh remove-domain --name mysite
sudo bash scripts/ubuntu/manage-publish.sh remove-domain --name mysite --apply
```

确认云安全组/入口防火墙和 DNS 是否还存在以前的公网开放；项目的删除命令不能替代这些外部平台操作。

## 5. Windows 资源

在管理员 PowerShell 下移除由 Home/Work 脚本创建的规则：

```powershell
.\scripts\windows\setup.ps1 -Rollback
```

若启用了多代理节点池，先停用再删除其计划任务和受控运行文件：

```powershell
.\scripts\windows\manage-proxy-pool.ps1 -Action Disable -Apply
.\scripts\windows\manage-proxy-pool.ps1 -Action Remove -Apply -ConfirmRemoval
```

如果此前启用了 Windows RDP 主机，还应在系统的远程桌面设置中关闭不再使用的 RDP 功能；`enable-remote-desktop.ps1` 没有对称的 `-Disable` 参数。上述操作不自动删除 v2rayN 配置、Windows 系统代理设置或 ZeroTier 客户端。应检查目标软件是否仍指向不存在的 `127.0.0.1:20808`。

## 6. 升级回退的限制

```bash
sudo bash scripts/ubuntu/upgrade.sh --rollback <backup-id>
```

```powershell
.\scripts\windows\upgrade.ps1 -Rollback <backup-id> -Apply
```

这些命令主要回退**项目管理状态**，不等于完整回滚网关网络、包版本、ZeroTier Central 或第三方客户端。务必按 [安全升级](upgrade.md) 核对具体场景。

## 7. 完成后的检查

- Ubuntu 不再监听已关闭的代理/中转/发布端口；仍使用的功能不受影响。
- Windows/Android 的代理与默认路由设置指向仍存在的服务，且真实访问成功。
- 云安全组、DNS、Central Managed Routes 与本机状态一致；没有留下不需要的公网入口。
- 敏感文件和日志按运维策略保留或安全销毁，并且没有提交到 GitHub。

Git tag 和 GitHub Release 的创建、回退属于仓库维护者发布流程，不属于用户卸载说明，见 [发布验证](release.md)。
