# 项目状态与路线图

## 当前状态

**版本**: 1.2.2  
**维护状态**: 重构中
**稳定性**: 新脚本为首版预览，旧脚本保留历史兼容

## 当前重构方向

项目当前主线已从旧“Linux 全局网关”转向更简单的个人远程场景：

- 一个 ZeroTier 私有局域网。
- 家里电脑和公司电脑通过 ZeroTier IP 双向远程，优先 DIRECT。
- Ubuntu 服务器提供私有 HTTP/SOCKS5 代理。
- 域名/IP/进程排除规则按需生成。
- 中转只在直连体验差时启用。

默认配置入口为项目根目录 `.env`，普通命令不需要反复传配置路径。

---

## 历史状态

---

## 已实现功能

### 核心功能
- ✅ VPN 全局出站（所有客户端流量通过网关）
- ✅ 内网穿透（远程访问局域网设备）
- ✅ OpenVPN 协同（智能流量分流）
- ✅ 自动路由配置（使用 API Token）
- ✅ 一键安装脚本
- ✅ 持久化配置（重启自动恢复）

### v1.2.2 新功能（安全与用户体验改进）
- ✅ 预安装系统检查（root、磁盘、网络、负载）
- ✅ 配置文件安全加固（chmod 600, root:root）
- ✅ 状态查询功能（-s, --status）
- ✅ 友好的错误消息（Network ID 验证）

### v1.2.1 功能
- ✅ 详细进度显示（12步可视化）
- ✅ 智能内网检测（自动识别私有 IP）
- ✅ 配置备份回滚
- ✅ 网络冲突检测
- ✅ MTU 自动优化
- ✅ 耗时统计
- ✅ 确认提示优化

### 测试与质量保证
- ✅ 单元测试套件（Network ID、网段验证、CIDR 格式等）
- ✅ 集成测试套件（系统依赖、iptables、网络接口等）
- ✅ 测试运行框架
- ✅ 使用示例（基础、高级、卸载）

### 文档
- ✅ 详细的 README.md
- ✅ CHANGELOG.md
- ✅ STATUS.md（本文件）
- ✅ 使用示例文档

---

## 进行中

### 中优先级改进
- 🔄 Dry-run 模式（预览不执行）
- 🔄 配置修改功能（无需重装）

### 测试增强
- 🔄 添加端到端测试
- 🔄 添加性能基准测试
- 🔄 CI/CD 集成（GitHub Actions）

### 文档改进
- 🔄 故障排查示例
- 🔄 自定义内网网段示例
- 🔄 API Token 自动配置示例

---

## 计划中

### 功能增强（v1.3.0）
- 📋 IPv6 支持
- 📋 多网关负载均衡
- 📋 流量统计和监控
- 📋 Web 管理界面（可选）
- 📋 DNS 转发配置
- 📋 QoS（流量优先级）支持

### 安全增强
- 📋 API Token 加密存储
- 📋 iptables 规则审计
- 📋 安全扫描集成
- 📋 自动安全更新

### 平台支持
- 📋 Docker 容器支持
- 📋 macOS 支持（测试）
- 📋 FreeBSD 支持（实验性）

### 工具改进
- 📋 健康检查命令
- 📋 日志分析工具
- 📋 配置导入/导出
- 📋 批量部署工具

### 测试与质量
- 📋 自动化测试覆盖率 >80%
- 📋 性能基准测试
- 📋 压力测试
- 📋 兼容性测试矩阵

---

## 已知问题

### 高优先级
- 无

### 中优先级
- ⚠️ 某些 Linux 发行版的 iptables 规则保存方式不统一
- ⚠️ MTU 测试在无网络环境可能失败
- ⚠️ 未检测 nftables vs iptables 冲突

### 低优先级
- 💡 备份目录未检查磁盘空间
- 💡 未处理多个 ZeroTier 接口的情况

---

## 版本计划

### v1.2.2（补丁版本）- 2025-11
- 修复已知问题
- 改进错误处理
- 优化测试覆盖率

### v1.3.0（次要版本）- 2025-12
- IPv6 支持
- 流量统计
- Web 管理界面

### v2.0.0（主要版本）- 2026-Q1
- 架构重构
- 多网关支持
- 完整的监控系统

---

## 贡献指南

欢迎贡献！请参考以下流程：

1. **报告问题**: 在 [GitHub Issues](https://github.com/rockyshi1993/zerotier-gateway/issues) 提交
2. **功能建议**: 在 Issues 中标记为 `enhancement`
3. **提交代码**: 
   - Fork 项目
   - 创建功能分支（`git checkout -b feature/your-feature`）
   - 编写测试用例
   - 提交变更（`git commit -m 'feat: add some feature'`）
   - 推送到分支（`git push origin feature/your-feature`）
   - 创建 Pull Request

4. **代码规范**:
   - 遵循 Shell 脚本最佳实践
   - 添加适当的注释
   - 包含测试用例
   - 更新文档

---

## 支持的平台

### 已测试
- ✅ Ubuntu 20.04 / 22.04 / 24.04
- ✅ Debian 10 / 11 / 12
- ✅ CentOS 7 / 8
- ✅ RHEL 7 / 8 / 9
- ✅ Fedora 38+

### 理论支持
- ⚪ Rocky Linux
- ⚪ AlmaLinux
- ⚪ Amazon Linux 2

---

## 社区

- **项目主页**: https://github.com/rockyshi1993/zerotier-gateway
- **问题追踪**: https://github.com/rockyshi1993/zerotier-gateway/issues
- **讨论**: GitHub Discussions

---

## 许可证

MIT License - 详见 [LICENSE](LICENSE) 文件

---

**最后更新**: 2025-10-18  
**维护者**: rockyshi1993
