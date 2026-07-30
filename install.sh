#!/bin/sh
# ============================================================
# NAT 小鸡 VLESS-REALITY (Sing-box) 一键安装
# 适用: Alpine Linux / NAT VPS / LXC 容器
# 修复: 防火墙持久化 / SSH 防护 / 卸载入口
# ============================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
PLAIN='\033[0m'

clear

printf "${GREEN}====================================================${PLAIN}\n"
printf "${GREEN}🚀  NAT 小鸡 VLESS-REALITY (Sing-box)${PLAIN}\n"
printf "${GREEN}     防火墙持久化 / SSH 防护 / 可卸载${PLAIN}\n"
printf "${GREEN}====================================================${PLAIN}\n\n"

# ============================================================
# 1. 架构与虚拟化检测
# ============================================================
ARCH=$(uname -m)
case "$ARCH" in
    x86_64|amd64)  SINGBOX_ARCH="amd64"  ;;
    aarch64|arm64) SINGBOX_ARCH="arm64"  ;;
    armv7l|armhf)  SINGBOX_ARCH="armv7"  ;;
    *)
        printf "${RED}不支持的系统架构: $ARCH${PLAIN}\n"
        exit 1
        ;;
esac

VTYPE="KVM/BareMetal"
if [ -f /proc/user_beancounters ]; then
    VTYPE="OpenVZ"
elif grep -q 'container=lxc' /proc/1/environ 2>/dev/null || grep -qa 'lxc' /proc/1/cgroup 2>/dev/null; then
    VTYPE="LXC"
elif grep -qa 'docker' /proc/1/cgroup 2>/dev/null; then
    VTYPE="Docker"
fi

printf "${BLUE}[环境] 架构: ${SINGBOX_ARCH} | 虚拟化: ${VTYPE}${PLAIN}\n\n"

# ============================================================
# 2. 端口输入
# ============================================================

# SSH 端口（用于防火墙放行）
while true; do
    printf "${YELLOW}SSH 端口 (内网/公网，例如 22/43694): ${PLAIN}"
    read ssh_input
    [ -z "$ssh_input" ] && continue
    ssh_internal=$(echo "$ssh_input" | cut -d'/' -f1)
    ssh_external=$(echo "$ssh_input" | cut -d'/' -f2)
    if echo "$ssh_internal" | grep -qE '^[0-9]+$' && echo "$ssh_external" | grep -qE '^[0-9]+$'; then
        break
    else
        printf "${RED}格式错误，请按 内网端口/公网端口 输入数字${PLAIN}\n"
    fi
done

# 节点端口
while true; do
    printf "${YELLOW}节点端口 (内网/公网，例如 20000/32090): ${PLAIN}"
    read node_input
    [ -z "$node_input" ] && continue
    node_internal=$(echo "$node_input" | cut -d'/' -f1)
    node_external=$(echo "$node_input" | cut -d'/' -f2)
    if echo "$node_internal" | grep -qE '^[0-9]+$' && echo "$node_external" | grep -qE '^[0-9]+$'; then
        break
    else
        printf "${RED}格式错误，请按 内网端口/公网端口 输入数字${PLAIN}\n"
    fi
done

# ============================================================
# 3. SNI 选择
# ============================================================
echo ""
printf "${YELLOW}SNI 伪装域名:${PLAIN}\n"
echo "1) www.yahoo.com"
echo "2) www.icloud.com"
echo "3) 自定义"
printf "选择 [1-3] (默认 2): "
read sni_choice
case "$sni_choice" in
    1) SNI="www.yahoo.com" ;;
    3)
        printf "自定义 SNI: "
        read custom_sni
        SNI=${custom_sni:-"www.icloud.com"}
        ;;
    *) SNI="www.icloud.com" ;;
esac

# ============================================================
# 4. 清理旧环境
# ============================================================
printf "\n${BLUE}[1/7] 清理旧环境...${PLAIN}\n"

if [ -f /etc/init.d/sing-box ]; then
    rc-service sing-box stop >/dev/null 2>&1 || true
    rc-update del sing-box >/dev/null 2>&1       || true
fi
pkill -f sing-box 2>/dev/null || true

rm -rf \
    /usr/local/bin/sing-box \
    /etc/sing-box \
    /usr/local/bin/vless \
    /tmp/sing-box.tar.gz \
    /tmp/sing-box-*

# ============================================================
# 5. 安装依赖
# ============================================================
printf "${BLUE}[2/7] 安装系统依赖...${PLAIN}\n"
apk update >/dev/null
apk add --no-cache curl wget tar openssl ca-certificates openrc iptables ip6tables >/dev/null 2>&1
mkdir -p /etc/sing-box

# ============================================================
# 6. 下载 Sing-box
# ============================================================
printf "${BLUE}[3/7] 下载 Sing-box...${PLAIN}\n"

# 安全获取 latest tag（重试 3 次防 GitHub API 限流）
LATEST_TAG=""
for i in 1 2 3; do
    LATEST_TAG=$(curl -sL --connect-timeout 5 \
        -H "Accept: application/vnd.github+json" \
        "https://api.github.com/repos/SagerNet/sing-box/releases/latest" 2>/dev/null \
        | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
    [ -n "$LATEST_TAG" ] && break
    sleep 1
done

# Fallback 版本
[ -z "$LATEST_TAG" ] && LATEST_TAG="v1.10.1"
VERSION=${LATEST_TAG#v}

DOWNLOAD_URL="https://github.com/SagerNet/sing-box/releases/download/${LATEST_TAG}/sing-box-${VERSION}-linux-${SINGBOX_ARCH}.tar.gz"

if ! wget -q -O /tmp/sing-box.tar.gz "$DOWNLOAD_URL" || [ ! -s /tmp/sing-box.tar.gz ]; then
    printf "${RED}下载失败，请检查网络或 GitHub 连通性${PLAIN}\n"
    printf "${RED}  $DOWNLOAD_URL${PLAIN}\n"
    exit 1
fi

tar -zxvf /tmp/sing-box.tar.gz -C /tmp/ >/dev/null
mv "/tmp/sing-box-${VERSION}-linux-${SINGBOX_ARCH}/sing-box" /usr/local/bin/
chmod +x /usr/local/bin/sing-box
rm -rf /tmp/sing-box.tar.gz "/tmp/sing-box-${VERSION}-linux-${SINGBOX_ARCH}"

# ============================================================
# 7. 获取公网 IP
# ============================================================
printf "${BLUE}[4/7] 获取公网 IP...${PLAIN}\n"
IP=$(curl -s4 --connect-timeout 5 icanhazip.com)
[ -z "$IP" ] && IP=$(curl -s4 --connect-timeout 5 ip.sb)
[ -z "$IP" ] && IP=$(curl -s4 --connect-timeout 5 api.ipify.org)

if [ -z "$IP" ]; then
    printf "${RED}无法获取公网 IP，请确认 IPv4 出站正常${PLAIN}\n"
    exit 1
fi

# ============================================================
# 8. 生成 UUID / Reality 密钥
# ============================================================
printf "${BLUE}[5/7] 生成密钥...${PLAIN}\n"
UUID=$(/usr/local/bin/sing-box generate uuid)
KEYPAIR=$(/usr/local/bin/sing-box generate reality-keypair)
PRIVATE_KEY=$(echo "$KEYPAIR" | grep 'PrivateKey' | awk '{print $2}')
PUBLIC_KEY=$(echo "$KEYPAIR"  | grep 'PublicKey'  | awk '{print $2}')
SHORT_ID=$(openssl rand -hex 4)

# ============================================================
# 9. 写入 Sing-box 配置
# ============================================================
printf "${BLUE}[6/7] 写入配置...${PLAIN}\n"

cat > /etc/sing-box/config.json <<EOF
{
  "log": {
    "level": "warn"
  },
  "inbounds": [
    {
      "type": "vless",
      "tag": "vless-in",
      "listen": "0.0.0.0",
      "listen_port": $node_internal,
      "users": [
        {
          "uuid": "$UUID",
          "flow": "xtls-rprx-vision"
        }
      ],
      "tls": {
        "enabled": true,
        "server_name": "$SNI",
        "reality": {
          "enabled": true,
          "handshake": {
            "server": "$SNI",
            "port": 443
          },
          "private_key": "$PRIVATE_KEY",
          "short_id": [
            "$SHORT_ID"
          ]
        }
      }
    }
  ],
  "outbounds": [
    {
      "type": "direct",
      "tag": "direct"
    }
  ]
}
EOF

/usr/local/bin/sing-box check -c /etc/sing-box/config.json >/dev/null 2>&1 || {
    printf "${RED}配置文件校验失败，请检查参数${PLAIN}\n"
    exit 1
}

# ============================================================
# 10. 防火墙配置（持久化）
# ============================================================
printf "${BLUE}[7/7] 防火墙规则 (iptables 持久化)...${PLAIN}\n"

# 写入规则文件 — 用 iptables-restore 格式，OpenRC 启动时自动应用
FWRULES="/etc/sing-box/firewall.rules"
cat > "$FWRULES" <<FEOF
# Sing-box 防火墙规则（由安装脚本生成）
# OpenRC 启动时自动恢复
*filter
:INPUT ACCEPT [0:0]
:FORWARD ACCEPT [0:0]
:OUTPUT ACCEPT [0:0]
-A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
-A INPUT -i lo -j ACCEPT
-A INPUT -p tcp --dport $ssh_internal -j ACCEPT
-A INPUT -p tcp --dport $node_internal -j ACCEPT
-A INPUT -p udp --dport $node_internal -j ACCEPT
COMMIT
FEOF

# 热应用
iptables-restore < "$FWRULES" 2>/dev/null || {
    # 降级：逐条添加
    iptables -I INPUT -p tcp --dport "$ssh_internal"  -j ACCEPT 2>/dev/null || true
    iptables -I INPUT -p tcp --dport "$node_internal" -j ACCEPT 2>/dev/null || true
    iptables -I INPUT -p udp --dport "$node_internal" -j ACCEPT 2>/dev/null || true
}

# ============================================================
# 11. OpenRC 服务注册
# ============================================================
printf "${BLUE}[8/7] 注册 OpenRC 服务...${PLAIN}\n"

cat > /etc/init.d/sing-box <<'SERVEOF'
#!/sbin/openrc-run
description="Sing-box Proxy Service"
command="/usr/local/bin/sing-box"
command_args="run -c /etc/sing-box/config.json"
pidfile="/run/sing-box.pid"
command_background=true

depend() {
    need net
}

start_pre() {
    # 重启后自动恢复防火墙规则
    if [ -f /etc/sing-box/firewall.rules ]; then
        iptables-restore < /etc/sing-box/firewall.rules 2>/dev/null || true
    fi
}
SERVEOF

chmod +x /etc/init.d/sing-box
rc-update add sing-box default >/dev/null 2>&1
rc-service sing-box restart >/dev/null 2>&1

# ============================================================
# 12. 快捷查询脚本
# ============================================================
cat > /usr/local/bin/vless <<VLINEOF
#!/bin/sh

echo ""
echo "========== VLESS REALITY (Sing-box) =========="
echo ""
echo "虚拟化:    $VTYPE"
echo "公网 IP:   $IP"
echo "公网端口:  $node_external"
echo "内网端口:  $node_internal"
echo "SSH 端口:  $ssh_external (内网: $ssh_internal)"
echo "UUID:      $UUID"
echo "PublicKey: $PUBLIC_KEY"
echo "ShortID:   $SHORT_ID"
echo "SNI:       $SNI"
echo ""
echo "VLESS 链接:"
echo "vless://$UUID@$IP:$node_external?encryption=none&flow=xtls-rprx-vision&security=reality&sni=$SNI&fp=chrome&pbk=$PUBLIC_KEY&sid=$SHORT_ID&type=tcp#NAT-SingBox"
echo ""
echo "--- 管理 ---"
echo "启动: rc-service sing-box start"
echo "停止: rc-service sing-box stop"
echo "重启: rc-service sing-box restart"
echo "状态: rc-service sing-box status"
echo "日志: tail -f /var/log/sing-box.log"
echo ""
echo "--- 卸载 ---"
echo "rc-service sing-box stop"
echo "rc-update del sing-box"
echo "rm -f /etc/init.d/sing-box"
echo "rm -rf /etc/sing-box"
echo "rm -f /usr/local/bin/sing-box"
echo "rm -f /usr/local/bin/vless"
echo ""
VLINEOF
chmod +x /usr/local/bin/vless

# ============================================================
# 完成
# ============================================================
echo ""
printf "${GREEN}====================================================${PLAIN}\n"
printf "${GREEN}✅ 安装成功${PLAIN}\n"
printf "${GREEN}${PLAIN}\n"
printf "${GREEN}   输入 ${YELLOW}vless${GREEN} 查看节点链接和配置信息${PLAIN}\n"
printf "${GREEN}   管理: ${YELLOW}rc-service sing-box {start|stop|restart|status}${PLAIN}\n"
printf "${GREEN}   卸载: ${YELLOW}执行 vless 里的卸载命令${PLAIN}\n"
printf "${GREEN}====================================================${PLAIN}\n"
