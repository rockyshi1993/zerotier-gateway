# 更新日志

所有显著变更将记录在此文件，遵循变更日志规范与语义化版本。

## [未发布]

### 修复
- Ubuntu 中转脚本现在会生成可用的 systemd socket/service，使用 `systemd-socket-proxyd` 把 Ubuntu ZeroTier 入口转发到家里和公司 Windows 远程端口，不再只输出“需要自行安装 relay”的提示。
- README、安装指南和中转文档补充中转验证流程，写清 Ubuntu 监听、Windows 到 Ubuntu、Ubuntu 到目标 Windows 远程端口的分段检查方式。
- Windows 防火墙规则写入现在会先检查管理员 PowerShell，`New-NetFirewallRule` 或 `Remove-NetFirewallRule` 失败时会立即停止，不再误报已应用。
- README、安装指南和故障排查补充 `拒绝访问` / `Windows System Error 5` 的处理步骤，并说明哪些 Windows 电脑需要执行脚本。
- README 和 Windows 安装文档补充管理员权限确认命令，拆分 `Home` / `Work` 执行块，避免用户在同一台电脑跑错角色。
- README 目录导航改为按任务跳转，补充 Ubuntu、Windows、防火墙、代理、排除规则、中转和验收入口。
- README、安装指南和代理文档补充后续启用、修改或关闭代理账号密码的完整流程。
- README、安装指南和故障排查补充 ZeroTier Central 网段、地址池清理，以及 TUN/全局代理开启后远程不通的处理流程。

## [1.3.0] - 2026-06-23

### 新增
- 新增轻量重构入口：`config/`、`templates/`、`scripts/ubuntu/`、`scripts/windows/`、`docs/`、`tests/`、`artifacts/`。
- 新增 Ubuntu 私有 HTTP/SOCKS5 代理脚本骨架，默认读取项目根目录 `.env`。
- 新增 Windows 入网、防火墙预览、网络诊断、代理测试、PAC 生成和本地规则客户端配置生成脚本。
- 新增低延时远程、私有代理、代理排除规则、中转兜底、排错和回滚文档。
- 新增发布验证与回滚说明，明确 `v1.3.0` 的发布前检查、tag 验收和失败恢复路径。

### 变更
- README 新增当前推荐入口：一个 ZeroTier 私有局域网、双向远程、Ubuntu 私有代理、可选中转。
- README 当前主入口调整为中文优先，并将旧版 README 降级为历史参考折叠区。
- `--env <path>` / `-Env <path>` 调整为覆盖参数；普通主流程默认不需要传 `.env` 路径。
- 旧 `zerotier-gateway-setup.sh` 标记为 deprecated，保留历史兼容，不再作为新功能主实现。

### 修复
- Ubuntu `.env` 读取改为安全解析，避免把配置文件当作 shell 脚本执行。
- 模板渲染改为按模板占位符替换，省略可选配置时也能使用脚本默认值。
- PAC 生成支持任意 `DIRECT_IP_CIDRS` 网段转换，不再只处理固定私网网段。
- Windows 本地客户端规则修正进程组数组合并，并显式输出 sing-box `action: route`。
- Windows 防火墙应用规则前会清理同名项目规则，避免重复创建。
- 恢复历史分析文档，避免发布包误删 `PROJECT_ANALYSIS.md` 与 `V1.2.2-IMPROVEMENTS.md`。
- 清理 README、状态页、历史文档中的中英混排术语残留，文档入口保持中文优先。

## [1.2.2] - 2025-01-23

### 新增
- 新增预安装系统检查功能（`pre_install_check`）
  - 检查 root 权限、磁盘空间、网络连接
  - 检查系统负载、已有配置、iptables
  - 检查内核 IP 转发状态
- 新增 `-s, --status` 参数，支持查看网关状态
  - 显示基本信息（版本、网络编号、安装日期）
  - 显示 ZeroTier 和 Gateway 服务状态
  - 显示网络配置（IP 转发、内网穿透、NAT 规则）
  - 显示路由信息和快速诊断结果

### 变更
- 改进网络编号验证错误消息，提供详细的获取指引
- 版本号更新为 1.2.2

### 安全
- 配置文件 `/etc/zerotier-gateway.conf` 权限设置为 600（仅 root 可读写）
- 配置文件所有者强制设为 root:root
- 移除配置文件中的接口令牌存储（安全考虑）

### 修复
- 修复配置文件权限过于宽松的安全隐患

## [1.2.1] - 2025-01-22

### 新增
- 添加完整的测试套件（单元测试和集成测试）
- 添加测试运行脚本 `test/run-tests.sh`
- 添加单元测试 `test/unit-tests.sh`（覆盖网络编号验证、网段验证、CIDR 格式等）
- 添加集成测试 `test/integration-tests.sh`（需要 root 权限）
- 添加使用示例目录 `examples/`
- 添加基础安装示例 `examples/basic-install.sh`
- 添加高级安装示例 `examples/advanced-install.sh`
- 添加卸载示例 `examples/uninstall.sh`
- 添加示例说明文档 `examples/README.md`

### 变更
- 无

### 修复
- 无

### 弃用
- 无

### 移除
- 无

### 性能
- 无

### 安全
- 建议在配置文件 `/etc/zerotier-gateway.conf` 中限制接口令牌权限（如存储）

## [1.2.1 历史补充] - 2025-10-18

### 新增
- 详细的实时进度显示（12步可视化）
- 每步骤耗时统计
- 可视化进度条（50字符宽）
- 彩色输出增强可读性
- 智能内网检测（自动识别私有 IP 网段）
- 配置备份回滚功能
- 网络冲突检测（端口占用、VPN 冲突、防火墙状态）
- MTU 自动优化
- 错误回滚机制

### 变更
- 优化确认流程（默认显示确认提示）
- 改进安装脚本用户体验

## [1.2.0] - 之前版本

### 新增
- 基础 VPN 网关功能
- 内网穿透支持
- OpenVPN 协同
- 自动路由配置（使用接口令牌）
- 一键安装脚本
- 持久化配置

### 修复
- 多项稳定性修复

## 版本规范

本项目遵循 [语义化版本](https://semver.org/lang/zh-CN/)：
- **主版本 (x.0.0)**：破坏性改动
- **次版本 (0.x.0)**：向后兼容的功能新增
- **补丁版本 (0.0.x)**：向后兼容的错误修复
