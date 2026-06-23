# 安装指南

## 概览

本项目使用一个 ZeroTier 私有局域网完成三件事：

1. Ubuntu 节点作为私有代理节点。
2. 家里电脑和公司电脑作为互相远程的节点。
3. 只有直连质量长期较差时，才启用中转兜底。

## 1. 获取仓库

Ubuntu：

```bash
git clone https://github.com/rockyshi1993/zerotier-gateway.git
cd zerotier-gateway
```

Windows PowerShell：

```powershell
git clone https://github.com/rockyshi1993/zerotier-gateway.git
cd .\zerotier-gateway
```

## 2. 准备 `.env`

复制配置样例：

```bash
cp config/example.env .env
```

Windows：

```powershell
Copy-Item .\config\example.env .\.env
```

编辑 `.env`，至少填写：

```text
ZEROTIER_NETWORK_ID=
PROXY_USERNAME=
PROXY_PASSWORD=
```

脚本默认读取项目根目录下的 `.env`。只有配置文件不在项目根目录，或你要临时使用另一份配置时，才需要传 `--env <path>` 或 `-Env <path>`。

## 3. Ubuntu

先预览：

```bash
sudo bash scripts/ubuntu/install.sh --dry-run
```

确认无误后安装：

```bash
sudo bash scripts/ubuntu/install.sh
```

然后到 ZeroTier Central 授权 Ubuntu 节点，并把它的托管 IP 固定为 `10.246.77.1`。

检查状态：

```bash
sudo bash scripts/ubuntu/health-check.sh
```

## 4. Windows

以管理员身份打开 PowerShell。

家里电脑：

```powershell
.\scripts\windows\setup.ps1 -Role Home
```

公司电脑：

```powershell
.\scripts\windows\setup.ps1 -Role Work
```

脚本会先打印防火墙计划。确认计划正确后，再追加 `-ApplyFirewall` 真正写入规则：

```powershell
.\scripts\windows\setup.ps1 -Role Home -ApplyFirewall
```

## 5. 验证

```powershell
.\scripts\windows\test-network.ps1
.\scripts\windows\test-proxy.ps1
```
