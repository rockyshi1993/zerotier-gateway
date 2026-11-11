# 故障排查

> **先按失败层定位，不要一上来重装所有服务。** 仅成员互访、应用级 HTTP/SOCKS5 代理、IPv4 Exit Node 是三种不同的路径。
> 对照 [安装与功能验收](verification.md) 先查 ZeroTier 授权和实际 IP，再查端口、代理出口、Central 默认路由与客户端 Allow Default。
> `health-check.sh` 的零退出码不等于真实业务请求成功。


## 找不到配置文件

脚本默认读取项目根目录下的 `.env`。

新增管理命令不要求打开该文件；升级、代理池、限速和发布问题优先运行各自的 `status`/`test` 命令。

修复方式：

```bash
bash scripts/ubuntu/init-config.sh
```

Windows：

```powershell
.\scripts\windows\init-config.ps1
```

## Windows 脚本无法运行

如果 PowerShell 提示：

```text
无法加载文件 ... 因为在此系统上禁止运行脚本
PSSecurityException
UnauthorizedAccess
```

先在当前 PowerShell 窗口执行：

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
```

然后重新运行刚才的脚本。`-Scope Process` 只影响当前窗口，关掉窗口后会恢复。

## Windows 防火墙规则写入失败

如果执行：

```powershell
.\scripts\windows\setup.ps1 -Role Home -ApplyFirewall
```

或：

```powershell
.\scripts\windows\setup.ps1 -Role Work -ApplyFirewall
```

看到类似报错：

```text
New-NetFirewallRule : 拒绝访问。
Windows System Error 5
```

通常是当前 PowerShell 不是管理员权限，或系统策略拒绝写入防火墙。处理方式：

1. 关闭当前 PowerShell。
2. 右键 PowerShell，选择“以管理员身份运行”。
3. 进入项目目录。
4. 确认管理员状态返回 `True`：

```powershell
# 在仓库根目录执行
([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
```

5. 先执行 `Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass`。这条命令只放行当前窗口运行脚本，不会提升管理员权限。
6. 家里电脑重新执行 `.\scripts\windows\setup.ps1 -Role Home -ApplyFirewall`。
7. 公司电脑重新执行 `.\scripts\windows\setup.ps1 -Role Work -ApplyFirewall`。

最新脚本会同时写入两类规则：对端 Windows 的 ZeroTier IP 用于直连，初始化时选择的 Ubuntu IP 用于中转。如果公司电脑或安全软件禁止修改防火墙，请联系系统管理员允许对应来源访问远程端口。默认示例里，家里电脑放行公司电脑 `10.246.77.20` 和 Ubuntu `10.246.77.1`；公司电脑放行家里电脑 `10.246.77.10` 和 Ubuntu `10.246.77.1`。

如果是第三台或更多 Windows 加入 ZeroTier，`setup.ps1 -Role Home/Work` 不会自动管理这些额外电脑。额外电脑只用代理或只访问别人时不需要执行 `setup.ps1`；如果它也要被远程访问，请在额外电脑上手动放行允许访问它的对端 ZeroTier IP，或放行可信的 `10.246.77.0/24`。

如果你新增了另一台 Ubuntu 中转服务器，Windows 不需要安装中转服务；但目标 Windows 必须允许新服务器的 ZeroTier IP 访问远程端口。比如新服务器是 `10.246.77.2`，先在目标 Windows 重跑 `init-config.ps1`，一路回车保留现值、只更新 Ubuntu IP，再重跑对应角色的 `setup.ps1 -ApplyFirewall`。

旧脚本或临时补救时，也可以在目标 Windows 的管理员 PowerShell 手动添加：

```powershell
New-NetFirewallRule -DisplayName "ZT Relay Server 10.246.77.2 Inbound 3389" -Direction Inbound -Action Allow -Protocol TCP -LocalPort 3389 -RemoteAddress 10.246.77.2 -Profile Any
```

手动规则的 `DisplayName` 可以自己定，但后续查询必须使用实际创建过的名字。脚本自动生成的中转规则名是 `ZT Gateway Relay Inbound Home 3389` 或 `ZT Gateway Relay Inbound Work 3389`；如果你没有创建过 `ZT Relay Singapore Inbound 3389`，用这个名字查询会提示找不到对象。

## 本地自动代理入口不可用

```powershell
.\scripts\windows\manage-proxy-pool.ps1 -Action Status
.\scripts\windows\manage-proxy-pool.ps1 -Action Test
Get-ScheduledTask -TaskPath '\ZeroTierGateway\' -TaskName ProxySelector
```

控制器与 sing-box 日志位于 `%ProgramData%\ZeroTierGateway\runtime\`；优先查看 `selector.log` 和 `sing-box.stderr.log`。项目会保留一份轮转备份，避免故障日志持续无界增长。

- 所有节点 `unhealthy`：先直接测试每台 `10.246.77.x:10808`，恢复至少一台服务器。
- Task 未运行：确认当前用户已登录，并重新预览/执行 `-Action Enable -Apply`。
- `127.0.0.1:20808` 被其他进程占用：不要强制结束未知进程；先查 `Get-NetTCPConnection -LocalPort 20808`。
- 急需恢复工作：在 v2rayN 临时切回保留的 `.1` 或 `.3` 直连节点。

## 限速规则未生效或影响范围不对

```bash
sudo bash scripts/ubuntu/manage-rate-limit.sh status --name <规则名>
sudo bash scripts/ubuntu/manage-rate-limit.sh test --name <规则名>
sudo systemctl status zerotier-gateway-rate-limit.service
```

如果 RDP、relay 或未限速客户端也变慢，先执行 `disable --name <规则名> --apply`。不要运行 `tc qdisc del` 或全局 filter flush；项目删除命令只处理有 state 与稳定 handle 的规则。

## 手机 Exit Node 没有接管移动网络

先在 Ubuntu 看项目状态：

```bash
sudo bash scripts/ubuntu/manage-exit-node.sh status
sudo bash scripts/ubuntu/manage-exit-node.sh test
```

- `rule.*=missing`：执行 `sudo bash scripts/ubuntu/manage-exit-node.sh restore --apply`，或先 `disable --apply` 再重新启用。
- Pixel 仍显示运营商 IPv4：检查 ZeroTier Central 是否有 `0.0.0.0/0 via 10.246.77.1`，以及 Pixel 是否对该网络开启 Allow Default / Allow Default Route。
- Windows 也全局走 VPN：检查那台 Windows 的 ZeroTier 客户端是否开启了 Allow Default；项目默认不会替 Windows 打开它。
- IPv4 出口正确但 `https://api64.ipify.org` 显示运营商 IPv6：当前 Exit Node 首期是 IPv4-only，需要严格 IPv6 时要另开需求。

手机移动网络且不想暴露公网代理端口时，不要按公网代理路径开放 `10808/tcp`；应按[私有 Exit Node](exit-node.md)处理。

## 公网端口或域名外部不可访问

先分层，不要直接重装（以下 `mysite` 是示例，须替换为已创建映射的实际名称；两种发布模式只执行对应的一条）：

```bash
sudo bash scripts/ubuntu/manage-publish.sh test --name mysite
sudo bash scripts/ubuntu/manage-publish.sh test-domain --name mysite
sudo ss -lntp
```

- 目标检查失败：修复 ZeroTier 目标 IP、目标端口或站点服务。
- 本机转发失败：查看对应 `zerotier-gateway-publish-*` unit。
- 本机通过、外部失败：检查云安全组、路由器 NAT、运营商入站限制和实际公网 IP。
- 域名 DNS 不正确：先修正 A 记录；Caddy不会伪造证书成功。
- 80/443 被占用：项目会停止，不接管第三方 Caddy/nginx/Apache；选择现有反向代理集成需要另行规划。

## 搬家、换宽带后延迟很高或显示 RELAY

如果以前远程访问很流畅，搬家、迁移宽带或把路由器恢复默认后突然变慢，先不要重装 ZeroTier。常见原因是路由器原有的 UDP 映射被清空，或新宽带改为运营商 CGNAT，导致两台设备无法建立 P2P 直连，只能经过 ZeroTier 中继。

先在两端 Windows 的管理员 PowerShell 中执行：

```powershell
zerotier-cli peers
ping -n 20 <对端 ZeroTier IP>
```

`peers` 中与对端相关的连接如果显示 `DIRECT`，说明已直连；若长期显示 `RELAY`，且 ping 延迟明显升高，说明正在走中继。先确认没有 TUN、全局代理或加速器接管 ZeroTier 流量；处理方式见[开启 TUN 或全局代理后远程不通](#开启-tun-或全局代理后远程不通)。

### 0. Ubuntu 节点放行 ZeroTier UDP 9993

Ubuntu 节点如果开着 `ufw` 且默认拒绝入站，ZeroTier 的 UDP `9993` 进不来，手机或其他对端可能打洞失败，退回 `RELAY` 中继，延迟高、抖动大、速度慢（2026-10-26 在东京出口实测：Pixel 到东京显示 `RELAY`，而服务器本身带宽正常）。可选放行，默认关闭，不影响已部署的机器：

```bash
# 当前示例的 install-proxy.sh 会刷新/重启代理；已有连接可能中断
sudo bash scripts/ubuntu/install-proxy.sh --allow-zerotier-udp --dry-run   # 先预览
sudo bash scripts/ubuntu/install-proxy.sh --allow-zerotier-udp
# 已部署的机器也可以只加这一条（ufw 会同时加 IPv4/IPv6，重复执行会跳过）
sudo ufw allow 9993/udp comment 'zerotier'
```

之后再次检查 `zerotier-cli peers`、实际 path 和延迟：放行 UDP `9993` **可能改善 DIRECT 建立率，但不保证一定转为 DIRECT**；NAT、运营商 CGNAT、云安全组或对端网络条件仍可能导致 RELAY。云厂商安全组也要检查入站 UDP `9993`。撤回项目建议规则前请核对规则归属；本机示例可使用 `sudo ufw delete allow 9993/udp`。

### 1. 恢复路由器的 UDP 映射

只在家里这台 Windows 需要作为 ZeroTier 节点时配置。先确认它当前的局域网 IPv4：

```powershell
ipconfig
```

在路由器的“端口映射”或“虚拟服务器”页面添加一条规则：

| 字段 | 填写值 |
|---|---|
| 服务名称 | `ZeroTier-UDP-9993` |
| 局域网 IP | 这台 Windows 的当前局域网 IPv4，例如 `192.168.1.131` |
| 协议 | **UDP** |
| 内部端口 | `9993` |
| 外部端口 | `9993` |

不要使用页面默认的 TCP，也不要把随机高端口手工固定映射。ZeroTier 会维护其他辅助 UDP 端口；手工映射只恢复稳定的 UDP `9993` 入口。路由器重置后，局域网 IP 可能变化；如果 Windows 没有 DHCP 保留地址，后续应检查这条规则仍指向正确的设备。

### 2. 判断是否处于运营商 CGNAT

在路由器的“网关信息”或“WAN 信息”中查看 WAN IPv4：

- 如果 WAN 地址位于 `100.64.0.0/10`，例如 `100.64.x.x`，通常表示运营商 CGNAT；
- 此时本地端口映射只能到达自家路由器，**无法穿透运营商上游 NAT**，仍可能保持 `RELAY`；
- 联系宽带运营商，说明“需要公网 IPv4 或取消 CGNAT，用于 ZeroTier 的 UDP P2P 直连”。

拿到公网 IPv4 后，确认 UDP `9993` 映射仍指向当前 Windows 局域网 IP，再重新执行：

```powershell
zerotier-cli peers
ping -n 20 <对端 ZeroTier IP>
```

重新观察 `zerotier-cli peers` 的实际 path 与延迟；条件改善时**可能**由 `RELAY` 转为 `DIRECT`，不能预先保证。若公网 IPv4、UDP 映射均已确认仍无法直连，可以按[指定 TCP 中转](relay.md)处理明确的远程 TCP 服务；它不等于 ZeroTier 底层通用中继。

## ZeroTier 无法连通

检查：

1. 设备已经在 ZeroTier Central 授权。
2. 基础三台机器的 ZeroTier IP 已按预期固定；更多设备也已固定为不冲突的 IP。
3. Windows 防火墙允许对端 ZeroTier IP 访问远程端口。
4. `10.246.77.0/24` 的路由走 ZeroTier。
5. ZeroTier Central 里没有残留 `172.27.x.x` 地址池或成员 IP。

运行：

```powershell
.\scripts\windows\test-network.ps1
```

## ZeroTier Central 网段或地址池配置不干净

到 ZeroTier Central 的网络详情页，打开 `Advanced`，建议保持：

| 位置 | 应该保留 |
|---|---|
| `Managed Routes` | `10.246.77.0/24 (LAN)` |
| `IPv4 Auto-Assign` | 可以关闭自动分配，改为手动固定 IP |
| `Auto-Assign Pools` | 如果保留自动分配，只用 `10.246.77.100` 到 `10.246.77.254` |

不要把 `10.246.77.0/24` 填到 `Via`。如果还有 `172.27.0.1` 到 `172.27.255.254` 的自动分配地址池、成员机器上的 `172.27.x.x`，或误填的 `192.168.x.x` 地址池，建议删掉。

基础三台机器只保留：

| 设备 | Managed IP |
|---|---|
| Ubuntu 节点 | `10.246.77.1` |
| 家里 Windows 电脑 | `10.246.77.10` |
| 公司 Windows 电脑 | `10.246.77.20` |

调整后，在 Windows 上执行：

```powershell
Restart-Service ZeroTierOneService
zerotier-cli listnetworks
```

`listnetworks` 里应该只看到本机的 `10.246.77.x/24`，不应该再看到 `172.27.x.x`。

## 开启 TUN 或全局代理后远程不通

如果已经用 v2rayN 或其他工具把 Windows 系统代理配置为本地监听地址，例如 `127.0.0.1:10808`，通常不需要再开启 TUN。系统代理已经能覆盖浏览器、Git、npm 和大多数遵守系统代理的软件；TUN 只在软件不支持系统代理、需要强制接管流量时再考虑。

如果开启 TUN、全局代理、加速器或其他接管系统流量的软件后远程不通，先让 ZeroTier 网段直连：

```text
10.246.77.0/24
```

如果当前代理节点就是 Ubuntu 私有入口，也把代理服务器地址和本机地址直连，避免代理连接本身被再次接管：

```text
10.246.77.1
服务器公网IP
127.0.0.1
localhost
```

v2rayN 的 TUN 模式建议先用：

```text
自动路由：开启
严格路由：先关闭
协议栈：gvisor
MTU：1500；如果仍不稳定再改 1400
IPv6：没有公网 IPv6 时关闭
```

如果代理工具支持按进程直连，把 ZeroTier 进程也加入直连。可用下面命令查看实际进程名和路径：

```powershell
Get-Process | Where-Object { $_.ProcessName -like "*ZeroTier*" } | Select-Object ProcessName,Path
```

远程工具本身也建议走直连；如果代理工具支持按进程规则，把远程工具的主进程、服务进程和辅助进程一起加入直连。

改完后，两台 Windows 都执行：

```powershell
Restart-Service ZeroTierOneService
zerotier-cli peers
```

公司访问家里时测 `ping -n 20 10.246.77.10`；家里访问公司时测 `ping -n 20 10.246.77.20`。

如果 `peers` 里对方节点的 `path` 仍然显示为代理出口 IP，说明 ZeroTier 进程还在被 TUN 接管，需要继续检查代理工具的直连规则。

## 代理无法连通

**先按故障层定位，不要直接重新执行 `install.sh`。** 当前推荐的首次部署方式是先 ZeroTier 入网并授权，再单独安装代理，详见 [快速开始](quick-start.md)。

### 1. Ubuntu ZeroTier 是否就绪

在 **Ubuntu** 仓库根目录：

```bash
sudo zerotier-cli info
sudo zerotier-cli listnetworks
ip -4 -br addr
```

检查目标 Network 为 `OK`，ZeroTier 网卡上确实存在初始化时填写的 Ubuntu ZT IP（示例 `10.246.77.1`）。如果显示 `ACCESS_DENIED`、`REQUESTING_CONFIGURATION` 或实际地址错误，先到 Central 授权并修正 Managed IP，不要尝试启动一个绑定到不存在 IP 的服务。

### 2. 服务和监听是否正常

```bash
sudo systemctl is-active sing-box-zt-proxy
sudo systemctl status sing-box-zt-proxy --no-pager
sudo ss -lntp | grep ':10808'
sudo journalctl -u sing-box-zt-proxy -n 80 --no-pager
```

如果使用自定义代理端口，应替换示例 `10808`。如果之前仅仅缺少代理组件，**在 ZeroTier 已经授权且 IP 正确之后**，先预览，再专项安装：

```bash
sudo bash scripts/ubuntu/install-proxy.sh --dry-run
sudo bash scripts/ubuntu/install-proxy.sh
```

注意 `install-proxy.sh` 会生成/覆盖代理配置、调整其防火墙规则并重启 sing-box，已有连接可能中断；即使 `--dry-run` 也可能在 `artifacts/` 写入生成文件。不要把它当作只读健康检查，更不要无条件重跑包含 ZeroTier 安装与设置的 `install.sh`。

### 3. Windows 到代理端口是否可达

在已加入同一 ZeroTier 网络并获授权的 **Windows** 运行：

```powershell
Test-NetConnection 10.246.77.1 -Port 10808
```

若 TCP 不通，先核对 ZeroTier IP、Ubuntu sing-box 监听地址、UFW、主机/云防火墙和客户端路由。**不要为了修复 TCP 不通直接把代理监听切成公网 `0.0.0.0`。** UDP `9993` 只影响 ZeroTier 入站连通性条件，不能保证 TCP 代理端口已经打开。

### 4. 端口通但代理出口失败

```powershell
curl.exe --ssl-no-revoke -x socks5h://10.246.77.1:10808 https://api.ipify.org
```

如果启用了认证，请使用支持安全输入凭据的客户端；不要把明文口令粘贴到共享日志或提交到仓库。核对 SOCKS5/HTTP 协议、身份认证、Ubuntu 实际互联网出口及 sing-box 日志。**代理端口可达不等于真实出口成功；只有得到并核对 Ubuntu 公网出口 IP 才算通过。**

### 5. 只有业务软件不走代理

检查该软件是否已经主动启用 HTTP/SOCKS5 或本地规则接管。加入 ZeroTier 不会自动修改 Windows 系统代理。使用 PAC、v2rayN、TUN 或节点池时，应分别按 [代理使用](proxy.md)、[代理规则](proxy-rules.md)、[多节点](proxy-multi-server.md) 的生效范围排查。

如果经证实私有路径不稳定，先检查实际 ZeroTier DIRECT/RELAY 和底层 UDP/NAT 条件；**公网 mixed 代理没有内建 TLS**，不应被作为默认的“提速修复”。如确需使用公网入口，必须先阅读 [公网代理安全要求](proxy-public.md)。

## 进程排除没有命中

多进程软件可能会启动服务进程、辅助进程或更新进程。

查找候选进程：

```powershell
.\scripts\windows\show-diagnostics.ps1 -FindProcess "远程"
.\scripts\windows\show-diagnostics.ps1 -FindProcessPath "C:\Program Files\远程工具"
```

确认实际进程名或路径后，重新生成本地规则客户端配置：

```powershell
.\scripts\windows\configure-proxy-rules.ps1 `
  -DirectProcessNames 'mstsc.exe,RemoteTool.exe' `
  -DirectProcessPaths 'C:\Program Files\RemoteTool\RemoteTool.exe' `
  -Generate
sing-box check -c .\artifacts\windows-local-client.json
sing-box run -c .\artifacts\windows-local-client.json
```

把示例值换成现场查到的名称或路径。多进程软件还要把服务进程、辅助进程和更新进程一并加入；只改主程序名后仍不命中时，继续用 `show-diagnostics.ps1 -FindProcess` 观察实际发起连接的进程。
