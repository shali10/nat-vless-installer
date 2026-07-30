# NAT VPS 代理一键安装 (Sing-box)

适用于 **NAT VPS、低配小鸡、LXC 容器**的一键代理安装脚本，基于 Sing-box 核心。

**无需配置环境，只要一个 curl 命令。**

## 快速开始

```bash
curl -fsSL https://github.com/shali10/nat-vless-installer/raw/main/install.sh | bash
```

然后按照提示选择协议、输入端口即可。

## 系统要求

| 项目 | 要求 |
|---|---|
| 系统 | Alpine Linux / Debian / Ubuntu / CentOS / Rocky / AlmaLinux |
| 架构 | x86_64 / arm64 / armv7 |
| 网络 | 公网 IPv4（NAT VPS 有映射端口即可） |
| 依赖 | 脚本自动安装，无需预先准备 |

> 在 LXC 容器中运行需要 iptables 权限（向宿主要求 `lxc.cap.drop =` 放行 netfilter）。
> 如没有 iptables 权限，脚本会自动跳过防火墙配置，不影响代理运行。

## 使用流程

运行后：

```
1️⃣ 选择协议（默认 VLESS + Reality，无需域名）
2️⃣ 输入节点端口（内网/公网，NAT VPS 格式）
3️⃣ 输入 SSH 端口（防火墙放行用）
4️⃣ 等待脚本自动完成
```

全部自动化，不需要写配置文件、不需要安装证书（Reality / Hysteria2 / Shadowsocks），**开箱即用**。

### 协议选择说明

| 选项 | 协议 | 推荐场景 | 需域名 |
|---|---|---|---|
| 1 | **VLESS + Reality** (默认) | 最隐蔽，流量像正常 TLS；NAT VPS 首选 | ❌ |
| 2 | VLESS + WebSocket + TLS | 需要套 CDN（Cloudflare）加速 | ✅ |
| 3 | VLESS + TCP + TLS | 标准 TLS，配合回落使用 | ✅ |
| 4 | **Hysteria2** | 高丢包网络（如跨国连接）加速 | ❌ |
| 5 | Shadowsocks | 轻量旧设备兼容 | ❌ |
| 6 | Trojan + TLS | 传统稳定方案 | ✅ |

### 端口输入格式

NAT VPS 的内网端口和公网端口通常不同，按 `内网端口/公网端口` 格式输入：

```
节点端口 (内网/公网，如 20000/32090): 20000/32090
SSH 端口  (内网/公网，如 22/43694):   22/43694
```

脚本会自动放行防火墙、生成配置。

## 安装后的管理

### 查看节点信息

```bash
vps-info
```

显示协议、IP、端口、UUID 等连接信息。

### 服务管理

**systemd 系统（Debian/Ubuntu/CentOS）:**

```bash
systemctl status sing-box      # 查看状态
systemctl restart sing-box     # 重启
systemctl stop sing-box        # 停止
journalctl -u sing-box -f      # 查看日志
```

**OpenRC 系统（Alpine）:**

```bash
rc-service sing-box status     # 查看状态
rc-service sing-box restart    # 重启
rc-service sing-box stop       # 停止
```

### 配置文件

```bash
/etc/sing-box/config.json      # 主配置
/etc/sing-box/firewall.rules   # 防火墙规则
```

### 完整卸载

```bash
# systemd
systemctl stop sing-box
systemctl disable sing-box
rm -f /etc/systemd/system/sing-box.service
systemctl daemon-reload

# OpenRC
rc-service sing-box stop
rc-update del sing-box
rm -f /etc/init.d/sing-box

# 删除文件
rm -rf /etc/sing-box
rm -f /usr/local/bin/sing-box
rm -f /usr/local/bin/vps-info
```

## 客户端连接

脚本安装完成后输出对应的客户端链接（`vless://` / `hy2://` / `ss://` / `trojan://`），可直接复制到以下客户端中使用：

- **Windows**: v2rayN, Nekoray, Sing-box GUI
- **macOS**: Stash, Sing-box GUI, V2rayU
- **Android**: v2rayNG, Sing-box
- **iOS**: Shadowrocket, Stash

## 示例

**最小安装（NAT VPS 最常用配置）:**

```bash
curl -fsSL https://github.com/shali10/nat-vless-installer/raw/main/install.sh | bash
# 1 → Reality → 20000/32090 → 22/43694 → 2 (icloud)
```

**Shadowsocks 直连:**

```bash
curl -fsSL https://github.com/shali10/nat-vless-installer/raw/main/install.sh | bash
# 5 → 30000/43090 → 22/43694
```

## 已知限制

- Shadowsocks 加密方法 `2022-blake3-*` 在预编译的 Sing-box 中不可用，当前使用 `none` 方法
- Reality 协议需等客户端 UoT（UDP over TCP）支持才能完整转发 UDP 流量
- 需域名的协议（WS+TLS / TCP+TLS / Trojan）使用 acme.sh 自动申请 Let's Encrypt 证书，需要 80 端口临时可用

## 更新日志

- 多系统兼容（Alpine / Debian / Ubuntu / CentOS）
- 6 种协议支持（Reality / WS+TLS / TCP+TLS / Hysteria2 / Shadowsocks / Trojan）
- NAT 端口映射
- 防火墙持久化
- Alpine musl / glibc 自动选择
- 卸载入口
