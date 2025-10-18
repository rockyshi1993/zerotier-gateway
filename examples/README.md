# ZeroTier Gateway 使用示例

本目录包含 ZeroTier Gateway 脚本的各种使用场景示例。

## 目录结构

```
examples/
├── README.md                          # 本文件
├── basic-install.sh                   # 基础安装示例
├── advanced-install.sh                # 高级安装示例
├── custom-lan-subnets.sh             # 自定义内网网段示例
├── api-token-auto-config.sh          # API Token 自动配置示例
├── uninstall.sh                       # 卸载示例
└── troubleshooting.sh                 # 故障排查示例
```

## 使用前提

1. 拥有 ZeroTier 账号（[免费注册](https://my.zerotier.com)）
2. 已创建 ZeroTier 网络并获取 Network ID
3. 具有 root 权限的 Linux 服务器

## 示例说明

### 1. 基础安装 (basic-install.sh)

最简单的安装方式，适合新手用户。
- 自动检测内网网段
- 标准安装模式（带确认提示）
- 适用场景：首次安装、生产环境

### 2. 高级安装 (advanced-install.sh)

完全自动化的快速安装。
- 使用 API Token 自动配置
- 跳过所有确认提示
- 适用场景：批量部署、CI/CD

### 3. 自定义内网网段 (custom-lan-subnets.sh)

手动指定内网网段，不使用自动检测。
- 适合复杂网络环境
- 支持多个网段
- 适用场景：企业内网、多网段环境

### 4. API Token 自动配置 (api-token-auto-config.sh)

演示如何使用 API Token 实现完全无人值守安装。
- 自动授权设备
- 自动配置路由
- 适用场景：自动化部署

### 5. 卸载 (uninstall.sh)

安全卸载 ZeroTier Gateway 配置。
- 清理所有配置
- 恢复系统设置
- 适用场景：维护、重新配置

### 6. 故障排查 (troubleshooting.sh)

常见问题的诊断和解决方案。
- 检查服务状态
- 验证网络配置
- 适用场景：问题诊断

## 获取 Network ID

1. 访问 [ZeroTier Central](https://my.zerotier.com)
2. 点击 **Create A Network**
3. 复制 **Network ID**（16位十六进制字符）

## 获取 API Token（可选）

1. 访问 [ZeroTier Account](https://my.zerotier.com/account)
2. 在 **API Access Tokens** 部分生成 Token
3. 复制并妥善保存（只显示一次）

## 注意事项

⚠️ **重要提示**：
- 示例中的 Network ID 和 API Token 都是占位符，请替换为真实值
- 所有示例都需要 root 权限运行
- 建议在测试环境先验证
- 生产环境使用前请仔细阅读脚本内容

## 快速开始

```bash
# 1. 进入示例目录
cd examples/

# 2. 选择合适的示例（例如基础安装）
bash basic-install.sh

# 3. 按照提示操作
```

## 获取帮助

如遇到问题，请：
1. 查看 [README.md](../README.md) 完整文档
2. 运行故障排查示例：`bash troubleshooting.sh`
3. 提交 Issue：https://github.com/rockyshi1993/zerotier-gateway/issues
