# 多台代理服务器

多台 Ubuntu 可以组成 Windows 代理节点池。日常只给软件配置一个稳定本地入口 `127.0.0.1:20808`；控制器检查真实 SOCKS 出口，当前节点连续失败后自动切换到其他健康节点。原来的 `.1`、`.3` 直连节点可以继续保留，作为控制器异常时的人工兜底。

> 自动切换只影响新连接，不迁移已经建立的 TCP 连接；所有节点不可用时会 fail-closed，不会静默改为本机直连。

## 1. 为每台 Ubuntu 分配地址

示例：

| 节点 | ZeroTier IP | 私有代理入口 |
|---|---|---|
| 新加坡 | `10.246.77.1` | `10.246.77.1:10808` |
| 东京 | `10.246.77.3` | `10.246.77.3:10808` |

在 ZeroTier Central 中授权每台服务器并固定不同的 Managed IP，不能重复。

## 2. 每台服务器独立安装（首次部署必须分两阶段）

**在每台新 Ubuntu 的仓库根目录分别执行**，使用各自的 ZeroTier IP；不要把第一台的 `.env` 原样复制为第二台的网络地址。

```bash
bash scripts/ubuntu/init-config.sh
sudo bash scripts/ubuntu/install-zerotier.sh --dry-run
sudo bash scripts/ubuntu/install-zerotier.sh
sudo zerotier-cli listnetworks
ip -4 -br addr
```

现在到 ZeroTier Central **授权这台服务器**，为它固定与其他成员不冲突的 Managed IP（例如第二台 `10.246.77.3`）。确认 `listnetworks` 显示目标网络为 `OK`，且 ZeroTier 网卡上实际存在**这台机器自己的**目标 IPv4 后，才继续：

```bash
sudo bash scripts/ubuntu/install-proxy.sh --dry-run
sudo bash scripts/ubuntu/install-proxy.sh
sudo bash scripts/ubuntu/health-check.sh
sudo systemctl is-active sing-box-zt-proxy
```

`install-proxy.sh --dry-run` 可能在仓库 `artifacts/` 写入含凭据的生成文件，但不会应用系统服务配置。检查 `ss -lntp` 中的监听地址与当前服务器的 ZeroTier IP 一致，随后按下一节验证真实 SOCKS 出口。具体说明见 [首次安装分阶段流程](quick-start.md)。

`install.sh` 会连续执行 ZeroTier 与 sing-box 安装；**首次尚未获得 Managed IP 时不要以它代替以上两阶段步骤**。已存在授权和正确 IP 的机器也应先检查现场配置，再决定是否重装。

如果客户端未加入 ZeroTier，公网代理入口属于独立、高风险的高级模式，**不能作为普通提速方案**；应先阅读 [公网代理安全边界](proxy-public.md)，评估传输加密、来源限制和凭据暴露风险。

## 3. 先逐台验证真实出口

在 Windows 分别测试：

```powershell
curl.exe --ssl-no-revoke -x socks5h://10.246.77.1:10808 https://api.ipify.org
curl.exe --ssl-no-revoke -x socks5h://10.246.77.3:10808 https://api.ipify.org
```

每条命令都应返回对应服务器的出口 IP。某一台失败时只检查该节点，不要把未通过验证的地址加入日常自动入口。

## 4. 在 Windows 安装本地数据面

在管理员 PowerShell 中安装 sing-box，并执行 Windows 管理层升级：

```powershell
winget install sing-box
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
.\scripts\windows\upgrade.ps1
.\scripts\windows\upgrade.ps1 -Apply
```

官方 Windows 包管理命令是 `winget install sing-box`。如果命令已安装，winget 会提示现有版本；可以用 `sing-box version` 确认命令可用。

## 5. 添加代理节点

每个节点先预览，再加 `-Apply` 保存。下面示例对应两台现有服务器：

```powershell
.\scripts\windows\manage-proxy-pool.ps1 -Action Add -Name old-gold -Server 10.246.77.1 -Port 10808
.\scripts\windows\manage-proxy-pool.ps1 -Action Add -Name old-gold -Server 10.246.77.1 -Port 10808 -Apply

.\scripts\windows\manage-proxy-pool.ps1 -Action Add -Name tokyo -Server 10.246.77.3 -Port 10808
.\scripts\windows\manage-proxy-pool.ps1 -Action Add -Name tokyo -Server 10.246.77.3 -Port 10808 -Apply
```

有用户名和密码时，运行不带完整参数的 `-Action Add`，按提示输入即可。项目最多保存 16 个节点；节点名不能重复。

逐个测试真实 SOCKS 出口：

```powershell
.\scripts\windows\manage-proxy-pool.ps1 -Action List
.\scripts\windows\manage-proxy-pool.ps1 -Action Test -Name old-gold
.\scripts\windows\manage-proxy-pool.ps1 -Action Test -Name tokyo
```

## 6. 启用一个稳定入口

先预览，再启用当前用户登录任务：

```powershell
.\scripts\windows\manage-proxy-pool.ps1 -Action Enable
.\scripts\windows\manage-proxy-pool.ps1 -Action Enable -Apply
```

启用后，SOCKS5 和 HTTP 都使用：

```text
地址：127.0.0.1
端口：20808
用户名/密码：留空
```

登录任务会记录当前仓库中控制器脚本的绝对路径。启用期间不要移动或删除仓库目录；确需移动时，先执行 `Disable -Apply`，移动后在新目录重新执行 `Enable -Apply`。

在 v2rayN 里只新增一个名为“ZeroTier 自动代理”的 SOCKS 节点，地址填 `127.0.0.1:20808`。原来的 `10.246.77.1:10808`、`10.246.77.3:10808` 节点不要立即删除，它们是紧急人工兜底。

验证本地入口：

```powershell
curl.exe --ssl-no-revoke -x socks5h://127.0.0.1:20808 https://api.ipify.org
curl.exe --ssl-no-revoke -x socks5h://127.0.0.1:20808 https://www.google.com/generate_204 -I
.\scripts\windows\manage-proxy-pool.ps1 -Action Status
```

## 7. 验证自动切换

先确认两台节点都健康，并让当前流量使用本地入口。选择当前未使用的代理服务器做故障注入，再观察恢复；不要先停止唯一健康节点。

在备用 Ubuntu 临时停止代理：

```bash
sudo systemctl stop sing-box-zt-proxy
```

Windows 等待两个健康周期后查看：

```powershell
.\scripts\windows\manage-proxy-pool.ps1 -Action Status
curl.exe --ssl-no-revoke -x socks5h://127.0.0.1:20808 https://api.ipify.org
```

恢复节点：

```bash
sudo systemctl start sing-box-zt-proxy
```

默认每 10 秒检查一次，连续 2 次失败才标记故障，连续 3 次成功才恢复健康。当前健康节点会继续使用，避免因为几毫秒延迟差来回切换。要验证真正的切换，可在已确认另一节点健康后短暂停止当前节点；新连接应在 60 秒内通过备用节点恢复。

如果所有节点都停用，本地端口仍可能存在，但请求会明确失败，不会绕过代理。恢复任一节点并连续通过 3 次检查后，新连接会恢复。

## 8. 停用或删除

停用控制器但保留节点：

```powershell
.\scripts\windows\manage-proxy-pool.ps1 -Action Disable
.\scripts\windows\manage-proxy-pool.ps1 -Action Disable -Apply
```

删除一个节点：

```powershell
.\scripts\windows\manage-proxy-pool.ps1 -Action Remove -Name tokyo
.\scripts\windows\manage-proxy-pool.ps1 -Action Remove -Name tokyo -Apply
```

完全移除项目任务、节点池 state 和本地运行文件：

```powershell
.\scripts\windows\manage-proxy-pool.ps1 -Action Remove
.\scripts\windows\manage-proxy-pool.ps1 -Action Remove -Apply -ConfirmRemoval
```

这些命令不会修改 v2rayN，也不会删除旧直连节点。

## 自动化边界

- 控制器只做健康故障转移，不做多节点负载均衡。
- 已建立的连接不会迁移，切换只保证新连接使用健康节点。
- **PAC / 本地分流客户端接入节点池尚无自动组合流程。** `init-config.ps1` 的普通私有模式不会把上游设成 `127.0.0.1:20808`；`generate-proxy-pac.ps1` 与 `generate-client-rules.ps1` 的上游使用 `PROXY_CONNECT_HOST:PROXY_PORT`，而节点池的本地入口是独立的 `127.0.0.1:<pool.localPort>`。不能照旧文档通过重新初始化来自动切换它们。
- 现有受支持的最短路径是让 **v2rayN 或其他支持 SOCKS5/HTTP 的软件直接连接节点池本地入口**。若同时运行生成的本地 sing-box 规则客户端，默认也会占用 `127.0.0.1:20808`，可能发生端口冲突或回环；未经独立设计和端到端验证，不要同时启用两套同端口监听。
- Windows 重启后由当前用户登录任务恢复；未登录时不会启动用户级本地入口。

出现问题先用旧直连节点恢复工作，再查看 `-Action Status`、Task Scheduler 的 `\ZeroTierGateway\ProxySelector` 和项目 runtime 日志。
