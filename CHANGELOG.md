# Changelog

所有显著变更将记录在此文件，遵循 Keep a Changelog 与 SemVer。

## [Unreleased]

## [1.2.2] - 2025-01-23

### Added
- 新增预安装系统检查功能（`pre_install_check`）
  - 检查 root 权限、磁盘空间、网络连接
  - 检查系统负载、已有配置、iptables
  - 检查内核 IP 转发状态
- 新增 `-s, --status` 参数，支持查看网关状态
  - 显示基本信息（版本、Network ID、安装日期）
  - 显示 ZeroTier 和 Gateway 服务状态
  - 显示网络配置（IP 转发、内网穿透、NAT 规则）
  - 显示路由信息和快速诊断结果

### Changed
- 改进 Network ID 验证错误消息，提供详细的获取指引
- 版本号更新为 1.2.2

### Security
- 配置文件 `/etc/zerotier-gateway.conf` 权限设置为 600（仅 root 可读写）
- 配置文件所有者强制设为 root:root
- 移除配置文件中的 API Token 存储（安全考虑）

### Fixed
- 修复配置文件权限过于宽松的安全隐患

## [1.2.1] - 2025-01-22

### Added
- 添加完整的测试套件（单元测试和集成测试）
- 添加测试运行脚本 `test/run-tests.sh`
- 添加单元测试 `test/unit-tests.sh`（覆盖 Network ID 验证、网段验证、CIDR 格式等）
- 添加集成测试 `test/integration-tests.sh`（需要 root 权限）
- 添加使用示例目录 `examples/`
- 添加基础安装示例 `examples/basic-install.sh`
- 添加高级安装示例 `examples/advanced-install.sh`
- 添加卸载示例 `examples/uninstall.sh`
- 添加示例说明文档 `examples/README.md`

### Changed
- 无

### Fixed
- 无

### Deprecated
- 无

### Removed
- 无

### Performance
- 无

### Security
- 建议在配置文件 `/etc/zerotier-gateway.conf` 中限制 API Token 权限（如存储）

## [1.2.1] - 2025-10-18

### Added
- 详细的实时进度显示（12步可视化）
- 每步骤耗时统计
- 可视化进度条（50字符宽）
- 彩色输出增强可读性
- 智能内网检测（自动识别私有 IP 网段）
- 配置备份回滚功能
- 网络冲突检测（端口占用、VPN 冲突、防火墙状态）
- MTU 自动优化
- 错误回滚机制

### Changed
- 优化确认流程（默认显示确认提示）
- 改进安装脚本用户体验

## [1.2.0] - 之前版本

### Added
- 基础 VPN 网关功能
- 内网穿透支持
- OpenVPN 协同
- 自动路由配置（使用 API Token）
- 一键安装脚本
- 持久化配置

### Fixed
- 多项稳定性修复

## 版本规范

本项目遵循 [Semantic Versioning](https://semver.org/)：
- **Major (x.0.0)**: 破坏性改动
- **Minor (0.x.0)**: 向后兼容的功能新增
- **Patch (0.0.x)**: 向后兼容的错误修复
