# NAT VLess Installer

一键部署 VLESS-REALITY (Sing-box) 到 Alpine Linux NAT VPS / 容器。

## 使用

```bash
curl -fsSL https://raw.githubusercontent.com/shali10/nat-vless-installer/main/install.sh | bash
```

## 特性

- 防火墙 iptables 持久化（OpenRC 启动自动恢复）
- SSH 端口防护
- GitHub API 防限流（3 次重试 + fallback 版本）
- 可卸载（脚本自带卸载指引）
- 支持 NAT VPS 内网/公网端口映射
