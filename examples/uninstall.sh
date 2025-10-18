#!/bin/bash

################################################################################
# ZeroTier Gateway - 卸载示例
#
# 功能描述：
#   安全卸载 ZeroTier Gateway 配置，恢复系统原始状态
#
# 使用场景：
#   - 不再需要网关功能
#   - 重新配置前清理
#   - 故障排查和重置
#
# 特点：
#   - 安全清理所有配置
#   - 可选保留备份文件
#   - 恢复系统设置
#
# 注意：
#   此脚本只会卸载 Gateway 配置，不会卸载 ZeroTier 本身
#   如需完全卸载 ZeroTier，请参考官方文档
#
# 作者: rockyshi1993
# 日期: 2025-10-18
################################################################################

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

echo ""
echo -e "${CYAN}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║${NC}          ZeroTier Gateway - 卸载示例                          ${CYAN}║${NC}"
echo -e "${CYAN}╚════════════════════════════════════════════════════════════════╝${NC}"
echo ""

# 检查 root 权限
if [ $EUID -ne 0 ]; then
    echo -e "${RED}错误: 需要 root 权限${NC}"
    echo "请使用: sudo bash $0"
    exit 1
fi

# 显示将要删除的内容
echo -e "${YELLOW}此操作将删除以下内容：${NC}"
echo ""
echo "  • ZeroTier Gateway 服务配置"
echo "  • 启动脚本: /usr/local/bin/zerotier-gateway-startup.sh"
echo "  • Systemd 服务: /etc/systemd/system/zerotier-gateway.service"
echo "  • Sysctl 配置: /etc/sysctl.d/99-zerotier.conf"
echo "  • Gateway 配置: /etc/zerotier-gateway.conf"
echo "  • iptables 规则（FORWARD 和 NAT）"
echo ""
echo -e "${GREEN}保留的内容：${NC}"
echo ""
echo "  • ZeroTier 软件本身（zerotier-one）"
echo "  • ZeroTier 网络成员资格"
echo "  • 备份文件（可选删除）"
echo ""

# 确认卸载
read -p "确认卸载 ZeroTier Gateway 配置？(y/N): " confirm
if ! [[ "$confirm" =~ ^[Yy]$ ]]; then
    echo "已取消卸载"
    exit 0
fi

echo ""
echo -e "${CYAN}开始卸载...${NC}"
echo ""

# 检查是否存在配置文件
if [ ! -f /etc/zerotier-gateway.conf ]; then
    echo -e "${YELLOW}警告: 未找到 Gateway 配置文件${NC}"
    echo "可能从未安装或已被删除"
    echo ""
    read -p "是否继续清理残留文件？(y/N): " continue_cleanup
    if ! [[ "$continue_cleanup" =~ ^[Yy]$ ]]; then
        echo "已取消"
        exit 0
    fi
fi

# 下载主脚本（如果不存在）
SCRIPT_PATH="../zerotier-gateway-setup.sh"

if [ ! -f "$SCRIPT_PATH" ]; then
    echo "下载卸载脚本..."
    wget -O "$SCRIPT_PATH" https://raw.githubusercontent.com/rockyshi1993/zerotier-gateway/main/zerotier-gateway-setup.sh
    chmod +x "$SCRIPT_PATH"
fi

# 执行卸载
# 参数说明：
#   -u: 卸载模式
bash "$SCRIPT_PATH" -u

# 检查卸载结果
if [ $? -eq 0 ]; then
    echo ""
    echo -e "${GREEN}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║${NC}                  卸载成功完成！                                ${GREEN}║${NC}"
    echo -e "${GREEN}╚════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    # 检查备份目录
    BACKUP_DIR="/var/backups/zerotier-gateway"
    if [ -d "$BACKUP_DIR" ]; then
        BACKUP_SIZE=$(du -sh "$BACKUP_DIR" 2>/dev/null | awk '{print $1}')
        echo -e "${CYAN}备份文件信息：${NC}"
        echo "  位置: $BACKUP_DIR"
        echo "  大小: $BACKUP_SIZE"
        echo ""
        echo -e "${YELLOW}是否删除备份文件？${NC}"
        echo "  (包含 iptables 规则和配置文件的历史备份)"
        echo ""
        read -p "删除备份文件？(y/N): " delete_backup
        if [[ "$delete_backup" =~ ^[Yy]$ ]]; then
            rm -rf "$BACKUP_DIR"
            echo -e "${GREEN}✓ 备份文件已删除${NC}"
        else
            echo -e "${GREEN}✓ 备份文件已保留${NC}"
        fi
    fi
    
    echo ""
    echo -e "${CYAN}系统状态：${NC}"
    echo "  • Gateway 配置已清除"
    echo "  • ZeroTier 仍在运行"
    echo "  • 网络成员资格保持不变"
    echo ""
    
    # 检查 ZeroTier 状态
    if systemctl is-active --quiet zerotier-one; then
        echo -e "${GREEN}✓ ZeroTier 服务运行正常${NC}"
        echo ""
        echo "如需完全卸载 ZeroTier："
        echo "  Debian/Ubuntu: sudo apt remove zerotier-one"
        echo "  CentOS/RHEL:   sudo yum remove zerotier-one"
    fi
    
    echo ""
    echo -e "${GREEN}卸载完成！${NC}"
    echo ""
    
else
    echo ""
    echo -e "${RED}卸载失败，请检查错误信息${NC}"
    exit 1
fi
