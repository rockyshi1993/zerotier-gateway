# 发布验证

本文记录正式发布前后的最小检查链。当前发布版本为 `v1.3.0`。

## 发布前检查

确认工作区没有误删文件：

```bash
git status --short
```

确认目标 tag 不存在：

```bash
git tag --list v1.3.0
git ls-remote --tags origin refs/tags/v1.3.0
```

执行脚本语法检查：

```bash
bash -n zerotier-gateway-setup.sh
bash -n scripts/ubuntu/*.sh
bash -n scripts/ubuntu/lib/*.sh
```

执行现有自动化验证：

```bash
bash tests/shell/env-parse.test.sh
powershell -NoProfile -ExecutionPolicy Bypass -File tests/powershell/ProxyRules.Tests.ps1
```

执行差异检查：

```bash
git diff --check
```

## 发布步骤

提交发布变更：

```bash
git add .
git commit -m "chore: prepare v1.3.0 release"
```

创建 tag：

```bash
git tag -a v1.3.0 -m "v1.3.0"
```

推送主分支和 tag：

```bash
git push origin main
git push origin v1.3.0
```

如果本机已登录 GitHub CLI，可以创建 GitHub Release。发布说明建议采用 `CHANGELOG.md` 中 `v1.3.0` 段落的用户可见变更摘要：

```bash
gh release create v1.3.0 --title "v1.3.0" --generate-notes
```

## 发布后验收

确认远端 tag 存在：

```bash
git ls-remote --tags origin refs/tags/v1.3.0
```

确认 GitHub Release 存在：

```bash
gh release view v1.3.0
```

再次确认 README 的快速开始仍指向当前主流程：

- 默认读取项目根目录 `.env`。
- Ubuntu 入口为 `scripts/ubuntu/install.sh`。
- Windows 入口为 `scripts/windows/setup.ps1`。
- 代理排除规则入口为 `docs/proxy-rules.md`。

## 已知限制

- 本项目当前没有包管理器发布面，不执行 npm、PyPI 或容器镜像发布。
- 本项目当前没有 GitHub Actions 工作流；远端 CI 验收为不适用，本地测试是发布前主验证链。
- 真实 ZeroTier 网络、Ubuntu 服务安装和 Windows 防火墙变更需要在目标机器上按安装指南实测。
