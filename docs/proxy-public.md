# 高风险高级配置：公网 HTTP/SOCKS5 代理

**优先使用 ZeroTier 私有代理。不要仅为了“提速”就默认将混合代理端口直接开放互联网。** 本项目当前公网上的 sing-box mixed HTTP/SOCKS5 入口没有配置 TLS；**用户名密码认证不等于连接被加密**。公网部署必须自行评估连接加密、来源访问控制、云安全组和代理滥用风险。

若需求是手机移动数据整机通过 Ubuntu 出口，同时希望入口只在 ZeroTier 私网中，请使用[IPv4 Exit Node](exit-node.md)，通常不需要暴露公网 `10808/tcp`。

## 什么时候才考虑公网入口

- 客户端无法加入 ZeroTier，且你已经有经批准、可验证的安全封装或额外加密通道。
- 已经过实测证明私网路径不可用，并且清楚理解明文混合代理的身份凭据和数据暴露边界。

**以下情形不推荐：** 无来源限制、未启用认证、没有加密保护而长期对整个互联网开放；使用简单密码的公网代理；将生产管理端口顺带暴露。

## 实际变更范围

在 Ubuntu 仓库中运行：

```bash
bash scripts/ubuntu/init-config.sh
sudo bash scripts/ubuntu/install-proxy.sh --dry-run
sudo bash scripts/ubuntu/install-proxy.sh
sudo bash scripts/ubuntu/health-check.sh
```

初始化选择公网入口后，当前脚本可能改为监听 `0.0.0.0:10808`，并修改 UFW 相关规则，`install-proxy.sh` 会重启 sing-box 服务；因此可能影响已有代理连接。`--dry-run` 会预览系统动作，但可能在工作目录生成含凭据的 JSON 配置，不是严格无文件写入。

至少应明确来源 IP/CIDR、代理认证和云安全组限制。然而**这些措施仍不等于为混合代理添加 TLS**。若需要从不可信互联网安全使用，优先采用经过独立审核的加密传输方案，而非依赖此功能本身。

## 客户端和验证

没有加入 ZeroTier 的客户端需要在代理软件中设置服务器公网 IP、实际端口，以及如已开启的认证。**没有安全传输层时，不建议在公网环境使用实际账号口令进行测试。**

在防火墙、安全组与额外加密通道已正确部署的受控环境中，先检查目标端口（不传输实际密码）：

```powershell
Test-NetConnection <服务器公网IP> -Port 10808
```

这只证明 TCP 可达。随后需要在安全传输通道内分别验证合法来源的代理出口、非授权来源的拒绝结果以及服务日志。不要因为 `0.0.0.0:10808` 存在监听就认定公网应用安全或可用。

## 关闭公网入口

在 Ubuntu 重新运行初始化器将公网入口选择为关闭，并刷新服务：

```bash
bash scripts/ubuntu/init-config.sh
sudo bash scripts/ubuntu/install-proxy.sh --dry-run
sudo bash scripts/ubuntu/install-proxy.sh
sudo ss -lntp | grep ':10808'
```

检查代理是否恢复为仅监听实际 ZeroTier 私网 IP，随后在云安全组/边界防火墙**撤销此前开放的公网端口**。在变更前后核对现有 UFW 规则：当前旧代码包含按端口删除规则的路径，未必只删除项目自有规则，必要时先保存防火墙快照。

关闭公网入口不等于删除 ZeroTier 网络或其他可选的站点发布能力。参见[安全说明](security.md)及[回滚与卸载](rollback.md)。
