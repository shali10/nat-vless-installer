#!/bin/sh
# sbx - NAT VPS 节点管理工具 (Sing-box)
# 安装: https://github.com/shali10/nat-vless-installer

CONFIG="/etc/sing-box/config.json"
NODES_CONF="/etc/sing-box/nodes.conf"
SBIN="/usr/local/bin/sing-box"
CERT_DIR="/etc/sing-box/certs"

# Colors
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[0;33m'; BLUE='\033[0;34m'; CYAN='\033[0;36m'; NC='\033[0m'

_info() { printf "${CYAN}[信息]${NC} %s\n" "$1"; }
_ok()   { printf "${GREEN}[成功]${NC} %s\n" "$1"; }
_warn() { printf "${YELLOW}[注意]${NC} %s\n" "$1"; }
_err()  { printf "${RED}[错误]${NC} %s\n" "$1"; }

# Detect whiptail
WHIPTAIL_CMD=""
command -v whiptail >/dev/null 2>&1 && WHIPTAIL_CMD="whiptail"
command -v newt >/dev/null 2>&1 && WHIPTAIL_CMD="newt"

whip_menu() {
    local title="$1" prompt="$2"; shift 2
    if [ -n "$WHIPTAIL_CMD" ]; then
        eval "$WHIPTAIL_CMD" --title "$title" --menu "$prompt" 0 0 0 "$@" 2>&1 /dev/tty | grep -oE '^[0-9]+$' || echo ""
    else
        echo ""
    fi
}

whip_input() {
    local title="$1" prompt="$2" default="$3"
    if [ -n "$WHIPTAIL_CMD" ]; then
        eval "$WHIPTAIL_CMD" --title "$title" --input-box "$prompt" 8 60 "$default" 2>&1 /dev/tty | grep -v '^$'
    else
        printf "${YELLOW}${prompt}${NC}\n"; read -r input; echo "$input"
    fi
}

whip_msg() {
    if [ -n "$WHIPTAIL_CMD" ]; then
        eval "$WHIPTAIL_CMD" --title "$1" --msgbox "$2" 6 40 2>&1 /dev/tty || true
    fi
}

# ---- Read nodes.conf ----
load_nodes() {
    NODE_COUNT=0
    [ -f "$NODES_CONF" ] && . "$NODES_CONF" 2>/dev/null || true
    NODE_COUNT=${NODE_COUNT:-0}
}

# ---- Regenerate config.json from nodes.conf ----
regenerate_config() {
    load_nodes
    _info "生成配置..."
    mkdir -p /etc/sing-box

    local inbounds="" sep=""
    for i in $(seq 0 $((NODE_COUNT - 1))); do
        eval "proto=\$NODE_${i}_PROTO" 2>/dev/null || continue
        eval "port=\$NODE_${i}_PORT_INTERNAL"
        eval "iport=\$NODE_${i}_PORT_EXTERNAL"
        eval "uuid=\$NODE_${i}_UUID"
        eval "pass=\$NODE_${i}_PASSWORD"
        eval "sni=\$NODE_${i}_SNI"
        eval "domain=\$NODE_${i}_DOMAIN"
        eval "wspath=\$NODE_${i}_WS_PATH"
        eval "pk=\$NODE_${i}_PUBLIC_KEY"
        eval "priv=\$NODE_${i}_PRIVATE_KEY"
        eval "sid=\$NODE_${i}_SHORT_ID"

        local tag="node-$i"
        case "$proto" in
            vless-reality)
                [ -z "$sni" ] && sni="www.icloud.com"
                line="{\"type\":\"vless\",\"tag\":\"$tag\",\"listen\":\"0.0.0.0\",\"listen_port\":$port,\"users\":[{\"uuid\":\"$uuid\",\"flow\":\"xtls-rprx-vision\"}],\"tls\":{\"enabled\":true,\"server_name\":\"$sni\",\"reality\":{\"enabled\":true,\"handshake\":{\"server\":\"$sni:443\"},\"private_key\":\"$priv\",\"short_id\":[\"$sid\"]}}}"
                ;;
            vless-ws)
                line="{\"type\":\"vless\",\"tag\":\"$tag\",\"listen\":\"0.0.0.0\",\"listen_port\":$port,\"users\":[{\"uuid\":\"$uuid\"}],\"tls\":{\"enabled\":true,\"server_name\":\"$domain\",\"key_path\":\"$CERT_DIR/key.pem\",\"certificate_path\":\"$CERT_DIR/fullchain.pem\"},\"transport\":{\"type\":\"ws\",\"path\":\"${wspath:-/vless}\"}}"
                ;;
            hysteria2)
                line="{\"type\":\"hysteria2\",\"tag\":\"$tag\",\"listen\":\"0.0.0.0\",\"listen_port\":$port,\"users\":[{\"password\":\"$pass\"}],\"tls\":{\"enabled\":true,\"server_name\":\"${sni:-www.bing.com}\",\"key_path\":\"$CERT_DIR/key.pem\",\"certificate_path\":\"$CERT_DIR/fullchain.pem\"},\"masquerade\":\"https://www.bing.com\"}"
                ;;
            shadowsocks)
                line="{\"type\":\"shadowsocks\",\"tag\":\"$tag\",\"listen\":\"0.0.0.0\",\"listen_port\":$port,\"method\":\"none\",\"password\":\"$pass\"}"
                ;;
            trojan)
                line="{\"type\":\"trojan\",\"tag\":\"$tag\",\"listen\":\"0.0.0.0\",\"listen_port\":$port,\"users\":[{\"password\":\"$pass\"}],\"tls\":{\"enabled\":true,\"server_name\":\"$domain\",\"key_path\":\"$CERT_DIR/key.pem\",\"certificate_path\":\"$CERT_DIR/fullchain.pem\"}}"
                ;;
            *) continue ;;
        esac
        inbounds="${inbounds}${sep}${line}"; sep=","
    done

    printf '{"log":{"level":"warn"},"inbounds":[%s],"outbounds":[{"type":"direct","tag":"direct"}]}\n' "$inbounds" > "$CONFIG"
    if ! "$SBIN" check -c "$CONFIG" >/dev/null 2>&1; then
        _err "配置文件校验失败！"; return 1
    fi
    _ok "配置已更新"
}

# ---- Save node to nodes.conf ----
save_node() {
    local idx="$1"; shift
    # Remove old entry and NODE_COUNT, rebuild
    local tmp=$(mktemp /tmp/sbx-XXXXXX.conf)
    [ -f "$NODES_CONF" ] && grep -v "^NODE_${idx}_\|^NODE_COUNT=" "$NODES_CONF" > "$tmp" 2>/dev/null || true
    # Append new values
    for kv; do printf '%s\n' "NODE_${idx}_${kv}" >> "$tmp"; done
    # Count existing entries
    local max_idx=$idx
    while [ -f "$tmp" ] && grep -q "^NODE_${max_idx}_" "$tmp" 2>/dev/null; do
        max_idx=$((max_idx + 1))
    done
    printf '%s\n' "NODE_COUNT=$max_idx" >> "$tmp"
    mv "$tmp" "$NODES_CONF"
}

# ---- Delete node ----
delete_node() {
    load_nodes
    if [ "$NODE_COUNT" -eq 0 ]; then _err "没有节点"; return 1; fi
    _info "当前节点:"
    for i in $(seq 0 $((NODE_COUNT - 1))); do
        eval "n=\$NODE_${i}_NAME; p=\$NODE_${i}_PROTO; pt=\$NODE_${i}_PORT_INTERNAL"
        printf "  [%d] %s — %s (端口: %s)\n" "$i" "$n" "$p" "$pt"
    done
    local idx
    if [ -n "$WHIPTAIL_CMD" ]; then
        local choices=""
        for i in $(seq 0 $((NODE_COUNT - 1))); do
            eval "n=\$NODE_${i}_NAME; p=\$NODE_${i}_PROTO"
            choices="$choices $i \"$n ($p)\""
        done
        idx=$(eval "$WHIPTAIL_CMD" --title "删除节点" --menu "选择要删除的节点" 0 0 0 $choices 2>&1 /dev/tty | grep -oE '^[0-9]+$')
    else
        printf "输入要删除的节点编号: "; read -r idx
    fi
    [ -z "$idx" ] && return 1
    echo "$idx" | grep -qE '^[0-9]+$' || { _err "无效编号"; return 1; }
    [ "$idx" -ge "$NODE_COUNT" ] && { _err "编号超出范围"; return 1; }

    eval "n=\$NODE_${idx}_NAME"
    
    # Build new nodes.conf without this node, re-indexing
    local newconf="/tmp/sbx-new-$$.conf"
    : > "$newconf"
    local new_idx=0
    for i in $(seq 0 $((NODE_COUNT - 1))); do
        [ "$i" -eq "$idx" ] && continue
        while IFS= read -r line; do
            case "$line" in
                NODE_${i}_*) echo "$line" | sed "s/^NODE_${i}_/NODE_${new_idx}_/" >> "$newconf" ;;
            esac
        done < "$NODES_CONF"
        new_idx=$((new_idx + 1))
    done
    echo "NODE_COUNT=$new_idx" >> "$newconf"
    mv "$newconf" "$NODES_CONF"
    _ok "已删除节点: $n"
    regenerate_config
}

# ---- Add node (interactive, same flow as install.sh) ----
add_node() {
    load_nodes
    local idx=$NODE_COUNT

    # Protocol selection
    local proto_choice
    if [ -n "$WHIPTAIL_CMD" ]; then
        proto_choice=$(whip_menu "添加节点" "选择协议" \
            1 "VLESS + Reality (无需域名，推荐)" \
            2 "VLESS + WebSocket + TLS (需域名)" \
            3 "VLESS + TCP + TLS (需域名)" \
            4 "Hysteria2 (高丢包加速)" \
            5 "Shadowsocks (轻量经典)" \
            6 "Trojan + TLS (需域名)")
    else
        echo "选择协议:"
        echo "1) VLESS + Reality  2) VLESS+WS+TLS  3) VLESS+TCP+TLS"
        echo "4) Hysteria2  5) Shadowsocks  6) Trojan+TLS"
        printf "选择 [1-6] (默认 1): "; read -r proto_choice
    fi
    [ -z "$proto_choice" ] && proto_choice=1

    local proto
    case "$proto_choice" in
        2) proto="vless-ws" ;; 3) proto="vless-tcp" ;; 4) proto="hysteria2" ;;
        5) proto="shadowsocks" ;; 6) proto="trojan" ;; *) proto="vless-reality" ;;
    esac

    # Port input
    local node_input=""
    while true; do
        node_input=$(whip_input "端口设置" "节点端口 (内网/公网，如 20000/32090)" "")
        [ -z "$node_input" ] && continue
        local in=$(echo "$node_input" | cut -d'/' -f1)
        local ex=$(echo "$node_input" | cut -d'/' -f2)
        echo "$in" | grep -qE '^[0-9]+$' && echo "$ex" | grep -qE '^[0-9]+$' && break
        whip_msg "格式错误" "请按 内网端口/公网端口 输入数字"
    done
    local node_internal=$(echo "$node_input" | cut -d'/' -f1)
    local node_external=$(echo "$node_input" | cut -d'/' -f2)

    # Name
    local name=$(whip_input "节点名称" "给这个节点起个名字 (如 mynode)" "node-$idx")
    [ -z "$name" ] && name="node-$idx"

    # Generate keys
    local uuid=""; local password=""; local sni="" domain="" wspath=""
    uuid=$("$SBIN" generate uuid 2>/dev/null || cat /proc/sys/kernel/random/uuid 2>/dev/null || uuidgen 2>/dev/null || echo "$(date +%s)-$$-RANDOM")

    if [ "$proto" = "vless-reality" ]; then
        local sni_choice
        if [ -n "$WHIPTAIL_CMD" ]; then
            sni_choice=$(whip_menu "SNI 伪装" "选择域名" \
                1 "www.yahoo.com" 2 "www.icloud.com" 3 "自定义")
        else
            printf "SNI (1-yahoo 2-icloud 3-自定义, 默认 2): "; read -r sni_choice
        fi
        case "$sni_choice" in
            1) sni="www.yahoo.com" ;;
            3) sni=$(whip_input "自定义 SNI" "SNI 域名" ""); [ -z "$sni" ] && sni="www.icloud.com" ;;
            *) sni="www.icloud.com" ;;
        esac
    fi

    if [ "$proto" = "hysteria2" ]; then
        sni=$(whip_input "SNI 伪装" "SNI (默认 www.bing.com)" "www.bing.com")
        [ -z "$sni" ] && sni="www.bing.com"
    fi

    local needs_cert=0
    case "$proto" in vless-ws|vless-tcp|trojan) needs_cert=1;; esac
    if [ "$needs_cert" = "1" ]; then
        domain=$(whip_input "域名" "A 记录指向本机" "")
        [ -z "$domain" ] && { whip_msg "错误" "域名不能为空"; return 1; }
        if [ ! -f "$CERT_DIR/fullchain.pem" ]; then
            _info "需 TLS 证书，运行 install.sh 安装时会自动申请"
            local email=$(whip_input "邮箱" "Let's Encrypt 邮箱" "admin@${domain}")
            [ -z "$email" ] && email="admin@${domain}"
        fi
    fi

    [ "$proto" = "vless-ws" ] && wspath=$(whip_input "WS 路径" "路径 (默认 /vless)" "/vless")
    [ -z "$wspath" ] && wspath="/vless"

    if [ "$proto" = "shadowsocks" ] || [ "$proto" = "hysteria2" ] || [ "$proto" = "trojan" ]; then
        password=$(openssl rand -base64 16 | tr -d '=+/')
    fi

    # Generate reality keys if needed
    local priv_key="" pub_key="" short_id=""
    if [ "$proto" = "vless-reality" ]; then
        local kp=$("$SBIN" generate reality-keypair)
        priv_key=$(echo "$kp" | grep PrivateKey | awk '{print $2}')
        pub_key=$(echo "$kp" | grep PublicKey | awk '{print $2}')
        short_id=$(openssl rand -hex 4)
    fi

    # Save to nodes.conf
    local ip=$(curl -s4 --connect-timeout 5 icanhazip.com 2>/dev/null || curl -s4 --connect-timeout 5 ip.sb 2>/dev/null || curl -s4 --connect-timeout 5 api.ipify.org 2>/dev/null || echo "")
    save_node "$idx" \
        "NAME='$name'" \
        "PROTO='$proto'" \
        "PORT_INTERNAL='$node_internal'" \
        "PORT_EXTERNAL='$node_external'" \
        "UUID='$uuid'" \
        "PASSWORD='$password'" \
        "SNI='$sni'" \
        "DOMAIN='$domain'" \
        "WS_PATH='$wspath'" \
        "PUBLIC_KEY='$pub_key'" \
        "PRIVATE_KEY='$priv_key'" \
        "SHORT_ID='$short_id'" \
        "IP='$ip'"

    # Regenerate config
    regenerate_config
    _ok "节点 '$name' ($proto) 已添加，端口: ${node_internal}/${node_external}"
}

# ---- Show node info / links ----
show_info() {
    load_nodes
    if [ "$NODE_COUNT" -eq 0 ]; then _err "没有节点"; return 1; fi

    for i in $(seq 0 $((NODE_COUNT - 1))); do
        eval "n=\$NODE_${i}_NAME; p=\$NODE_${i}_PROTO; pt=\$NODE_${i}_PORT_INTERNAL"
        eval "pe=\$NODE_${i}_PORT_EXTERNAL; ip=\$NODE_${i}_IP; uuid=\$NODE_${i}_UUID"
        eval "pass=\$NODE_${i}_PASSWORD; sni=\$NODE_${i}_SNI; domain=\$NODE_${i}_DOMAIN"
        eval "wsp=\$NODE_${i}_WS_PATH; pubk=\$NODE_${i}_PUBLIC_KEY; sid=\$NODE_${i}_SHORT_ID"

        echo ""
        printf "${GREEN}====== %s (%s) ======${NC}\n" "$n" "$p"
        case "$p" in
            vless-reality)
                echo "协议:     VLESS + Reality"
                echo "地址/端口: $ip:$pe (内网: $pt)"
                echo "UUID:     $uuid"
                echo "SNI:      $sni"
                echo "PublicKey: $pubk"
                echo "ShortID:  $sid"
                echo ""
                echo "链接:"
                echo "vless://$uuid@$ip:$pe?encryption=none&flow=xtls-rprx-vision&security=reality&sni=$sni&fp=chrome&pbk=$pubk&sid=$sid&type=tcp#${n}"
                ;;
            vless-ws)
                echo "协议:     VLESS + WebSocket + TLS"
                echo "域名/端口: $domain:$pe"
                echo "UUID:     $uuid"
                echo "WS 路径:  ${wsp:-/vless}"
                echo ""
                echo "链接:"
                echo "vless://$uuid@$domain:$pe?encryption=none&security=tls&type=ws&path=${wsp:-/vless}&host=$domain&sni=$domain#${n}"
                ;;
            vless-tcp)
                echo "协议:     VLESS + TCP + TLS"
                echo "域名/端口: $domain:$pe"
                echo "UUID:     $uuid"
                echo ""
                echo "链接:"
                echo "vless://$uuid@$domain:$pe?encryption=none&security=tls&type=tcp&sni=$domain#${n}"
                ;;
            hysteria2)
                echo "协议:     Hysteria2"
                echo "地址/端口: $ip:$pe (内网: $pt)"
                echo "密码:     $pass"
                echo "SNI:      ${sni:-www.bing.com}"
                echo ""
                echo "链接:"
                echo "hy2://$pass@$ip:$pe?insecure=1&sni=${sni:-www.bing.com}#${n}"
                ;;
            shadowsocks)
                echo "协议:     Shadowsocks (无加密)"
                echo "地址/端口: $ip:$pe (内网: $pt)"
                echo "密码:     $pass"
                echo ""
                local b64=$(printf '%s' "none:$pass" | base64 | tr -d '\n' | sed 's/=//g')
                echo "链接:"
                echo "ss://${b64}@${ip}:${pe}#${n}"
                ;;
            trojan)
                echo "协议:     Trojan + TLS"
                echo "域名/端口: $domain:$pe"
                echo "密码:     $pass"
                echo ""
                echo "链接:"
                echo "trojan://$pass@$domain:$pe?security=tls&sni=$domain#${n}"
                ;;
        esac
        echo ""
    done
}

# ---- List nodes (short format) ----
list_nodes() {
    load_nodes
    if [ "$NODE_COUNT" -eq 0 ]; then
        _warn "没有节点"
        echo "使用 sbx add 添加一个"
        return
    fi
    printf "${GREEN}%s 个节点:${NC}\n" "$NODE_COUNT"
    for i in $(seq 0 $((NODE_COUNT - 1))); do
        eval "n=\$NODE_${i}_NAME; p=\$NODE_${i}_PROTO; pt=\$NODE_${i}_PORT_INTERNAL; pe=\$NODE_${i}_PORT_EXTERNAL"
        printf "  ${CYAN}[%d]${NC} %-20s %-18s %s/%s\n" "$i" "$n" "$p" "$pt" "$pe"
    done
}

# ---- Service management ----
svc_restart() {
    _info "重启 sing-box..."
    if command -v systemctl >/dev/null 2>&1 && [ -d /run/systemd/system ]; then
        systemctl restart sing-box 2>/dev/null || { _warn "重试..."; sleep 2; systemctl restart sing-box 2>/dev/null || true; }
    elif command -v rc-service >/dev/null 2>&1; then
        rc-service sing-box restart 2>/dev/null || true
    fi
    _ok "已重启"
}

svc_status() {
    if command -v systemctl >/dev/null 2>&1 && [ -d /run/systemd/system ]; then
        systemctl status sing-box 2>&1 || true
    elif command -v rc-service >/dev/null 2>&1; then
        rc-service sing-box status 2>&1 || true
    else
        pgrep -f sing-box >/dev/null && echo "sing-box 运行中" || echo "sing-box 未运行"
    fi
}

svc_logs() {
    if command -v journalctl >/dev/null 2>&1; then
        journalctl -u sing-box -n 30 --no-pager 2>&1 || true
    elif [ -f /var/log/sing-box.log ]; then
        tail -30 /var/log/sing-box.log 2>/dev/null || true
    else
        _warn "未找到日志"
    fi
}

# ---- Uninstall ----
do_uninstall() {
    _warn "将卸载 sing-box 和所有节点配置！"
    if [ -n "$WHIPTAIL_CMD" ]; then
        local confirm
        confirm=$(eval "$WHIPTAIL_CMD" --title "确认卸载" --yesno "确定要卸载？" 6 30 2>&1 /dev/tty; echo $?)
        [ "$confirm" -ne 0 ] && { _info "已取消"; return; }
    else
        printf "确定卸载？(y/N): "; read -r confirm
        [ "$confirm" != "y" ] && [ "$confirm" != "Y" ] && { _info "已取消"; return; }
    fi

    _info "停止服务..."
    if command -v systemctl >/dev/null 2>&1 && [ -d /run/systemd/system ]; then
        systemctl stop sing-box 2>/dev/null || true
        systemctl disable sing-box 2>/dev/null || true
        rm -f /etc/systemd/system/sing-box.service
        systemctl daemon-reload 2>/dev/null || true
    elif command -v rc-service >/dev/null 2>&1; then
        rc-service sing-box stop 2>/dev/null || true
        rc-update del sing-box 2>/dev/null || true
        rm -f /etc/init.d/sing-box
    fi
    pkill -f sing-box 2>/dev/null || true

    rm -rf /etc/sing-box /usr/local/bin/sing-box /usr/local/bin/sbx /usr/local/bin/vps-info
    _ok "已卸载"
}

# ---- Menu ----
show_menu() {
    while true; do
        echo ""
        printf "${GREEN}========================================${NC}\n"
        printf "${GREEN}  NAT VPS 节点管理 (sbx)${NC}\n"
        printf "${GREEN}========================================${NC}\n"
        echo ""
        load_nodes
        printf "  ${CYAN}节点数:${NC} ${NODE_COUNT:-0}\n"
        echo ""
        echo "  1)  查看所有节点"
        echo "  2)  查看节点链接"
        echo "  3)  添加节点"
        echo "  4)  删除节点"
        echo "  5)  重启服务"
        echo "  6)  查看状态"
        echo "  7)  查看日志"
        echo "  8)  卸载"
        echo "  0)  退出"
        echo ""
        printf "选择 [0-8]: "; read -r choice
        case "$choice" in
            1) list_nodes ;;
            2) show_info ;;
            3) add_node; svc_restart ;;
            4) delete_node; svc_restart ;;
            5) svc_restart ;;
            6) svc_status ;;
            7) svc_logs ;;
            8) do_uninstall; return ;;
            0) echo ""; return ;;
            *) _err "无效选择" ;;
        esac
    done
}

# ---- Main ----
main() {
    [ "$(id -u)" -ne 0 ] && { _err "需要 root 权限"; exit 1; }
    [ ! -f "$SBIN" ] && { _err "sing-box 未安装，请先运行 install.sh"; exit 1; }

    case "${1:-menu}" in
        list|ls)    list_nodes ;;
        info|links) show_info ;;
        add)        add_node; svc_restart ;;
        del|rm)     delete_node; svc_restart ;;
        restart)    svc_restart ;;
        status)     svc_status ;;
        logs)       svc_logs ;;
        uninstall)  do_uninstall ;;
        menu|"")    show_menu ;;
        *)          _err "用法: sbx {list|info|add|del|restart|status|logs|uninstall}"; exit 1 ;;
    esac
}

main "$@"
