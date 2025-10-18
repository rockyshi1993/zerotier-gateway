#!/bin/bash

################################################################################
# ZeroTier Gateway - 高级安装示例
#
# 功能描述：
#   演示完全自动化的快速安装，适合批量部署和自动化场景
#
# 使用场景：
#   - 批量部署多台服务器
#   - CI/CD 自动化流程
#   - 无人值守安装
#
# 特点：
#   - 使用 API Token 自动配置路由
#   - 跳过所有确认提示（-y 参数）
#   - 自动检测内网网段
#   - 完全无人值守
#
# 前置要求：
#   1. 拥有 ZeroTier 账号
#   2. 已创建网络并获取 Network ID
#   3. 已生成 API Token
#   4. 具有 root 权限
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
echo -e "${CYAN}║${NC}          ZeroTier Gateway - 高级安装示例                      ${CYAN}║${NC}"
echo -e "${CYAN}╚════════════════════════════════════════════════════════════════╝${NC}"
echo ""

# 检查 root 权限
if [ $EUID -ne 0 ]; then
    echo -e "${RED}错误: 需要 root 权限${NC}"
    echo "请使用: sudo bash $0"
    exit 1
fi

# 配置参数（请替换为你的真实值）
NETWORK_ID="YOUR_NETWORK_ID_HERE"
API_TOKEN="YOUR_API_TOKEN_HERE"

# 验证配置
if [ "$NETWORK_ID" = "YOUR_NETWORK_ID_HERE" ] || [ "$API_TOKEN" = "YOUR_API_TOKEN_HERE" ]; then
    echo -e "${YELLOW}请先配置你的 Network ID 和 API Token！${NC}"
    echo ""
    echo "获取 Network ID："
    echo "1. 访问 https://my.zerotier.com"
    echo "2. 创建或选择一个网络"
    echo "3. 复制 Network ID（16位十六进制）"
    echo ""
    echo "获取 API Token："
    echo "1. 访问 https://my.zerotier.com/account"
    echo "2. 在 'API Access Tokens' 部分生成 Token"
    echo "3. 复制 Token（只显示一次，请妥善保存）"
    echo ""
    echo "然后编辑本文件，替换占位符为真实值"
    echo ""
    exit 1
fi

# 验证 Network ID 格式
if ! [[ "$NETWORK_ID" =~ ^[a-f0-9]{16}$ ]]; then
    echo -e "${RED}错误: Network ID 格式不正确${NC}"
    echo "Network ID 必须是 16 位小写十六进制字符"
    exit 1
fi

# 显示配置信息
echo -e "${GREEN}配置信息：${NC}"
echo "  Network ID: $NETWORK_ID"
echo "  API Token: ${API_TOKEN:0:10}...（已隐藏）"
echo "  安装模式: 快速模式（跳过确认）"
echo "  内网检测: 自动检测"
echo "  自动配置: 启用（设备授权 + 路由配置）"
echo ""

# 安全提示
echo -e "${YELLOW}注意：此脚本将执行以下操作（无确认提示）：${NC}"
echo "  • 安装 ZeroTier（如未安装）"
echo "  • 加入指定网络"
echo "  • 自动授权设备"
echo "  • 配置防火墙规则"
echo "  • 自动配置路由"
echo "  • 启用系统服务"
echo ""

# 最后确认（高级模式仍建议保留）
read -p "确认开始快速安装？(Y/n): " confirm
if [[ "$confirm" =~ ^[Nn]$ ]]; then
    echo "已取消安装"
    exit 0
fi

echo ""
echo -e "${CYAN}开始快速安装...${NC}"
echo ""

# 记录开始时间
START_TIME=$(date +%s)

# 下载主脚本（如果不存在）
SCRIPT_PATH="../zerotier-gateway-setup.sh"

if [ ! -f "$SCRIPT_PATH" ]; then
    echo "下载安装脚本..."
    wget -O "$SCRIPT_PATH" https://raw.githubusercontent.com/rockyshi1993/zerotier-gateway/main/zerotier-gateway-setup.sh
    chmod +x "$SCRIPT_PATH"
fi

# 执行快速安装
# 参数说明：
#   -n: Network ID（必填）
#   -t: API Token（可选，用于自动配置）
#   -a: 自动检测内网网段
#   -y: 跳过所有确认提示（快速模式）
bash "$SCRIPT_PATH" -n "$NETWORK_ID" -t "$API_TOKEN" -a -y

# 检查安装结果
INSTALL_EXIT=$?
END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

if [ $INSTALL_EXIT -eq 0 ]; then
    echo ""
    echo -e "${GREEN}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║${NC}               快速安装成功完成！                               ${GREEN}║${NC}"
    echo -e "${GREEN}╚════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${CYAN}安装摘要：${NC}"
    echo "  总耗时: $DURATION 秒"
    echo "  Network ID: $NETWORK_ID"
    echo "  配置文件: /etc/zerotier-gateway.conf"
    echo "  备份目录: /var/backups/zerotier-gateway"
    echo ""
    echo -e "${GREEN}✓ 所有配置已自动完成！${NC}"
    echo ""
    echo -e "${CYAN}客户端连接步骤：${NC}"
    echo "1. 下载并安装 ZeroTier 客户端"
    echo "   https://www.zerotier.com/download/"
    echo ""
    echo "2. 加入网络: $NETWORK_ID"
    echo "   (设备会自动被授权)"
    echo ""
    echo "3. 测试连接"
    echo "   所有流量将通过此网关"
    echo ""
    echo -e "${CYAN}管理命令：${NC}"
    echo "  查看状态: systemctl status zerotier-gateway"
    echo "  查看日志: journalctl -u zerotier-one -f"
    echo "  查看配置: cat /etc/zerotier-gateway.conf"
    echo ""
else
    echo ""
    echo -e "${RED}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${RED}║${NC}                   安装失败                                     ${RED}║${NC}"
    echo -e "${RED}╚════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${YELLOW}建议操作：${NC}"
    echo "1. 检查错误信息（见上面输出）"
    echo "2. 验证 Network ID 和 API Token 是否正确"
    echo "3. 检查网络连接是否正常"
    echo "4. 查看日志: journalctl -u zerotier-one -n 50"
    echo ""
    echo "如需卸载并重试: sudo bash examples/uninstall.sh"
    echo ""
    exit 1
fi
