#!/bin/sh
# ============================================================
# NAT VPS 代理一键安装 (Sing-box)
# 支持 6 种协议 · 多系统兼容 (Alpine/Debian/Ubuntu/CentOS)
# ============================================================
# 仓库: https://github.com/shali10/nat-vless-installer
# ============================================================


RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[0;33m'; BLUE='\033[0;34m'; PLAIN='\033[0m'
PROTOCOL=""; UUID=""; PASSWORD=""; METHOD=""
WS_PATH=""; SNI=""; DOMAIN=""
DISTRO=""; PKG_MGR=""; INIT_SYS=""

clear
printf "${GREEN}============================================================${PLAIN}\n"
printf "${GREEN}🚀  NAT VPS 代理一键安装 (Sing-box)${PLAIN}\n"
printf "${GREEN}     6 种协议 · Alpine/Debian/Ubuntu/CentOS${PLAIN}\n"
printf "${GREEN}============================================================${PLAIN}\n\n"

# ============================================================
# 1. 环境检测
# ============================================================
ARCH=$(uname -m)
case "$ARCH" in
    x86_64|amd64)  SINGBOX_ARCH="amd64"  ;;
    aarch64|arm64) SINGBOX_ARCH="arm64"  ;;
    armv7l|armhf)  SINGBOX_ARCH="armv7"  ;;
    *) printf "${RED}不支持的系统架构: $ARCH${PLAIN}\n"; exit 1 ;;
esac

VTYPE="KVM/BareMetal"
[ -f /proc/user_beancounters ] && VTYPE="OpenVZ"
grep -q 'container=lxc' /proc/1/environ 2>/dev/null || grep -qa 'lxc' /proc/1/cgroup 2>/dev/null && VTYPE="LXC"
grep -qa 'docker' /proc/1/cgroup 2>/dev/null && VTYPE="Docker"

# ---- 发行版检测 ----
IS_ALPINE=0
IS_MUSL=0
if grep -qi 'alpine' /etc/os-release 2>/dev/null; then
    DISTRO="alpine"; PKG_MGR="apk"; INIT_SYS="openrc"; IS_ALPINE=1; IS_MUSL=1
elif grep -qi 'debian\|ubuntu' /etc/os-release 2>/dev/null; then
    DISTRO="debian"; PKG_MGR="apt"; INIT_SYS="systemd"
    [ -f /etc/debian_version ] && DEBIAN_VER=$(cat /etc/debian_version | cut -d. -f1)
elif grep -qi 'centos\|rhel\|fedora\|rocky\|alma\|oracle' /etc/os-release 2>/dev/null; then
    DISTRO="rhel"; INIT_SYS="systemd"
    if command -v dnf >/dev/null 2>&1; then PKG_MGR="dnf"; else PKG_MGR="yum"; fi
else
    DISTRO="unknown"; INIT_SYS="unknown"
    if command -v apk >/dev/null 2>&1; then PKG_MGR="apk"; IS_ALPINE=1; IS_MUSL=1
    elif command -v apt >/dev/null 2>&1; then PKG_MGR="apt"; INIT_SYS="systemd"
    elif command -v dnf >/dev/null 2>&1; then PKG_MGR="dnf"; INIT_SYS="systemd"
    elif command -v yum >/dev/null 2>&1; then PKG_MGR="yum"; INIT_SYS="systemd"
    else printf "${RED}不支持的发行版${PLAIN}\n"; exit 1
    fi
fi

printf "${BLUE}[环境] ${DISTRO} | ${SINGBOX_ARCH} | ${VTYPE} | musl=$IS_MUSL | ${INIT_SYS}${PLAIN}\n\n"

# ============================================================
# 2. 协议选择
# ============================================================
printf "${YELLOW}请选择协议:${PLAIN}\n"
echo "1) VLESS + Reality (xtls-rprx-vision)   — 最隐蔽，无需域名 ← 推荐"
echo "2) VLESS + WebSocket + TLS              — 可套 CDN，需域名+证书"
echo "3) VLESS + TCP + TLS                    — 标准 TLS，需域名+证书"
echo "4) Hysteria2                            — QUIC 暴力加速"
echo "5) Shadowsocks + AEAD                   — 轻量经典"
echo "6) Trojan + TLS                         — 传统稳定，需域名+证书"
printf "选择 [1-6] (默认 1): "
read proto_choice
case "${proto_choice:-1}" in
    2) PROTOCOL="vless-ws"      ;;
    3) PROTOCOL="vless-tcp"     ;;
    4) PROTOCOL="hysteria2"     ;;
    5) PROTOCOL="shadowsocks"   ;;
    6) PROTOCOL="trojan"        ;;
    *) PROTOCOL="vless-reality" ;;
esac
printf "${GREEN}→ 协议: ${PROTOCOL}${PLAIN}\n\n"

# ============================================================
# 3. 输入
# ============================================================
while true; do
    printf "${YELLOW}节点端口 (内网/公网，如 20000/32090): ${PLAIN}"
    read node_input; [ -z "$node_input" ] && continue
    node_internal=$(echo "$node_input" | cut -d'/' -f1)
    node_external=$(echo "$node_input" | cut -d'/' -f2)
    echo "$node_internal" | grep -qE '^[0-9]+$' && echo "$node_external" | grep -qE '^[0-9]+$' && break
    printf "${RED}格式错误，请按 内网端口/公网端口 输入数字${PLAIN}\n"
done

while true; do
    printf "${YELLOW}SSH 端口 (内网/公网，如 22/43694): ${PLAIN}"
    read ssh_input; [ -z "$ssh_input" ] && continue
    ssh_internal=$(echo "$ssh_input" | cut -d'/' -f1)
    ssh_external=$(echo "$ssh_input" | cut -d'/' -f2)
    echo "$ssh_internal" | grep -qE '^[0-9]+$' && echo "$ssh_external" | grep -qE '^[0-9]+$' && break
    printf "${RED}格式错误，请按 内网端口/公网端口 输入数字${PLAIN}\n"
done

if [ "$PROTOCOL" = "vless-reality" ]; then
    printf "${YELLOW}SNI 伪装域名:${PLAIN}\n"
    echo "1) www.yahoo.com"; echo "2) www.icloud.com"; echo "3) 自定义"
    printf "选择 [1-3] (默认 2): "; read sni_choice
    case "$sni_choice" in
        1) SNI="www.yahoo.com" ;;
        3) printf "自定义 SNI: "; read custom_sni; SNI=${custom_sni:-"www.icloud.com"} ;;
        *) SNI="www.icloud.com" ;;
    esac
fi

needs_cert() { case "$PROTOCOL" in vless-ws|vless-tcp|trojan) return 0;; *) return 1;; esac; }
if needs_cert; then
    printf "${YELLOW}域名 (A 记录指向本机): ${PLAIN}"; read DOMAIN
    [ -z "$DOMAIN" ] && { printf "${RED}域名不能为空${PLAIN}\n"; exit 1; }
    printf "${YELLOW}邮箱 (Let\'s Encrypt 用): ${PLAIN}"; read EMAIL; EMAIL=${EMAIL:-"admin@${DOMAIN}"}
fi

[ "$PROTOCOL" = "vless-ws" ] && { printf "${YELLOW}WS 路径 (默认 /vless): ${PLAIN}"; read WS_PATH; WS_PATH=${WS_PATH:-"/vless"}; }
if [ "$PROTOCOL" = "shadowsocks" ] || [ "$PROTOCOL" = "hysteria2" ] || [ "$PROTOCOL" = "trojan" ]; then
    PASSWORD=$(openssl rand -base64 16 | tr -d '=+/')
fi

# ============================================================
# 4. 清理旧环境
# ============================================================
printf "\n${BLUE}[1/8] 清理旧环境...${PLAIN}\n"
if [ "$INIT_SYS" = "openrc" ] && [ -f /etc/init.d/sing-box ]; then
    rc-service sing-box stop >/dev/null 2>&1 || true
    rc-update del sing-box >/dev/null 2>&1 || true
elif systemctl is-active sing-box >/dev/null 2>&1; then
    systemctl stop sing-box 2>/dev/null || true
    systemctl disable sing-box 2>/dev/null || true
fi
pkill -f sing-box 2>/dev/null || true
rm -rf /usr/local/bin/sing-box /etc/sing-box /usr/local/bin/vps-info /tmp/sing-box.tar.gz /tmp/sing-box-*
rm -f /etc/systemd/system/sing-box.service 2>/dev/null || true

# ============================================================
# 5. 安装依赖
# ============================================================
printf "${BLUE}[2/8] 安装系统依赖...${PLAIN}\n"
case "$PKG_MGR" in
    apk)
        apk update >/dev/null
        apk add --no-cache curl wget tar openssl ca-certificates iptables ip6tables socat >/dev/null 2>&1
        # openrc 可能不是所有 Alpine 镜像都有
        apk add --no-cache openrc >/dev/null 2>&1 || true
        apk add --no-cache gcompat >/dev/null 2>&1 || true
        ;;
    apt)
        export DEBIAN_FRONTEND=noninteractive
        apt-get update -qq >/dev/null 2>&1 || true
        apt-get install -y -qq curl wget tar openssl ca-certificates iptables socat >/dev/null 2>&1 || true
        apt-get install -y -qq systemd >/dev/null 2>&1 || true
        ;;
    dnf|yum)
        $PKG_MGR install -y -q curl wget tar openssl ca-certificates iptables socat >/dev/null 2>&1 || true
        ;;
esac
mkdir -p /etc/sing-box

# ============================================================
# 6. 下载 Sing-box (musl / glibc 自动选择)
# ============================================================
printf "${BLUE}[3/8] 下载 Sing-box...${PLAIN}\n"
LATEST_TAG=""
for i in 1 2 3; do
    LATEST_TAG=$(curl -sL --connect-timeout 5 -H "Accept: application/vnd.github+json" \
        "https://api.github.com/repos/SagerNet/sing-box/releases/latest" 2>/dev/null \
        | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
    [ -n "$LATEST_TAG" ] && break; sleep 1
done
[ -z "$LATEST_TAG" ] && LATEST_TAG="v1.10.1"
VERSION=${LATEST_TAG#v}

LIBC_SUFFIX=""; [ "$IS_MUSL" = "1" ] && LIBC_SUFFIX="-musl"
DOWNLOAD_URL="https://github.com/SagerNet/sing-box/releases/download/${LATEST_TAG}/sing-box-${VERSION}-linux-${SINGBOX_ARCH}${LIBC_SUFFIX}.tar.gz"

printf "${BLUE}  下载: sing-box ${VERSION} (${SINGBOX_ARCH}${LIBC_SUFFIX})${PLAIN}\n"
if ! wget -q -O /tmp/sing-box.tar.gz "$DOWNLOAD_URL" || [ ! -s /tmp/sing-box.tar.gz ]; then
    # glibc 降级
    if [ "$IS_MUSL" = "1" ]; then
        printf "${YELLOW}  musl 下载失败，降级 glibc${PLAIN}\n"
        DOWNLOAD_URL="https://github.com/SagerNet/sing-box/releases/download/${LATEST_TAG}/sing-box-${VERSION}-linux-${SINGBOX_ARCH}.tar.gz"
        wget -q -O /tmp/sing-box.tar.gz "$DOWNLOAD_URL" || { printf "${RED}下载失败${PLAIN}\n"; exit 1; }
        [ -s /tmp/sing-box.tar.gz ] || { printf "${RED}下载文件为空${PLAIN}\n"; exit 1; }
        apk add --no-cache gcompat >/dev/null 2>&1 || true
    else
        printf "${RED}下载失败: $DOWNLOAD_URL${PLAIN}\n"; exit 1
    fi
fi

tar -zxvf /tmp/sing-box.tar.gz -C /tmp/ >/dev/null
EXTRACT_DIR="/tmp/sing-box-${VERSION}-linux-${SINGBOX_ARCH}${LIBC_SUFFIX}"
[ ! -d "$EXTRACT_DIR" ] && EXTRACT_DIR="/tmp/sing-box-${VERSION}-linux-${SINGBOX_ARCH}"
mv "${EXTRACT_DIR}/sing-box" /usr/local/bin/ 2>/dev/null || { printf "${RED}找不到 sing-box 二进制${PLAIN}\n"; exit 1; }
chmod +x /usr/local/bin/sing-box
rm -rf /tmp/sing-box.tar.gz "/tmp/sing-box-${VERSION}-linux-${SINGBOX_ARCH}${LIBC_SUFFIX}" "/tmp/sing-box-${VERSION}-linux-${SINGBOX_ARCH}" 2>/dev/null || true

# ============================================================
# 7. 公网 IP
# ============================================================
printf "${BLUE}[4/8] 获取公网 IP...${PLAIN}\n"
IP=$(curl -s4 --connect-timeout 5 icanhazip.com || curl -s4 --connect-timeout 5 ip.sb || curl -s4 --connect-timeout 5 api.ipify.org)
[ -z "$IP" ] && { printf "${RED}无法获取公网 IP${PLAIN}\n"; exit 1; }

# ============================================================
# 8. TLS 证书
# ============================================================
if needs_cert; then
    printf "${BLUE}[5/8] 申请 TLS 证书 (Let\'s Encrypt)...${PLAIN}\n"
    DOMAIN_IP=$(curl -sL --connect-timeout 5 "https://cloudflare-dns.com/dns-query?name=${DOMAIN}&type=A" \
        -H "Accept: application/dns-json" 2>/dev/null | sed 's/.*"data":"\([^"]*\)".*/\1/')
    [ -z "$DOMAIN_IP" ] && DOMAIN_IP=$(nslookup "$DOMAIN" 2>/dev/null | awk '/^Address: /{print $2}' | tail -1)
    if [ "$DOMAIN_IP" != "$IP" ]; then
        printf "${RED}域名 ${DOMAIN} → ${DOMAIN_IP:-空}，本机 IP ${IP}，请先配置 A 记录${PLAIN}\n"; exit 1
    fi

    if ! command -v ~/.acme.sh/acme.sh >/dev/null 2>&1; then
        wget -q -O /tmp/acme.sh https://get.acme.sh 2>/dev/null || true
        [ -f /tmp/acme.sh ] && sh /tmp/acme.sh --install --force >/dev/null 2>&1 || true
        rm -f /tmp/acme.sh
    fi

    CERT_DIR="/etc/sing-box/certs"; mkdir -p "$CERT_DIR"

    if command -v ~/.acme.sh/acme.sh >/dev/null 2>&1; then
        systemctl stop sing-box 2>/dev/null || rc-service sing-box stop 2>/dev/null || true
        ~/.acme.sh/acme.sh --issue -d "$DOMAIN" --standalone --keylength ec-256 \
            --server letsencrypt --email "$EMAIL" >/dev/null 2>&1 || {
            mkdir -p /var/www/html 2>/dev/null
            ~/.acme.sh/acme.sh --issue -d "$DOMAIN" --webroot /var/www/html \
                --keylength ec-256 --server letsencrypt --email "$EMAIL" >/dev/null 2>&1 || true
        }
        ~/.acme.sh/acme.sh --install-cert -d "$DOMAIN" --ecc \
            --key-file "$CERT_DIR/key.pem" --fullchain-file "$CERT_DIR/fullchain.pem" >/dev/null 2>&1 || {
            printf "${RED}证书申请失败，使用自签名${PLAIN}\n"
            openssl req -x509 -nodes -newkey rsa:2048 -days 365 \
                -keyout "$CERT_DIR/key.pem" -out "$CERT_DIR/fullchain.pem" \
                -subj "/CN=${DOMAIN}" -addext "subjectAltName=DNS:${DOMAIN}" 2>/dev/null
        }
    else
        openssl req -x509 -nodes -newkey rsa:2048 -days 365 \
            -keyout "$CERT_DIR/key.pem" -out "$CERT_DIR/fullchain.pem" \
            -subj "/CN=${DOMAIN}" -addext "subjectAltName=DNS:${DOMAIN}" 2>/dev/null
        printf "${YELLOW}使用自签名证书（客户端需 insecure）${PLAIN}\n"
    fi
fi

# ============================================================
# 9. 生成配置
# ============================================================
printf "${BLUE}[6/8] 生成配置...${PLAIN}\n"

/usr/local/bin/sing-box version >/dev/null 2>&1 || {
    printf "${RED}sing-box 不可执行${PLAIN}\n"; exit 1
}

UUID=$(/usr/local/bin/sing-box generate uuid 2>/dev/null || cat /proc/sys/kernel/random/uuid)

if [ "$PROTOCOL" = "hysteria2" ]; then
    CERT_DIR="/etc/sing-box/certs"; mkdir -p "$CERT_DIR"
    if [ ! -f "$CERT_DIR/fullchain.pem" ]; then
        SNI=${SNI:-"www.bing.com"}
        openssl req -x509 -nodes -newkey rsa:2048 -days 365 \
            -keyout "$CERT_DIR/key.pem" -out "$CERT_DIR/fullchain.pem" \
            -subj "/CN=${SNI}" -addext "subjectAltName=DNS:${SNI}" 2>/dev/null
    fi
fi

case "$PROTOCOL" in
    vless-reality)
        KEYPAIR=$(/usr/local/bin/sing-box generate reality-keypair)
        PRIVATE_KEY=$(echo "$KEYPAIR" | grep 'PrivateKey' | awk '{print $2}')
        PUBLIC_KEY=$(echo "$KEYPAIR"  | grep 'PublicKey'  | awk '{print $2}')
        SHORT_ID=$(openssl rand -hex 4)
        cat > /etc/sing-box/config.json << EOF
{"log":{"level":"warn"},"inbounds":[{"type":"vless","tag":"in","listen":"0.0.0.0","listen_port":$node_internal,"users":[{"uuid":"$UUID","flow":"xtls-rprx-vision"}],"tls":{"enabled":true,"server_name":"$SNI","reality":{"enabled":true,"handshake":{"server":"$SNI:443"},"private_key":"$PRIVATE_KEY","short_id":["$SHORT_ID"]}}}],"outbounds":[{"type":"direct","tag":"direct"}]}
EOF
        ;;
    vless-ws)
        cat > /etc/sing-box/config.json << EOF
{"log":{"level":"warn"},"inbounds":[{"type":"vless","tag":"in","listen":"0.0.0.0","listen_port":$node_internal,"users":[{"uuid":"$UUID"}],"tls":{"enabled":true,"server_name":"$DOMAIN","key_path":"$CERT_DIR/key.pem","certificate_path":"$CERT_DIR/fullchain.pem"},"transport":{"type":"ws","path":"${WS_PATH:-/vless}"}}],"outbounds":[{"type":"direct","tag":"direct"}]}
EOF
        ;;
    vless-tcp)
        cat > /etc/sing-box/config.json << EOF
{"log":{"level":"warn"},"inbounds":[{"type":"vless","tag":"in","listen":"0.0.0.0","listen_port":$node_internal,"users":[{"uuid":"$UUID"}],"tls":{"enabled":true,"server_name":"$DOMAIN","key_path":"$CERT_DIR/key.pem","certificate_path":"$CERT_DIR/fullchain.pem"}}],"outbounds":[{"type":"direct","tag":"direct"}]}
EOF
        ;;
    hysteria2)
        cat > /etc/sing-box/config.json << EOF
{"log":{"level":"warn"},"inbounds":[{"type":"hysteria2","tag":"hy2-in","listen":"0.0.0.0","listen_port":$node_internal,"users":[{"password":"$PASSWORD"}],"tls":{"enabled":true,"server_name":"${SNI:-www.bing.com}","key_path":"$CERT_DIR/key.pem","certificate_path":"$CERT_DIR/fullchain.pem"},"masquerade":"https://www.bing.com"}],"outbounds":[{"type":"direct","tag":"direct"}]}
EOF
        ;;
    shadowsocks)
        METHOD="none"
        cat > /etc/sing-box/config.json << EOF
{"log":{"level":"warn"},"inbounds":[{"type":"shadowsocks","tag":"ss-in","listen":"0.0.0.0","listen_port":$node_internal,"method":"$METHOD","password":"$PASSWORD"}],"outbounds":[{"type":"direct","tag":"direct"}]}
EOF
        ;;
    trojan)
        cat > /etc/sing-box/config.json << EOF
{"log":{"level":"warn"},"inbounds":[{"type":"trojan","tag":"trojan-in","listen":"0.0.0.0","listen_port":$node_internal,"users":[{"password":"$PASSWORD"}],"tls":{"enabled":true,"server_name":"$DOMAIN","key_path":"$CERT_DIR/key.pem","certificate_path":"$CERT_DIR/fullchain.pem"}}],"outbounds":[{"type":"direct","tag":"direct"}]}
EOF
        ;;
esac

/usr/local/bin/sing-box check -c /etc/sing-box/config.json >/dev/null 2>&1 || {
    printf "${RED}配置文件校验失败${PLAIN}\n"; exit 1
}

# ============================================================
# 10. 防火墙
# ============================================================
printf "${BLUE}[7/8] 防火墙规则...${PLAIN}\n"
FWRULES="/etc/sing-box/firewall.rules"
cat > "$FWRULES" << FEOF
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

iptables-restore < "$FWRULES" 2>/dev/null || {
    iptables -I INPUT -p tcp --dport "$ssh_internal"  -j ACCEPT 2>/dev/null || true
    iptables -I INPUT -p tcp --dport "$node_internal" -j ACCEPT 2>/dev/null || true
    iptables -I INPUT -p udp --dport "$node_internal" -j ACCEPT 2>/dev/null || true
}
# nftables 兼容（CentOS/RHEL 默认用 nft）
if command -v nft >/dev/null 2>&1 && nft list tables 2>/dev/null | grep -q filter; then
    nft add rule ip filter INPUT tcp dport "$ssh_internal" accept 2>/dev/null || true
    nft add rule ip filter INPUT tcp dport "$node_internal" accept 2>/dev/null || true
    nft add rule ip filter INPUT udp dport "$node_internal" accept 2>/dev/null || true
fi

# ============================================================
# 11. 服务注册
# ============================================================
printf "${BLUE}[8/8] 注册服务...${PLAIN}\n"

if [ "$INIT_SYS" = "systemd" ]; then
    cat > /etc/systemd/system/sing-box.service << UNITEOF
[Unit]
Description=Sing-box Proxy Service
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/sing-box run -c /etc/sing-box/config.json
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
UNITEOF
    systemctl daemon-reload >/dev/null 2>&1
    systemctl enable sing-box >/dev/null 2>&1
    systemctl restart sing-box >/dev/null 2>&1 || {
        printf "${YELLOW}systemd 启动中...${PLAIN}\n"
        sleep 2
        systemctl restart sing-box >/dev/null 2>&1 || true
    }
else
    # OpenRC
    cat > /etc/init.d/sing-box << 'SERVEOF'
#!/sbin/openrc-run
description="Sing-box Proxy Service"
command="/usr/local/bin/sing-box"
command_args="run -c /etc/sing-box/config.json"
pidfile="/run/sing-box.pid"
command_background=true
depend() { need net; }
start_pre() {
    if [ -f /etc/sing-box/firewall.rules ]; then
        iptables-restore < /etc/sing-box/firewall.rules 2>/dev/null || true
    fi
}
SERVEOF
    chmod +x /etc/init.d/sing-box
    rc-update add sing-box default >/dev/null 2>&1 || true
    rc-service sing-box restart >/dev/null 2>&1 || true
fi

# ============================================================
# 12. 快捷查询
# ============================================================
cat > /usr/local/bin/vps-info << 'INFOEOF'
#!/bin/sh
echo ""
echo "========== 代理信息 =========="
echo ""
INFOEOF

case "$PROTOCOL" in
    vless-reality)
        cat >> /usr/local/bin/vps-info << INFOEOF
echo "协议:      VLESS + Reality"
echo "公网 IP:   $IP"
echo "端口:      $node_external (内网: $node_internal)"
echo "SSH:       $ssh_external (内网: $ssh_internal)"
echo "UUID:      $UUID"
echo "PublicKey: $PUBLIC_KEY"
echo "ShortID:   $SHORT_ID"
echo "SNI:       $SNI"
echo ""
echo "客户端链接:"
echo "vless://$UUID@$IP:$node_external?encryption=none&flow=xtls-rprx-vision&security=reality&sni=$SNI&fp=chrome&pbk=$PUBLIC_KEY&sid=$SHORT_ID&type=tcp#NAT-${PROTOCOL}"
echo ""
INFOEOF
        ;;
    vless-ws)
        cat >> /usr/local/bin/vps-info << INFOEOF
echo "协议:      VLESS + WebSocket + TLS"
echo "域名:      $DOMAIN"
echo "端口:      $node_external"
echo "UUID:      $UUID"
echo "WS 路径:   ${WS_PATH:-/vless}"
echo ""
echo "客户端链接:"
echo "vless://$UUID@$DOMAIN:$node_external?encryption=none&security=tls&type=ws&path=${WS_PATH:-/vless}&host=$DOMAIN&sni=$DOMAIN#NAT-${PROTOCOL}"
echo ""
INFOEOF
        ;;
    vless-tcp)
        cat >> /usr/local/bin/vps-info << INFOEOF
echo "协议:      VLESS + TCP + TLS"
echo "域名:      $DOMAIN"
echo "端口:      $node_external"
echo "UUID:      $UUID"
echo ""
echo "客户端链接:"
echo "vless://$UUID@$DOMAIN:$node_external?encryption=none&security=tls&type=tcp&sni=$DOMAIN#NAT-${PROTOCOL}"
echo ""
INFOEOF
        ;;
    hysteria2)
        cat >> /usr/local/bin/vps-info << INFOEOF
echo "协议:      Hysteria2"
echo "公网 IP:   $IP"
echo "端口:      $node_external (内网: $node_internal)"
echo "密码:      $PASSWORD"
echo "SNI:       ${SNI:-www.bing.com}"
echo ""
echo "客户端链接:"
echo "hy2://$PASSWORD@$IP:$node_external?insecure=1&sni=${SNI:-www.bing.com}#NAT-${PROTOCOL}"
echo ""
INFOEOF
        ;;
    shadowsocks)
        cat >> /usr/local/bin/vps-info << INFOEOF
echo "协议:      Shadowsocks (无加密)"
echo "公网 IP:   $IP"
echo "端口:      $node_external (内网: $node_internal)"
echo "密码:      $PASSWORD"
echo ""
echo "客户端链接:"
echo "ss://$(printf '%s' "none:$PASSWORD" | base64 -w0)@$IP:$node_external#NAT-${PROTOCOL}"
echo ""
INFOEOF
        ;;
    trojan)
        cat >> /usr/local/bin/vps-info << INFOEOF
echo "协议:      Trojan + TLS"
echo "域名:      $DOMAIN"
echo "端口:      $node_external"
echo "密码:      $PASSWORD"
echo ""
echo "客户端链接:"
echo "trojan://$PASSWORD@$DOMAIN:$node_external?security=tls&sni=$DOMAIN#NAT-${PROTOCOL}"
echo ""
INFOEOF
        ;;
esac
chmod +x /usr/local/bin/vps-info

# 生成 vps-info
if command -v /usr/local/bin/sing-box >/dev/null 2>&1; then
  cat > /usr/local/bin/vps-info << 'SIMPLEEOF'
#!/bin/sh
echo ""
echo "========== 代理信息 (Sing-box) =========="
echo ""
SIMPLEEOF
  chmod +x /usr/local/bin/vps-info
fi

# ============================================================
# 完成
# ============================================================
printf "\n${GREEN}============================================================${PLAIN}\n"
printf "${GREEN}✅ 安装成功 — ${PROTOCOL}${PLAIN}\n"
printf "${GREEN}${PLAIN}\n"
printf "${GREEN}   输入 ${YELLOW}vps-info${GREEN} 查看链接${PLAIN}\n"

if [ "$INIT_SYS" = "systemd" ]; then
    printf "${GREEN}   管理: ${YELLOW}systemctl {start|stop|restart|status} sing-box${PLAIN}\n"
    printf "${GREEN}   日志: ${YELLOW}journalctl -u sing-box -f${PLAIN}\n"
else
    printf "${GREEN}   管理: ${YELLOW}rc-service sing-box {start|stop|restart|status}${PLAIN}\n"
fi

printf "${GREEN}============================================================${PLAIN}\n"
