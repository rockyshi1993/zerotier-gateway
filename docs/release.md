# 发布验证

本文是**仓库维护者**的发布检查模板，不是普通用户安装步骤。历史标签 `v1.3.0` 已存在，**不能照抄该标签重新创建**；`VERSION=1.4.0-dev` 是开发标识，也不代表可以发布为稳定版本。执行前必须先确认本次正式发布的目标版本号、CHANGELOG 和远端 tag 状态。

## 发布前检查

确认工作区没有误删文件：

```bash
git status --short
```

确认目标 tag 不存在：

```bash
# 示例：在真正发布前将 vX.Y.Z 替换为已确认的、尚未发布的正式版本（非 -dev）
RELEASE_TAG='vX.Y.Z'
# 注意：此处是模板占位符；替换之前不要继续执行
# 验证格式和不存在性：不要把 vX.Y.Z 或 -dev 标记当成正式发布版
[[ "$RELEASE_TAG" =~ ^v[0-9]+\\.[0-9]+\\.[0-9]+$ ]] || echo "ERROR: 请先替换成正式版本号；不要继续发布"
git tag --list "$RELEASE_TAG"
git ls-remote --tags origin "refs/tags/$RELEASE_TAG"
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
bash tests/shell/init-config.test.sh
# 在 Linux/macOS 的 Bash 终端
for test in tests/shell/*.test.sh; do bash "$test"; done
```

Windows 使用 **PowerShell** 运行所有回归测试（与 Bash 分开执行）：

```powershell
Get-ChildItem tests/powershell -Filter '*.Tests.ps1' | ForEach-Object { & $_.FullName }
```

执行差异检查：

```bash
git diff --check
```

验证用户文档和 GitHub Pages 构建产物：

```bash
cd website
npm ci
npm run verify
cd ..
```

## 发布步骤

提交发布变更：

```bash
git add .
git commit -m "chore: prepare $RELEASE_TAG release"
```

只有在前面的检查确认**本地和远端都不存在目标正式 tag**、当前分支和源码状态正确、需要的 CI 已通过后才能创建 tag：

```bash
git tag -a "$RELEASE_TAG" -m "$RELEASE_TAG"
```

推送主分支和 tag：

```bash
git push origin main
git push origin "$RELEASE_TAG"
```

如果本机已登录 GitHub CLI，可以创建 GitHub Release。发布说明建议采用 `CHANGELOG.md` 中本次实际 `$RELEASE_TAG` 对应的用户可见变更摘要：

```bash
gh release create "$RELEASE_TAG" --title "$RELEASE_TAG" --generate-notes
```

## 发布后验收

确认远端 tag 存在：

```bash
git ls-remote --tags origin "refs/tags/$RELEASE_TAG"
```

确认 GitHub Release 存在：

```bash
gh release view "$RELEASE_TAG"
```

再次确认 README 的快速开始仍指向当前主流程：

- 普通用户通过 `init-config.sh` 或 `init-config.ps1` 生成项目配置，不需要手工编辑 `.env`。
- Ubuntu **首次安装**优先按 `install-zerotier.sh` → Central 授权/确认 Managed IP → `install-proxy.sh` 两阶段进行；`install.sh` 是既有一体化入口，不能在网络 IP 未就绪时无条件使用。
- Windows 入口为 `scripts/windows/setup.ps1`。
- 代理排除规则入口为 `docs/proxy-rules.md`。

确认仓库的 **Settings → Pages → Build and deployment → Source** 已选择 **GitHub Actions**，再检查 `Documentation site` 工作流的 build 和 deploy 都成功；最后直接打开站点首页、快速开始和至少一个任务页，确认刷新后仍能访问。

## 已知限制

- 本项目当前没有包管理器发布面，不执行 npm、PyPI 或容器镜像发布。
- `.github/workflows/pages.yml` 负责站点构建与部署；Shell/PowerShell 行为测试应由单独 CI 作业验证。真实联网测试仍需在目标设备上完成，远端 Pages 部署也必须在推送后确认。
- 真实 ZeroTier 网络、Ubuntu 服务安装和 Windows 防火墙变更需要在目标机器上按安装指南实测。
