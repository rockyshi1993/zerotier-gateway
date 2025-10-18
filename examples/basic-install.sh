#!/bin/bash

################################################################################
# ZeroTier Gateway - 基础安装示例
#
# 功能描述：
#   演示最简单的安装方式，适合新手用户首次使用
#
# 使用场景：
#   - 首次安装 ZeroTier Gateway
#   - 个人 VPN 搭建
#   - 简单的内网穿透
#
# 特点：
#   - 自动检测内网网段
#   - 标准安装模式（带确认提示）
#   - 适合学习和测试
#
# 前置要求：
#   1. 拥有 ZeroTier 账号
#   2. 已创建网络并获取 Network ID
#   3. 具有 root 权限
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
echo -e "${CYAN}║${NC}          ZeroTier Gateway - 基础安装示例                      ${CYAN}║${NC}"
echo -e "${CYAN}╚════════════════════════════════════════════════════════════════╝${NC}"
echo ""

# 检查 root 权限
if [ $EUID -ne 0 ]; then
    echo -e "${RED}错误: 需要 root 权限${NC}"
    echo "请使用: sudo bash $0"
    exit 1
fi

# 配置参数（请替换为你的 Network ID）
NETWORK_ID="YOUR_NETWORK_ID_HERE"

# 验证 Network ID
if [ "$NETWORK_ID" = "YOUR_NETWORK_ID_HERE" ]; then
    echo -e "${YELLOW}请先配置你的 Network ID！${NC}"
    echo ""
    echo "步骤："
    echo "1. 访问 https://my.zerotier.com"
    echo "2. 创建或选择一个网络"
    echo "3. 复制 Network ID（16位十六进制）"
    echo "4. 编辑本文件，将 YOUR_NETWORK_ID_HERE 替换为你的 Network ID"
    echo ""
    exit 1
fi

# 验证 Network ID 格式
if ! [[ "$NETWORK_ID" =~ ^[a-f0-9]{16}$ ]]; then
    echo -e "${RED}错误: Network ID 格式不正确${NC}"
    echo "Network ID 必须是 16 位小写十六进制字符"
    echo "示例: 1234567890abcdef"
    exit 1
fi

# 显示配置信息
echo -e "${GREEN}配置信息：${NC}"
echo "  Network ID: $NETWORK_ID"
echo "  安装模式: 标准模式（带确认提示）"
echo "  内网检测: 自动检测"
echo ""

# 确认继续
read -p "是否继续安装？(Y/n): " confirm
if [[ "$confirm" =~ ^[Nn]$ ]]; then
    echo "已取消安装"
    exit 0
fi

echo ""
echo -e "${CYAN}开始安装...${NC}"
echo ""

# 下载主脚本（如果不存在）
SCRIPT_PATH="../zerotier-gateway-setup.sh"

if [ ! -f "$SCRIPT_PATH" ]; then
    echo "下载安装脚本..."
    wget -O "$SCRIPT_PATH" https://raw.githubusercontent.com/rockyshi1993/zerotier-gateway/main/zerotier-gateway-setup.sh
    chmod +x "$SCRIPT_PATH"
fi

# 执行安装
# 参数说明：
#   -n: Network ID（必填）
#   -a: 自动检测内网网段（推荐）
#
# 注意：不使用 -y 参数，保留确认提示
bash "$SCRIPT_PATH" -n "$NETWORK_ID" -a

# 检查安装结果
if [ $? -eq 0 ]; then
    echo ""
    echo -e "${GREEN}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║${NC}                   安装成功完成！                               ${GREEN}║${NC}"
    echo -e "${GREEN}╚════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${CYAN}下一步操作：${NC}"
    echo ""
    echo "1. 手动配置路由（在 ZeroTier Central）："
    echo "   访问: https://my.zerotier.com/network/$NETWORK_ID"
    echo ""
    echo "   在 Managed Routes 部分添加："
    echo "   • 目标: 0.0.0.0/0"
    echo "   • Via: <你的 ZeroTier IP>（在上面输出中查看）"
    echo ""
    echo "2. 客户端连接："
    echo "   • 下载 ZeroTier 客户端: https://www.zerotier.com/download/"
    echo "   • 加入网络: $NETWORK_ID"
    echo "   • 在 ZeroTier Central 授权设备"
    echo ""
    echo "3. 测试连接："
    echo "   • ping <你的 ZeroTier 网关 IP>"
    echo "   • 访问互联网（流量会通过网关）"
    echo ""
else
    echo ""
    echo -e "${RED}安装失败，请检查错误信息${NC}"
    exit 1
fi
