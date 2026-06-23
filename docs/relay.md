# 中转兜底

中转是可选能力，不是默认主路径。

只有满足下面情况时才考虑启用：

1. 家里电脑和公司电脑长期无法建立直连。
2. 远程访问体验明显较差。
3. UDP 或 NAT 条件无法继续优化。

先预览：

```bash
sudo bash scripts/ubuntu/install-relay.sh --dry-run
```

安装或接入中转服务：

```bash
sudo bash scripts/ubuntu/install-relay.sh
```

停用：

```bash
sudo bash scripts/ubuntu/disable-relay.sh
```

直连工作良好时，不要用中转替代正常直连。
