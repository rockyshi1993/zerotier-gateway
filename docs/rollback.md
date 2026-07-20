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

该命令会停用并移除本项目生成的 `zerotier-gateway-relay-*.socket` 和 `zerotier-gateway-relay-*.service`。默认不会影响 ZeroTier 本身和代理服务。

新增能力按对象单独关闭或删除，不需要卸载整套网络：

```bash
sudo bash scripts/ubuntu/manage-rate-limit.sh disable --name <规则名> --apply
sudo bash scripts/ubuntu/manage-rate-limit.sh remove --name <规则名> --apply
sudo bash scripts/ubuntu/manage-exit-node.sh disable --apply
sudo bash scripts/ubuntu/manage-publish.sh remove --name <映射名> --apply
sudo bash scripts/ubuntu/manage-publish.sh remove-domain --name <域名映射名> --apply
```

管理层升级只回退 state，使用升级输出的 backup id：

```bash
sudo bash scripts/ubuntu/upgrade.sh --rollback <backup-id>
```

## Windows

用管理员 PowerShell 移除本项目创建的 Windows 防火墙规则：

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
.\scripts\windows\setup.ps1 -Rollback
```

停用自动代理入口但保留节点：

```powershell
.\scripts\windows\manage-proxy-pool.ps1 -Action Disable -Apply
```

完全移除自动代理任务和项目运行文件：

```powershell
.\scripts\windows\manage-proxy-pool.ps1 -Action Remove -Apply -ConfirmRemoval
```

Windows 管理状态回退：

```powershell
.\scripts\windows\upgrade.ps1 -Rollback <backup-id> -Apply
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
