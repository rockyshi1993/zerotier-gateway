# ZeroTier Gateway 一键配置脚本

**通过 ZeroTier 搭建 VPN 网关，支持全局出站、内网穿透、OpenVPN 协同**

[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Shell Script](https://img.shields.io/badge/shell-bash-green.svg)](zerotier-gateway-setup.sh)
[![ZeroTier](https://img.shields.io/badge/ZeroTier-1.12+-orange.svg)](https://www.zerotier.com)
[![Version](https://img.shields.io/badge/version-1.0.1-brightgreen.svg)](https://github.com/rockyshi1993/zerotier-gateway/releases)
[![Maintenance](https://img.shields.io/badge/maintained-yes-green.svg)](https://github.com/rockyshi1993/zerotier-gateway/commits/main)

## 🌟 功能特性

### 核心功能

- ✅ **VPN 全局出站** - 所有客户端流量通过网关节点上网
- ✅ **内网穿透** - 远程访问网关节点所在的局域网设备
- ✅ **OpenVPN 协同** - 支持与 OpenVPN 配合，实现智能流量分流
- ✅ **自动路由配置** - 可选 API Token，自动在 ZeroTier Central 配置路由
- ✅ **一键安装** - 自动化安装和配置，支持多种 Linux 发行版
- ✅ **持久化配置** - 重启后自动恢复配置

### 使用场景

```
┌─────────────┐         ┌──────────────────┐         ┌─────────────┐
│ Windows客户端│────────▶│  ZeroTier 网络   │────────▶│  Linux网关  │
│   (家里)    │         │  (虚拟局域网)    │         │   (VPS)     │
└─────────────┘         └──────────────────┘         └──────┬──────┘
                                                             │
                        ┌────────────────────────────────────┼────────┐
                        │                                    │        │
                        ▼                                    ▼        ▼
                  ┌──────────┐                         ┌─────────┐ ┌──────┐
                  │ 内网设备 │                         │ OpenVPN │ │ 互联网│
                  │192.168.x│                         │特定路由 │ │      │
                  └──────────┘                         └─────────┘ └──────┘
```

## 🚀 快速开始

### 前置要求

- Linux 服务器/VPS (Ubuntu/Debian/CentOS/RHEL/Fedora)
- Root 权限
- ZeroTier 账号 ([免费注册](https://my.zerotier.com))

### 基础安装（3 步完成）

```bash
# 1. 下载脚本
wget https://raw.githubusercontent.com/rockyshi1993/zerotier-gateway/main/zerotier-gateway-setup.sh

# 2. 添加执行权限
chmod +x zerotier-gateway-setup.sh

# 3. 运行安装（替换为你的 Network ID）
sudo bash zerotier-gateway-setup.sh -n YOUR_NETWORK_ID -y
```

### 获取 Network ID

1. 访问 [ZeroTier Central](https://my.zerotier.com)
2. 点击 **Create A Network**
3. 复制 **Network ID** (16位十六进制字符，如: `1234567890abcdef`)

### 获取 API Token（可选）

如果想要自动配置路由，获取 API Token：

1. 访问 [ZeroTier Account](https://my.zerotier.com/account)
2. 滚动到 **API Access Tokens** 部分
3. 在 **New Token** 输入框填写名称（如: `gateway-script`）
4. 点击 **Generate**
5. 复制生成的 Token（只显示一次，请妥善保存）

⚠️ **注意**: 
- API Token 完全可选，仅用于自动配置路由
- 免费版完全支持，无任何限制
- 丢失后需要重新生成

## 📖 使用说明

### 命令选项

```bash
sudo bash zerotier-gateway-setup.sh [选项]

选项:
    -n <ID>     ZeroTier Network ID (16位十六进制，必填)
    -t <TOKEN>  API Token (可选，用于自动配置路由)
    -l <NETS>   内网网段，逗号分隔 (可选)
    -y          跳过确认提示
    -u          卸载所有配置
    -h          显示帮助
```

### 使用示例

#### 1️⃣ 基础 VPN 网关（手动配置路由）

```bash
sudo bash zerotier-gateway-setup.sh -n 1234567890abcdef -y
```

**执行后需要手动配置:**
1. 访问 `https://my.zerotier.com/network/YOUR_NETWORK_ID`
2. 在 **Managed Routes** 部分点击 **Add Routes**
3. 添加路由: `0.0.0.0/0` via `网关的ZT IP地址`

#### 2️⃣ 自动配置路由（推荐✨）

```bash
# 获取 API Token: https://my.zerotier.com/account -> API Access Tokens
sudo bash zerotier-gateway-setup.sh -n 1234567890abcdef -t YOUR_API_TOKEN -y
```

✅ **脚本会自动配置路由，无需手动操作**

#### 3️⃣ VPN + 内网穿透

```bash
# 同时启用 VPN 和访问 192.168.1.0/24 网段
sudo bash zerotier-gateway-setup.sh -n 1234567890abcdef -l 192.168.1.0/24 -y
```

⚠️ **内网穿透要求**:
- 网关节点必须在内网环境，或通过其他方式能访问内网
- 如果网关是公网 VPS，无法直接访问你的家庭/办公室内网

#### 4️⃣ 多个内网网段

```bash
sudo bash zerotier-gateway-setup.sh \
  -n 1234567890abcdef \
  -l 192.168.1.0/24,10.0.0.0/24,172.16.0.0/16 \
  -y
```

#### 5️⃣ 完整配置（自动路由 + 内网穿透）

```bash
sudo bash zerotier-gateway-setup.sh \
  -n 1234567890abcdef \
  -t YOUR_API_TOKEN \
  -l 192.168.1.0/24,10.0.0.0/24 \
  -y
```

#### 6️⃣ 卸载

```bash
sudo bash zerotier-gateway-setup.sh -u
```

## 🔍 如何确定内网网段

### 方法一：Linux 系统查看

```bash
# 查看所有网络接口和 IP 地址
ip addr show

# 或者使用传统命令
ifconfig

# 查看路由表（找局域网网段）
ip route show
```

**输出示例：**
```
2: eth0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500
    inet 192.168.1.100/24 brd 192.168.1.255 scope global eth0
```

**解读：**
- `192.168.1.100/24` 表示当前 IP 是 192.168.1.100
- `/24` 表示子网掩码 255.255.255.0
- **内网网段就是：`192.168.1.0/24`**

### 方法二：Windows 系统查看

```powershell
# 查看网络配置
ipconfig

# 详细信息
ipconfig /all
```

**输出示例：**
```
以太网适配器 以太网:
   IPv4 地址 . . . . . . . . . : 192.168.1.100
   子网掩码 . . . . . . . . . : 255.255.255.0
   默认网关 . . . . . . . . . : 192.168.1.1
```

**换算方法：**
- IP: 192.168.1.100
- 子网掩码: 255.255.255.0 = /24
- **内网网段：`192.168.1.0/24`**

### 方法三：macOS 系统查看

```bash
# 查看网络配置
ifconfig | grep "inet "

# 输出示例：
# inet 192.168.1.100 netmask 0xffffff00 broadcast 192.168.1.255
# 0xffffff00 = 255.255.255.0 = /24
```

### 方法四：路由器管理界面

1. 访问路由器管理页面（常见地址）：
   - `http://192.168.1.1` (TP-Link/D-Link)
   - `http://192.168.0.1` (Netgear)
   - `http://192.168.31.1` (小米路由器)
   - `http://192.168.3.1` (华为路由器)
   - `http://tplogin.cn` (TP-Link 中国)

2. 查看 **LAN 设置** 或 **局域网设置**
3. 找到 **IP 地址段** 或 **DHCP 地址池**

### 子网掩码对照表

| 子网掩码 | CIDR | 可用 IP 数 | 常见场景 |
|---------|------|-----------|---------|
| 255.255.255.0 | /24 | 254 | 家庭网络 |
| 255.255.254.0 | /23 | 510 | 小型企业 |
| 255.255.252.0 | /22 | 1022 | 中型企业 |
| 255.255.0.0 | /16 | 65534 | 大型企业 |
| 255.0.0.0 | /8 | 16777214 | 超大型网络 |

### 常见内网网段表

| 网段类型 | CIDR 格式 | IP 范围 | 可用 IP 数量 | 常见场景 |
|---------|-----------|---------|-------------|---------|
| C类私网 | 192.168.1.0/24 | 192.168.1.1 - 192.168.1.254 | 254 | 家庭/小型办公室 |
| C类私网(大) | 192.168.0.0/16 | 192.168.0.1 - 192.168.255.254 | 65534 | 企业内网 |
| A类私网 | 10.0.0.0/8 | 10.0.0.1 - 10.255.255.254 | 16777214 | 大型企业 |
| B类私网 | 172.16.0.0/12 | 172.16.0.1 - 172.31.255.254 | 1048574 | 中型企业 |

### 实际应用示例

#### 场景 1：家庭网络穿透

**需求：** 远程访问家里的 NAS (192.168.1.50)

```bash
# 1. 在家里的电脑上确认网段
ip addr show | grep "inet "
# 输出：inet 192.168.1.100/24

# 2. 在家里的 Linux 机器上安装网关（不是 VPS！）
sudo bash zerotier-gateway-setup.sh \
  -n 1234567890abcdef \
  -l 192.168.1.0/24 \
  -y

# 3. 现在在外面可以通过 ZeroTier 访问家里的 NAS
ping 192.168.1.50
ssh user@192.168.1.50
```

#### 场景 2：办公室网络访问

**需求：** 在家访问办公室的内网服务器 (10.0.0.50)

```bash
# 在办公室的 Linux 服务器上安装
sudo bash zerotier-gateway-setup.sh \
  -n 1234567890abcdef \
  -l 10.0.0.0/24 \
  -y

# 在家通过 ZeroTier 客户端加入网络后即可访问
ping 10.0.0.50
```

#### 场景 3：多地网络互联

**需求：** 同时访问家里 (192.168.1.0/24) 和办公室 (10.0.0.0/24)

```bash
# 方案 1：在一台机器上配置多个网段（该机器需要能访问两个网络）
sudo bash zerotier-gateway-setup.sh \
  -n 1234567890abcdef \
  -l 192.168.1.0/24,10.0.0.0/24 \
  -y

# 方案 2：分别在两个地方各安装一个网关（推荐）
# 家里机器：
sudo bash zerotier-gateway-setup.sh -n 1234567890abcdef -l 192.168.1.0/24 -y

# 办公室机器：
sudo bash zerotier-gateway-setup.sh -n 1234567890abcdef -l 10.0.0.0/24 -y
```

### 快速验证

```bash
# 1. 在网关节点查看路由是否添加成功
ip route show | grep zt
# 应该看到：192.168.1.0/24 dev zt0 scope link

# 2. 从客户端测试
ping <网关ZT IP>        # 测试网关连通性
ping 192.168.1.1        # 测试内网网关
ping 192.168.1.50       # 测试内网设备

# 3. 使用 traceroute 查看路径
traceroute 192.168.1.50
# 应该看到流量经过 ZeroTier 网关
```

### ⚠️ 常见错误

| 错误现象 | 可能原因 | 解决方案 |
|---------|---------|---------|
| 无法访问内网 | 网段填错 | 检查确认正确的网段 |
| ping 不通 | 网关不在内网 | 网关必须能访问目标内网 |
| 部分 IP 不通 | 网段范围太小 | 使用更大的网段如 /16 |
| 路由冲突 | 客户端也在相同网段 | 修改客户端本地网段 |

## 💻 客户端配置

### Windows 客户端

#### 1. 安装 ZeroTier

- 下载: [https://www.zerotier.com/download/](https://www.zerotier.com/download/)
- 双击安装包，以管理员权限安装

#### 2. 加入网络

- 打开 ZeroTier 客户端（系统托盘图标）
- 右键点击图标 → **Join New Network**
- 输入 Network ID
- 点击 **Join**

#### 3. 授权设备

- 访问 `https://my.zerotier.com/network/YOUR_NETWORK_ID`
- 在 **Members** 部分找到新加入的设备
- 勾选 **Auth** 复选框
- （可选）设置设备名称

#### 4. （可选）配置全局路由

如果想让所有流量通过 ZeroTier 网关：

以**管理员权限**运行 PowerShell:

```powershell
# 添加默认路由（所有流量通过 ZeroTier）
route add 0.0.0.0 mask 0.0.0.0 <网关ZT IP> metric 10

# 示例
route add 0.0.0.0 mask 0.0.0.0 10.147.20.1 metric 10

# 查看路由表
route print

# 删除路由
route delete 0.0.0.0 mask 0.0.0.0 <网关ZT IP>
```

### macOS 客户端

```bash
# 1. 安装 ZeroTier
brew install --cask zerotier-one
# 或从官网下载: https://www.zerotier.com/download/

# 2. 加入网络
sudo zerotier-cli join YOUR_NETWORK_ID

# 3. 查看状态
sudo zerotier-cli listnetworks

# 4. （可选）配置全局路由
sudo route add default <网关ZT IP> -interface <ZT接口>
```

### Linux 客户端

```bash
# 1. 安装 ZeroTier
curl -s https://install.zerotier.com | sudo bash

# 2. 加入网络
sudo zerotier-cli join YOUR_NETWORK_ID

# 3. 查看状态
sudo zerotier-cli listnetworks

# 4. 查看接口信息
ip addr show | grep zt

# 5. （可选）配置全局路由
sudo ip route add default via <网关ZT IP> dev <ZT接口> metric 100
```

### Android/iOS 客户端

1. 在应用商店搜索并安装 **ZeroTier One**
2. 打开应用，点击 **+** 添加网络
3. 输入 Network ID 并加入
4. 在 ZeroTier Central 授权设备

## 🔧 高级配置

### OpenVPN 协同（流量分流）

**场景**: 企业内网走 OpenVPN，其他流量走 ZeroTier

```bash
# 1. 先安装基础 ZeroTier Gateway
sudo bash zerotier-gateway-setup.sh -n 1234567890abcdef -y

# 2. 手动配置策略路由
# 创建路由表
echo "101 openvpn" | sudo tee -a /etc/iproute2/rt_tables

# 添加 OpenVPN 路由
sudo ip route add 10.10.0.0/16 dev tun0 table openvpn
sudo ip rule add to 10.10.0.0/16 table openvpn priority 50

# 确保本地流量优先
sudo ip rule add from all lookup main priority 10
```

### 防火墙配置

#### UFW (Ubuntu/Debian)

```bash
# 允许 ZeroTier 端口
sudo ufw allow 9993/udp

# 启用转发
sudo ufw default allow routed

# 重新加载
sudo ufw reload
```

#### firewalld (CentOS/RHEL/Fedora)

```bash
# 允许 ZeroTier 端口
sudo firewall-cmd --permanent --add-port=9993/udp

# 启用 IP 伪装
sudo firewall-cmd --permanent --add-masquerade

# 重新加载
sudo firewall-cmd --reload
```

### 性能优化

```bash
# 1. 调整 MTU（如果遇到连接问题）
sudo ip link set <ZT接口> mtu 1280

# 2. 启用 TCP BBR（提升速度）
echo "net.core.default_qdisc=fq" | sudo tee -a /etc/sysctl.conf
echo "net.ipv4.tcp_congestion_control=bbr" | sudo tee -a /etc/sysctl.conf
sudo sysctl -p

# 3. 增加连接跟踪表大小（高并发场景）
echo "net.netfilter.nf_conntrack_max=262144" | sudo tee -a /etc/sysctl.conf
sudo sysctl -p
```

### 自定义 Moon 节点（加速）

```bash
# 1. 在网关节点生成 Moon 配置
sudo zerotier-idtool initmoon /var/lib/zerotier-one/identity.public > moon.json

# 2. 编辑 moon.json，添加公网 IP
# 3. 生成 Moon 文件
sudo zerotier-idtool genmoon moon.json

# 4. 移动到配置目录
sudo mkdir -p /var/lib/zerotier-one/moons.d
sudo mv *.moon /var/lib/zerotier-one/moons.d/

# 5. 重启服务
sudo systemctl restart zerotier-one

# 6. 客户端使用 Moon
sudo zerotier-cli orbit <MOON_ID> <MOON_ID>
```

## 🐛 故障排查

### 问题 1: 无法访问互联网

```bash
# 检查 ZeroTier 状态
sudo zerotier-cli listnetworks
# 应该看到状态为 "OK"

# 检查 IP 转发
sysctl net.ipv4.ip_forward
# 应该返回 "net.ipv4.ip_forward = 1"

# 检查 NAT 规则
sudo iptables -t nat -L -n -v | grep MASQUERADE
# 应该看到 MASQUERADE 规则

# 检查路由
ip route
# 应该看到默认路由

# 测试网关连通性
ping <网关ZT IP>
```

### 问题 2: 无法访问内网设备

```bash
# 检查内网路由
ip route show | grep <内网网段>

# 在网关节点测试能否访问内网
ping <内网设备IP>

# 在网关抓包
sudo tcpdump -i <ZT接口> icmp

# 检查内网设备防火墙
# 确保内网设备允许来自 ZeroTier 网段的访问

# 测试内网连通性
ping <内网设备IP>
traceroute <内网设备IP>
```

### 问题 3: 客户端无法连接到 ZeroTier

1. **检查授权状态**
   - 访问 ZeroTier Central
   - 确认设备已勾选 Auth

2. **检查防火墙**
   ```bash
   # 确保 9993/UDP 端口开放
   sudo netstat -uln | grep 9993
   ```

3. **查看日志**
   ```bash
   # Linux
   sudo journalctl -u zerotier-one -f
   
   # Windows
   # 查看 C:\ProgramData\ZeroTier\One\service.log
   ```

### 问题 4: 路由配置不生效

```bash
# 重启 ZeroTier 服务
sudo systemctl restart zerotier-one
sudo systemctl restart zerotier-gateway

# 查看配置文件
cat /etc/zerotier-gateway.conf

# 手动重新应用规则
sudo /usr/local/bin/zerotier-gateway-startup.sh

# 检查 iptables 规则
sudo iptables -t nat -L -n -v
sudo iptables -L FORWARD -n -v
```

### 问题 5: 速度慢

```bash
# 1. 检查是否建立了直连（P2P）
sudo zerotier-cli peers
# 查找你的目标节点，延迟应该在几十毫秒

# 2. 使用 iperf3 测速
# 服务端
iperf3 -s

# 客户端
iperf3 -c <网关ZT IP>

# 3. 检查 MTU
ping -M do -s 1472 <网关ZT IP>
# 如果失败，尝试降低 MTU
```

## 📊 架构说明

### 网络拓扑

```
Internet
   │
   │ (公网 IP)
   │
   ▼
[Linux Gateway/VPS]
   │
   ├─ eth0 (物理网卡 - 公网/局域网)
   │   └─ 123.456.789.0
   │
   ├─ zt0 (ZeroTier 虚拟网卡)
   │   └─ 10.147.20.1/16 (ZeroTier IP)
   │
   └─ (可选) 本地局域网
       └─ 192.168.1.0/24
```

### iptables 规则链

```bash
# 1. NAT 转发（核心规则）
iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
# 将所有从 eth0 出去的数据包进行源地址转换

# 2. 允许 ZeroTier → 外网
iptables -A FORWARD -i zt0 -o eth0 -j ACCEPT
# 允许从 ZeroTier 接口到物理网卡的数据包转发

# 3. 允许外网 → ZeroTier (已建立的连接)
iptables -A FORWARD -i eth0 -o zt0 -m state --state RELATED,ESTABLISHED -j ACCEPT
# 只允许已建立连接的返回数据包
```

### ZeroTier Central 路由配置

在 https://my.zerotier.com/network/YOUR_NETWORK_ID 的 **Managed Routes** 配置：

```
Destination         Via             Description
───────────────────────────────────────────────────────
0.0.0.0/0          10.147.20.1     全局出站（VPN）
192.168.1.0/24     10.147.20.1     内网访问
10.0.0.0/24        10.147.20.1     内网访问
```

### 数据流向

```
客户端 (192.168.0.100)
   │
   │ 发送数据包到 google.com
   │ 目标: 172.217.160.46:443
   │ 源: 192.168.0.100
   │
   ▼
ZeroTier 网络 (加密隧道)
   │ 源: 10.147.20.5 (客户端 ZT IP)
   │ 目标: 172.217.160.46:443
   │
   ▼
Linux Gateway (10.147.20.1)
   │ zt0 接收数据
   │
   ├─ iptables FORWARD 检查 ✓
   │
   ├─ iptables NAT (MASQUERADE)
   │  将源 IP 改为网关公网 IP
   │  源: 123.456.789.0
   │  目标: 172.217.160.46:443
   │
   ▼
eth0 (物理网卡)
   │
   ▼
Internet → Google 服务器

(返回数据包按相反路径返回)
```

## 🔐 安全建议

### 1. 最小权限原则

- 仅授权必要的设备加入网络
- 定期审查 ZeroTier Central 的设备列表
- 移除不再使用的设备

### 2. 使用防火墙

```bash
# 限制只允许特定网段访问
iptables -A FORWARD -i zt0 -s 10.147.20.0/24 -j ACCEPT
iptables -A FORWARD -i zt0 -j DROP

# 限制访问特定端口
iptables -A FORWARD -i zt0 -p tcp --dport 22 -j DROP  # 禁止 SSH
```

### 3. 启用双因素认证

在 ZeroTier Central 账户设置中启用 2FA

### 4. 监控流量

```bash
# 安装 iftop
sudo apt-get install iftop  # Ubuntu/Debian
sudo yum install iftop      # CentOS/RHEL

# 监控 ZeroTier 接口
sudo iftop -i <ZT接口>

# 查看连接统计
sudo iptables -t nat -L -n -v
sudo iptables -L FORWARD -n -v
```

### 5. 定期更新

```bash
# 更新 ZeroTier
curl -s https://install.zerotier.com | sudo bash

# 更新系统
sudo apt update && sudo apt upgrade  # Ubuntu/Debian
sudo yum update                       # CentOS/RHEL
```

## ❓ 常见问题 (FAQ)

### Q1: API Token 是必需的吗？

**A:** **不是**。API Token 完全可选，仅用于自动配置路由。

- ✅ **有 Token**: 脚本自动在 ZeroTier Central 配置路由
- ✅ **无 Token**: 脚本显示详细的手动配置步骤

两种方式最终效果相同。

### Q2: 免费版支持 API Token 吗？

**A:** **是的**。ZeroTier 免费版完全支持 API Token，无任何限制。

### Q3: 支持哪些Linux发行版？

**A:** 
- ✅ Ubuntu 18.04+
- ✅ Debian 10+
- ✅ CentOS 7+
- ✅ RHEL 7+
- ✅ Fedora 30+
- ✅ Rocky Linux 8+
- ✅ AlmaLinux 8+

### Q4: 如何检查是否配置成功？

**A:** 从客户端执行：

```bash
# 1. Ping 网关
ping <网关ZT IP>

# 2. 测试外网访问
curl -I http://www.google.com

# 3. 测试内网访问（如果配置了）
ping <内网设备IP>
```

### Q5: 性能如何？延迟多少？

**A:** 
- **直连 (P2P)**: 延迟 10-50ms，速度取决于带宽
- **中继连接**: 延迟 50-200ms
- **建议**: 配置 Moon 节点可显著提升速度

### Q6: 可以同时运行多个网关吗？

**A:** 可以。但需要注意：
- 不同网关使用不同的 ZeroTier IP
- 客户端需要手动选择使用哪个网关
- 或使用路由优先级

### Q7: 如何查看流量统计？

```bash
# 查看接口流量
ip -s link show <ZT接口>

# 使用 vnstat（需要安装）
sudo apt-get install vnstat
vnstat -i <ZT接口>

# 实时监控
sudo iftop -i <ZT接口>
```

### Q8: 支持 IPv6 吗？

**A:** ZeroTier 支持 IPv6，但本脚本主要配置 IPv4。如需 IPv6:

```bash
# 启用 IPv6 转发
sudo sysctl -w net.ipv6.conf.all.forwarding=1

# 配置 IPv6 NAT（需要内核 3.7+）
sudo ip6tables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
```

### Q9: 如何备份配置？

```bash
# 备份配置文件
sudo cp /etc/zerotier-gateway.conf ~/zerotier-gateway-backup.conf

# 导出 iptables 规则
sudo iptables-save > ~/iptables-backup.rules

# 备份 ZeroTier 身份
sudo cp -r /var/lib/zerotier-one ~/zerotier-one-backup
```

### Q10: 如何迁移到新服务器？

```bash
# 1. 在旧服务器导出配置
sudo cat /etc/zerotier-gateway.conf
sudo iptables-save > iptables.rules

# 2. 在新服务器安装
sudo bash zerotier-gateway-setup.sh -n YOUR_NETWORK_ID -y

# 3. （可选）复制 ZeroTier 身份保持相同 Node ID
sudo systemctl stop zerotier-one
sudo cp -r ~/zerotier-one-backup/* /var/lib/zerotier-one/
sudo systemctl start zerotier-one
```

### Q11: 内网穿透时网关应该放在哪里？

**A:** 网关节点**必须**能访问到目标内网，有以下几种部署方案：

#### 方案 1：网关在内网（推荐）
```
[家里内网] ← 网关在这里
  ├─ 网关服务器 (运行脚本)
  ├─ NAS (192.168.1.50)
  └─ 其他设备

外网客户端 → ZeroTier → 网关 → 内网设备 ✅
```

#### 方案 2：公网 VPS + VPN 连接内网
```
[公网 VPS] ← 网关在这里
     │
     │ (通过 OpenVPN/WireGuard 连接)
     ▼
[家里内网]
  ├─ NAS (192.168.1.50)
  └─ 其他设备

外网客户端 → ZeroTier → VPS网关 → VPN → 内网设备 ✅
```

#### 方案 3：公网 VPS 直接访问（不推荐）
```
[公网 VPS] ← 网关在这里
     │
     ✗ (无法直接访问内网)
     
[家里内网] ← 无法访问 ❌
```

### Q12: 内网穿透不通怎么办？

**A:** 按以下步骤排查：

```bash
# 1. 在网关节点测试能否访问内网
ping 192.168.1.50
# 如果不通，说明网关无法访问内网

# 2. 检查网关的路由
ip route show | grep 192.168.1.0
# 应该看到：192.168.1.0/24 dev zt0

# 3. 从客户端 traceroute
traceroute 192.168.1.50
# 查看数据包是否到达网关

# 4. 在网关抓包
sudo tcpdump -i zt0 -n icmp
# 然后从客户端 ping，看是否收到数据包

# 5. 检查内网设备防火墙
# 确保内网设备允许来自 ZeroTier 网段的访问
```

## 📚 参考资源

### 官方文档

- [ZeroTier 官方文档](https://docs.zerotier.com/)
- [ZeroTier GitHub](https://github.com/zerotier/ZeroTierOne)
- [ZeroTier Central](https://my.zerotier.com)

### 技术资料

- [iptables 教程](https://www.netfilter.org/documentation/)
- [Linux 高级路由](https://lartc.org/howto/)
- [systemd 服务管理](https://www.freedesktop.org/software/systemd/man/systemd.service.html)

### 相关项目

- [ZeroTier Moon](https://docs.zerotier.com/zerotier/moons) - 自建 Planet 根服务器
- [zerotier-docker](https://github.com/zerotier/ZeroTierOne/tree/master/docker) - Docker 部署
- [zerotier-openwrt](https://github.com/mwarning/zerotier-openwrt) - OpenWrt 支持

## 🤝 贡献

欢迎贡献代码、提交 Issue 或改进文档！

### 如何贡献

1. Fork 本仓库
2. 创建特性分支 (`git checkout -b feature/AmazingFeature`)
3. 提交更改 (`git commit -m 'Add some AmazingFeature'`)
4. 推送到分支 (`git push origin feature/AmazingFeature`)
5. 开启 Pull Request

### 贡献者

感谢所有为本项目做出贡献的开发者！

## 📄 许可证

本项目采用 MIT 许可证 - 详见 [LICENSE](LICENSE) 文件

## 👤 作者

**rockyshi1993**

- GitHub: [@rockyshi1993](https://github.com/rockyshi1993)
- 项目主页: [zerotier-gateway](https://github.com/rockyshi1993/zerotier-gateway)

## 📮 联系方式

如有问题或建议，请通过以下方式联系：

- 提交 [Issue](https://github.com/rockyshi1993/zerotier-gateway/issues)
- 参与 [Discussions](https://github.com/rockyshi1993/zerotier-gateway/discussions)

---

## 📝 更新日志

### v1.0.1 (2025-01-18)

#### 🐛 Bug 修复
- 修复 API 路由配置 JSON 拼接错误（阻断性问题）
- 修复 hostname 命令注入安全风险
- 修复 iptables 规则重复添加问题
- 修复 NODE_ID 获取失败时未正确处理

#### ✨ 新增功能
- 添加 CIDR 网段格式验证
- 添加 jq 依赖检查和友好提示
- 添加网络连通性自动测试
- 添加 ZeroTier 安装确认提示

#### 🔧 优化改进
- 改进错误提示信息（显示详细诊断）
- 优化 iptables 保存逻辑
- 完善异常情况处理

### v1.0.0 (2025-01-18)

- ✨ 初始版本发布
- ✅ 支持 VPN 全局出站
- ✅ 支持内网穿透
- ✅ 支持 API Token 自动配置路由
- ✅ 支持一键安装/卸载
- ✅ 支持多种 Linux 发行版

---

⭐ **如果这个项目对你有帮助，请给个 Star！**

🔗 **项目地址**: https://github.com/rockyshi1993/zerotier-gateway