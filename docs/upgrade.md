# 安全升级

本页适合正在使用旧版本代理、网关或中转的设备。默认升级只登记新的管理能力和备份，不重启、不重配现有 ZeroTier、代理、relay、防火墙、PAC、本地规则或 v2rayN；自动切换、限速和站点发布仍保持关闭。

## 升级前先确认

在仓库目录检查是否有自己尚未保存的改动：

```bash
git status --short
```

结果为空再拉取。结果不为空时先自行提交或备份，不要用强制重置覆盖现场配置：

```bash
git pull --ff-only
```

如果 `--ff-only` 提示分支已经分叉，本次升级先停止；处理 Git 历史后再继续，升级脚本不会替你 stash 或 reset。

## 两台 Ubuntu 的安全顺序

例如当前有 `10.246.77.1` 和 `10.246.77.3` 两个代理节点：

1. 记下 v2rayN 当前使用哪一台。
2. 先升级当前未承载流量的备用节点。
3. 验证备用节点的服务、监听和真实代理出口。
4. 在 v2rayN 手动切到已验证的备用直连节点。
5. 再升级原活动节点并重复验证。
6. 两台都通过后，最后升级 Windows 并配置自动切换。

默认管理层升级不重启服务，但这个顺序仍能避免把两台未经验证的服务器同时作为可用节点。单台 Ubuntu 也可执行默认升级；未来如果某个版本明确要求运行态迁移，再按该版本说明安排维护时间。

## Ubuntu：预览、应用、验证

先预览。该命令只读取安装指纹和计划，不创建目录或状态：

```bash
sudo bash scripts/ubuntu/upgrade.sh --dry-run
```

确认输出的安装类型是 `historical-gateway`、`modular-proxy` 或 `source-only`。如果显示 `unknown` 或 `unknown-mixed`，脚本会安全停止，不猜测资源所有权。

应用默认升级：

```bash
sudo bash scripts/ubuntu/upgrade.sh
```

输出会给出 backup id 和回退命令。随后验证旧运行态仍正常：

```bash
sudo bash scripts/ubuntu/health-check.sh
sudo systemctl is-active zerotier-one
sudo systemctl is-active sing-box-zt-proxy
sudo ss -lntp | grep ':10808'
```

从 Windows 再验证该节点的真实出口；把地址换成正在升级的服务器：

```powershell
curl.exe --ssl-no-revoke -x socks5h://10.246.77.1:10808 https://api.ipify.org
curl.exe --ssl-no-revoke -x socks5h://10.246.77.1:10808 https://www.google.com/generate_204 -I
```

第一条应返回该服务器出口 IP，第二条应返回 `204`。只有端口能连接不算升级验证完成。

## Windows：预览、应用、验证

在管理员 PowerShell 中执行：

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
.\scripts\windows\upgrade.ps1
.\scripts\windows\upgrade.ps1 -Apply
```

Windows 命令默认只预览，只有 `-Apply` 才写入项目管理状态。它不会注册代理选择任务，也不会改防火墙、PAC、客户端 JSON、v2rayN 或当前监听。

验证原有网络和代理：

```powershell
.\scripts\windows\show-diagnostics.ps1
.\scripts\windows\test-network.ps1
.\scripts\windows\test-proxy.ps1
```

## 回退管理状态

Ubuntu 使用升级输出中的 backup id：

```bash
sudo bash scripts/ubuntu/upgrade.sh --rollback <backup-id>
```

Windows 使用：

```powershell
.\scripts\windows\upgrade.ps1 -Rollback <backup-id> -Apply
```

这里回退的是项目管理状态。默认升级本来就没有重启或覆盖旧服务，因此不要把它理解为“重新启动旧版本运行服务”。

## 通过标准

- 升级脚本识别到明确的项目安装类型。
- Ubuntu 旧 service、PID、监听、配置和防火墙保持不变。
- Windows 现有任务、进程、监听、PAC、本地规则和 v2rayN 保持不变。
- Ubuntu 健康检查、Windows 网络检查和真实代理出口均通过。
- 新的代理池、限速和公网发布没有被自动启用。

两台代理都通过后，可继续配置[多台代理服务器与自动切换](proxy-multi-server.md)。
