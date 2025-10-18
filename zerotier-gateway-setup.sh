#!/bin/bash

################################################################################
# ZeroTier Linux 网关一键配置脚本
# 功能：
#   1. 通过 ZeroTier 节点的 VPN 上网（全局出站）
#   2. 远程内网穿透（访问私有网络）
#   3. 与 OpenVPN 协同工作（流量分流）
#   4. 可选：自动配置 ZeroTier Central 路由规则（需要 API Token）
#
# 使用场景：在 Linux 服务器/VPS 上部署 ZeroTier 网关
# Windows 客户端：直接使用官方客户端 https://www.zerotier.com/download/
#
# 作者: rockyshi1993
# 日期: 2025-01-18
# 版本: 1.0.1
################################################################################

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# 配置变量
NETWORK_ID=""
API_TOKEN=""
LAN_SUBNETS=""
SKIP_CONFIRM=false
UNINSTALL=false

# 日志函数
log_info() { echo -e "${GREEN}[✓]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[!]${NC} $1"; }
log_error() { echo -e "${RED}[✗]${NC} $1"; }
log_step() { echo -e "${BLUE}[▶]${NC} $1"; }

check_root() {
    [[ $EUID -ne 0 ]] && log_error "需要 root 权限，请使用: sudo bash $0" && exit 1
}

show_help() {
    cat << 'EOF'
ZeroTier Gateway Setup Script v1.0.1

用法: sudo bash zerotier-gateway-setup.sh [选项]

选项:
    -n <ID>     ZeroTier Network ID (16位十六进制，必填)
    -t <TOKEN>  API Token (可选，用于自动配置路由)
    -l <NETS>   内网网段，逗号分隔 (可选，如: 192.168.1.0/24,10.0.0.0/24)
    -y          跳过确认提示
    -u          卸载所有配置
    -h          显示帮助

示例:
    # 基础安装（手动配置路由）
    sudo bash zerotier-gateway-setup.sh -n 1234567890abcdef -y

    # 自动配置路由（推荐）
    sudo bash zerotier-gateway-setup.sh -n 1234567890abcdef -t <API_TOKEN> -y

    # 配置内网穿透
    sudo bash zerotier-gateway-setup.sh -n 1234567890abcdef -l 192.168.1.0/24 -y

    # 卸载
    sudo bash zerotier-gateway-setup.sh -u

API Token 说明:
    • 完全可选，仅用于自动配置路由
    • 免费版支持，无限制
    • 获取: https://my.zerotier.com/account -> API Access Tokens

项目: https://github.com/rockyshi1993/zerotier-gateway
EOF
}

# 参数解析
while [[ $# -gt 0 ]]; do
    case $1 in
        -n) NETWORK_ID="$2"; shift 2 ;;
        -t) API_TOKEN="$2"; shift 2 ;;
        -l) 
            # 验证 CIDR 格式
            for subnet in $(echo "$2" | tr ',' ' '); do
                if ! [[ "$subnet" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}/[0-9]{1,2}$ ]]; then
                    log_error "无效的网段格式: $subnet (应为 CIDR 格式，如 192.168.1.0/24)"
                    exit 1
                fi
            done
            LAN_SUBNETS=$(echo "$2" | tr ',' ' ')
            shift 2 
            ;;
        -y) SKIP_CONFIRM=true; shift ;;
        -u) UNINSTALL=true; shift ;;
        -h|--help) show_help; exit 0 ;;
        *) log_error "未知选项: $1"; show_help; exit 1 ;;
    esac
done

# 卸载功能
if [ "$UNINSTALL" = true ]; then
    check_root
    log_step "卸载 ZeroTier Gateway..."
    systemctl stop zerotier-gateway 2>/dev/null || true
    systemctl disable zerotier-gateway 2>/dev/null || true
    rm -f /usr/local/bin/zerotier-gateway-startup.sh
    rm -f /etc/systemd/system/zerotier-gateway.service
    rm -f /etc/sysctl.d/99-zerotier.conf
    rm -f /etc/zerotier-gateway.conf
    systemctl daemon-reload
    iptables -t nat -F POSTROUTING 2>/dev/null || true
    iptables -F FORWARD 2>/dev/null || true
    log_info "卸载完成"
    exit 0
fi

# 检查必填参数
check_root
if [[ ! "$NETWORK_ID" =~ ^[a-f0-9]{16}$ ]]; then
    log_error "无效的 Network ID (必须是16位十六进制)"
    echo ""
    show_help
    exit 1
fi

log_info "ZeroTier Gateway 安装开始..."
log_info "Network ID: $NETWORK_ID"

# 安装 ZeroTier
log_step "检查 ZeroTier..."
if ! command -v zerotier-cli &>/dev/null; then
    log_step "安装 ZeroTier..."
    log_warn "即将从官方源下载并安装 ZeroTier..."
    if [ "$SKIP_CONFIRM" != true ]; then
        read -p "是否继续? (y/N): " confirm
        [[ ! "$confirm" =~ ^[Yy]$ ]] && log_info "用户取消安装" && exit 0
    fi
    curl -s https://install.zerotier.com | bash
    systemctl enable zerotier-one
    systemctl start zerotier-one
    sleep 3
    log_info "ZeroTier 安装完成"
else
    log_info "ZeroTier 已安装"
    systemctl is-active --quiet zerotier-one || systemctl start zerotier-one
fi

# 加入网络
log_step "加入网络: $NETWORK_ID"
zerotier-cli join "$NETWORK_ID" >/dev/null 2>&1 || true
NODE_ID=$(zerotier-cli info 2>/dev/null | awk '{print $3}')
if [ -z "$NODE_ID" ]; then
    log_error "无法获取 Node ID，ZeroTier 可能未正确启动"
    log_error "请检查: sudo systemctl status zerotier-one"
    exit 1
fi
log_info "Node ID: $NODE_ID"

# 尝试自动授权
if [ -n "$API_TOKEN" ]; then
    log_step "尝试自动授权..."
    HOSTNAME=$(hostname | tr -d '"' | tr -d "'")
    curl -s -X POST -H "Authorization: token $API_TOKEN" \
        -H "Content-Type: application/json" \
        -d '{"config":{"authorized":true},"name":"Gateway-'"$HOSTNAME"'"}' \
        "https://api.zerotier.com/api/v1/network/$NETWORK_ID/member/$NODE_ID" >/dev/null 2>&1 || true
    sleep 2
fi

# 等待授权
log_step "等待授权..."
if ! zerotier-cli listnetworks 2>/dev/null | grep "$NETWORK_ID" | grep -q "OK"; then
    echo ""
    log_warn "请在 ZeroTier Central 授权此设备:"
    echo "  1. 访问: https://my.zerotier.com/network/$NETWORK_ID"
    echo "  2. 找到 Node ID: $NODE_ID"
    echo "  3. 勾选 'Auth' 复选框"
    echo ""
    
    for i in {1..60}; do
        if zerotier-cli listnetworks 2>/dev/null | grep "$NETWORK_ID" | grep -q "OK"; then
            echo ""
            log_info "设备已授权"
            break
        fi
        [ $i -eq 60 ] && log_error "授权超时" && exit 1
        printf "\r  等待授权... %d/60 秒" $i
        sleep 1
    done
else
    log_info "设备已授权"
fi

# 获取网络信息
log_step "获取网络信息..."
sleep 2
ZT_IFACE=$(ip addr | grep -oP 'zt\w+' | head -n 1)
for i in {1..10}; do
    ZT_IP=$(ip -4 addr show "$ZT_IFACE" 2>/dev/null | grep -oP '(?<=inet\s)\d+(\.\d+){3}' || true)
    [ -n "$ZT_IP" ] && break
    sleep 1
done
PHY_IFACE=$(ip route | grep default | awk '{print $5}' | head -n 1)

if [ -z "$ZT_IFACE" ] || [ -z "$ZT_IP" ] || [ -z "$PHY_IFACE" ]; then
    log_error "无法获取网络信息"
    log_error "ZT_IFACE: ${ZT_IFACE:-未找到}, ZT_IP: ${ZT_IP:-未找到}, PHY_IFACE: ${PHY_IFACE:-未找到}"
    exit 1
fi

log_info "ZT 接口: $ZT_IFACE"
log_info "ZT IP: $ZT_IP"
log_info "物理网卡: $PHY_IFACE"

# 启用 IP 转发
log_step "启用 IP 转发..."
sysctl -w net.ipv4.ip_forward=1 >/dev/null
cat > /etc/sysctl.d/99-zerotier.conf << 'EOF'
net.ipv4.ip_forward=1
net.ipv6.conf.all.forwarding=1
EOF
sysctl -p /etc/sysctl.d/99-zerotier.conf >/dev/null
log_info "IP 转发已启用"

# 配置 NAT
log_step "配置 NAT 规则..."
iptables -t nat -D POSTROUTING -o "$PHY_IFACE" -j MASQUERADE 2>/dev/null || true
iptables -t nat -A POSTROUTING -o "$PHY_IFACE" -j MASQUERADE
iptables -D FORWARD -i "$ZT_IFACE" -o "$PHY_IFACE" -j ACCEPT 2>/dev/null || true
iptables -A FORWARD -i "$ZT_IFACE" -o "$PHY_IFACE" -j ACCEPT
iptables -D FORWARD -i "$PHY_IFACE" -o "$ZT_IFACE" -m state --state RELATED,ESTABLISHED -j ACCEPT 2>/dev/null || true
iptables -A FORWARD -i "$PHY_IFACE" -o "$ZT_IFACE" -m state --state RELATED,ESTABLISHED -j ACCEPT
iptables -C INPUT -p udp --dport 9993 -j ACCEPT 2>/dev/null || \
    iptables -A INPUT -p udp --dport 9993 -j ACCEPT
log_info "NAT 规则配置完成"

# 配置内网路由
if [ -n "$LAN_SUBNETS" ]; then
    log_step "配置内网路由..."
    for subnet in $LAN_SUBNETS; do
        ip route add "$subnet" dev "$ZT_IFACE" 2>/dev/null || true
        iptables -t nat -A POSTROUTING -s 10.0.0.0/8 -d "$subnet" -j MASQUERADE 2>/dev/null || true
        log_info "已添加: $subnet"
    done
fi

# 保存 iptables
log_step "保存 iptables 规则..."
OS=$(cat /etc/os-release | grep ^ID= | cut -d= -f2 | tr -d '"')
case $OS in
    ubuntu|debian)
        if command -v netfilter-persistent &>/dev/null; then
            netfilter-persistent save 2>/dev/null || true
        elif command -v iptables-save &>/dev/null; then
            iptables-save > /etc/iptables/rules.v4 2>/dev/null || true
        fi
        ;;
    centos|rhel|rocky|alma|fedora)
        service iptables save 2>/dev/null || true
        ;;
esac
log_info "iptables 规则已保存"

# 创建启动脚本
log_step "创建启动脚本..."
cat > /usr/local/bin/zerotier-gateway-startup.sh << 'SCRIPT'
#!/bin/bash
sleep 5
ZT_IFACE=$(ip addr | grep -oP 'zt\w+' | head -n 1)
PHY_IFACE=$(ip route | grep default | awk '{print $5}' | head -n 1)
[ -z "$ZT_IFACE" ] || [ -z "$PHY_IFACE" ] && exit 0
iptables -t nat -C POSTROUTING -o "$PHY_IFACE" -j MASQUERADE 2>/dev/null || \
    iptables -t nat -A POSTROUTING -o "$PHY_IFACE" -j MASQUERADE
iptables -C FORWARD -i "$ZT_IFACE" -o "$PHY_IFACE" -j ACCEPT 2>/dev/null || \
    iptables -A FORWARD -i "$ZT_IFACE" -o "$PHY_IFACE" -j ACCEPT
iptables -C FORWARD -i "$PHY_IFACE" -o "$ZT_IFACE" -m state --state RELATED,ESTABLISHED -j ACCEPT 2>/dev/null || \
    iptables -A FORWARD -i "$PHY_IFACE" -o "$ZT_IFACE" -m state --state RELATED,ESTABLISHED -j ACCEPT
SCRIPT
chmod +x /usr/local/bin/zerotier-gateway-startup.sh

cat > /etc/systemd/system/zerotier-gateway.service << 'SERVICE'
[Unit]
Description=ZeroTier Gateway
After=zerotier-one.service network.target
Wants=zerotier-one.service

[Service]
Type=oneshot
ExecStart=/usr/local/bin/zerotier-gateway-startup.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
SERVICE

systemctl daemon-reload
systemctl enable zerotier-gateway.service
log_info "启动脚本已创建"

# 自动配置路由
if [ -n "$API_TOKEN" ]; then
    if ! command -v jq &>/dev/null; then
        log_warn "未检测到 jq，无法自动配置路由"
        log_warn "安装 jq:"
        log_warn "  Ubuntu/Debian: sudo apt-get install jq"
        log_warn "  CentOS/RHEL:   sudo yum install jq"
        log_warn "  Fedora:        sudo dnf install jq"
        echo ""
        log_warn "安装 jq 后，可运行以下命令手动配置路由:"
        echo "  curl -X POST -H \"Authorization: token \$API_TOKEN\" \\"
        echo "    -H \"Content-Type: application/json\" \\"
        echo "    -d '{\"config\":{\"routes\":[{\"target\":\"0.0.0.0/0\",\"via\":\"$ZT_IP\"}]}}' \\"
        echo "    \"https://api.zerotier.com/api/v1/network/$NETWORK_ID\""
    else
        log_step "自动配置路由..."
        
        ROUTES=$(curl -s -H "Authorization: token $API_TOKEN" \
            "https://api.zerotier.com/api/v1/network/$NETWORK_ID" | \
            jq -c '.config.routes // []')
        
        NEW_ROUTES=$(echo "$ROUTES" | jq --arg ip "$ZT_IP" \
            '. += [{"target": "0.0.0.0/0", "via": $ip}]')
        
        if [ -n "$LAN_SUBNETS" ]; then
            for subnet in $LAN_SUBNETS; do
                NEW_ROUTES=$(echo "$NEW_ROUTES" | jq --arg subnet "$subnet" --arg ip "$ZT_IP" \
                    '. += [{"target": $subnet, "via": $ip}]')
            done
        fi
        
        FINAL_ROUTES=$(echo "$NEW_ROUTES" | jq 'unique_by(.target)')
        
        curl -s -X POST -H "Authorization: token $API_TOKEN" \
            -H "Content-Type: application/json" \
            -d '{"config":{"routes":'"$FINAL_ROUTES"'}}' \
            "https://api.zerotier.com/api/v1/network/$NETWORK_ID" >/dev/null 2>&1
        
        log_info "路由已自动配置"
    fi
fi

# 保存配置
cat > /etc/zerotier-gateway.conf << EOF
NETWORK_ID=$NETWORK_ID
NODE_ID=$NODE_ID
ZT_IFACE=$ZT_IFACE
ZT_IP=$ZT_IP
PHY_IFACE=$PHY_IFACE
LAN_SUBNETS="$LAN_SUBNETS"
INSTALL_DATE=$(date '+%Y-%m-%d %H:%M:%S')
EOF

# 测试网络连通性
log_step "测试网络连通性..."
if ping -c 2 -W 3 8.8.8.8 &>/dev/null; then
    log_info "网络连通性正常"
elif ping -c 2 -W 3 1.1.1.1 &>/dev/null; then
    log_info "网络连通性正常"
else
    log_warn "无法访问外网，请检查网络配置"
fi

echo ""
log_info "═════════════════════════════════════════"
log_info "✓ 安装完成！"
log_info "═════════════════════════════════════════"
echo ""

if [ -z "$API_TOKEN" ]; then
    echo -e "${YELLOW}下一步操作:${NC}"
    echo ""
    echo "1. 在 ZeroTier Central 手动配置路由:"
    echo "   https://my.zerotier.com/network/$NETWORK_ID"
    echo ""
    echo "   添加以下路由 (Managed Routes):"
    echo "   • 0.0.0.0/0 via $ZT_IP  (全局出站)"
    [ -n "$LAN_SUBNETS" ] && for s in $LAN_SUBNETS; do echo "   • $s via $ZT_IP  (内网)"; done
    echo ""
elif ! command -v jq &>/dev/null; then
    echo -e "${YELLOW}提示: 未安装 jq，路由未自动配置${NC}"
    echo "请手动在 ZeroTier Central 配置路由"
    echo "https://my.zerotier.com/network/$NETWORK_ID"
    echo ""
else
    echo -e "${GREEN}✓ 路由已自动配置${NC}"
    echo "   查看: https://my.zerotier.com/network/$NETWORK_ID"
    echo ""
fi

echo -e "${CYAN}Windows 客户端:${NC}"
echo "  1. 下载: https://www.zerotier.com/download/"
echo "  2. 加入网络: $NETWORK_ID"
echo "  3. 在 ZeroTier Central 授权设备"
echo "  4. (可选) PowerShell: route add 0.0.0.0 mask 0.0.0.0 $ZT_IP metric 10"
echo ""
echo -e "${CYAN}测试连接:${NC}"
echo "  ping $ZT_IP"
echo ""
echo -e "${CYAN}卸载:${NC}"
echo "  sudo bash $0 -u"
echo ""