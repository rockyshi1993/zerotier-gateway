#!/bin/bash

################################################################################
# ZeroTier Linux 网关一键配置脚本 (智能增强版)
# 版本: 1.2.1 - 优化进度显示和用户体验
# 作者: rockyshi1993
# 日期: 2025-10-18
################################################################################

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m'

# 配置变量
NETWORK_ID=""
API_TOKEN=""
LAN_SUBNETS=""
SKIP_CONFIRM=false
UNINSTALL=false
AUTO_DETECT_LAN=false
BACKUP_DIR="/var/backups/zerotier-gateway"

# 进度跟踪变量
TOTAL_STEPS=12
CURRENT_STEP=0
STEP_START_TIME=0

# 日志函数
log_info() { echo -e "${GREEN}[✓]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[!]${NC} $1"; }
log_error() { echo -e "${RED}[✗]${NC} $1"; }
log_step() { echo -e "${BLUE}[▶]${NC} $1"; }

# 进度显示函数
show_progress() {
    local step=$1
    local total=$2
    local description=$3
    local percent=$((step * 100 / total))
    
    # 创建进度条
    local bar_width=50
    local filled=$((bar_width * step / total))
    local bar=""
    
    for ((i=0; i<filled; i++)); do bar="${bar}█"; done
    for ((i=filled; i<bar_width; i++)); do bar="${bar}░"; done
    
    # 显示进度
    echo ""
    echo -e "${CYAN}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${NC} 安装进度: ${MAGENTA}[$bar]${NC} ${GREEN}${percent}%${NC}"
    echo -e "${CYAN}║${NC} 步骤 ${YELLOW}$step${NC}/${YELLOW}$total${NC}: $description"
    echo -e "${CYAN}╚════════════════════════════════════════════════════════════════╝${NC}"
}

# 步骤开始
step_start() {
    ((CURRENT_STEP++))
    STEP_START_TIME=$(date +%s)
    show_progress "$CURRENT_STEP" "$TOTAL_STEPS" "$1"
    sleep 0.3  # 短暂延迟，确保进度条可见
}

# 步骤完成
step_done() {
    local elapsed=$(($(date +%s) - STEP_START_TIME))
    log_info "$1 (耗时: ${elapsed}秒)"
}

check_root() {
    [[ $EUID -ne 0 ]] && log_error "需要 root 权限，请使用: sudo bash $0" && exit 1
}

show_help() {
    cat << 'EOF'
ZeroTier Gateway Setup Script v1.2.1 (优化版)

用法: sudo bash zerotier-gateway-setup.sh [选项]

选项:
    -n <ID>     ZeroTier Network ID (16位十六进制，必填)
    -t <TOKEN>  API Token (可选，用于自动配置路由)
    -l <NETS>   内网网段，逗号分隔 (可选，如: 192.168.1.0/24,10.0.0.0/24)
    -a          自动检测内网网段
    -y          跳过所有确认提示（快速安装）
    -u          卸载所有配置
    -h          显示帮助

示例:
    # 标准安装（推荐 - 有进度和确认）
    sudo bash zerotier-gateway-setup.sh -n 1234567890abcdef -a

    # 快速安装（跳过确认）
    sudo bash zerotier-gateway-setup.sh -n 1234567890abcdef -a -y

    # 完全自动化（API Token + 自动检测 + 跳过确认）
    sudo bash zerotier-gateway-setup.sh -n 1234567890abcdef -t YOUR_TOKEN -a -y

新功能 (v1.2.1):
    ✨ 详细的实时进度显示
    ✨ 每步骤耗时统计
    ✨ 可视化进度条（50字符宽）
    ✨ 彩色输出增强可读性
    ✨ 优化确认流程

项目: https://github.com/rockyshi1993/zerotier-gateway
EOF
}

# ==================== 新增功能 ====================

# 备份现有配置
backup_config() {
    step_start "备份现有配置"
    
    mkdir -p "$BACKUP_DIR"
    
    local timestamp=$(date +%Y%m%d-%H%M%S)
    
    # 备份 iptables 规则
    echo -n "  正在备份 iptables 规则... "
    if command -v iptables-save &>/dev/null; then
        iptables-save > "$BACKUP_DIR/iptables-${timestamp}.rules" 2>/dev/null || true
        echo -e "${GREEN}完成${NC}"
    else
        echo -e "${YELLOW}跳过${NC}"
    fi
    
    # 备份路由表
    echo -n "  正在备份路由表... "
    ip route save > "$BACKUP_DIR/routes-${timestamp}.dump" 2>/dev/null || true
    echo -e "${GREEN}完成${NC}"
    
    # 备份现有配置文件
    if [ -f /etc/zerotier-gateway.conf ]; then
        echo -n "  正在备份配置文件... "
        cp /etc/zerotier-gateway.conf "$BACKUP_DIR/zerotier-gateway-${timestamp}.conf"
        echo -e "${GREEN}完成${NC}"
    fi
    
    # 清理旧备份（保留最近5个）
    echo -n "  正在清理旧备份... "
    find "$BACKUP_DIR" -name "iptables-*.rules" -type f | sort -r | tail -n +6 | xargs rm -f 2>/dev/null || true
    find "$BACKUP_DIR" -name "routes-*.dump" -type f | sort -r | tail -n +6 | xargs rm -f 2>/dev/null || true
    echo -e "${GREEN}完成${NC}"
    
    step_done "配置备份完成"
}

# 错误回滚
rollback_on_error() {
    log_error "安装失败 (第 $1 行)，正在回滚..."
    
    echo -n "  正在恢复 iptables... "
    local latest_backup=$(ls -t "$BACKUP_DIR"/iptables-*.rules 2>/dev/null | head -1)
    if [ -f "$latest_backup" ]; then
        iptables-restore < "$latest_backup" 2>/dev/null || true
        echo -e "${GREEN}完成${NC}"
    else
        echo -e "${YELLOW}无备份${NC}"
    fi
    
    echo -n "  正在清理安装文件... "
    rm -f /usr/local/bin/zerotier-gateway-startup.sh
    rm -f /etc/systemd/system/zerotier-gateway.service
    rm -f /etc/sysctl.d/99-zerotier.conf
    systemctl daemon-reload 2>/dev/null || true
    echo -e "${GREEN}完成${NC}"
    
    log_error "回滚完成，请检查错误后重试"
    exit 1
}

setup_error_handling() {
    trap 'rollback_on_error $LINENO' ERR
}

# 自动检测内网网段
auto_detect_lan_subnets() {
    step_start "自动检测内网网段"
    
    local detected_subnets=""
    local temp_file=$(mktemp)
    local count=0
    
    echo "  正在扫描网络接口..."
    
    # 获取所有非回环、非 ZeroTier 的私有 IP 网段
    ip -4 addr show | grep "inet " | grep -v "127.0.0.1" | grep -v "zt" | \
        awk '{print $2}' | while read -r cidr; do
        local ip=$(echo "$cidr" | cut -d'/' -f1)
        local mask=$(echo "$cidr" | cut -d'/' -f2)
        
        # 检查是否为私有 IP
        if [[ "$ip" =~ ^192\.168\. ]] || \
           [[ "$ip" =~ ^10\. ]] || \
           [[ "$ip" =~ ^172\.(1[6-9]|2[0-9]|3[0-1])\. ]]; then
            
            echo "    发现私有 IP: $cidr"
            
            # 计算网络地址
            if command -v ipcalc &>/dev/null; then
                local network=$(ipcalc -n "$cidr" 2>/dev/null | grep Network | awk '{print $2}')
                if [ -n "$network" ]; then
                    echo "$network" >> "$temp_file"
                    ((count++))
                fi
            fi
        fi
    done
    
    # 去重并排序
    if [ -f "$temp_file" ] && [ -s "$temp_file" ]; then
        detected_subnets=$(sort -u "$temp_file" | tr '\n' ' ')
        rm -f "$temp_file"
        
        if [ -n "$detected_subnets" ]; then
            echo ""
            log_info "检测到 $count 个内网网段:"
            for subnet in $detected_subnets; do
                echo "    • $subnet"
            done
            
            # 询问用户是否使用（除非指定了 -y）
            if [ -z "$LAN_SUBNETS" ]; then
                if [ "$SKIP_CONFIRM" = true ]; then
                    LAN_SUBNETS="$detected_subnets"
                    log_info "已自动配置内网网段"
                else
                    echo ""
                    echo -e "${YELLOW}是否使用这些网段进行内网穿透?${NC}"
                    echo "  选择 Yes: 远程可以访问这些内网设备"
                    echo "  选择 No:  仅配置 VPN 全局出站"
                    read -p "请选择 (Y/n): " confirm
                    if [[ ! "$confirm" =~ ^[Nn]$ ]]; then
                        LAN_SUBNETS="$detected_subnets"
                        log_info "已配置内网穿透"
                    else
                        log_info "跳过内网穿透配置"
                    fi
                fi
            fi
        fi
    else
        log_info "未检测到内网网段"
        rm -f "$temp_file"
    fi
    
    step_done "网段检测完成"
}

# 网络冲突检测
check_network_conflicts() {
    step_start "检查网络冲突"
    
    local warnings=0
    local conflicts=()
    
    echo "  正在检查端口占用..."
    if ss -uln 2>/dev/null | grep -q ":9993 " || netstat -uln 2>/dev/null | grep -q ":9993 "; then
        conflicts+=("端口 9993 已被占用")
        ((warnings++))
    fi
    
    echo "  正在检查 VPN 连接..."
    if ip link show 2>/dev/null | grep -qE "tun[0-9]+|tap[0-9]+|wg[0-9]+"; then
        local vpn_interfaces=$(ip link show | grep -oE "(tun|tap|wg)[0-9]+" | tr '\n' ' ')
        conflicts+=("检测到其他 VPN: $vpn_interfaces")
        ((warnings++))
    fi
    
    echo "  正在检查 NAT 规则..."
    if iptables -t nat -L POSTROUTING -n 2>/dev/null | grep -q "MASQUERADE"; then
        conflicts+=("存在现有的 MASQUERADE 规则")
        ((warnings++))
    fi
    
    echo "  正在检查防火墙..."
    if systemctl is-active --quiet ufw 2>/dev/null; then
        conflicts+=("UFW 防火墙正在运行")
        ((warnings++))
    fi
    
    if systemctl is-active --quiet firewalld 2>/dev/null; then
        conflicts+=("firewalld 正在运行")
        ((warnings++))
    fi
    
    echo "  正在检查已有配置..."
    if [ -f /etc/zerotier-gateway.conf ]; then
        conflicts+=("检测到已存在的配置")
        ((warnings++))
    fi
    
    # 显示冲突信息
    if [ $warnings -gt 0 ]; then
        echo ""
        log_warn "发现 $warnings 个潜在冲突:"
        for conflict in "${conflicts[@]}"; do
            echo "    ⚠ $conflict"
        done
        echo ""
        
        if [ "$SKIP_CONFIRM" != true ]; then
            echo -e "${YELLOW}提示: 这些冲突通常不会影响安装，但可能需要额外配置${NC}"
            read -p "是否继续安装? (Y/n): " confirm
            if [[ "$confirm" =~ ^[Nn]$ ]]; then
                log_info "用户取消安装"
                if [ -f /etc/zerotier-gateway.conf ]; then
                    echo ""
                    echo "建议先卸载现有配置: sudo bash $0 -u"
                fi
                exit 0
            fi
        else
            log_warn "跳过确认，继续安装..."
        fi
    else
        log_info "未发现网络冲突"
    fi
    
    step_done "冲突检测完成"
}

# MTU 自动优化
optimize_mtu() {
    step_start "优化 MTU 设置"
    
    local zt_iface="$1"
    local best_mtu=1500
    
    echo "  正在测试最佳 MTU 值..."
    
    # 测试不同 MTU 值
    for mtu in 1500 1400 1280 1200; do
        echo -n "    测试 MTU $mtu... "
        if ping -c 1 -M do -s $((mtu - 28)) -W 2 8.8.8.8 &>/dev/null; then
            best_mtu=$mtu
            echo -e "${GREEN}通过${NC}"
            break
        else
            echo -e "${RED}失败${NC}"
        fi
    done
    
    # 应用 MTU 设置
    if [ "$best_mtu" != "1500" ]; then
        ip link set "$zt_iface" mtu "$best_mtu" 2>/dev/null || true
        log_info "MTU 已优化为: $best_mtu"
    else
        log_info "MTU 保持默认值: 1500"
    fi
    
    step_done "MTU 优化完成"
}

# 安装依赖工具
install_dependencies() {
    step_start "检查必要工具"
    
    local missing_tools=()
    
    echo "  正在检查 ipcalc..."
    if ! command -v ipcalc &>/dev/null; then
        missing_tools+=("ipcalc")
        echo "    ✗ 缺少 ipcalc"
    else
        echo "    ✓ ipcalc 已安装"
    fi
    
    echo "  正在检查网络工具..."
    if ! command -v ss &>/dev/null && ! command -v netstat &>/dev/null; then
        missing_tools+=("net-tools")
        echo "    ✗ 缺少 ss/netstat"
    else
        echo "    ✓ 网络工具已安装"
    fi
    
    # 如果有缺失的工具，询问是否安装
    if [ ${#missing_tools[@]} -gt 0 ]; then
        log_warn "缺少必要工具: ${missing_tools[*]}"
        
        if [ "$SKIP_CONFIRM" = true ]; then
            echo "  自动安装缺失工具..."
        else
            echo ""
            read -p "是否自动安装? (Y/n): " confirm
            if [[ "$confirm" =~ ^[Nn]$ ]]; then
                log_warn "跳过依赖安装（某些功能可能受限）"
                step_done "依赖检查完成（部分工具缺失）"
                return
            fi
        fi
        
        echo "  正在安装依赖工具..."
        # 检测包管理器并安装
        if command -v apt-get &>/dev/null; then
            echo "    使用 apt-get 安装..."
            apt-get update -qq 2>/dev/null || true
            apt-get install -y ipcalc net-tools 2>&1 | grep -v "^Selecting" | grep -v "^Preparing" || true
        elif command -v yum &>/dev/null; then
            echo "    使用 yum 安装..."
            yum install -y ipcalc net-tools 2>&1 | grep -v "^Loaded plugins" || true
        elif command -v dnf &>/dev/null; then
            echo "    使用 dnf 安装..."
            dnf install -y ipcalc net-tools 2>&1 | grep -v "^Last metadata" || true
        fi
        
        log_info "依赖工具已安装"
    else
        log_info "所有依赖工具已就绪"
    fi
    
    step_done "依赖检查完成"
}

# ==================== 主程序 ====================

# 参数解析
while [[ $# -gt 0 ]]; do
    case $1 in
        -n) NETWORK_ID="$2"; shift 2 ;;
        -t) API_TOKEN="$2"; shift 2 ;;
        -l) 
            for subnet in $(echo "$2" | tr ',' ' '); do
                if ! [[ "$subnet" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}/[0-9]{1,2}$ ]]; then
                    log_error "无效的网段格式: $subnet"
                    exit 1
                fi
            done
            LAN_SUBNETS=$(echo "$2" | tr ',' ' ')
            shift 2 
            ;;
        -a) AUTO_DETECT_LAN=true; shift ;;
        -y) SKIP_CONFIRM=true; shift ;;
        -u) UNINSTALL=true; shift ;;
        -h|--help) show_help; exit 0 ;;
        *) log_error "未知选项: $1"; show_help; exit 1 ;;
    esac
done

# 卸载功能
if [ "$UNINSTALL" = true ]; then
    check_root
    echo ""
    echo -e "${CYAN}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${NC}                    ${YELLOW}卸载 ZeroTier Gateway${NC}                    ${CYAN}║${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    echo -n "正在停止服务... "
    systemctl stop zerotier-gateway 2>/dev/null || true
    systemctl disable zerotier-gateway 2>/dev/null || true
    echo -e "${GREEN}完成${NC}"
    
    echo -n "正在删除文件... "
    rm -f /usr/local/bin/zerotier-gateway-startup.sh
    rm -f /etc/systemd/system/zerotier-gateway.service
    rm -f /etc/sysctl.d/99-zerotier.conf
    rm -f /etc/zerotier-gateway.conf
    systemctl daemon-reload
    echo -e "${GREEN}完成${NC}"
    
    echo -n "正在清理 iptables... "
    iptables -t nat -F POSTROUTING 2>/dev/null || true
    iptables -F FORWARD 2>/dev/null || true
    echo -e "${GREEN}完成${NC}"
    
    log_info "卸载完成"
    
    if [ -d "$BACKUP_DIR" ] && [ "$SKIP_CONFIRM" != true ]; then
        echo ""
        read -p "是否删除备份文件? (y/N): " confirm
        if [[ "$confirm" =~ ^[Yy]$ ]]; then
            rm -rf "$BACKUP_DIR"
            log_info "备份文件已删除"
        else
            log_info "备份文件保留在: $BACKUP_DIR"
        fi
    fi
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

# 显示欢迎信息
clear
echo ""
echo -e "${CYAN}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║${NC}                                                                ${CYAN}║${NC}"
echo -e "${CYAN}║${NC}          ${GREEN}ZeroTier Gateway 智能安装向导 v1.2.1${NC}               ${CYAN}║${NC}"
echo -e "${CYAN}║${NC}                                                                ${CYAN}║${NC}"
echo -e "${CYAN}╠════════════════════════════════════════════════════════════════╣${NC}"
echo -e "${CYAN}║${NC}  Network ID: ${YELLOW}$NETWORK_ID${NC}                         ${CYAN}║${NC}"
echo -e "${CYAN}║${NC}  总步骤: ${YELLOW}$TOTAL_STEPS${NC} 步                                             ${CYAN}║${NC}"
echo -e "${CYAN}║${NC}  预计时间: ${YELLOW}3-5${NC} 分钟                                          ${CYAN}║${NC}"
[ "$SKIP_CONFIRM" = true ] && echo -e "${CYAN}║${NC}  模式: ${YELLOW}快速安装${NC} (跳过确认)                              ${CYAN}║${NC}"
[ "$SKIP_CONFIRM" != true ] && echo -e "${CYAN}║${NC}  模式: ${GREEN}标准安装${NC} (带确认提示)                            ${CYAN}║${NC}"
echo -e "${CYAN}╚════════════════════════════════════════════════════════════════╝${NC}"
echo ""

if [ "$SKIP_CONFIRM" != true ]; then
    echo -e "${YELLOW}提示: 使用 -y 参数可跳过所有确认提示进行快速安装${NC}"
    echo ""
    read -p "按回车键开始安装，或按 Ctrl+C 取消: " _
fi

# 记录开始时间
INSTALL_START_TIME=$(date +%s)

# 设置错误处理
setup_error_handling

# 步骤 1: 安装依赖
install_dependencies

# 步骤 2: 备份配置
backup_config

# 步骤 3: 冲突检测
check_network_conflicts

# 步骤 4: 自动检测内网
if [ "$AUTO_DETECT_LAN" = true ] || [ -z "$LAN_SUBNETS" ]; then
    auto_detect_lan_subnets
else
    ((CURRENT_STEP++))
fi

# 步骤 5: 安装 ZeroTier
step_start "安装 ZeroTier"

if ! command -v zerotier-cli &>/dev/null; then
    echo "  ZeroTier 未安装，需要安装..."
    
    if [ "$SKIP_CONFIRM" != true ]; then
        echo ""
        echo -e "${YELLOW}即将从官方源下载并安装 ZeroTier${NC}"
        echo "  来源: https://install.zerotier.com"
        read -p "是否继续? (Y/n): " confirm
        if [[ "$confirm" =~ ^[Nn]$ ]]; then
            log_info "用户取消安装"
            exit 0
        fi
    fi
    
    echo "  正在下载并安装 ZeroTier (可能需要 1-2 分钟，请耐心等待)..."
    echo ""
    
    # 显示安装输出（但过滤掉过多的细节）
    if curl -s https://install.zerotier.com 2>&1 | bash 2>&1 | \
       grep -E "Installing|Installed|Starting|zerotier-one|Success|已安装|正在安装" || true; then
        echo ""
        log_info "ZeroTier 安装成功"
    fi
    
    echo -n "  正在启动 ZeroTier 服务... "
    systemctl enable zerotier-one >/dev/null 2>&1
    systemctl start zerotier-one
    sleep 3
    echo -e "${GREEN}完成${NC}"
else
    log_info "ZeroTier 已安装，跳过安装步骤"
    systemctl is-active --quiet zerotier-one || systemctl start zerotier-one
fi

step_done "ZeroTier 安装完成"

# 步骤 6: 加入网络
step_start "加入 ZeroTier 网络"

echo -n "  正在加入网络 $NETWORK_ID... "
zerotier-cli join "$NETWORK_ID" >/dev/null 2>&1 || true
echo -e "${GREEN}完成${NC}"

echo -n "  正在获取 Node ID... "
NODE_ID=$(zerotier-cli info 2>/dev/null | awk '{print $3}')
if [ -z "$NODE_ID" ]; then
    echo -e "${RED}失败${NC}"
    log_error "无法获取 Node ID，请检查 ZeroTier 服务状态"
    exit 1
fi
echo -e "${GREEN}$NODE_ID${NC}"

step_done "网络加入完成"

# 步骤 7: 设备授权
step_start "等待设备授权"

if [ -n "$API_TOKEN" ]; then
    echo -n "  正在使用 API Token 自动授权... "
    HOSTNAME=$(hostname | tr -d '"' | tr -d "'")
    if curl -s -X POST -H "Authorization: token $API_TOKEN" \
        -H "Content-Type: application/json" \
        -d '{"config":{"authorized":true},"name":"Gateway-'"$HOSTNAME"'"}' \
        "https://api.zerotier.com/api/v1/network/$NETWORK_ID/member/$NODE_ID" >/dev/null 2>&1; then
        sleep 2
        echo -e "${GREEN}完成${NC}"
    else
        echo -e "${YELLOW}失败，需要手动授权${NC}"
    fi
fi

if ! zerotier-cli listnetworks 2>/dev/null | grep "$NETWORK_ID" | grep -q "OK"; then
    echo ""
    log_warn "请在 ZeroTier Central 授权此设备:"
    echo ""
    echo "  1. 打开浏览器访问: ${CYAN}https://my.zerotier.com/network/$NETWORK_ID${NC}"
    echo "  2. 在 Members 列表中找到 Node ID: ${YELLOW}$NODE_ID${NC}"
    echo "  3. 勾选该设备的 ${GREEN}Auth${NC} 复选框"
    echo ""
    echo "  等待授权中..."
    
    for i in {1..60}; do
        if zerotier-cli listnetworks 2>/dev/null | grep "$NETWORK_ID" | grep -q "OK"; then
            echo ""
            log_info "设备已成功授权"
            break
        fi
        [ $i -eq 60 ] && log_error "授权超时 (60秒)，请检查网络连接" && exit 1
        printf "\r  已等待 %d/60 秒... " $i
        sleep 1
    done
else
    log_info "设备已授权"
fi

step_done "设备授权完成"

# 步骤 8: 获取网络信息
step_start "获取网络配置信息"

echo "  等待网络接口就绪..."
sleep 2

echo -n "  正在获取 ZeroTier 接口... "
ZT_IFACE=$(ip addr | grep -oP 'zt\w+' | head -n 1)
if [ -z "$ZT_IFACE" ]; then
    echo -e "${RED}失败${NC}"
    log_error "未找到 ZeroTier 接口"
    exit 1
fi
echo -e "${GREEN}$ZT_IFACE${NC}"

echo -n "  正在获取 ZeroTier IP 地址... "
for i in {1..10}; do
    ZT_IP=$(ip -4 addr show "$ZT_IFACE" 2>/dev/null | grep -oP '(?<=inet\s)\d+(\.\d+){3}' || true)
    [ -n "$ZT_IP" ] && break
    sleep 1
done
if [ -z "$ZT_IP" ]; then
    echo -e "${RED}失败${NC}"
    log_error "未获取到 ZeroTier IP 地址"
    exit 1
fi
echo -e "${GREEN}$ZT_IP${NC}"

echo -n "  正在获取物理网卡... "
PHY_IFACE=$(ip route | grep default | awk '{print $5}' | head -n 1)
if [ -z "$PHY_IFACE" ]; then
    echo -e "${RED}失败${NC}"
    log_error "未找到默认网络接口"
    exit 1
fi
echo -e "${GREEN}$PHY_IFACE${NC}"

step_done "网络信息获取完成"

# 步骤 9: MTU 优化
optimize_mtu "$ZT_IFACE"

# 步骤 10: 配置系统
step_start "配置系统参数"

echo -n "  正在启用 IP 转发... "
sysctl -w net.ipv4.ip_forward=1 >/dev/null
cat > /etc/sysctl.d/99-zerotier.conf << 'EOF'
net.ipv4.ip_forward=1
net.ipv6.conf.all.forwarding=1
EOF
sysctl -p /etc/sysctl.d/99-zerotier.conf >/dev/null
echo -e "${GREEN}完成${NC}"

step_done "系统参数配置完成"

# 步骤 11: 配置防火墙规则
step_start "配置防火墙规则"

echo "  正在配置 NAT 规则..."
iptables -t nat -D POSTROUTING -o "$PHY_IFACE" -j MASQUERADE 2>/dev/null || true
iptables -t nat -A POSTROUTING -o "$PHY_IFACE" -j MASQUERADE
echo "    ✓ MASQUERADE 规则已添加"

echo "  正在配置转发规则..."
iptables -D FORWARD -i "$ZT_IFACE" -o "$PHY_IFACE" -j ACCEPT 2>/dev/null || true
iptables -A FORWARD -i "$ZT_IFACE" -o "$PHY_IFACE" -j ACCEPT
iptables -D FORWARD -i "$PHY_IFACE" -o "$ZT_IFACE" -m state --state RELATED,ESTABLISHED -j ACCEPT 2>/dev/null || true
iptables -A FORWARD -i "$PHY_IFACE" -o "$ZT_IFACE" -m state --state RELATED,ESTABLISHED -j ACCEPT
echo "    ✓ FORWARD 规则已添加"

echo "  正在配置端口规则..."
iptables -C INPUT -p udp --dport 9993 -j ACCEPT 2>/dev/null || \
    iptables -A INPUT -p udp --dport 9993 -j ACCEPT
echo "    ✓ 端口 9993/UDP 已开放"

if [ -n "$LAN_SUBNETS" ]; then
    echo "  正在配置内网路由..."
    for subnet in $LAN_SUBNETS; do
        echo -n "    添加 $subnet... "
        ip route add "$subnet" dev "$ZT_IFACE" 2>/dev/null || true
        iptables -t nat -A POSTROUTING -s 10.0.0.0/8 -d "$subnet" -j MASQUERADE 2>/dev/null || true
        echo -e "${GREEN}完成${NC}"
    done
fi

echo -n "  正在保存 iptables 规则... "
OS=$(cat /etc/os-release | grep ^ID= | cut -d= -f2 | tr -d '"')
case $OS in
    ubuntu|debian)
        if command -v netfilter-persistent &>/dev/null; then
            netfilter-persistent save 2>/dev/null || true
        elif command -v iptables-save &>/dev/null; then
            mkdir -p /etc/iptables
            iptables-save > /etc/iptables/rules.v4 2>/dev/null || true
        fi
        ;;
    centos|rhel|rocky|alma|fedora)
        service iptables save 2>/dev/null || true
        ;;
esac
echo -e "${GREEN}完成${NC}"

step_done "防火墙规则配置完成"

# 步骤 12: 创建启动脚本和服务
step_start "创建启动脚本"

echo -n "  正在创建启动脚本... "
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
echo -e "${GREEN}完成${NC}"

echo -n "  正在创建 systemd 服务... "
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
echo -e "${GREEN}完成${NC}"

echo -n "  正在启用服务... "
systemctl daemon-reload
systemctl enable zerotier-gateway.service >/dev/null 2>&1
echo -e "${GREEN}完成${NC}"

step_done "启动脚本创建完成"

# API 路由配置
if [ -n "$API_TOKEN" ]; then
    if command -v jq &>/dev/null; then
        echo ""
        echo -n "正在使用 API Token 自动配置路由... "
        
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
        
        if curl -s -X POST -H "Authorization: token $API_TOKEN" \
            -H "Content-Type: application/json" \
            -d '{"config":{"routes":'"$FINAL_ROUTES"'}}' \
            "https://api.zerotier.com/api/v1/network/$NETWORK_ID" >/dev/null 2>&1; then
            echo -e "${GREEN}完成${NC}"
        else
            echo -e "${YELLOW}失败${NC}"
            log_warn "自动路由配置失败，请手动配置"
        fi
    else
        echo ""
        log_warn "未安装 jq，无法自动配置路由"
        log_warn "请手动在 ZeroTier Central 配置路由"
    fi
fi

# 保存配置
cat > /etc/zerotier-gateway.conf << EOF
# ZeroTier Gateway 配置文件
VERSION=1.2.1
NETWORK_ID=$NETWORK_ID
NODE_ID=$NODE_ID
ZT_IFACE=$ZT_IFACE
ZT_IP=$ZT_IP
PHY_IFACE=$PHY_IFACE
LAN_SUBNETS="$LAN_SUBNETS"
INSTALL_DATE=$(date '+%Y-%m-%d %H:%M:%S')
BACKUP_DIR=$BACKUP_DIR
EOF

# 测试网络
echo ""
echo -n "正在测试网络连通性... "
if ping -c 2 -W 3 8.8.8.8 &>/dev/null; then
    echo -e "${GREEN}成功 (8.8.8.8)${NC}"
elif ping -c 2 -W 3 1.1.1.1 &>/dev/null; then
    echo -e "${GREEN}成功 (1.1.1.1)${NC}"
else
    echo -e "${YELLOW}警告: 无法访问外网${NC}"
fi

# 禁用错误陷阱
trap - ERR

# 计算总耗时
INSTALL_END_TIME=$(date +%s)
TOTAL_TIME=$((INSTALL_END_TIME - INSTALL_START_TIME))
MINUTES=$((TOTAL_TIME / 60))
SECONDS=$((TOTAL_TIME % 60))

# 显示完成信息
clear
echo ""
echo -e "${CYAN}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║${NC}                                                                ${CYAN}║${NC}"
echo -e "${CYAN}║${NC}                  ${GREEN}✓ 安装成功完成！${NC}                          ${CYAN}║${NC}"
echo -e "${CYAN}║${NC}                                                                ${CYAN}║${NC}"
echo -e "${CYAN}╠════════════════════════════════════════════════════════════════╣${NC}"
echo -e "${CYAN}║${NC}  总耗时: ${YELLOW}${MINUTES}${NC} 分 ${YELLOW}${SECONDS}${NC} 秒                                        ${CYAN}║${NC}"
echo -e "${CYAN}║${NC}  完成步骤: ${GREEN}${CURRENT_STEP}${NC}/${GREEN}${TOTAL_STEPS}${NC}                                            ${CYAN}║${NC}"
echo -e "${CYAN}╚════════════════════════════════════════════════════════════════╝${NC}"
echo ""

# 显示配置摘要
echo -e "${CYAN}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║${NC}                      ${YELLOW}配置摘要${NC}                                ${CYAN}║${NC}"
echo -e "${CYAN}╠════════════════════════════════════════════════════════════════╣${NC}"
echo -e "${CYAN}║${NC}  Network ID:    ${YELLOW}$NETWORK_ID${NC}                  ${CYAN}║${NC}"
echo -e "${CYAN}║${NC}  Node ID:       ${YELLOW}$NODE_ID${NC}                     ${CYAN}║${NC}"
echo -e "${CYAN}║${NC}  ZeroTier IP:   ${YELLOW}$ZT_IP${NC}                                  ${CYAN}║${NC}"
echo -e "${CYAN}║${NC}  物理网卡:      ${YELLOW}$PHY_IFACE${NC}                                    ${CYAN}║${NC}"
[ -n "$LAN_SUBNETS" ] && echo -e "${CYAN}║${NC}  内网网段:      ${YELLOW}$(echo $LAN_SUBNETS | tr ' ' ',')${NC}                    ${CYAN}║${NC}"
echo -e "${CYAN}║${NC}  备份目录:      ${YELLOW}$BACKUP_DIR${NC}     ${CYAN}║${NC}"
echo -e "${CYAN}╚════════════════════════════════════════════════════════════════╝${NC}"
echo ""

if [ -z "$API_TOKEN" ] || ! command -v jq &>/dev/null; then
    echo -e "${YELLOW}下一步操作:${NC}"
    echo ""
    echo "1. 在 ZeroTier Central 手动配置路由:"
    echo "   ${CYAN}https://my.zerotier.com/network/$NETWORK_ID${NC}"
    echo ""
    echo "   添加以下路由 (Managed Routes):"
    echo "   • ${GREEN}0.0.0.0/0${NC} via ${YELLOW}$ZT_IP${NC}  (全局出站)"
    [ -n "$LAN_SUBNETS" ] && for s in $LAN_SUBNETS; do echo "   • ${GREEN}$s${NC} via ${YELLOW}$ZT_IP${NC}  (内网)"; done
    echo ""
else
    echo -e "${GREEN}✓ 路由已自动配置${NC}"
    echo "   查看: ${CYAN}https://my.zerotier.com/network/$NETWORK_ID${NC}"
    echo ""
fi

echo -e "${CYAN}客户端配置:${NC}"
echo "  Windows: https://www.zerotier.com/download/"
echo "  加入网络: $NETWORK_ID"
echo ""
echo -e "${CYAN}测试连接:${NC}"
echo "  ping $ZT_IP"
echo ""
echo -e "${CYAN}管理命令:${NC}"
echo "  查看状态: ${GREEN}systemctl status zerotier-gateway${NC}"
echo "  查看配置: ${GREEN}cat /etc/zerotier-gateway.conf${NC}"
echo "  查看日志: ${GREEN}journalctl -u zerotier-one -f${NC}"
echo "  卸载: ${YELLOW}sudo bash $0 -u${NC}"
echo ""

log_info "感谢使用 ZeroTier Gateway！"
echo ""
