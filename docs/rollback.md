# 回滚与卸载

## Ubuntu

```bash
sudo bash scripts/ubuntu/uninstall.sh
```

该命令会移除本项目管理的代理服务，默认不会卸载 ZeroTier。

停用中转：

```bash
sudo bash scripts/ubuntu/disable-relay.sh
```

## Windows

移除本项目创建的 Windows 防火墙规则：

```powershell
.\scripts\windows\setup.ps1 -Rollback
```

生成的 PAC 和本地客户端配置位于 `artifacts/` 目录，可按需手动删除。

## 发布回滚

如果发布过程中发现 `vX.Y.Z` tag 或 GitHub Release 创建错误，先确认没有用户正在基于该版本安装或测试，再执行回滚。

本地 tag 回滚：

```bash
git tag -d vX.Y.Z
```

远端 tag 回滚：

```bash
git push origin :refs/tags/vX.Y.Z
```

GitHub Release 回滚：

```bash
gh release delete vX.Y.Z --yes
```

如果发布 commit 已经推送但需要撤回，优先使用 `git revert <commit>` 创建反向提交，再重新发布补丁版本。不要在共享分支上使用强制推送覆盖历史，除非仓库维护者明确确认。

发布后验收失败时，建议按以下顺序处理：

1. 停止继续传播 Release 链接。
2. 在 GitHub Release 说明中标记已撤回或直接删除错误 Release。
3. 删除错误 tag。
4. 用 `git revert` 或补丁 commit 修复主分支。
5. 重新运行发布验证后发布新的补丁版本。
