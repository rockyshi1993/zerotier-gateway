# 故障排查

## 找不到配置文件

脚本默认读取项目根目录下的 `.env`。

修复方式：

```bash
bash scripts/ubuntu/init-config.sh
```

Windows：

```powershell
.\scripts\windows\init-config.ps1
```

## ZeroTier 无法连通

检查：

1. 设备已经在 ZeroTier Central 授权。
2. 三台机器的 ZeroTier IP 已按预期固定。
3. Windows 防火墙允许对端 ZeroTier IP 访问远程端口。
4. `10.246.77.0/24` 的路由走 ZeroTier。

运行：

```powershell
.\scripts\windows\test-network.ps1
```

## 代理无法连通

检查：

1. Ubuntu 节点已经拿到 `10.246.77.1`。
2. sing-box 服务正在运行。
3. 代理监听在 `10.246.77.1:10808`。
4. 如果启用了代理认证，用户名和密码正确；如果没启用认证，客户端里不要填写用户名和密码。

运行：

```powershell
.\scripts\windows\test-proxy.ps1
```

## 进程排除没有命中

多进程软件可能会启动服务进程、辅助进程或更新进程。

查找候选进程：

```powershell
.\scripts\windows\show-diagnostics.ps1 -FindProcess "远程"
.\scripts\windows\show-diagnostics.ps1 -FindProcessPath "C:\Program Files\远程工具"
```
