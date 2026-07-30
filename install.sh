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
# 2. 协议选择 (使用 whiptail 菜单界面)
# ============================================================

# 检测 whiptail/newt
WHIPTAIL_CMD=""
if command -v whiptail >/dev/null 2>&1; then
    WHIPTAIL_CMD="whiptail"
elif command -v newt >/dev/null 2>&1; then
    WHIPTAIL_CMD="newt"
fi

if [ -n "$WHIPTAIL_CMD" ]; then
    # TUI 模式 — whiptail 直接操作 /dev/tty
    proto_choice=$(eval "$WHIPTAIL_CMD" --menu "选择协议" 0 0 0 \
        1 "VLESS + Reality (无需域名，推荐)" \
        2 "VLESS + WebSocket + TLS (需套 CDN+域名)" \
        3 "VLESS + TCP + TLS (标准 TLS)" \
        4 "Hysteria2 (高丢包加速)" \
        5 "Shadowsocks (轻量经典)" \
        6 "Trojan + TLS (传统稳定)" \
        --default-item 1 2>&1 /dev/tty | grep -oE '^[0-9]+$' || echo 1)
else
    # fallback: 纯文本菜单
    printf "${YELLOW}请选择协议:${PLAIN}\n"
    echo "1) VLESS + Reality (xtls-rprx-vision)   — 最隐蔽，无需域名 ← 推荐"
    echo "2) VLESS + WebSocket + TLS              — 可套 CDN，需域名+证书"
    echo "3) VLESS + TCP + TLS                    — 标准 TLS，需域名+证书"
    echo "4) Hysteria2                            — QUIC 暴力加速"
    echo "5) Shadowsocks + AEAD                   — 轻量经典"
    echo "6) Trojan + TLS                         — 传统稳定，需域名+证书"
    printf "选择 [1-6] (默认 1): "
    read -r proto_choice
fi
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
# ============================================================
# 3. 输入 (使用 whiptail TUI，兼容 fallback)
# ============================================================

# 函数: 节点端口输入 (内网/公网)
read_node_port() {
    local prompt="节点端口 (内网/公网，如 20000/32090)"
    while true; do
        if [ -n "$WHIPTAIL_CMD" ]; then
            input=$(eval "$WHIPTAIL_CMD" --input-box "$prompt" 8 60 "" 2>&1 /dev/tty | grep -v '^$')
        else
            printf "${YELLOW}${prompt}:${PLAIN}\n"
            read -r input
        fi
        [ -z "$input" ] && continue
        in=$(echo "$input" | cut -d'/' -f1)
        ex=$(echo "$input" | cut -d'/' -f2)
        echo "$in" | grep -qE '^[0-9]+$' && echo "$ex" | grep -qE '^[0-9]+$' && break
        if [ -n "$WHIPTAIL_CMD" ]; then
            eval "$WHIPTAIL_CMD" --msgbox "格式错误，请按 \"内网/公网\" 输入数字" 6 40 2>&1 /dev/tty || true
        else
            printf "${RED}格式错误，请按 内网端口/公网端口 输入数字${PLAIN}\n"
        fi
    done
    echo "$in/$ex"
}

# 函数: SSH 端口输入 (内网/公网)
read_ssh_port() {
    local prompt="SSH 端口 (内网/公网，如 22/43694)"
    while true; do
        if [ -n "$WHIPTAIL_CMD" ]; then
            input=$(eval "$WHIPTAIL_CMD" --input-box "$prompt" 8 60 "" 2>&1 /dev/tty | grep -v '^$')
        else
            printf "${YELLOW}${prompt}:${PLAIN}\n"
            read -r input
        fi
        [ -z "$input" ] && continue
        in=$(echo "$input" | cut -d'/' -f1)
        ex=$(echo "$input" | cut -d'/' -f2)
        echo "$in" | grep -qE '^[0-9]+$' && echo "$ex" | grep -qE '^[0-9]+$' && break
        if [ -n "$WHIPTAIL_CMD" ]; then
            eval "$WHIPTAIL_CMD" --msgbox "格式错误，请按 \"内网/公网\" 输入数字" 6 40 2>&1 /dev/tty || true
        else
            printf "${RED}格式错误，请按 内网端口/公网端口 输入数字${PLAIN}\n"
        fi
    done
    echo "$in/$ex"
}

node_input=$(read_node_port)
node_internal=$(echo "$node_input" | cut -d'/' -f1)
node_external=$(echo "$node_input" | cut -d'/' -f2)

ssh_input=$(read_ssh_port)
ssh_internal=$(echo "$ssh_input" | cut -d'/' -f1)
ssh_external=$(echo "$ssh_input" | cut -d'/' -f2)

# ============================================================
# 多用户配置
# ============================================================
USER_COUNT=1
if [ -n "$WHIPTAIL_CMD" ]; then
    user_input=$(eval "$WHIPTAIL_CMD" --input-box "用户数量" "生成几个用户？每个用户有独立的 UUID/密码" "1" 2>&1 /dev/tty | grep -oE '^[0-9]+$')
    [ -n "$user_input" ] && USER_COUNT=$user_input
else
    printf "${YELLOW}用户数量 (默认 1): ${PLAIN}"
    read -r user_input
    [ -n "$user_input" ] && USER_COUNT=$user_input
fi
[ "$USER_COUNT" -lt 1 ] && USER_COUNT=1
if [ "$USER_COUNT" -gt 1 ]; then
    printf "${BLUE}→ 用户数: ${USER_COUNT}，将生成多个 UUID/密码${PLAIN}\n\n"
fi

# ============================================================
# SNI 选择 (TUI 菜单)
# ============================================================
if [ "$PROTOCOL" = "vless-reality" ]; then
    if [ -n "$WHIPTAIL_CMD" ]; then
        sni_choice=$(eval "$WHIPTAIL_CMD" --menu "选择 SNI 伪装域名" 0 0 0 \
            1 "www.yahoo.com" \
            2 "www.icloud.com (推荐)" \
            3 "自定义" \
            --default-item 2 2>&1 /dev/tty | grep -oE '^[0-9]+$' || echo 2)
    else
        printf "${YELLOW}SNI 伪装域名:${PLAIN}\n"
        echo "1) www.yahoo.com"; echo "2) www.icloud.com"; echo "3) 自定义"
        printf "选择 [1-3] (默认 2): "
        read -r sni_choice
    fi
    case "$sni_choice" in
        1) SNI="www.yahoo.com" ;;
        3) printf "自定义 SNI: "; read -r custom_sni; SNI=${custom_sni:-"www.icloud.com"} ;;
        *) SNI="www.icloud.com" ;;
    esac
fi

needs_cert() { case "$PROTOCOL" in vless-ws|vless-tcp|trojan) return 0;; *) return 1;; esac; }

if needs_cert; then
    if [ -n "$WHIPTAIL_CMD" ]; then
        DOMAIN=$(eval "$WHIPTAIL_CMD" --input-box "域名 (A 记录指向本机)" 8 60 "" 2>&1 /dev/tty | grep -v '^$')
        [ -z "$DOMAIN" ] && { eval "$WHIPTAIL_CMD" --msgbox "域名不能为空" 6 40 2>&1 /dev/tty || true; exit 1; }
        EMAIL=$(eval "$WHIPTAIL_CMD" --input-box "Let's Encrypt 邮箱" 8 60 "admin@${DOMAIN}" 2>&1 /dev/tty | grep -v '^$')
        EMAIL=${EMAIL:-"admin@${DOMAIN}"}
    else
        printf "${YELLOW}域名 (A 记录指向本机): ${PLAIN}\n"
        read -r DOMAIN
        [ -z "$DOMAIN" ] && { printf "${RED}域名不能为空${PLAIN}\n"; exit 1; }
        printf "${YELLOW}邮箱 (Let's Encrypt 用): ${PLAIN}\n"
        read -r EMAIL; EMAIL=${EMAIL:-"admin@${DOMAIN}"}
    fi
fi

[ "$PROTOCOL" = "vless-ws" ] && {
    if [ -n "$WHIPTAIL_CMD" ]; then
        WS_PATH=$(eval "$WHIPTAIL_CMD" --input-box "WS 路径 (默认 /vless)" 8 60 "/vless" 2>&1 /dev/tty | grep -v '^$')
        WS_PATH=${WS_PATH:-"/vless"}
    else
        printf "${YELLOW}WS 路径 (默认 /vless): ${PLAIN}\n"
        read -r WS_PATH; WS_PATH=${WS_PATH:-"/vless"}
    fi
}
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
IP4=$(curl -s4 --connect-timeout 5 icanhazip.com || curl -s4 --connect-timeout 5 ip.sb || curl -s4 --connect-timeout 5 api.ipify.org)
IP6=$(curl -s6 --connect-timeout 5 icanhazip.com 2>/dev/null || curl -s6 --connect-timeout 5 ip.sb 2>/dev/null || curl -s6 --connect-timeout 5 api.ipify.org 2>/dev/null || echo "")
IP=${IP4:-$IP6}
[ -z "$IP" ] && { printf "${RED}无法获取公网 IP${PLAIN}\n"; exit 1; }
[ -n "$IP4" ] && printf "${BLUE}  IPv4: ${IP4}${PLAIN}\n"
[ -n "$IP6" ] && printf "${BLUE}  IPv6: ${IP6}${PLAIN}\n"

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

# 生成多用户凭证
GEN_UUID_CMD="/usr/local/bin/sing-box generate uuid"
UUID_LIST=""; PASSWORD_LIST=""
for i in $(seq 1 $USER_COUNT); do
    u=$($GEN_UUID_CMD 2>/dev/null || cat /proc/sys/kernel/random/uuid 2>/dev/null || echo "$(date +%s)-$$-$i")
    p=$(openssl rand -base64 16 | tr -d '=+/')
    [ -n "$UUID_LIST" ] && UUID_LIST="${UUID_LIST},"
    [ -n "$PASSWORD_LIST" ] && PASSWORD_LIST="${PASSWORD_LIST},"
    UUID_LIST="${UUID_LIST}${u}"
    PASSWORD_LIST="${PASSWORD_LIST}${p}"
done
UUID=$(echo "$UUID_LIST" | cut -d',' -f1)
PASSWORD=$(echo "$PASSWORD_LIST" | cut -d',' -f1)

# 辅助: 生成 users JSON 数组 (用于多用户配置)
build_users_json() {
    local proto="$1"
    local result="" sep=""
    if [ "$proto" = "vless-reality" ]; then
        for u in $(echo "$UUID_LIST" | tr ',' ' '); do
            result="${result}${sep}{\"uuid\":\"$u\",\"flow\":\"xtls-rprx-vision\"}"; sep=","
        done
    elif [ "$proto" = "vless-ws" ] || [ "$proto" = "vless-tcp" ]; then
        for u in $(echo "$UUID_LIST" | tr ',' ' '); do
            result="${result}${sep}{\"uuid\":\"$u\"}"; sep=","
        done
    elif [ "$proto" = "hysteria2" ] || [ "$proto" = "trojan" ] || [ "$proto" = "shadowsocks" ]; then
        for p in $(echo "$PASSWORD_LIST" | tr ',' ' '); do
            result="${result}${sep}{\"password\":\"$p\"}"; sep=","
        done
    fi
    printf '%s' "[$result]"
}

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
{"log":{"level":"warn"},"inbounds":[{"type":"vless","tag":"in","listen":"0.0.0.0","listen_port":$node_internal,"users":$(build_users_json "$PROTOCOL"),"tls":{"enabled":true,"server_name":"$SNI","reality":{"enabled":true,"handshake":{"server":"$SNI:443"},"private_key":"$PRIVATE_KEY","short_id":["$SHORT_ID"]}}}],"outbounds":[{"type":"direct","tag":"direct"}]}
EOF
        ;;
    vless-ws)
        cat > /etc/sing-box/config.json << EOF
{"log":{"level":"warn"},"inbounds":[{"type":"vless","tag":"in","listen":"0.0.0.0","listen_port":$node_internal,"users":$(build_users_json "$PROTOCOL"),"tls":{"enabled":true,"server_name":"$DOMAIN","key_path":"$CERT_DIR/key.pem","certificate_path":"$CERT_DIR/fullchain.pem"},"transport":{"type":"ws","path":"${WS_PATH:-/vless}"}}],"outbounds":[{"type":"direct","tag":"direct"}]}
EOF
        ;;
    vless-tcp)
        cat > /etc/sing-box/config.json << EOF
{"log":{"level":"warn"},"inbounds":[{"type":"vless","tag":"in","listen":"0.0.0.0","listen_port":$node_internal,"users":$(build_users_json "$PROTOCOL"),"tls":{"enabled":true,"server_name":"$DOMAIN","key_path":"$CERT_DIR/key.pem","certificate_path":"$CERT_DIR/fullchain.pem"}}],"outbounds":[{"type":"direct","tag":"direct"}]}
EOF
        ;;
    hysteria2)
        cat > /etc/sing-box/config.json << EOF
{"log":{"level":"warn"},"inbounds":[{"type":"hysteria2","tag":"hy2-in","listen":"0.0.0.0","listen_port":$node_internal,"users":$(build_users_json "$PROTOCOL"),"tls":{"enabled":true,"server_name":"${SNI:-www.bing.com}","key_path":"$CERT_DIR/key.pem","certificate_path":"$CERT_DIR/fullchain.pem"},"masquerade":"https://www.bing.com"}],"outbounds":[{"type":"direct","tag":"direct"}]}
EOF
        ;;
    shadowsocks)
        METHOD="none"
        cat > /etc/sing-box/config.json << EOF
{"log":{"level":"warn"},"inbounds":[{"type":"shadowsocks","tag":"ss-in","listen":"0.0.0.0","listen_port":$node_internal,"method":"$METHOD","users":$(build_users_json "$PROTOCOL")}],"outbounds":[{"type":"direct","tag":"direct"}]}
EOF
        ;;
    trojan)
        cat > /etc/sing-box/config.json << EOF
{"log":{"level":"warn"},"inbounds":[{"type":"trojan","tag":"trojan-in","listen":"0.0.0.0","listen_port":$node_internal,"users":$(build_users_json "$PROTOCOL"),"tls":{"enabled":true,"server_name":"$DOMAIN","key_path":"$CERT_DIR/key.pem","certificate_path":"$CERT_DIR/fullchain.pem"}}],"outbounds":[{"type":"direct","tag":"direct"}]}
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
# 12. 安装节点管理工具 (sbx)
# ============================================================

# 写入节点元数据
cat > /etc/sing-box/nodes.conf << NODEOF
# NAT VPS 节点元数据 — 由 sbx 管理，请勿手动编辑
NODE_COUNT=1
NODE_0_NAME='NAT-${PROTOCOL}'
NODE_0_PROTO='${PROTOCOL}'
NODE_0_PORT_INTERNAL='${node_internal}'
NODE_0_PORT_EXTERNAL='${node_external}'
NODE_0_UUIDS='${UUID_LIST}'
NODE_0_PASSWORDS='${PASSWORD_LIST}'
NODE_0_SNI='${SNI}'
NODE_0_DOMAIN='${DOMAIN}'
NODE_0_WS_PATH='${WS_PATH:-/vless}'
NODE_0_TLS_CERT='${CERT_DIR:-}/fullchain.pem'
NODE_0_TLS_KEY='${CERT_DIR:-}/key.pem'
NODE_0_PUBLIC_KEY='${PUBLIC_KEY}'
NODE_0_PRIVATE_KEY='${PRIVATE_KEY}'
NODE_0_SHORT_ID='${SHORT_ID}'
NODE_0_IP4='${IP4}'
NODE_0_IP6='${IP6}'
NODEOF

# 检查是否已有 warp.conf (升级安装时保留)

# 安装 sbx 管理命令
printf "${BLUE}  安装 sbx 管理工具...${PLAIN}\n"
SBX_URL="https://raw.githubusercontent.com/shali10/nat-vless-installer/main/sbx.sh"
if command -v curl >/dev/null 2>&1; then
    curl -fsSL "$SBX_URL" -o /usr/local/bin/sbx 2>/dev/null || true
elif command -v wget >/dev/null 2>&1; then
    wget -q "$SBX_URL" -O /usr/local/bin/sbx 2>/dev/null || true
fi
if [ -s /usr/local/bin/sbx ]; then
    chmod +x /usr/local/bin/sbx
    # vps-info 作为兼容别名
    ln -sf /usr/local/bin/sbx /usr/local/bin/vps-info
    printf "${GREEN}  ✅ sbx 已安装${PLAIN}\n"
else
    printf "${YELLOW}  ⚠️  sbx 下载失败, 稍后可手动安装${PLAIN}\n"
fi

# ============================================================
# 13. Warp 解锁 (可选)
# ============================================================
if [ -n "$WHIPTAIL_CMD" ]; then
    warp_choice=$(eval "$WHIPTAIL_CMD" --title "Warp 解锁" --yesno "添加 Warp 出站以解锁 ChatGPT/Netflix/流媒体？" 8 40 2>&1 /dev/tty; echo $?)
    warp_yn=; [ "$warp_choice" = "0" ] && warp_yn="y"
else
    printf "\n${YELLOW}是否添加 Warp 出站解锁 ChatGPT/Netflix？ (y/N): ${PLAIN}"
    read -r warp_yn
fi

if [ "$warp_yn" = "y" ] || [ "$warp_yn" = "Y" ]; then
    printf "${BLUE}[Warp] 注册 Cloudflare Warp...${PLAIN}\n"

    # 下载 wgcf
    WGCF_ARCH="$SINGBOX_ARCH"
    [ "$WGCF_ARCH" = "armv7" ] && WGCF_ARCH="arm"
    WGCF_URL="https://github.com/ViRb3/wgcf/releases/latest/download/wgcf_2.2.22_linux_${WGCF_ARCH}"
    if ! wget -q -O /tmp/wgcf "$WGCF_URL" 2>/dev/null; then
        printf "${YELLOW}  wgcf 下载失败，跳过 Warp 设置${PLAIN}\n"
    else
        chmod +x /tmp/wgcf
        cd /tmp
        /tmp/wgcf register --accept-tos >/dev/null 2>&1 || { printf "${YELLOW}  Warp 注册失败${PLAIN}\n"; rm -f /tmp/wgcf; }
        if [ -f wgcf-account.toml ]; then
            /tmp/wgcf generate >/dev/null 2>&1 || true
        fi
        if [ -f wgcf-profile.conf ]; then
            printf "${BLUE}[Warp] 提取 WireGuard 参数...${PLAIN}\n"
            WG_PRIV=$(grep '^PrivateKey' wgcf-profile.conf | head -1 | awk '{print $3}')
            WG_ADDR=$(grep '^Address' wgcf-profile.conf | head -1 | awk '{print $3}')
            WG_PUB=$(grep '^PublicKey' wgcf-profile.conf | head -1 | awk '{print $3}')
            WG_EP=$(grep '^Endpoint' wgcf-profile.conf | head -1 | awk '{print $3}')
            WG_PORT=$(echo "$WG_EP" | cut -d: -f2)
            WG_SERVER=$(echo "$WG_EP" | cut -d: -f1)
            WG_RESERVED=$(grep -o 'ReservedBit.*=[^0-9]*[0-9,]*' wgcf-profile.conf 2>/dev/null | grep -oE '[0-9,]+' || echo "0,0,0")

            # 保存 Warp 配置
            cat > /etc/sing-box/warp.conf << WEOF
WARP_ENABLED=true
WARP_PRIVATE_KEY='$WG_PRIV'
WARP_ADDRESS='$WG_ADDR'
WARP_PUBLIC_KEY='$WG_PUB'
WARP_SERVER='$WG_SERVER'
WARP_PORT='$WG_PORT'
WARP_RESERVED='$WG_RESERVED'
WEOF

            rm -f /tmp/wgcf wgcf-profile.conf wgcf-account.toml 2>/dev/null || true

            # 注入 Sing-box 配置
            printf "${BLUE}[Warp] 注入 Sing-box 配置...${PLAIN}\n"
            WARPOUT='{"type":"wireguard","tag":"warp","server":"'$WG_SERVER'","server_port":'$WG_PORT',"local_address":["'$WG_ADDR'"],"private_key":"'$WG_PRIV'","peer_public_key":"'$WG_PUB'","reserved":['$WG_RESERVED'],"mtu":1420}'
            WARP_RULE='{"domain_suffix":["openai.com","chatgpt.com","ai.com","netflix.com","nflxvideo.net","nflximg.net","youtube.com","googlevideo.com","disneyplus.com","bbc.co.uk","tvb.com","hbo.com","max.com","spotify.com","abema.tv"],"outbound":"warp"}'
            sed -i 's|"outbounds":\[{"type":"direct","tag":"direct"}\]|"outbounds":[{"type":"direct","tag":"direct"},'"$WARPOUT"'],"route":{"rules":['"$WARP_RULE"']}|' /etc/sing-box/config.json 2>/dev/null || true

            if /usr/local/bin/sing-box check -c /etc/sing-box/config.json >/dev/null 2>&1; then
                printf "${GREEN}  ✅ Warp 已启用 (解锁 ChatGPT + Netflix + YouTube + 主流流媒体)${PLAIN}\n"
                echo "NODE_0_WARP=true" >> /etc/sing-box/nodes.conf
                # 重启服务
                if command -v systemctl >/dev/null 2>&1 && [ -d /run/systemd/system ]; then
                    systemctl restart sing-box 2>/dev/null || true
                elif command -v rc-service >/dev/null 2>&1; then
                    rc-service sing-box restart 2>/dev/null || true
                fi
                printf "${GREEN}  ✅ 服务已重启${PLAIN}\n"
            else
                printf "${RED}  Warp 配置校验失败，已回滚${PLAIN}\n"
                # Regenerate without warp
                sed -i 's|,"outbounds":\[{"type":"direct","tag":"direct"},"type":"wireguard".*"route":{.*}||' /etc/sing-box/config.json 2>/dev/null || true
                rm -f /etc/sing-box/warp.conf
            fi
        else
            printf "${YELLOW}  Warp 配置生成失败${PLAIN}\n"
            rm -f /tmp/wgcf 2>/dev/null || true
        fi
    fi
    cd /
fi

# ============================================================
# 完成
# ============================================================
printf "\n${GREEN}============================================================${PLAIN}\n"
printf "${GREEN}✅ 安装成功 — ${PROTOCOL}${PLAIN}\n"
printf "${GREEN}  输入 ${YELLOW}sbx${GREEN} 管理节点 | ${YELLOW}sbx info${GREEN} 查看链接${PLAIN}\n"

if [ "$INIT_SYS" = "systemd" ]; then
    printf "${GREEN}   管理: ${YELLOW}systemctl {start|stop|restart|status} sing-box${PLAIN}\n"
    printf "${GREEN}   日志: ${YELLOW}journalctl -u sing-box -f${PLAIN}\n"
else
    printf "${GREEN}   管理: ${YELLOW}rc-service sing-box {start|stop|restart|status}${PLAIN}\n"
fi

printf "${GREEN}============================================================${PLAIN}\n"
