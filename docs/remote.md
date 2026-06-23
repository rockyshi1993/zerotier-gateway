# 远程访问

远程访问请使用 ZeroTier IP。

默认 IP 规划：

| 设备 | ZeroTier IP |
|---|---|
| Ubuntu 节点 | `10.246.77.1` |
| 家里电脑 | `10.246.77.10` |
| 公司电脑 | `10.246.77.20` |

## 访问方向

公司电脑访问家里电脑：

```text
10.246.77.10
```

家里电脑访问公司电脑：

```text
10.246.77.20
```

## 防火墙

只允许对端 ZeroTier IP 访问远程端口。

预览：

```powershell
.\scripts\windows\set-firewall-rules.ps1 -Role Home
```

应用：

```powershell
.\scripts\windows\set-firewall-rules.ps1 -Role Home -Apply
```

不要把远程桌面或远程控制端口暴露到公网。
