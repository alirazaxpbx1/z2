#!/usr/bin/env bash
# ============================================================================
# Project Name : ALIRAZA WEB PANEL (multi-protocol VPS panel, web based)
# Base         : v55.4-HOTFIX engine (Xray / SSH-WS / SSL / UDP / SlowDNS / ZiVPN / HY2)
# Control      : Install terminal se (domain, panel port, user, password),
#                baqi sab kuch Web Panel se.
# ============================================================================

printf "\033[?1049l" 2>/dev/null || true
sed -i '/acme.sh.env/d' /root/.bashrc 2>/dev/null || true
export PATH="$PATH:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/local/go/bin"

RED='\033[1;91m'; GREEN='\033[1;92m'; YELLOW='\033[1;93m'; BLUE='\033[1;94m'
PURPLE='\033[1;95m'; CYAN='\033[1;96m'; WHITE='\033[1;97m'; GRAY='\033[0;37m'
BG_PURPLE='\033[1;97;45m'; BG_RED='\033[1;97;41m'; NC='\033[0m'

[[ "$EUID" -ne 0 ]] && { echo -e "${RED}[!] Run as root (sudo su)!${NC}"; exit 1; }

DATA_DIR="/etc/aliraza"
BACKUP_DIR="/etc/aliraza/backup"
INSTALLED_FLAG="/etc/aliraza/.installed"
V55_FLAG="/etc/aliraza/.v55_fixed_ready"
V554_FLAG="/etc/aliraza/.v554_realip_ready"
USAGE_DIR="/etc/aliraza/usage"
USERS_CONF_DIR="/etc/aliraza/users"
CLIENTS_DIR="/root/zainu-configs"
BUNNY_DIR="/root/zainu-configs/bunnycdn"
USERS_DB="/etc/aliraza/users.db"
TG_CONF="/etc/aliraza/tgbot.conf"
TG_ADMINS="/etc/aliraza/tg_admins.txt"
BUNNY_CONF="/etc/aliraza/bunnycdn.conf"
XRAY_CONF="/usr/local/etc/xray/config.json"
SLOWDNS_DIR="/etc/slowdns"
WS_DIR="/etc/zainu-ws"
UDP_DIR="/etc/udp-custom"
ZIVPN_DIR="/etc/zivpn"
HY2_DIR="/etc/hysteria"
OVPN_DIR="/etc/openvpn"
BANNER_FILE="/etc/issue.net"

mkdir -p "$DATA_DIR" "$BACKUP_DIR" "$USAGE_DIR" "$USERS_CONF_DIR" "$CLIENTS_DIR" "$BUNNY_DIR" "$SLOWDNS_DIR" "$WS_DIR" "$UDP_DIR" "$ZIVPN_DIR" "$HY2_DIR" "$OVPN_DIR" \
         /etc/ssl/xray /var/log/xray /var/log/nginx /etc/nginx/conf.d /etc/nginx/sites-enabled /etc/stunnel /etc/dropbear /etc/haproxy /var/www/html
touch "$USERS_DB" "$TG_ADMINS" /var/log/ws-proxy.log
rm -f "$CLIENTS_DIR"/*-bunnycdn.txt 2>/dev/null || true

backup_original_system_files() {
    [[ ! -f "$BACKUP_DIR/sshd_config.orig" && -f /etc/ssh/sshd_config ]] && cp -pf /etc/ssh/sshd_config "$BACKUP_DIR/sshd_config.orig" 2>/dev/null || true
    [[ ! -d "$BACKUP_DIR/sshd_config.d.orig" && -d /etc/ssh/sshd_config.d ]] && cp -a /etc/ssh/sshd_config.d "$BACKUP_DIR/sshd_config.d.orig" 2>/dev/null || true
    [[ ! -f "$BACKUP_DIR/issue.net.orig" && -f /etc/issue.net ]] && cp -pf /etc/issue.net "$BACKUP_DIR/issue.net.orig" 2>/dev/null || true
}
backup_original_system_files

is_protected_system_user() {
    local u="$1"
    [[ -z "$u" ]] && return 0
    case "$u" in
        root|ubuntu|debian|admin|ec2-user|centos|rocky|almalinux|fedora|sshd|nobody|systemd-*|daemon|bin|sys|sync|haproxy|www-data) return 0 ;;
    esac
    id "$u" >/dev/null 2>&1 && [[ $(id -u "$u" 2>/dev/null || echo 0) -lt 1000 ]] && return 0
    return 1
}

clear_screen() { printf "\033[2J\033[3J\033[H"; }

fix_hostname_resolution() {
    local hname=$(hostname 2>/dev/null || echo "localhost")
    [[ -n "$hname" ]] && ! grep -qw "$hname" /etc/hosts 2>/dev/null && echo "127.0.0.1 $hname" >> /etc/hosts 2>/dev/null || true
    sed -i '/^#*precedence ::ffff:0:0\/96/d' /etc/gai.conf 2>/dev/null || true
    echo "precedence ::ffff:0:0/96  100" >> /etc/gai.conf 2>/dev/null || true
}

get_vps_ip() {
    local ip=""
    [[ -s "$DATA_DIR/vps_ip.txt" ]] && ip=$(head -n1 "$DATA_DIR/vps_ip.txt" 2>/dev/null | tr -d '[:space:]')
    if [[ -z "$ip" || "$ip" == "127.0.0.1" ]]; then
        ip=$(curl -s4 --max-time 2 api.ipify.org 2>/dev/null | head -n1 | tr -d '[:space:]')
        [[ -z "$ip" ]] && ip=$(curl -s4 --max-time 2 icanhazip.com 2>/dev/null | head -n1 | tr -d '[:space:]')
        [[ -z "$ip" ]] && ip=$(hostname -I 2>/dev/null | awk '{print $1}' | tr -d '[:space:]')
        [[ -n "$ip" ]] && echo "$ip" > "$DATA_DIR/vps_ip.txt"
    fi
    echo "${ip:-Unknown}"
}

get_vps_provider() {
    local prov=""
    [[ -s "$DATA_DIR/provider.txt" ]] && prov=$(head -n1 "$DATA_DIR/provider.txt" 2>/dev/null | tr -d '{}[]"')
    if [[ -z "$prov" ]]; then
        prov=$(curl -s --max-time 2 "http://ip-api.com/line/?fields=isp" 2>/dev/null | head -n1 | tr -d '{}[]"' | cut -c1-18)
        [[ -n "$prov" ]] && echo "$prov" > "$DATA_DIR/provider.txt"
    fi
    echo "${prov:-Cloud VPS}"
}

get_real_google_ping() {
    local ping_out ms CPUS
    CPUS=$(nproc 2>/dev/null || echo 4)
    ping_out=$(ping -c 1 -W 1 8.8.8.8 2>/dev/null)
    if [[ $? -eq 0 ]]; then
        ms=$(echo "$ping_out" | grep -oE 'time=[0-9.]+' | head -n1 | cut -d= -f2)
        [[ -n "$ms" ]] && printf "${GREEN}${ms} ms (${CPUS}-Core BBR Turbo)${NC}" || printf "${GREEN}ONLINE (${CPUS}-Core BBR)${NC}"
    else
        printf "${GREEN}ONLINE (${CPUS}-Core BBR)${NC}"
    fi
}

check_domain_live_status() {
    local dom="$1" my_ip="$2" a_ip cname_rec isp_info
    [[ -z "$dom" || "$dom" == "Not-Set" ]] && { printf "${RED}[NOT SET]${NC}"; return; }
    [[ "$dom" == "$my_ip" ]] && { printf "${YELLOW}[IP ONLY]${NC}"; return; }
    local cache_f="/run/zainu_dom_${dom//[^a-zA-Z0-9]/_}"
    if [[ -f "$cache_f" ]] && [[ $(( $(date +%s) - $(stat -c %Y "$cache_f" 2>/dev/null || echo 0) )) -lt 60 ]]; then
        cat "$cache_f"
        return
    fi
    cname_rec=$(dig +short +time=1 +tries=1 CNAME "$dom" @8.8.8.8 2>/dev/null | head -n1 | tr '[:upper:]' '[:lower:]')
    a_ip=$(dig +short +time=1 +tries=1 A "$dom" @8.8.8.8 2>/dev/null | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' | tail -n1)
    local out_str=""
    if [[ -z "$a_ip" ]]; then
        out_str="${RED}[NOT POINTED]${NC}"
    elif [[ "$a_ip" == "$my_ip" ]]; then
        out_str="${GREEN}[POINTED -> ${a_ip}]${NC}"
    elif [[ "$cname_rec" == *"b-cdn.net"* || "$dom" == *"b-cdn.net"* ]]; then
        out_str="${CYAN}[BUNNY-CDN -> ${a_ip}]${NC}"
    else
        isp_info=$(curl -s --max-time 1 "http://ip-api.com/line/${a_ip}?fields=isp,org" 2>/dev/null | tr '\n' ' ' | tr '[:upper:]' '[:lower:]')
        if [[ "$isp_info" == *"cloudflare"* || "$isp_info" == *"bunny"* || "$isp_info" == *"fastly"* || "$isp_info" == *"cloudfront"* ]]; then
            out_str="${YELLOW}[CDN/PROXY -> ${a_ip}]${NC}"
        else
            out_str="${RED}[NOT POINTED! IP: ${a_ip}]${NC}"
        fi
    fi
    printf "%b" "$out_str" > "$cache_f" 2>/dev/null || true
    printf "%b" "$out_str"
}

check_ns_live_status() {
    local ns_dom="$1" my_ip="$2"
    [[ -z "$ns_dom" || "$ns_dom" == "Not-Set" || "$ns_dom" == "$my_ip" ]] && { printf "${RED}[NOT SET]${NC}"; return; }
    local cache_f="/run/zainu_ns_${ns_dom//[^a-zA-Z0-9]/_}"
    if [[ -f "$cache_f" ]] && [[ $(( $(date +%s) - $(stat -c %Y "$cache_f" 2>/dev/null || echo 0) )) -lt 60 ]]; then
        cat "$cache_f"
        return
    fi
    local parent_dom auth_ns ns_target target_ip out_str=""
    parent_dom=$(echo "$ns_dom" | awk -F. '{if (NF>=2) print $(NF-1)"."$NF; else print $0}')
    auth_ns=$(dig +short +time=1 +tries=1 NS "$parent_dom" @8.8.8.8 2>/dev/null | head -n1 | sed 's/\.$//')
    [[ -n "$auth_ns" ]] && ns_target=$(dig +time=1 +tries=1 @"$auth_ns" "$ns_dom" NS +norecurse +noall +authority +answer 2>/dev/null | awk '$4=="NS" {print $5}' | head -n1 | sed 's/\.$//')
    [[ -z "$ns_target" ]] && ns_target=$(dig +short +time=1 +tries=1 NS "$ns_dom" @8.8.8.8 2>/dev/null | head -n1 | sed 's/\.$//')
    if [[ -z "$ns_target" ]]; then
        out_str="${RED}[NS MISSING]${NC}"
    else
        target_ip=$(dig +short +time=1 +tries=1 A "$ns_target" @8.8.8.8 2>/dev/null | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' | tail -n1)
        [[ "$target_ip" == "$my_ip" ]] && out_str="${GREEN}[POINTED -> ${target_ip}]${NC}" || out_str="${RED}[NOT POINTED]${NC}"
    fi
    printf "%b" "$out_str" > "$cache_f" 2>/dev/null || true
    printf "%b" "$out_str"
}

format_bytes() {
    awk -v b="${1:-0}" 'BEGIN {
        b = b + 0;
        if (b >= 1073741824) printf "%.2f GB (%.1f MB)", b/1073741824, b/1048576;
        else if (b >= 1048576) printf "%.2f MB", b/1048576;
        else if (b >= 1024) printf "%.2f KB", b/1024;
        else printf "%d B", b;
    }'
}

format_bytes_short() {
    awk -v b="${1:-0}" 'BEGIN {
        b = b + 0;
        if (b >= 1073741824) printf "%.2f GB", b/1073741824;
        else if (b >= 1048576) printf "%.2f MB", b/1048576;
        else if (b >= 1024) printf "%.2f KB", b/1024;
        else printf "%d B", b;
    }'
}

get_total_users_count() { awk -F'|' 'NF>=6 && $1!="" {c++} END {print c+0}' "$USERS_DB" 2>/dev/null; }

get_all_users_used_bytes() {
    local sum=0
    if [[ -s "$USERS_DB" ]]; then
        while IFS='|' read -r uname rest; do
            [[ -z "$uname" ]] && continue
            local ub=0
            [[ -f "$USAGE_DIR/${uname}.bytes" ]] && ub=$(head -n1 "$USAGE_DIR/${uname}.bytes" 2>/dev/null | tr -dc '0-9')
            sum=$((sum + ${ub:-0}))
        done < "$USERS_DB"
    fi
    echo "$sum"
}

get_all_users_limit_gb() { awk -F'|' 'NF>=4 && $1!="" {s+=$4} END {print s+0}' "$USERS_DB" 2>/dev/null; }

verify_real_dnstt_binary() {
    local bin="$SLOWDNS_DIR/dnstt-server"
    [[ ! -x "$bin" ]] && return 1
    local tk1="/tmp/.dnstt_k1_$$" tp1="/tmp/.dnstt_p1_$$"
    "$bin" -gen-key -privkey-file "$tk1" -pubkey-file "$tp1" >/dev/null 2>&1 || { rm -f "$tk1" "$tp1"; return 1; }
    local p1=$(head -n1 "$tp1" 2>/dev/null | tr -d '[:space:]')
    rm -f "$tk1" "$tp1"
    [[ "$p1" =~ ^[0-9a-fA-F]{64}$ ]] && return 0 || return 1
}

real_badge() {
    local svc="$1" port="$2" proto="$3" bin="$4"
    if [[ "$proto" == "bot" ]]; then
        [[ -s "$TG_CONF" ]] && systemctl is-active --quiet zainu-tgbot 2>/dev/null && printf "${GREEN}[ON]${NC}" || printf "${RED}[OF]${NC}"
        return
    fi
    if [[ "$svc" == "mux443" ]]; then
        systemctl is-active --quiet haproxy 2>/dev/null && ss -tln 2>/dev/null | grep -qE ":443\b" && printf "${GREEN}[ON]${NC}" || printf "${RED}[OF]${NC}"
        return
    fi
    [[ -n "$bin" && ! -x "$bin" ]] && { printf "${RED}[OF]${NC}"; return; }
    if [[ "$svc" == "ssh" ]]; then
        systemctl is-active --quiet ssh 2>/dev/null || systemctl is-active --quiet sshd 2>/dev/null || { printf "${RED}[OF]${NC}"; return; }
    elif ! systemctl is-active --quiet "$svc" 2>/dev/null; then
        printf "${RED}[OF]${NC}"; return
    fi
    [[ "$proto" == "tcp" ]] && { ss -tln 2>/dev/null | grep -qE ":${port}\b" && printf "${GREEN}[ON]${NC}" || printf "${RED}[OF]${NC}"; }
    [[ "$proto" == "udp" ]] && { ss -uln 2>/dev/null | grep -qE ":${port}\b" && printf "${GREEN}[ON]${NC}" || printf "${RED}[OF]${NC}"; }
}

enable_bbr_and_kernel_speed() {
    fix_hostname_resolution
    modprobe tcp_bbr >/dev/null 2>&1 || true
    modprobe nf_conntrack >/dev/null 2>&1 || true
    cat << 'EOF' > /etc/sysctl.d/99-zainu-speed.conf
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
net.ipv4.ip_forward = 1
net.ipv6.conf.all.forwarding = 1
net.netfilter.nf_conntrack_acct = 1
net.netfilter.nf_conntrack_max = 1048576
net.core.rmem_default = 262144
net.core.wmem_default = 262144
net.core.rmem_max = 67108864
net.core.wmem_max = 67108864
net.core.netdev_max_backlog = 250000
net.core.netdev_budget = 600
net.core.somaxconn = 65535
net.ipv4.tcp_rmem = 4096 131072 67108864
net.ipv4.tcp_wmem = 4096 131072 67108864
net.ipv4.tcp_window_scaling = 1
net.ipv4.tcp_moderate_rcvbuf = 1
net.ipv4.tcp_mtu_probing = 1
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_fin_timeout = 10
net.ipv4.tcp_slow_start_after_idle = 0
net.ipv4.tcp_notsent_lowat = 16384
net.ipv4.tcp_limit_output_bytes = 262144
net.ipv4.tcp_keepalive_time = 15
net.ipv4.tcp_keepalive_intvl = 5
net.ipv4.tcp_keepalive_probes = 2
fs.file-max = 2000000
EOF
    sysctl --system >/dev/null 2>&1 || true
    echo 1 > /proc/sys/net/netfilter/nf_conntrack_acct 2>/dev/null || true
    for gov in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do
        [[ -f "$gov" ]] && echo "performance" > "$gov" 2>/dev/null || true
    done
    local DEF_IF CPUS MASK
    DEF_IF=$(ip route get 8.8.8.8 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="dev") print $(i+1)}' | head -n1)
    if [[ -n "$DEF_IF" ]]; then
        ip link set dev "$DEF_IF" txqueuelen 10000 2>/dev/null || true
        tc qdisc replace dev "$DEF_IF" root fq 2>/dev/null || true
        command -v ethtool >/dev/null 2>&1 && ethtool -K "$DEF_IF" tso on gso on gro on >/dev/null 2>&1 || true
        CPUS=$(nproc 2>/dev/null || echo 4)
        MASK=$(printf '%x' $(( (1 << CPUS) - 1 )) 2>/dev/null || echo "ff")
        for rps in /sys/class/net/"$DEF_IF"/queues/rx-*/rps_cpus; do [[ -f "$rps" ]] && echo "$MASK" > "$rps" 2>/dev/null || true; done
    fi
}

ensure_golang_compiler() {
    export PATH="$PATH:/usr/local/go/bin"
    # Purana distro Go (Debian 10 = 1.11) dnstt/WS build FAIL karta hai -> Go >= 1.20 zaroori
    if command -v go >/dev/null 2>&1; then
        local GMM=$(go version 2>/dev/null | grep -oE 'go[0-9]+\.[0-9]+' | head -n1 | sed 's/go//')
        local GMJ=${GMM%%.*} GMN=${GMM##*.}
        if [[ "${GMJ:-0}" -gt 1 || ( "${GMJ:-1}" -eq 1 && "${GMN:-0}" -ge 20 ) ]]; then return 0; fi
    fi
    local ARCH=$(uname -m) GO_ARCH="amd64"
    [[ "$ARCH" == "aarch64" || "$ARCH" == "arm64" ]] && GO_ARCH="arm64"
    for base in "https://dl.google.com/go" "https://go.dev/dl"; do
        curl -fsSL --retry 2 --max-time 90 "${base}/go1.22.5.linux-${GO_ARCH}.tar.gz" -o /tmp/go.tar.gz 2>/dev/null || continue
        if tar -tzf /tmp/go.tar.gz >/dev/null 2>&1; then
            rm -rf /usr/local/go && tar -C /usr/local -xzf /tmp/go.tar.gz 2>/dev/null || true
            ln -sf /usr/local/go/bin/go /usr/bin/go 2>/dev/null || true
            break
        fi
    done
    rm -f /tmp/go.tar.gz
    command -v go >/dev/null 2>&1 && return 0
    echo -e "${RED}[!] Go compiler install nahi ho saka! WS Engine/SlowDNS build fail ho sakta hai (network check karein).${NC}"
    return 1
}

ensure_base_packages() {
    fix_hostname_resolution
    rm -f /etc/apt/sources.list.d/*speedtest* /etc/apt/sources.list.d/*ookla* 2>/dev/null || true
    local REQ_PKGS=(curl wget socat jq ufw iptables net-tools openssl cron unzip zip tar screen dropbear stunnel4 python3 nginx haproxy openvpn easy-rsa golang-go git dnsutils conntrack iproute2 psmisc lsof tcpdump rsyslog ethtool ca-certificates gnupg nano)
    local need=""
    for cmd in curl wget nginx haproxy openvpn jq python3 dropbear stunnel4 dig ss iptables conntrack tcpdump git zip rsyslogd lsof nano; do
        command -v "$cmd" >/dev/null 2>&1 || need="yes"
    done
    if [[ -n "$need" ]]; then
        export DEBIAN_FRONTEND=noninteractive
        echo -e "${YELLOW}[*] Base packages install ho rahe hain (fresh VPS one-time setup, 1-2 min lag sakte hain)...${NC}"
        local apt_ok=0
        for attempt in 1 2 3; do
            apt-get update -y >/dev/null 2>&1 || true
            dpkg --configure -a >/dev/null 2>&1 || true
            if apt-get install -y "${REQ_PKGS[@]}" >/dev/null 2>&1; then apt_ok=1; break; fi
            echo -e "${YELLOW}[!] apt attempt ${attempt}/3 fail - 5s baad dobara try...${NC}"
            sleep 5
        done
        apt-get -f install -y >/dev/null 2>&1 || true
        dpkg --configure -a >/dev/null 2>&1 || true
        [[ "$apt_ok" != "1" ]] && apt-get install -y "${REQ_PKGS[@]}" >/dev/null 2>&1 || true
    fi
    local missing=""
    for cmd in nginx haproxy openvpn jq python3 dropbear stunnel4 dig ss iptables tcpdump git rsyslogd curl; do
        command -v "$cmd" >/dev/null 2>&1 || missing="${missing} ${cmd}"
    done
    if [[ -n "$missing" ]]; then
        echo -e "${RED}[X] GHALTI: yeh packages install nahi hue:${missing}${NC}"
        echo -e "${RED}    VPS ka internet/apt repo check karein, warna services chalengi nahi!${NC}"
    fi
    systemctl enable rsyslog >/dev/null 2>&1 || true
    systemctl start rsyslog >/dev/null 2>&1 || true
    touch /var/log/auth.log && chmod 640 /var/log/auth.log 2>/dev/null || true
    ensure_golang_compiler
    if ! command -v speedtest-cli >/dev/null 2>&1; then
        curl -sL --max-time 10 https://raw.githubusercontent.com/sivel/speedtest-cli/master/speedtest.py -o /usr/local/bin/speedtest-cli 2>/dev/null && chmod +x /usr/local/bin/speedtest-cli || true
    fi
    enable_bbr_and_kernel_speed
}

write_zainu_vip_banner() {
    cat << 'BANNER_EOF' > /etc/issue.net
<font color="#FF00FF"><b>━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━</b></font><br>
<font color="#00FFFF"><b>         👑  W E L C O M E   T O   AliRaza+server  👑         </b></font><br>
<font color="#00FF00"><b>         ⚡ ULTRA HIGH-SPEED VIP CLOUD GAMING SERVER ⚡         </b></font><br>
<font color="#FF00FF"><b>━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━</b></font><br>
<font color="#00FFFF"><b>  💎 Owner & Brand    : AliRaza+server                      </b></font><br>
<font color="#00FF00"><b>  🚀 Supported        : SSH-WS | SSL | ZIVPN | XHTTP | HY2  </b></font><br>
<font color="#FFA500"><b>  🔥 Performance      : 4K Fast Streaming & Low Gaming Ping </b></font><br>
<font color="#FF00FF"><b>━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━</b></font><br>
<font color="#FF3333"><b>  ⚠️ STRICT RULES : NO Torrent | NO DDoS | NO Multi-Login   </b></font><br>
<font color="#FFFF00"><b>  🔒 Auto-Lock System Active : Expiry ya Quota par Auto-Lock</b></font><br>
<font color="#FF00FF"><b>━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━</b></font>
BANNER_EOF
    chmod 644 /etc/issue.net 2>/dev/null || true
}

fix_dropbear_core() {
    [[ ! -s /etc/issue.net ]] && write_zainu_vip_banner
    mkdir -p /etc/dropbear && chmod 700 /etc/dropbear
    # Debian 12 / Ubuntu 24: dropbear.socket port 22 pakad leta hai -> OpenSSH DOWN! Ab mask hoga:
    systemctl stop dropbear.socket >/dev/null 2>&1 || true
    systemctl disable dropbear.socket >/dev/null 2>&1 || true
    systemctl mask dropbear.socket >/dev/null 2>&1 || true
    systemctl unmask dropbear.service >/dev/null 2>&1 || true
    printf 'NO_START=0\nDROPBEAR_BANNER="/etc/issue.net"\nDROPBEAR_PORT=109\nDROPBEAR_EXTRA_ARGS="-p 143 -p 447"\n' > /etc/default/dropbear 2>/dev/null || true
    [[ ! -f /etc/dropbear/dropbear_rsa_host_key ]] && dropbearkey -t rsa -f /etc/dropbear/dropbear_rsa_host_key &>/dev/null || true
    [[ ! -f /etc/dropbear/dropbear_ecdsa_host_key ]] && dropbearkey -t ecdsa -f /etc/dropbear/dropbear_ecdsa_host_key &>/dev/null || true
    [[ ! -f /etc/dropbear/dropbear_ed25519_host_key ]] && dropbearkey -t ed25519 -f /etc/dropbear/dropbear_ed25519_host_key &>/dev/null || true
    local DB_BIN=$(command -v dropbear || echo "/usr/sbin/dropbear")
    cat << EOF > /etc/systemd/system/dropbear.service
[Unit]
Description=AliRaza+server Dropbear SSH (109, 143, 447)
After=network.target
[Service]
Type=simple
Nice=-10
ExecStart=${DB_BIN} -F -E -a -p 109 -p 143 -p 447 -b /etc/issue.net -W 262144 -K 15 -I 120
Restart=always
RestartSec=2s
[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload && systemctl enable dropbear >/dev/null 2>&1 && systemctl restart dropbear >/dev/null 2>&1 || true
}

fix_stunnel_core() {
    generate_fallback_cert
    mkdir -p /etc/stunnel /var/run/stunnel4
    cat << 'EOF' > /etc/stunnel/stunnel.conf
foreground = yes
cert = /etc/ssl/xray/fullchain.pem
key = /etc/ssl/xray/privkey.pem
client = no
socket = l:TCP_NODELAY=1
socket = r:TCP_NODELAY=1
[ssh-tls-8443]
accept = 0.0.0.0:8443
connect = 127.0.0.1:22
[ssh-tls-444]
accept = 0.0.0.0:444
connect = 127.0.0.1:22
[ovpn-tls-992]
accept = 0.0.0.0:992
connect = 127.0.0.1:1194
EOF
    local ST_BIN=$(command -v stunnel4 || command -v stunnel || echo "/usr/bin/stunnel4")
    cat << EOF > /etc/systemd/system/stunnel4.service
[Unit]
Description=Stunnel4 TLS Wrapper
After=network.target
[Service]
Type=simple
Nice=-10
ExecStart=${ST_BIN} /etc/stunnel/stunnel.conf
Restart=always
RestartSec=2s
[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload && systemctl enable stunnel4 >/dev/null 2>&1 && systemctl restart stunnel4 >/dev/null 2>&1 || true
}

fix_ssh_auth_and_banner() {
    [[ ! -s /etc/issue.net ]] && write_zainu_vip_banner
    rm -f /etc/ssh/sshd_config.d/*.conf 2>/dev/null || true
    sed -i 's/^ENCRYPT_METHOD.*/ENCRYPT_METHOD SHA512/g' /etc/login.defs 2>/dev/null || true
    sed -i 's/yescrypt/sha512/g' /etc/pam.d/common-password 2>/dev/null || true

    local SFTP_LINE="Subsystem sftp /usr/lib/openssh/sftp-server"
    if [[ -f /etc/ssh/sshd_config ]]; then
        local found_sftp=$(grep -E "^[[:space:]]*Subsystem[[:space:]]+sftp" /etc/ssh/sshd_config | head -n1)
        [[ -n "$found_sftp" ]] && SFTP_LINE="$found_sftp"
    fi

    cat << EOF > /etc/ssh/sshd_config
Port 22
Port 2222
AddressFamily inet
UsePAM yes
PasswordAuthentication yes
PermitRootLogin yes
PubkeyAuthentication yes
AllowTcpForwarding yes
PermitTunnel yes
GatewayPorts yes
UseDNS no
PrintMotd no
TCPKeepAlive yes
MaxStartups 1000:30:2000
MaxSessions 1000
ClientAliveInterval 15
ClientAliveCountMax 3
Banner /etc/issue.net
Ciphers aes128-gcm@openssh.com,chacha20-poly1305@openssh.com,aes128-ctr,aes256-gcm@openssh.com,aes256-ctr
${SFTP_LINE}

Match LocalPort 2222
    Banner none
    PasswordAuthentication yes
EOF
    mkdir -p /run/sshd
    systemctl stop ssh.socket >/dev/null 2>&1 || true
    systemctl disable ssh.socket >/dev/null 2>&1 || true
    systemctl mask ssh.socket >/dev/null 2>&1 || true
    systemctl daemon-reload >/dev/null 2>&1 || true
    systemctl unmask ssh ssh.service sshd 2>/dev/null || true
    systemctl enable ssh >/dev/null 2>&1 || systemctl enable sshd >/dev/null 2>&1 || true
    systemctl restart ssh >/dev/null 2>&1 || systemctl restart sshd >/dev/null 2>&1 || true
    sleep 1
    if ss -tln 2>/dev/null | grep -qE ':22\b'; then
        echo -e "${GREEN}[OK] OpenSSH LIVE (ports 22/2222)${NC}"
    else
        echo -e "${RED}[X] OpenSSH port 22 DOWN! 'systemctl status ssh' se check karein.${NC}"
    fi
}

setup_openvpn_server() {
    generate_fallback_cert
    mkdir -p /etc/openvpn/server /dev/net
    [[ ! -c /dev/net/tun ]] && mknod /dev/net/tun c 10 200 2>/dev/null && chmod 600 /dev/net/tun 2>/dev/null || true
    if [[ ! -s /etc/openvpn/server/ca.crt || ! -s /etc/openvpn/server/server.crt ]]; then
        openssl req -x509 -nodes -newkey rsa:2048 -days 3650 -subj "/CN=aliraza-OVPN-CA" -keyout /etc/openvpn/server/ca.key -out /etc/openvpn/server/ca.crt 2>/dev/null
        openssl req -nodes -newkey rsa:2048 -subj "/CN=server" -keyout /etc/openvpn/server/server.key -out /etc/openvpn/server/server.csr 2>/dev/null
        printf "basicConstraints=CA:FALSE\nkeyUsage=digitalSignature,keyEncipherment\nextendedKeyUsage=serverAuth\n" > /etc/openvpn/server/ext.cnf
        openssl x509 -req -days 3650 -in /etc/openvpn/server/server.csr -CA /etc/openvpn/server/ca.crt -CAkey /etc/openvpn/server/ca.key -CAcreateserial -extfile /etc/openvpn/server/ext.cnf -out /etc/openvpn/server/server.crt 2>/dev/null
    fi
    cat << 'EOF' > /etc/openvpn/server/auth-pam.sh
#!/usr/bin/env bash
U=$(head -n1 "$1" 2>/dev/null | tr -d '\r\n'); P=$(tail -n1 "$1" 2>/dev/null | tr -d '\r\n')
grep -q "^${U}|${P}|.*|UNLOCKED$" "/etc/aliraza/users.db" 2>/dev/null && exit 0 || exit 1
EOF
    chmod +x /etc/openvpn/server/auth-pam.sh
    for p in "tcp:1194:tun0:10.8.0.0" "udp:2200:tun1:10.9.0.0"; do
        IFS=':' read -r prt port dev net <<< "$p"
        cat << EOF > "/etc/openvpn/server/server-${prt}.conf"
port ${port}
proto ${prt}
dev ${dev}
ca /etc/openvpn/server/ca.crt
cert /etc/openvpn/server/server.crt
key /etc/openvpn/server/server.key
dh none
ecdh-curve prime256v1
server ${net} 255.255.255.0
push "redirect-gateway def1 bypass-dhcp"
push "dhcp-option DNS 8.8.8.8"
push "dhcp-option DNS 1.1.1.1"
tun-mtu 1400
mssfix 1360
keepalive 10 60
data-ciphers AES-128-GCM:AES-256-GCM:CHACHA20-POLY1305:AES-128-CBC
cipher AES-128-GCM
auth SHA256
verify-client-cert none
username-as-common-name
script-security 3
auth-user-pass-verify /etc/openvpn/server/auth-pam.sh via-file
duplicate-cn
persist-key
persist-tun
status /var/log/openvpn-${prt}.log 5
verb 1
EOF
    done
    systemctl enable openvpn-server@server-tcp openvpn-server@server-udp >/dev/null 2>&1 || true
    systemctl restart openvpn-server@server-tcp openvpn-server@server-udp >/dev/null 2>&1 || true
}

fix_xray_systemd_unit() {
    local CPUS=$(nproc 2>/dev/null || echo 8)
    rm -rf /etc/systemd/system/xray.service.d 2>/dev/null || true
    cat << EOF > /etc/systemd/system/xray.service
[Unit]
Description=Xray Multi-Core High-Speed Service
After=network.target
[Service]
User=root
Nice=-15
Environment="GOMAXPROCS=${CPUS}"
Environment="GOGC=100"
ExecStart=/usr/local/bin/xray run -config /usr/local/etc/xray/config.json
Restart=always
RestartSec=2s
LimitNPROC=65535
LimitNOFILE=1000000
[Install]
WantedBy=multi-user.target
EOF
    mkdir -p /var/log/xray && touch /var/log/xray/access.log /var/log/xray/error.log && chmod 666 /var/log/xray/*.log 2>/dev/null || true
    systemctl daemon-reload 2>/dev/null || true
}

ensure_reality_keys() {
    local priv=$(head -n1 "$DATA_DIR/reality_priv.txt" 2>/dev/null | tr -d '[:space:]')
    local pub=$(head -n1 "$DATA_DIR/reality_pub.txt" 2>/dev/null | tr -d '[:space:]')
    if [[ -z "$priv" || -z "$pub" || ${#priv} -lt 40 || ${#pub} -lt 40 ]]; then
        if [[ -x /usr/local/bin/xray ]]; then
            local kout=$(/usr/local/bin/xray x25519 2>/dev/null || true)
            priv=$(echo "$kout" | grep -iE "Private" | awk -F': *' '{print $2}' | tr -d '[:space:]' | head -n1)
            pub=$(echo "$kout" | grep -iE "Public|Password" | awk -F': *' '{print $2}' | tr -d '[:space:]' | head -n1)
            [[ -n "$priv" && -n "$pub" ]] && { echo "$priv" > "$DATA_DIR/reality_priv.txt"; echo "$pub" > "$DATA_DIR/reality_pub.txt"; }
        fi
    fi
    [[ ! -s "$DATA_DIR/ss2022_key.txt" ]] && openssl rand -base64 16 > "$DATA_DIR/ss2022_key.txt"
}

install_xray_binary() {
    if [[ -x /usr/local/bin/xray ]] && /usr/local/bin/xray version >/dev/null 2>&1; then return 0; fi
    echo -e "${YELLOW}[*] Xray-core download/install ho raha hai...${NC}"
    curl -fsSL --retry 3 --max-time 90 "https://raw.githubusercontent.com/XTLS/Xray-install/main/install-release.sh" -o /tmp/xray-inst.sh 2>/dev/null || true
    if [[ -s /tmp/xray-inst.sh ]] && grep -qi 'xray' /tmp/xray-inst.sh; then
        bash /tmp/xray-inst.sh install >/dev/null 2>&1 || true
    fi
    rm -f /tmp/xray-inst.sh
    if ! { [[ -x /usr/local/bin/xray ]] && /usr/local/bin/xray version >/dev/null 2>&1; }; then
        # Fallback 1: official script dobara (GitHub kabi-kabi pehli dafa rate-limit karta hai)
        curl -fsSL --retry 3 --max-time 90 "https://github.com/XTLS/Xray-install/raw/main/install-release.sh" -o /tmp/xray-inst.sh 2>/dev/null || true
        [[ -s /tmp/xray-inst.sh ]] && bash /tmp/xray-inst.sh install >/dev/null 2>&1 || true
        rm -f /tmp/xray-inst.sh
    fi
    if ! { [[ -x /usr/local/bin/xray ]] && /usr/local/bin/xray version >/dev/null 2>&1; }; then
        # Fallback 2: direct release binary zip (amd64/arm64) latest tag detect kar ke
        local ARCH=$(uname -m) XARCH="64"
        [[ "$ARCH" == "aarch64" || "$ARCH" == "arm64" ]] && XARCH="arm64-v8a"
        local XTAG=$(curl -fsSL --retry 2 --max-time 20 "https://api.github.com/repos/XTLS/Xray-core/releases/latest" 2>/dev/null | grep -oE '"tag_name"[[:space:]]*:[[:space:]]*"v[^"]+"' | head -n1 | grep -oE 'v[0-9.]+')
        [[ -z "$XTAG" ]] && XTAG="v25.3.6"
        curl -fsSL --retry 3 --max-time 120 "https://github.com/XTLS/Xray-core/releases/download/${XTAG}/Xray-linux-${XARCH}.zip" -o /tmp/xray-core.zip 2>/dev/null || true
        if [[ -s /tmp/xray-core.zip ]]; then
            mkdir -p /tmp/xray-unpack /usr/local/share/xray
            unzip -o /tmp/xray-core.zip -d /tmp/xray-unpack >/dev/null 2>&1 || true
            [[ -f /tmp/xray-unpack/xray ]] && install -m 755 /tmp/xray-unpack/xray /usr/local/bin/xray
            cp -f /tmp/xray-unpack/geoip.dat /tmp/xray-unpack/geosite.dat /usr/local/share/xray/ 2>/dev/null || true
            cp -f /tmp/xray-unpack/geoip.dat /tmp/xray-unpack/geosite.dat /usr/local/bin/ 2>/dev/null || true
        fi
        rm -rf /tmp/xray-core.zip /tmp/xray-unpack
    fi
    if [[ -x /usr/local/bin/xray ]] && /usr/local/bin/xray version >/dev/null 2>&1; then
        echo -e "${GREEN}[OK] Xray-core LIVE: $(/usr/local/bin/xray version 2>/dev/null | head -n1)${NC}"
        return 0
    fi
    echo -e "${RED}[X] Xray download FAIL! Internet/GitHub block lag raha hai - baad me Panel ka Auto-Doctor chalayein.${NC}"
    return 1
}

write_base_xray_config() {
    mkdir -p /usr/local/etc/xray /var/log/xray
    install_xray_binary || true
    generate_fallback_cert
    ensure_reality_keys
    local R_PRIV=$(head -n1 "$DATA_DIR/reality_priv.txt" 2>/dev/null | tr -d '[:space:]')
    local SS22_KEY=$(head -n1 "$DATA_DIR/ss2022_key.txt" 2>/dev/null | tr -d '[:space:]')
    local DOM_NOW=$(head -n1 "$DATA_DIR/domain.txt" 2>/dev/null | tr -d '[:space:]'); [[ -z "$DOM_NOW" ]] && DOM_NOW="aliraza.com"
    local XHTTP_NET="xhttp" XHTTP_SET="xhttpSettings"
    if [[ -x /usr/local/bin/xray ]] && /usr/local/bin/xray version 2>/dev/null | head -n1 | grep -qE "Xray 1\.8\."; then
        XHTTP_NET="splithttp"; XHTTP_SET="splithttpSettings"
    fi

    cat << EOF > "$XRAY_CONF"
{
  "log": { "access": "/var/log/xray/access.log", "error": "/var/log/xray/error.log", "loglevel": "info" },
  "dns": { "servers": ["8.8.8.8", "1.1.1.1"], "queryStrategy": "UseIPv4" },
  "stats": {},
  "api": { "tag": "api", "services": ["StatsService"] },
  "policy": {
    "levels": { "0": { "handshake": 4, "connIdle": 600, "uplinkOnly": 0, "downlinkOnly": 0, "bufferSize": 65535, "statsUserUplink": true, "statsUserDownlink": true } },
    "system": { "statsInboundUplink": true, "statsInboundDownlink": true, "statsOutboundUplink": true, "statsOutboundDownlink": true }
  },
  "inbounds": [
    { "tag": "vless-ws", "listen": "127.0.0.1", "port": 10001, "protocol": "vless", "settings": { "clients": [], "decryption": "none" }, "streamSettings": { "network": "ws", "wsSettings": { "path": "/vless" }, "sockopt": { "tcpNoDelay": true, "tcpFastOpen": true, "acceptProxyProtocol": false } } },
    { "tag": "vmess-ws", "listen": "127.0.0.1", "port": 10002, "protocol": "vmess", "settings": { "clients": [] }, "streamSettings": { "network": "ws", "wsSettings": { "path": "/vmess" }, "sockopt": { "tcpNoDelay": true, "tcpFastOpen": true, "acceptProxyProtocol": false } } },
    { "tag": "trojan-ws", "listen": "127.0.0.1", "port": 10003, "protocol": "trojan", "settings": { "clients": [] }, "streamSettings": { "network": "ws", "wsSettings": { "path": "/trojan" }, "sockopt": { "tcpNoDelay": true, "tcpFastOpen": true, "acceptProxyProtocol": false } } },
    { "tag": "vless-grpc", "listen": "127.0.0.1", "port": 10004, "protocol": "vless", "settings": { "clients": [], "decryption": "none" }, "streamSettings": { "network": "grpc", "grpcSettings": { "serviceName": "zainu-vless-grpc", "multiMode": true }, "sockopt": { "tcpNoDelay": true, "tcpFastOpen": true } } },
    { "tag": "vmess-grpc", "listen": "127.0.0.1", "port": 10005, "protocol": "vmess", "settings": { "clients": [] }, "streamSettings": { "network": "grpc", "grpcSettings": { "serviceName": "zainu-vmess-grpc", "multiMode": true }, "sockopt": { "tcpNoDelay": true, "tcpFastOpen": true } } },
    { "tag": "trojan-grpc", "listen": "127.0.0.1", "port": 10006, "protocol": "trojan", "settings": { "clients": [] }, "streamSettings": { "network": "grpc", "grpcSettings": { "serviceName": "zainu-trojan-grpc", "multiMode": true }, "sockopt": { "tcpNoDelay": true, "tcpFastOpen": true } } },
    { "tag": "vless-httpupgrade", "listen": "127.0.0.1", "port": 10007, "protocol": "vless", "settings": { "clients": [], "decryption": "none" }, "streamSettings": { "network": "httpupgrade", "httpupgradeSettings": { "path": "/vless-hup" }, "sockopt": { "tcpNoDelay": true, "tcpFastOpen": true, "acceptProxyProtocol": false } } },
    { "tag": "vmess-httpupgrade", "listen": "127.0.0.1", "port": 10008, "protocol": "vmess", "settings": { "clients": [] }, "streamSettings": { "network": "httpupgrade", "httpupgradeSettings": { "path": "/vmess-hup" }, "sockopt": { "tcpNoDelay": true, "tcpFastOpen": true, "acceptProxyProtocol": false } } },
    { "tag": "trojan-httpupgrade", "listen": "127.0.0.1", "port": 10009, "protocol": "trojan", "settings": { "clients": [] }, "streamSettings": { "network": "httpupgrade", "httpupgradeSettings": { "path": "/trojan-hup" }, "sockopt": { "tcpNoDelay": true, "tcpFastOpen": true, "acceptProxyProtocol": false } } },
    { "tag": "vless-xhttp", "listen": "127.0.0.1", "port": 10010, "protocol": "vless", "settings": { "clients": [], "decryption": "none" }, "streamSettings": { "network": "${XHTTP_NET}", "${XHTTP_SET}": { "path": "/zainu-vless-xhttp", "mode": "auto" }, "sockopt": { "tcpNoDelay": true, "tcpFastOpen": true, "acceptProxyProtocol": false } } },
    { "tag": "vmess-xhttp", "listen": "127.0.0.1", "port": 10011, "protocol": "vmess", "settings": { "clients": [] }, "streamSettings": { "network": "${XHTTP_NET}", "${XHTTP_SET}": { "path": "/zainu-vmess-xhttp", "mode": "auto" }, "sockopt": { "tcpNoDelay": true, "tcpFastOpen": true, "acceptProxyProtocol": false } } },
    { "tag": "trojan-xhttp", "listen": "127.0.0.1", "port": 10012, "protocol": "trojan", "settings": { "clients": [] }, "streamSettings": { "network": "${XHTTP_NET}", "${XHTTP_SET}": { "path": "/zainu-trojan-xhttp", "mode": "auto" }, "sockopt": { "tcpNoDelay": true, "tcpFastOpen": true, "acceptProxyProtocol": false } } },
    { "tag": "vless-vision", "listen": "127.0.0.1", "port": 8444, "protocol": "vless", "settings": { "clients": [], "decryption": "none" }, "streamSettings": { "network": "tcp", "security": "tls", "tlsSettings": { "alpn": ["h2", "http/1.1"], "certificates": [{ "certificateFile": "/etc/ssl/xray/fullchain.pem", "keyFile": "/etc/ssl/xray/privkey.pem" }] }, "sockopt": { "tcpNoDelay": true, "tcpFastOpen": true, "acceptProxyProtocol": true } } },
    { "tag": "vless-reality", "listen": "127.0.0.1", "port": 10013, "protocol": "vless", "settings": { "clients": [], "decryption": "none" }, "streamSettings": { "network": "tcp", "security": "reality", "realitySettings": { "show": false, "dest": "www.apple.com:443", "xver": 0, "serverNames": ["reality.${DOM_NOW}", "www.apple.com", "www.microsoft.com"], "privateKey": "${R_PRIV}", "shortIds": ["", "6ba85179e30d4fc2"] }, "sockopt": { "tcpNoDelay": true, "tcpFastOpen": true, "acceptProxyProtocol": true } } },
    { "tag": "dnstt-vless", "listen": "127.0.0.1", "port": 20010, "protocol": "vless", "settings": { "clients": [], "decryption": "none" }, "streamSettings": { "network": "tcp", "security": "none", "sockopt": { "tcpNoDelay": true } } },
    { "tag": "vless-mkcp", "listen": "0.0.0.0", "port": 10014, "protocol": "vless", "settings": { "clients": [], "decryption": "none" }, "streamSettings": { "network": "kcp", "kcpSettings": { "mtu": 1350, "tti": 20, "uplinkCapacity": 100, "downlinkCapacity": 1000, "congestion": true, "header": { "type": "none" } } } },
    { "tag": "ss-2022", "listen": "0.0.0.0", "port": 10015, "protocol": "shadowsocks", "settings": { "method": "2022-blake3-aes-128-gcm", "password": "${SS22_KEY}", "network": "tcp,udp" } },
    { "tag": "socks5-in", "listen": "0.0.0.0", "port": 10808, "protocol": "socks", "settings": { "auth": "password", "accounts": [], "udp": true } },
    { "tag": "http-in", "listen": "0.0.0.0", "port": 10809, "protocol": "http", "settings": { "accounts": [] } },
    { "tag": "ss-in", "listen": "0.0.0.0", "port": 8888, "protocol": "shadowsocks", "settings": { "clients": [], "network": "tcp,udp" } },
    { "tag": "api", "listen": "127.0.0.1", "port": 10085, "protocol": "dokodemo-door", "settings": { "address": "127.0.0.1" } }
  ],
  "outbounds": [
    { "protocol": "freedom", "tag": "direct", "settings": { "domainStrategy": "UseIPv4" }, "streamSettings": { "sockopt": { "tcpFastOpen": true, "tcpNoDelay": true } } }
  ],
  "routing": { "rules": [{ "type": "field", "inboundTag": ["api"], "outboundTag": "api" }] }
}
EOF
    chmod 644 "$XRAY_CONF"
}

sync_all_users_to_engines() {
    [[ ! -s "$XRAY_CONF" ]] && write_base_xray_config
    python3 - << 'PY' 2>/dev/null || true
import json, os

users_db = "/etc/aliraza/users.db"
xray_cfg = "/usr/local/etc/xray/config.json"
zivpn_cfg = "/etc/zivpn/config.json"
hy2_cfg = "/etc/hysteria/config.yaml"

users, pws = [], []
if os.path.exists(users_db):
    for ln in open(users_db):
        pts = ln.strip().split("|")
        if len(pts) >= 7 and pts[6] == "UNLOCKED":
            users.append({"u": pts[0], "pw": pts[1], "uuid": pts[2]})
            if pts[1] not in pws:
                pws.append(pts[1])

if os.path.exists(xray_cfg):
    cfg = json.load(open(xray_cfg))
    for idx, ib in enumerate(cfg.get("inbounds", [])):
        if idx in (0, 1, 3, 4, 6, 7, 9, 10, 14, 15):
            ib["settings"]["clients"] = [{"id": x["uuid"], "email": x["u"], "level": 0} for x in users]
        elif idx in (2, 5, 8, 11):
            ib["settings"]["clients"] = [{"password": x["pw"], "email": x["u"], "level": 0} for x in users]
        elif idx in (12, 13):
            ib["settings"]["clients"] = [{"id": x["uuid"], "email": x["u"], "flow": "xtls-rprx-vision", "level": 0} for x in users]
        elif idx in (17, 18):
            ib["settings"]["accounts"] = [{"user": x["u"], "pass": x["pw"]} for x in users]
        elif idx == 19:
            ib["settings"]["clients"] = [{"password": x["pw"], "method": "chacha20-ietf-poly1305", "email": x["u"], "level": 0} for x in users]
    json.dump(cfg, open(xray_cfg, "w"), indent=2)

if not pws: pws = ["aliraza"]
os.makedirs("/etc/zivpn", exist_ok=True)
json.dump({"listen": ":5667", "cert": "/etc/ssl/xray/fullchain.pem", "key": "/etc/ssl/xray/privkey.pem", "obfs": "zivpn", "auth": {"mode": "passwords", "config": pws}}, open(zivpn_cfg, "w"), indent=2)

os.makedirs("/etc/hysteria", exist_ok=True)
with open(hy2_cfg, "w") as hf:
    hf.write("listen: :20800\ntls:\n  cert: /etc/ssl/xray/fullchain.pem\n  key: /etc/ssl/xray/privkey.pem\nbandwidth:\n  up: 1 gbps\n  down: 1 gbps\ntrafficStats:\n  listen: 127.0.0.1:9999\nauth:\n  type: userpass\n  userpass:\n")
    for x in (users or [{"u": "aliraza", "pw": "aliraza"}]):
        hf.write(f"    {x['u']}: {x['pw']}\n")
PY
    systemctl restart zivpn hysteria 2>/dev/null || true
}

add_user_to_xray_json() {
    sync_all_users_to_engines
}
setup_slowdns_and_udp_nat() {
    cat << 'EOF' > /usr/local/bin/zainu-firewall-restore
#!/usr/bin/env bash
modprobe nf_conntrack >/dev/null 2>&1 || true
echo 1 > /proc/sys/net/netfilter/nf_conntrack_acct 2>/dev/null || true
ufw disable >/dev/null 2>&1 || true
iptables -P INPUT ACCEPT >/dev/null 2>&1 || true
iptables -P FORWARD ACCEPT >/dev/null 2>&1 || true
iptables -P OUTPUT ACCEPT >/dev/null 2>&1 || true
iptables -F INPUT >/dev/null 2>&1 || true
iptables -F FORWARD >/dev/null 2>&1 || true

iptables -t mangle -F OUTPUT >/dev/null 2>&1 || true
iptables -t mangle -A FORWARD -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu 2>/dev/null || true

DEF_IF=$(ip route get 8.8.8.8 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="dev") print $(i+1)}' | head -n1)
if [[ -n "$DEF_IF" ]]; then
    ip link set dev "$DEF_IF" txqueuelen 10000 2>/dev/null || true
    iptables -t nat -F PREROUTING >/dev/null 2>&1 || true
    iptables -t nat -A PREROUTING -i "$DEF_IF" -p udp --sport 53 -j ACCEPT >/dev/null 2>&1 || true
    iptables -t nat -A PREROUTING -i "$DEF_IF" -p udp --sport 123 -j ACCEPT >/dev/null 2>&1 || true
    iptables -t nat -A PREROUTING -i "$DEF_IF" -p udp --sport 443 -j ACCEPT >/dev/null 2>&1 || true
    iptables -t nat -A PREROUTING -i "$DEF_IF" -p udp --dport 53 -j REDIRECT --to-ports 5300 >/dev/null 2>&1 || true
    for prt in 2200 5300 5667 7100 7200 7300 8888 10014 10015 10808 20800 36712; do
        iptables -t nat -A PREROUTING -i "$DEF_IF" -p udp --dport "$prt" -j ACCEPT >/dev/null 2>&1 || true
    done
    # Exclude Linux ephemeral outbound ports (32768:65535) so server's own UDP replies never loop into 36712!
    iptables -t nat -A PREROUTING -i "$DEF_IF" -p udp --dport 32768:65535 -j ACCEPT >/dev/null 2>&1 || true
    iptables -t nat -A PREROUTING -i "$DEF_IF" -p udp --dport 1:32767 -j REDIRECT --to-ports 36712 >/dev/null 2>&1 || true
    iptables -t nat -C POSTROUTING -o "$DEF_IF" -j MASQUERADE >/dev/null 2>&1 || iptables -t nat -A POSTROUTING -o "$DEF_IF" -j MASQUERADE >/dev/null 2>&1 || true
fi
EOF
    chmod +x /usr/local/bin/zainu-firewall-restore
    /usr/local/bin/zainu-firewall-restore
    cat << 'EOF' > /etc/systemd/system/zainu-firewall.service
[Unit]
Description=ZAINU X BRAND NAT & Firewall
After=network-online.target
[Service]
Type=oneshot
ExecStart=/usr/local/bin/zainu-firewall-restore
RemainAfterExit=yes
[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload && systemctl enable zainu-firewall 2>/dev/null || true
}

fix_dns_resolver() {
    fix_hostname_resolution
    systemctl stop systemd-resolved 2>/dev/null || true
    systemctl disable systemd-resolved 2>/dev/null || true
    rm -f /etc/resolv.conf 2>/dev/null || true
    printf "nameserver 8.8.8.8\nnameserver 1.1.1.1\n" > /etc/resolv.conf
}

generate_fallback_cert() {
    mkdir -p /etc/ssl/xray /etc/haproxy
    local pub_cert="" pub_key=""
    if [[ -s /etc/ssl/xray/fullchain.pem && -s /etc/ssl/xray/privkey.pem ]]; then
        pub_cert=$(openssl x509 -in /etc/ssl/xray/fullchain.pem -noout -pubkey 2>/dev/null || true)
        pub_key=$(openssl pkey -in /etc/ssl/xray/privkey.pem -pubout 2>/dev/null || true)
    fi
    if [[ -z "$pub_cert" || -z "$pub_key" || "$pub_cert" != "$pub_key" ]]; then
        openssl req -new -newkey rsa:2048 -days 3650 -nodes -x509 -sha256 -subj "/CN=aliraza.com" \
            -keyout /etc/ssl/xray/privkey.pem -out /etc/ssl/xray/fullchain.pem 2>/dev/null
    fi
    awk 1 /etc/ssl/xray/fullchain.pem /etc/ssl/xray/privkey.pem > /etc/ssl/xray/haproxy.pem 2>/dev/null || true
    chmod 644 /etc/ssl/xray/*.pem 2>/dev/null || true
}

issue_ssl_cert() {
    local DOMAIN="$1"
    local MY_IP=$(get_vps_ip)
    rm -f /run/zainu_dom_* /run/zainu_ns_* 2>/dev/null || true
    setup_slowdns_and_udp_nat
    systemctl stop haproxy nginx zainu-ws apache2 2>/dev/null || true
    fuser -k 80/tcp 443/tcp >/dev/null 2>&1 || true
    local DOM_IP=$(dig +short +time=2 +tries=1 A "$DOMAIN" @8.8.8.8 2>/dev/null | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' | tail -n1)
    if [[ "$DOM_IP" == "$MY_IP" ]]; then
        echo -e "${CYAN}[*] Domain $DOMAIN -> $MY_IP [POINTED OK]${NC}"
        echo -e "${CYAN}[*] Let's Encrypt REAL SSL issue ho raha hai (TLS 443 ke liye)...${NC}"
        [[ ! -f /root/.acme.sh/acme.sh ]] && curl -s https://get.acme.sh | sh -s email=admin@"$DOMAIN" >/dev/null 2>&1
        /root/.acme.sh/acme.sh --set-default-ca --server letsencrypt 2>/dev/null || true
        local issued=0
        for attempt in 1 2; do
            if /root/.acme.sh/acme.sh --issue -d "$DOMAIN" --standalone --keylength ec-256 --force; then
                /root/.acme.sh/acme.sh --install-cert -d "$DOMAIN" --ecc \
                    --fullchain-file /etc/ssl/xray/fullchain.pem \
                    --key-file /etc/ssl/xray/privkey.pem \
                    --reloadcmd "systemctl restart haproxy nginx stunnel4 zivpn hysteria aliraza-panel 2>/dev/null || true" >/dev/null 2>&1 \
                    && issued=1 && break
            fi
            echo -e "${YELLOW}[!] SSL attempt ${attempt}/2 fail - 80/443 free kar ke dobara try...${NC}"
            fuser -k 80/tcp 443/tcp >/dev/null 2>&1 || true
            sleep 3
        done
        [[ "$issued" != "1" ]] && echo -e "${YELLOW}[!] Real SSL issue nahi ho saka - abhi Self-Signed lagega. Baad me Panel -> Domain & SSL -> Renew SSL chalayein.${NC}"
    else
        echo -e "${YELLOW}[!] Domain ($DOMAIN) abhi is VPS IP ($MY_IP) par pointed nahi hai (Current: ${DOM_IP:-None}).${NC}"
        echo -e "${YELLOW}    Abhi Self-Signed SSL lagega - TLS 443 apps me 'allow insecure' ON karna parega.${NC}"
        echo -e "${YELLOW}    Domain point karne ke baad: Panel -> Domain & SSL -> Renew SSL chalayein to REAL SSL mil jayega.${NC}"
    fi
    generate_fallback_cert
    systemctl restart nginx zainu-ws haproxy stunnel4 zivpn hysteria aliraza-panel 2>/dev/null || true
    local ISSUER=$(openssl x509 -in /etc/ssl/xray/fullchain.pem -noout -issuer 2>/dev/null | sed 's/.*O = //' | cut -d, -f1)
    if echo "$ISSUER" | grep -qiE "Let's Encrypt|ISRG"; then
        echo -e "${GREEN}[OK] REAL SSL LIVE hai (Issuer: ${ISSUER:-LE}) - TLS 443/2053/2083/2087/2096 sab chalenge!${NC}"
    else
        echo -e "${YELLOW}[!] Abhi Self-Signed cert active hai (Issuer: ${ISSUER:-self}). Domain point kar ke Renew SSL karein.${NC}"
    fi
}

install_port_watchdog() {
    # Har 60s ports check karta hai; down mile to wahi service restart (fresh VPS races ko permanent fix)
    cat << 'WEOF' > /usr/local/bin/zainu-watchdog.sh
#!/bin/bash
while true; do
    sleep 60
    CHK() { ss -tln 2>/dev/null | grep -qE ":${1}\b"; }
    if ! CHK 443 || ! CHK 80 || ! CHK 8442; then
        systemctl restart haproxy 2>/dev/null || true
    fi
    if ! CHK 8081; then
        systemctl restart nginx 2>/dev/null || true
    fi
    if ! CHK 10000; then
        systemctl restart zainu-ws 2>/dev/null || true
    fi
    if [[ -x /usr/local/bin/xray ]] && ! CHK 10001; then
        systemctl restart xray 2>/dev/null || true
    fi
    if ! CHK 22; then
        systemctl restart ssh 2>/dev/null || systemctl restart sshd 2>/dev/null || true
    fi
done
WEOF
    chmod +x /usr/local/bin/zainu-watchdog.sh
    cat << 'WEOF' > /etc/systemd/system/zainu-watchdog.service
[Unit]
Description=ZAINU 24/7 Port Watchdog (443/80/8442/10000 Auto-Repair)
After=network.target
StartLimitIntervalSec=0

[Service]
Type=simple
ExecStart=/usr/local/bin/zainu-watchdog.sh
Restart=always
RestartSec=10s

[Install]
WantedBy=multi-user.target
WEOF
    systemctl daemon-reload 2>/dev/null || true
    systemctl enable zainu-watchdog >/dev/null 2>&1 || true
    systemctl restart zainu-watchdog 2>/dev/null || true
}

self_test_tls_and_repair() {
    # Real end-to-end 443 TLS handshake test — fail ho to auto-repair (cert regen + restart)
    local DOMC=$(head -n1 "$DATA_DIR/domain.txt" 2>/dev/null | tr -d '[:space:]')
    [[ -z "$DOMC" ]] && DOMC="localhost"
    local ok=0
    for t in 1 2; do
        if timeout 8 openssl s_client -connect 127.0.0.1:443 -servername "$DOMC" </dev/null 2>/dev/null | grep -q "BEGIN CERTIFICATE"; then
            ok=1; break
        fi
        echo -e "${YELLOW}[!] Port 443 TLS self-test FAIL (attempt ${t}/2) — cert+services auto-repair ho rahe hain...${NC}"
        generate_fallback_cert
        systemctl restart zainu-ws nginx haproxy 2>/dev/null || true
        sleep 3
    done
    if [[ "$ok" == "1" ]]; then
        echo -e "${GREEN}[OK] Port 443 TLS SELF-TEST PASS (handshake verified)${NC}"
    else
        echo -e "${RED}[X] Port 443 TLS ab bhi fail — haproxy logs dekhein, watchdog auto-retry karta rahega.${NC}"
    fi
}

configure_nginx_mux() {
    mkdir -p /etc/nginx/sites-available /etc/nginx/sites-enabled /root/backups
    generate_fallback_cert
    local DOMAIN=$(head -n1 "$DATA_DIR/domain.txt" 2>/dev/null | tr -d '[:space:]'); [[ -z "$DOMAIN" ]] && DOMAIN="_"
    local B_HOST=$(head -n1 "$DATA_DIR/bunny_host.txt" 2>/dev/null | tr -d '[:space:]')
    rm -f /etc/nginx/sites-enabled/default /etc/nginx/conf.d/*.conf 2>/dev/null || true

    cat << 'EOF' > /etc/nginx/nginx.conf
user www-data;
worker_processes auto;
worker_rlimit_nofile 1000000;
pid /run/nginx.pid;
include /etc/nginx/modules-enabled/*.conf;
events { worker_connections 65535; multi_accept on; use epoll; }
http {
    sendfile on; tcp_nopush on; tcp_nodelay on; keepalive_timeout 86400s;
    types_hash_max_size 2048; server_tokens off;
    proxy_buffer_size 32k; proxy_buffers 8 32k; proxy_busy_buffers_size 64k;
    include /etc/nginx/mime.types; default_type application/octet-stream;
    access_log off; error_log /var/log/nginx/error.log crit;
    include /etc/nginx/conf.d/*.conf;
}
EOF

    cat << EOF > /etc/nginx/conf.d/zainu-mux.conf
map \$http_x_forwarded_for \$first_xff_ip {
    "~^([^,\\s]+)" \$1;
    default        \$proxy_protocol_addr;
}
map \$http_cf_connecting_ip \$real_client_ip {
    ""      \$first_xff_ip;
    default \$http_cf_connecting_ip;
}

server {
    listen 127.0.0.1:8081 proxy_protocol default_server;
    server_name ${DOMAIN} ${B_HOST} _;
    root /var/www/html;
    set_real_ip_from 127.0.0.1;
    real_ip_header proxy_protocol;
    tcp_nodelay on; keepalive_timeout 86400s; client_max_body_size 0;
    proxy_redirect off; proxy_buffering off; proxy_request_buffering off;
    proxy_http_version 1.1; proxy_set_header Host \$host;
    proxy_set_header X-Real-IP \$real_client_ip; proxy_set_header X-Forwarded-For \$real_client_ip;
    proxy_read_timeout 86400s; proxy_send_timeout 86400s;

    location ~ ^/(vless|zainu-vless-ws)\$ { rewrite ^ /vless break; proxy_set_header Upgrade \$http_upgrade; proxy_set_header Connection "upgrade"; proxy_pass http://127.0.0.1:10001; }
    location ~ ^/(vmess|zainu-vmess-ws)\$ { rewrite ^ /vmess break; proxy_set_header Upgrade \$http_upgrade; proxy_set_header Connection "upgrade"; proxy_pass http://127.0.0.1:10002; }
    location ~ ^/(trojan|zainu-trojan-ws)\$ { rewrite ^ /trojan break; proxy_set_header Upgrade \$http_upgrade; proxy_set_header Connection "upgrade"; proxy_pass http://127.0.0.1:10003; }
    location ~ ^/(vless-hup|zainu-vless-httpupgrade)\$ { rewrite ^ /vless-hup break; proxy_set_header Upgrade \$http_upgrade; proxy_set_header Connection "upgrade"; proxy_pass http://127.0.0.1:10007; }
    location ~ ^/(vmess-hup|zainu-vmess-httpupgrade)\$ { rewrite ^ /vmess-hup break; proxy_set_header Upgrade \$http_upgrade; proxy_set_header Connection "upgrade"; proxy_pass http://127.0.0.1:10008; }
    location ~ ^/(trojan-hup|zainu-trojan-httpupgrade)\$ { rewrite ^ /trojan-hup break; proxy_set_header Upgrade \$http_upgrade; proxy_set_header Connection "upgrade"; proxy_pass http://127.0.0.1:10009; }
    location ^~ /zainu-vless-xhttp { proxy_set_header Connection ""; proxy_pass http://127.0.0.1:10010; }
    location ^~ /zainu-vmess-xhttp { proxy_set_header Connection ""; proxy_pass http://127.0.0.1:10011; }
    location ^~ /zainu-trojan-xhttp { proxy_set_header Connection ""; proxy_pass http://127.0.0.1:10012; }
}

server {
    listen 127.0.0.1:8082 http2 proxy_protocol default_server;
    server_name ${DOMAIN} ${B_HOST} _;
    set_real_ip_from 127.0.0.1;
    real_ip_header proxy_protocol;
    tcp_nodelay on; keepalive_timeout 86400s; client_max_body_size 0;
    grpc_socket_keepalive on; grpc_set_header Host \$host;
    grpc_set_header X-Real-IP \$real_client_ip; grpc_set_header X-Forwarded-For \$real_client_ip;
    grpc_read_timeout 86400s; grpc_send_timeout 86400s;

    location ^~ /zainu-vless-grpc { grpc_pass grpc://127.0.0.1:10004; }
    location ^~ /zainu-vmess-grpc { grpc_pass grpc://127.0.0.1:10005; }
    location ^~ /zainu-trojan-grpc { grpc_pass grpc://127.0.0.1:10006; }
    location ^~ /zainu-vless-xhttp { proxy_buffering off; proxy_request_buffering off; proxy_http_version 1.1; proxy_set_header Connection ""; proxy_set_header Host \$host; proxy_set_header X-Real-IP \$real_client_ip; proxy_set_header X-Forwarded-For \$real_client_ip; proxy_pass http://127.0.0.1:10010; }
    location ^~ /zainu-vmess-xhttp { proxy_buffering off; proxy_request_buffering off; proxy_http_version 1.1; proxy_set_header Connection ""; proxy_set_header Host \$host; proxy_set_header X-Real-IP \$real_client_ip; proxy_set_header X-Forwarded-For \$real_client_ip; proxy_pass http://127.0.0.1:10011; }
    location ^~ /zainu-trojan-xhttp { proxy_buffering off; proxy_request_buffering off; proxy_http_version 1.1; proxy_set_header Connection ""; proxy_set_header Host \$host; proxy_set_header X-Real-IP \$real_client_ip; proxy_set_header X-Forwarded-For \$real_client_ip; proxy_pass http://127.0.0.1:10012; }
}
EOF
    systemctl enable nginx 2>/dev/null || true
    systemctl restart nginx 2>/dev/null || true
}

configure_haproxy_c_mux() {
    generate_fallback_cert
    systemctl stop apache2 2>/dev/null || true
    systemctl disable apache2 2>/dev/null || true

    for p in 80 8080 2082 8880 2052 2086 2095 443 2053 2083 2087 2096 8442; do
        for pid in $(lsof -t -iTCP:"$p" -sTCP:LISTEN 2>/dev/null); do
            local svc=$(ps -o unit= -p "$pid" 2>/dev/null | tr -d '[:space:]')
            if [[ -n "$svc" && "$svc" != "haproxy.service" && "$svc" != "session-"* && "$svc" != "ssh"* && "$svc" != "user@"* ]]; then
                systemctl stop "$svc" >/dev/null 2>&1 || true
                systemctl disable "$svc" >/dev/null 2>&1 || true
            fi
            kill -9 "$pid" >/dev/null 2>&1 || true
        done
    done

    cat << EOF > /etc/haproxy/haproxy.cfg
global
    maxconn 65535

defaults
    mode tcp
    timeout connect 5s
    timeout client  300s
    timeout server  300s
    timeout tunnel  3600s
    timeout client-fin 5s
    timeout server-fin 5s

frontend zainu_80_http
    bind 0.0.0.0:80
    bind 0.0.0.0:8080
    bind 0.0.0.0:2082
    bind 0.0.0.0:8880
    bind 0.0.0.0:2052
    bind 0.0.0.0:2086
    bind 0.0.0.0:2095
    mode tcp
    tcp-request inspect-delay 500ms
    acl is_h2_preface req.payload(0,14) -m bin 505249202a20485454502f322e30
    acl is_xray_path req.payload(0,0) -m sub /zainu- /vless /vmess /trojan
    acl is_ovpn_dl req.payload(0,0) -m sub .ovpn .zip .html
    acl is_ssh_banner req.payload(0,4) -m str SSH-
    acl xr_vless_ws req.payload(0,80) -m sub "GET /vless " "GET /zainu-vless-ws"
    acl xr_vmess_ws req.payload(0,80) -m sub "GET /vmess " "GET /zainu-vmess-ws"
    acl xr_trojan_ws req.payload(0,80) -m sub "GET /trojan " "GET /zainu-trojan-ws"
    acl xr_vless_hup req.payload(0,96) -m sub "GET /vless-hup" "GET /zainu-vless-httpupgrade"
    acl xr_vmess_hup req.payload(0,96) -m sub "GET /vmess-hup" "GET /zainu-vmess-httpupgrade"
    acl xr_trojan_hup req.payload(0,96) -m sub "GET /trojan-hup" "GET /zainu-trojan-httpupgrade"
    acl xr_vless_xhttp req.payload(0,96) -m sub "GET /zainu-vless-xhttp" "POST /zainu-vless-xhttp"
    acl xr_vmess_xhttp req.payload(0,96) -m sub "GET /zainu-vmess-xhttp" "POST /zainu-vmess-xhttp"
    acl xr_trojan_xhttp req.payload(0,96) -m sub "GET /zainu-trojan-xhttp" "POST /zainu-trojan-xhttp"
    tcp-request content accept if is_h2_preface or is_xray_path or is_ovpn_dl or is_ssh_banner
    tcp-request content accept if { req.len gt 0 }
    # v55.4 FIX: Xray WS/HUP/XHTTP/gRPC ab Golang Engine (10000) se guzarta hai
    # jo CF-Connecting-IP / X-Forwarded-For se REAL SIM IP extract karta hai
    # (pehle xd_* direct Xray raw path Cloudflare/BunnyCDN ke EDGE IPs show karta tha = FAKE)
    use_backend ws_ssh_plain_backend if is_h2_preface or xr_vless_ws or xr_vmess_ws or xr_trojan_ws or xr_vless_hup or xr_vmess_hup or xr_trojan_hup or xr_vless_xhttp or xr_vmess_xhttp or xr_trojan_xhttp or is_xray_path
    use_backend nginx_http_backend if is_ovpn_dl
    use_backend direct_ssh_backend if is_ssh_banner or { req.len eq 0 }
    default_backend ws_ssh_plain_backend

frontend zainu_443_raw
    bind 0.0.0.0:443
    bind 0.0.0.0:2053
    bind 0.0.0.0:2083
    bind 0.0.0.0:2087
    bind 0.0.0.0:2096
    mode tcp
    tcp-request inspect-delay 500ms
    acl is_ssl req.ssl_hello_type 1
    acl is_vision_sni req.ssl_sni -m beg vision. xtls.
    acl is_reality_sni req.ssl_sni -m beg reality. www.apple.com www.microsoft.com
    acl is_ssh_banner req.payload(0,4) -m str SSH-
    acl is_xray_plain req.payload(0,0) -m sub /zainu- /vless /vmess /trojan
    acl xr_vless_ws req.payload(0,80) -m sub "GET /vless " "GET /zainu-vless-ws"
    acl xr_vmess_ws req.payload(0,80) -m sub "GET /vmess " "GET /zainu-vmess-ws"
    acl xr_trojan_ws req.payload(0,80) -m sub "GET /trojan " "GET /zainu-trojan-ws"
    acl xr_vless_hup req.payload(0,96) -m sub "GET /vless-hup" "GET /zainu-vless-httpupgrade"
    acl xr_vmess_hup req.payload(0,96) -m sub "GET /vmess-hup" "GET /zainu-vmess-httpupgrade"
    acl xr_trojan_hup req.payload(0,96) -m sub "GET /trojan-hup" "GET /zainu-trojan-httpupgrade"
    acl xr_vless_xhttp req.payload(0,96) -m sub "GET /zainu-vless-xhttp" "POST /zainu-vless-xhttp"
    acl xr_vmess_xhttp req.payload(0,96) -m sub "GET /zainu-vmess-xhttp" "POST /zainu-vmess-xhttp"
    acl xr_trojan_xhttp req.payload(0,96) -m sub "GET /zainu-trojan-xhttp" "POST /zainu-trojan-xhttp"
    tcp-request content accept if is_ssl or is_ssh_banner or is_xray_plain
    tcp-request content accept if { req.len gt 0 }
    use_backend xray_vision_tls_backend if is_ssl is_vision_sni
    use_backend xray_reality_backend if is_ssl is_reality_sni
    # v55.4 FIX: non-TLS Xray payloads par bhi real SIM IP engine se hi guzarein
    use_backend ws_ssh_plain_backend if xr_vless_ws or xr_vmess_ws or xr_trojan_ws or xr_vless_hup or xr_vmess_hup or xr_trojan_hup or xr_vless_xhttp or xr_vmess_xhttp or xr_trojan_xhttp or is_xray_plain
    use_backend loop_ssl_terminator if is_ssl
    use_backend direct_ssh_backend if is_ssh_banner or { req.len eq 0 }
    default_backend ws_ssh_plain_backend

backend loop_ssl_terminator
    mode tcp
    server local_tls 127.0.0.1:8442 send-proxy

frontend zainu_443_tls_terminated
    bind 127.0.0.1:8442 accept-proxy ssl crt /etc/ssl/xray/haproxy.pem alpn h2,http/1.1
    mode tcp
    tcp-request inspect-delay 500ms
    acl is_h2_preface req.payload(0,14) -m bin 505249202a20485454502f322e30
    acl is_xray_path req.payload(0,0) -m sub /zainu- /vless /vmess /trojan
    acl is_ssh_banner req.payload(0,4) -m str SSH-
    acl xr_vless_ws req.payload(0,80) -m sub "GET /vless " "GET /zainu-vless-ws"
    acl xr_vmess_ws req.payload(0,80) -m sub "GET /vmess " "GET /zainu-vmess-ws"
    acl xr_trojan_ws req.payload(0,80) -m sub "GET /trojan " "GET /zainu-trojan-ws"
    acl xr_vless_hup req.payload(0,96) -m sub "GET /vless-hup" "GET /zainu-vless-httpupgrade"
    acl xr_vmess_hup req.payload(0,96) -m sub "GET /vmess-hup" "GET /zainu-vmess-httpupgrade"
    acl xr_trojan_hup req.payload(0,96) -m sub "GET /trojan-hup" "GET /zainu-trojan-httpupgrade"
    acl xr_vless_xhttp req.payload(0,96) -m sub "GET /zainu-vless-xhttp" "POST /zainu-vless-xhttp"
    acl xr_vmess_xhttp req.payload(0,96) -m sub "GET /zainu-vmess-xhttp" "POST /zainu-vmess-xhttp"
    acl xr_trojan_xhttp req.payload(0,96) -m sub "GET /zainu-trojan-xhttp" "POST /zainu-trojan-xhttp"
    tcp-request content accept if is_h2_preface or is_xray_path or is_ssh_banner
    tcp-request content accept if { req.len gt 0 }
    # TLS ke ANDAR wala payload ab Golang Engine dekhta hai (CF-Connecting-IP = real SIM IP)
    use_backend ws_ssh_plain_backend if is_h2_preface or xr_vless_ws or xr_vmess_ws or xr_trojan_ws or xr_vless_hup or xr_vmess_hup or xr_trojan_hup or xr_vless_xhttp or xr_vmess_xhttp or xr_trojan_xhttp or is_xray_path
    use_backend direct_ssh_backend if is_ssh_banner
    default_backend ws_ssh_plain_backend

backend xray_vision_tls_backend
    mode tcp
    server xray_vis 127.0.0.1:8444 send-proxy

backend xray_reality_backend
    mode tcp
    server xray_real 127.0.0.1:10013 send-proxy

backend xd_vless_ws
    mode tcp
    server xd1 127.0.0.1:10001 send-proxy

backend xd_vmess_ws
    mode tcp
    server xd2 127.0.0.1:10002 send-proxy

backend xd_trojan_ws
    mode tcp
    server xd3 127.0.0.1:10003 send-proxy

backend xd_vless_hup
    mode tcp
    server xd7 127.0.0.1:10007 send-proxy

backend xd_vmess_hup
    mode tcp
    server xd8 127.0.0.1:10008 send-proxy

backend xd_trojan_hup
    mode tcp
    server xd9 127.0.0.1:10009 send-proxy

backend xd_vless_xhttp
    mode tcp
    server xd10 127.0.0.1:10010 send-proxy

backend xd_vmess_xhttp
    mode tcp
    server xd11 127.0.0.1:10011 send-proxy

backend xd_trojan_xhttp
    mode tcp
    server xd12 127.0.0.1:10012 send-proxy

backend nginx_h2c_backend
    mode tcp
    server ngx_h2 127.0.0.1:8082 send-proxy

backend nginx_http_backend
    mode tcp
    server ngx_h1 127.0.0.1:8081 send-proxy

backend direct_ssh_backend
    mode tcp
    server ws_direct_ssh 127.0.0.1:10000 send-proxy

backend ws_ssh_plain_backend
    mode tcp
    server ws_engine 127.0.0.1:10000 send-proxy
EOF
    local HAP_BIN=$(command -v haproxy || echo "/usr/sbin/haproxy")
    rm -rf /etc/systemd/system/haproxy.service.d 2>/dev/null || true
    cat << EOF > /etc/systemd/system/haproxy.service
[Unit]
Description=ZAINU X BRAND HAProxy 80/443 Multiplexer
After=network.target nginx.service
StartLimitIntervalSec=0
[Service]
Type=simple
User=root
Nice=-15
LimitNOFILE=1000000
ExecStartPre=-/bin/sh -c "fuser -k 80/tcp 8080/tcp 2082/tcp 8880/tcp 2052/tcp 2086/tcp 2095/tcp 443/tcp 2053/tcp 2083/tcp 2087/tcp 2096/tcp 8442/tcp >/dev/null 2>&1 || true"
ExecStart=${HAP_BIN} -db -f /etc/haproxy/haproxy.cfg
Restart=always
RestartSec=1s
[Install]
WantedBy=multi-user.target
EOF
    # Config validate — fail ho to cert dobara bana ke ek aur try
    local HAP_CHK="$HAP_BIN"
    [[ ! -x "$HAP_CHK" ]] && HAP_CHK="/usr/sbin/haproxy"
    if ! "$HAP_CHK" -c -f /etc/haproxy/haproxy.cfg >/dev/null 2>&1; then
        generate_fallback_cert
        "$HAP_CHK" -c -f /etc/haproxy/haproxy.cfg >/dev/null 2>&1 || true
    fi
    systemctl daemon-reload
    systemctl reset-failed haproxy 2>/dev/null || true
    systemctl enable haproxy 2>/dev/null || true
    systemctl restart haproxy 2>/dev/null || true
    sleep 2
    if ! ss -tln 2>/dev/null | grep -qE ":443\b"; then
        systemctl restart haproxy 2>/dev/null || true
    fi
    install_port_watchdog
}

install_ws_ssh_engine() {
    mkdir -p "$WS_DIR"
    generate_fallback_cert
    ensure_golang_compiler
    cat << 'EOF' > "$WS_DIR/ws.go"
package main

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"net"
	"os"
	"runtime"
	"strings"
	"sync"
	"sync/atomic"
	"time"
)

type PortEntry struct {
	IP    string `json:"ip"`
	Mode  string `json:"mode"`
	Bytes int64  `json:"bytes"`
	Open  bool   `json:"open"`
	Ts    int64  `json:"ts"`
}

var portMap sync.Map

type byteCounter struct {
	w     io.Writer
	entry *PortEntry
}

func (bc *byteCounter) Write(p []byte) (int, error) {
	n, err := bc.w.Write(p)
	if n > 0 && bc.entry != nil {
		atomic.AddInt64(&bc.entry.Bytes, int64(n))
		atomic.StoreInt64(&bc.entry.Ts, time.Now().Unix())
	}
	return n, err
}

func writeMapNow() {
	snap := make(map[string]PortEntry)
	now := time.Now().Unix()
	portMap.Range(func(k, v interface{}) bool {
		key := k.(string)
		pe := v.(*PortEntry)
		if pe.Open || (strings.Contains(pe.Mode, "XHTTP") && now-atomic.LoadInt64(&pe.Ts) < 15) {
			snap[key] = PortEntry{
				IP:    pe.IP,
				Mode:  pe.Mode,
				Bytes: atomic.LoadInt64(&pe.Bytes),
				Open:  true,
				Ts:    atomic.LoadInt64(&pe.Ts),
			}
		}
		return true
	})
	if b, err := json.Marshal(snap); err == nil {
		_ = os.WriteFile("/run/zainu_ws_map.json", b, 0644)
	}
}

func mapWriterDaemon() {
	for {
		time.Sleep(1500 * time.Millisecond)
		writeMapNow()
	}
}

func tuneTCP(c net.Conn) {
	if tc, ok := c.(*net.TCPConn); ok {
		_ = tc.SetNoDelay(true)
		_ = tc.SetKeepAlive(true)
		_ = tc.SetKeepAlivePeriod(15 * time.Second)
	}
}

func extractHeaderIP(req string, fallback string) string {
	for _, h := range []string{"cf-connecting-ip:", "true-client-ip:", "x-real-ip:", "x-forwarded-for:", "x-client-ip:"} {
		for _, ln := range strings.Split(req, "\n") {
			l := strings.TrimSpace(ln)
			if strings.HasPrefix(strings.ToLower(l), h) {
				pts := strings.SplitN(l, ":", 2)
				if len(pts) == 2 {
					for _, cand := range strings.Split(pts[1], ",") {
						ip := strings.TrimSpace(cand)
						if ip != "" && !strings.HasPrefix(ip, "127.") && !strings.HasPrefix(ip, "10.") && !strings.HasPrefix(ip, "192.168.") && ip != "::1" {
							return ip
						}
					}
				}
			}
		}
	}
	return fallback
}

func buildProxyHeader(ipStr string) []byte {
	parsed := net.ParseIP(ipStr)
	if parsed != nil && parsed.To4() != nil {
		return []byte(fmt.Sprintf("PROXY TCP4 %s 127.0.0.1 44300 443\r\n", parsed.To4().String()))
	}
	if parsed != nil {
		return []byte(fmt.Sprintf("PROXY TCP6 %s ::1 44300 443\r\n", parsed.String()))
	}
	return []byte("PROXY TCP4 127.0.0.1 127.0.0.1 44300 443\r\n")
}

func stripExtraPayloads(b []byte) []byte {
	if idx := bytes.Index(b, []byte("SSH-2.0-")); idx != -1 {
		return b[idx:]
	}
	trimmed := bytes.TrimLeft(b, "\r\n ")
	for _, m := range [][]byte{[]byte("GET "), []byte("POST "), []byte("CONNECT "), []byte("HEAD "), []byte("PUT "), []byte("OPTIONS "), []byte("HTTP/")} {
		if bytes.HasPrefix(trimmed, m) {
			if sep := bytes.Index(b, []byte("\r\n\r\n")); sep != -1 {
				return stripExtraPayloads(b[sep+4:])
			}
			return nil
		}
	}
	return b
}

func dialLocalSSH() (net.Conn, error) {
	c, err := net.DialTimeout("tcp", "127.0.0.1:22", 3*time.Second)
	if err != nil {
		c, err = net.DialTimeout("tcp", "127.0.0.1:109", 3*time.Second)
	}
	if err == nil {
		tuneTCP(c)
	}
	return c, err
}

func detectXrayMode(firstLine string) string {
	fl := strings.ToLower(firstLine)
	if strings.Contains(fl, "vless-xhttp") {
		return "VLESS-XHTTP"
	} else if strings.Contains(fl, "vmess-xhttp") {
		return "VMESS-XHTTP"
	} else if strings.Contains(fl, "trojan-xhttp") {
		return "TROJAN-XHTTP"
	} else if strings.Contains(fl, "vless-hup") || strings.Contains(fl, "vless-httpupgrade") {
		return "VLESS-HUP"
	} else if strings.Contains(fl, "vmess-hup") || strings.Contains(fl, "vmess-httpupgrade") {
		return "VMESS-HUP"
	} else if strings.Contains(fl, "trojan-hup") || strings.Contains(fl, "trojan-httpupgrade") {
		return "TROJAN-HUP"
	} else if strings.Contains(fl, "/vless") || strings.Contains(fl, "zainu-vless") {
		return "VLESS-WS"
	} else if strings.Contains(fl, "/vmess") || strings.Contains(fl, "zainu-vmess") {
		return "VMESS-WS"
	} else if strings.Contains(fl, "/trojan") || strings.Contains(fl, "zainu-trojan") {
		return "TROJAN-WS"
	}
	return ""
}

func handleClient(client net.Conn) {
	defer client.Close()
	tuneTCP(client)

	rawIP, _, _ := net.SplitHostPort(client.RemoteAddr().String())
	rawIP = strings.TrimPrefix(rawIP, "::ffff:")

	_ = client.SetReadDeadline(time.Now().Add(2000 * time.Millisecond))
	buf := make([]byte, 16384)
	n, _ := client.Read(buf)
	_ = client.SetReadDeadline(time.Time{})
	data := buf[:n]

	if bytes.HasPrefix(data, []byte("PROXY ")) {
		if idx := bytes.Index(data, []byte("\r\n")); idx != -1 {
			fields := strings.Fields(string(data[:idx]))
			if len(fields) >= 3 && fields[2] != "127.0.0.1" {
				rawIP = fields[2]
			}
			data = data[idx+2:]
		}
	}
	if len(data) == 0 {
		_ = client.SetReadDeadline(time.Now().Add(1500 * time.Millisecond))
		n2, _ := client.Read(buf)
		_ = client.SetReadDeadline(time.Time{})
		data = buf[:n2]
	}

	var target net.Conn
	var err error
	var lportKey string
	var entry *PortEntry
	modeLabel := "SSH-WS"

	// 1. Check HTTP/2 Preface (gRPC / H2 XHTTP)
	if bytes.HasPrefix(data, []byte("PRI * HTTP/2.0")) {
		target, err = net.DialTimeout("tcp", "127.0.0.1:8082", 3*time.Second)
		if err != nil {
			return
		}
		tuneTCP(target)
		defer target.Close()
		_, lportKey, _ = net.SplitHostPort(target.LocalAddr().String())
		_, _ = target.Write(buildProxyHeader(rawIP))
		_, _ = target.Write(data)
		entry = &PortEntry{IP: rawIP, Mode: "XRAY-GRPC", Bytes: 0, Open: true, Ts: time.Now().Unix()}
		portMap.Store("xray-"+lportKey, entry)
		writeMapNow()
		defer func() {
			entry.Open = false
			portMap.Delete("xray-" + lportKey)
			writeMapNow()
		}()
		done := make(chan struct{}, 2)
		go func() {
			_, _ = io.Copy(&byteCounter{w: target, entry: entry}, client)
			_ = target.Close()
			done <- struct{}{}
		}()
		go func() {
			_, _ = io.Copy(&byteCounter{w: client, entry: entry}, target)
			_ = client.Close()
			done <- struct{}{}
		}()
		<-done
		return
	}

	if len(data) == 0 || bytes.HasPrefix(data, []byte("SSH-")) {
		modeLabel = "SSH-SSL/Direct"
		target, err = dialLocalSSH()
		if err != nil {
			return
		}
		_, lportKey, _ = net.SplitHostPort(target.LocalAddr().String())
		if len(data) > 0 {
			_, _ = target.Write(data)
		}
	} else {
		reqStr := string(data)
		rawIP = extractHeaderIP(reqStr, rawIP)
		firstLine := strings.TrimSpace(strings.Split(reqStr, "\n")[0])
		flLower := strings.ToLower(firstLine)

		// 2. Check Web Config Download (.html / .ovpn / .zip)
		if strings.Contains(flLower, ".html") || strings.Contains(flLower, ".ovpn") || strings.Contains(flLower, ".zip") {
			target, err = net.DialTimeout("tcp", "127.0.0.1:8081", 3*time.Second)
			if err != nil {
				return
			}
			defer target.Close()
			_, _ = target.Write(buildProxyHeader(rawIP))
			_, _ = target.Write(data)
			go func() { _, _ = io.Copy(target, client); _ = target.Close() }()
			_, _ = io.Copy(client, target)
			return
		}

		// 3. Check Xray WS / HTTPUpgrade / XHTTP (Direct, Cloudflare, or BunnyCDN)
		if xMode := detectXrayMode(firstLine); xMode != "" {
			if strings.Contains(strings.ToLower(reqStr), "b-cdn.net") || strings.Contains(strings.ToLower(reqStr), "bunny") {
				xMode = "BUNNY-" + xMode
			}
			target, err = net.DialTimeout("tcp", "127.0.0.1:8081", 3*time.Second)
			if err != nil {
				return
			}
			tuneTCP(target)
			defer target.Close()
			_, lportKey, _ = net.SplitHostPort(target.LocalAddr().String())
			_, _ = target.Write(buildProxyHeader(rawIP))
			_, _ = target.Write(data)
			mapKey := "xray-" + lportKey
			if strings.Contains(xMode, "XHTTP") {
				mapKey = "xhttp-" + rawIP
			}
			entry = &PortEntry{IP: rawIP, Mode: xMode, Bytes: 0, Open: true, Ts: time.Now().Unix()}
			portMap.Store(mapKey, entry)
			writeMapNow()
			defer func() {
				entry.Open = false
				if !strings.Contains(xMode, "XHTTP") {
					portMap.Delete(mapKey)
				}
				writeMapNow()
			}()
			done := make(chan struct{}, 2)
			go func() {
				_, _ = io.Copy(&byteCounter{w: target, entry: entry}, client)
				_ = target.Close()
				done <- struct{}{}
			}()
			go func() {
				_, _ = io.Copy(&byteCounter{w: client, entry: entry}, target)
				_ = client.Close()
				done <- struct{}{}
			}()
			<-done
			return
		}

		// 4. SSH-SSL (CONNECT) or SSH-WS / BunnyCDN SSH-WS
		if strings.HasPrefix(strings.ToUpper(firstLine), "CONNECT ") && !strings.Contains(strings.ToLower(reqStr), "upgrade: websocket") {
			modeLabel = "SSH-SSL"
			target, err = dialLocalSSH()
			if err != nil {
				return
			}
			_, lportKey, _ = net.SplitHostPort(target.LocalAddr().String())
			if sep := bytes.Index(data, []byte("\r\n\r\n")); sep != -1 && sep+4 < len(data) {
				clean := stripExtraPayloads(data[sep+4:])
				if len(clean) > 0 {
					_, _ = target.Write(clean)
				}
			}
		} else {
			modeLabel = "SSH-WS"
			if strings.Contains(strings.ToLower(reqStr), "b-cdn.net") || strings.Contains(strings.ToLower(reqStr), "bunny") {
				modeLabel = "BUNNY-SSH"
			}
			target, err = dialLocalSSH()
			if err != nil {
				return
			}
			_, lportKey, _ = net.SplitHostPort(target.LocalAddr().String())
			_, _ = client.Write([]byte("HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n\r\n"))
			if sep := bytes.Index(data, []byte("\r\n\r\n")); sep != -1 && sep+4 < len(data) {
				clean := stripExtraPayloads(data[sep+4:])
				if len(clean) > 0 {
					_, _ = target.Write(clean)
				}
			}
		}
	}

	defer target.Close()
	if lportKey != "" {
		entry = &PortEntry{IP: rawIP, Mode: modeLabel, Bytes: 0, Open: true, Ts: time.Now().Unix()}
		portMap.Store(lportKey, entry)
		writeMapNow()
		defer func() {
			entry.Open = false
			portMap.Delete(lportKey)
			writeMapNow()
		}()
	}

	done := make(chan struct{}, 2)
	go func() {
		bufUp := make([]byte, 65536)
		firstChunk := true
		for {
			nr, er := client.Read(bufUp)
			if nr > 0 {
				chunk := bufUp[:nr]
				if firstChunk {
					firstChunk = false
					chunk = stripExtraPayloads(chunk)
				}
				if len(chunk) > 0 {
					nw, ew := target.Write(chunk)
					if nw > 0 && entry != nil {
						atomic.AddInt64(&entry.Bytes, int64(nw))
						atomic.StoreInt64(&entry.Ts, time.Now().Unix())
					}
					if ew != nil {
						break
					}
				}
			}
			if er != nil {
				break
			}
		}
		_ = target.Close()
		done <- struct{}{}
	}()
	go func() {
		bufDown := make([]byte, 65536)
		_, _ = io.CopyBuffer(&byteCounter{w: client, entry: entry}, target, bufDown)
		_ = client.Close()
		done <- struct{}{}
	}()
	<-done
}

func main() {
	runtime.GOMAXPROCS(runtime.NumCPU())
	go mapWriterDaemon()
	ln, err := net.Listen("tcp", "0.0.0.0:10000")
	if err != nil {
		return
	}
	for {
		c, err := ln.Accept()
		if err == nil {
			go handleClient(c)
		}
	}
}
EOF
    local GO_BIN=$(command -v go || echo "/usr/local/go/bin/go")
    if [[ -x "$GO_BIN" ]]; then
        export GOPATH="/tmp/go-ws" GOCACHE="/tmp/go-ws-cache"
        (cd "$WS_DIR" && timeout 240 "$GO_BIN" build -o "$WS_DIR/zainu-ws-go" ws.go 2>/dev/null || true)
        chmod +x "$WS_DIR/zainu-ws-go" 2>/dev/null || true
    fi
    if [[ ! -x "$WS_DIR/zainu-ws-go" ]]; then
        echo -e "${RED}[X] WS Engine build FAIL! SSH-WS/SSL (ports 80/443) iske baghair nahi chalenge.${NC}"
        echo -e "${RED}    Fix: Panel ka Auto-Doctor dobara chalayein ya 'go version' check karein.${NC}"
    fi
    cat << EOF > /etc/systemd/system/zainu-ws.service
[Unit]
Description=ZAINU X BRAND Multi-Core Golang WS/SSL Engine
After=network.target ssh.service dropbear.service nginx.service
[Service]
Nice=-15
ExecStart=$WS_DIR/zainu-ws-go
Restart=always
RestartSec=2s
User=root
LimitNOFILE=1000000
[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload && systemctl enable zainu-ws 2>/dev/null && systemctl restart zainu-ws 2>/dev/null || true
    configure_haproxy_c_mux
}
# ============================================================================
# UPGRADED LIVE SIM IP ENGINE (WORKS EVEN AFTER CLEAN LOGS & MULTI-USER!)
# ============================================================================
get_live_client_ips_table() {
    install_liveips_helper 2>/dev/null || true
    python3 /usr/local/bin/zainu-liveips.py 2>/dev/null
}

# ============================================================================
# v55.4-HOTFIX: AUTH-ONLY REAL SIM IP ENGINE (panel + Telegram bot SHARED source)
# 1) Cloudflare/BunnyCDN ke EDGE IPs ko kabhi SIM IP nahi dikhata (FAKE display fix)
# 2) Sirf AUTHENTICATED user sessions dikhata hai (scanner/spoof/bots = show NAHI)
# 3) Xray WS/HUP/XHTTP/gRPC ka real SIM IP Golang Engine ke CF-Connecting-IP
#    extraction se aata hai, Xray access log sirf DIRECT protocols (Vision/Reality/
#    mKCP/SS/Socks) ke liye use hota hai
# ============================================================================
install_liveips_helper() {
    cat << 'LIVEIPS_EOF' > /usr/local/bin/zainu-liveips.py
#!/usr/bin/env python3
import os, sys, json, subprocess, re, datetime, ipaddress, pwd, time, urllib.request

USERS_DB = "/etc/aliraza/users.db"
WS_MAP_FILE = "/run/zainu_ws_map.json"
ACTIVE_U_FILE = "/run/zainu_active_users.json"
XRAY_LOG = "/var/log/xray/access.log"
VPS_IP_FILE = "/etc/aliraza/vps_ip.txt"
CACHE_FILE = "/run/zainu_liveips.cache"
CACHE_TTL = 4

CDN_NETS = [ipaddress.ip_network(n) for n in (
    "173.245.48.0/20", "103.21.244.0/22", "103.22.200.0/22", "103.31.4.0/22",
    "141.101.64.0/18", "108.162.192.0/18", "190.93.240.0/20", "188.114.96.0/20",
    "197.234.240.0/22", "198.41.128.0/17", "162.158.0.0/15", "104.16.0.0/13",
    "104.24.0.0/14", "172.64.0.0/13", "131.0.72.0/22")]

vps_ip = ""
if os.path.exists(VPS_IP_FILE):
    try: vps_ip = open(VPS_IP_FILE).read().split()[0]
    except Exception: vps_ip = ""

def clean_ip(ip):
    return str(ip or "").strip().strip("[]").replace("::ffff:", "")

def is_cdn_ip(ip):
    try:
        a = ipaddress.ip_address(ip)
        return any(a in n for n in CDN_NETS)
    except Exception:
        return False

def is_real_sim_ip(ip):
    ip = clean_ip(ip)
    if not ip or ip == vps_ip: return False
    if is_cdn_ip(ip): return False
    try:
        a = ipaddress.ip_address(ip)
        return a.is_global and not (a.is_private or a.is_loopback or a.is_link_local or a.is_multicast or a.is_reserved)
    except Exception:
        return False

def build_peers():
    valid_users = []
    if os.path.exists(USERS_DB):
        for line in open(USERS_DB, errors="ignore"):
            pts = line.strip().split("|")
            if len(pts) >= 7 and pts[6] == "UNLOCKED":
                valid_users.append(pts[0])
    if not valid_users:
        return {}
    valid_set = set(valid_users)
    single_user = valid_users[0] if len(valid_users) == 1 else ""

    peers = {}
    def add_peer(ip, proto_label, user):
        ip = clean_ip(ip)
        if not is_real_sim_ip(ip): return
        tag = ("%s(%s)" % (proto_label, user)) if user else proto_label
        if ip not in peers:
            peers[ip] = {"ports": set(), "tunnels": 0}
        if tag not in peers[ip]["ports"]:
            peers[ip]["ports"].add(tag)
            peers[ip]["tunnels"] += 1

    ws_map = {}
    if os.path.exists(WS_MAP_FILE):
        try: ws_map = json.loads(open(WS_MAP_FILE).read())
        except Exception: ws_map = {}

    active_u_map = {}
    if os.path.exists(ACTIVE_U_FILE):
        try: active_u_map = json.loads(open(ACTIVE_U_FILE).read())
        except Exception: active_u_map = {}

    now_ts = int(time.time())
    rx_live = next((u for u, ts in sorted(active_u_map.items(), key=lambda x: -x[1]) if u in valid_set and now_ts - int(ts) < 30), "")

    pid_to_user = {}
    for pid_dir in os.listdir("/proc"):
        if not pid_dir.isdigit(): continue
        p_path = "/proc/" + pid_dir
        try:
            uid = os.stat(p_path).st_uid
            if uid >= 1000:
                uname = pwd.getpwuid(uid).pw_name
                if uname in valid_set:
                    pid_to_user[pid_dir] = uname
                    continue
        except Exception:
            pass
        try:
            cmd = open(p_path + "/cmdline", "rb").read().replace(b"\x00", b" ").decode("utf-8", errors="ignore").strip()
            m = re.search(r"sshd(?:-session)?:\s*([a-zA-Z0-9_-]+)", cmd)
            if m and m.group(1) in valid_set:
                pid_to_user[pid_dir] = m.group(1)
        except Exception:
            pass

    auth_by_port, auth_by_pid = {}, {}
    log_lines = []
    if os.path.exists("/var/log/auth.log"):
        try: log_lines.extend(subprocess.check_output(["tail", "-n", "250", "/var/log/auth.log"], text=True, stderr=subprocess.DEVNULL).splitlines())
        except Exception: pass
    if not log_lines:
        try: log_lines.extend(subprocess.check_output(["journalctl", "-u", "ssh", "-u", "dropbear", "-n", "150", "--no-pager"], text=True, stderr=subprocess.DEVNULL).splitlines())
        except Exception: pass
    for ln in log_lines:
        if "Password auth succeeded" in ln or "Accepted password for" in ln:
            m_u = re.search(r"for '([^']+)'", ln) or re.search(r"for (\S+)", ln)
            m_prt = re.search(r"from [0-9a-fA-F:\.]+(?::| port )(\d+)", ln)
            m_pid = re.search(r"\[(\d+)\]:", ln)
            if m_u and m_u.group(1) in valid_set:
                if m_prt: auth_by_port[m_prt.group(1)] = m_u.group(1)
                if m_pid: auth_by_pid[m_pid.group(1)] = m_u.group(1)

    # 1) Golang WS/SSL Engine live tunnels (yahan REAL SIM IP header se aati hai)
    for lport_key, wentry in ws_map.items():
        if not wentry.get("open", True): continue
        wip, wmode = wentry.get("ip", ""), wentry.get("mode", "SSH-WS")
        if any(k in wmode for k in ("VLESS", "VMESS", "TROJAN", "XRAY")):
            u = rx_live or single_user
            if u: add_peer(wip, wmode, u)
        else:
            u = auth_by_port.get(lport_key)
            # FIX: baghair auth wale naye socket kisi user par ilzaam (fake) nahi
            if u: add_peer(wip, wmode, u)

    # 2) Xray access log = sirf DIRECT protocols (Vision/Reality/mKCP/SS/Socks)
    if os.path.exists(XRAY_LOG):
        try:
            now_dt = datetime.datetime.now()
            xlines = subprocess.check_output(["tail", "-n", "250", XRAY_LOG], text=True, stderr=subprocess.DEVNULL).splitlines()
            for ln in reversed(xlines):
                if "accepted" not in ln or "email:" not in ln: continue
                m_ts = re.match(r"^(\d{4}/\d{2}/\d{2} \d{2}:\d{2}:\d{2})", ln)
                if m_ts and abs((now_dt - datetime.datetime.strptime(m_ts.group(1), "%Y/%m/%d %H:%M:%S")).total_seconds()) > 45:
                    continue
                u = ln.split("email:")[-1].strip().split()[0]
                if u not in valid_set: continue
                m_tag = re.search(r"\[([a-z0-9-]+)\s*(?:->|>>)", ln)
                lbl = (m_tag.group(1).upper() if m_tag else "XRAY")
                # WS family ka real IP Engine map se aati hai, log ka IP CDN hota hai
                if lbl.endswith("-WS") or "-XHTTP" in lbl or "HTTPUPGRADE" in lbl or lbl.endswith("-GRPC"):
                    continue
                m_ip = re.search(r"from (?:tcp:|udp:)?([0-9a-fA-F:\.]+):\d+", ln)
                if m_ip: add_peer(m_ip.group(1), lbl, u)
        except Exception:
            pass

    # 3) Direct SSH / Dropbear / Stunnel sockets (AUTH-gated only)
    stunnel_ips = []
    try:
        ss_out = subprocess.check_output(["ss", "-tnp", "state", "established"], text=True, stderr=subprocess.DEVNULL)
        for ln in ss_out.splitlines()[1:]:
            cols = ln.split()
            if len(cols) < 5: continue
            loc, peer = cols[3], cols[4]
            lport = loc.rsplit(":", 1)[-1]
            p_ip = clean_ip(peer.rsplit(":", 1)[0])
            p_port = peer.rsplit(":", 1)[-1]
            pids = re.findall(r"pid=(\d+)", ln)
            if lport in ("444", "8443", "992") and is_real_sim_ip(p_ip):
                stunnel_ips.append((p_ip, lport))
            elif lport in ("22", "2222", "109", "143", "447"):
                u = next((pid_to_user.get(p) or auth_by_pid.get(p) for p in pids if p in pid_to_user or p in auth_by_pid), None) or auth_by_port.get(p_port)
                if not u: continue
                if p_port in ws_map and ws_map[p_port].get("open", True):
                    continue
                if is_real_sim_ip(p_ip):
                    add_peer(p_ip, "DROPBEAR" if lport in ("109", "143", "447") else ("SSH-" + lport), u)
                elif p_ip == "127.0.0.1" and stunnel_ips:
                    add_peer(stunnel_ips[0][0], "STUNNEL-" + stunnel_ips[0][1], u)
            elif lport in ("8444", "10013", "10015", "8888", "10808", "10809") and is_real_sim_ip(p_ip):
                u = rx_live or single_user
                if u:
                    lbl = "VLESS-VISION" if lport == "8444" else ("VLESS-REALITY" if lport == "10013" else ("SOCKS5" if lport == "10808" else "SS/PROXY"))
                    add_peer(p_ip, lbl, u)
    except Exception:
        pass

    # 4) OpenVPN status logs
    for ovpn_log in ("/var/log/openvpn-tcp.log", "/var/log/openvpn-udp.log"):
        if os.path.exists(ovpn_log):
            try:
                for ln in open(ovpn_log, errors="ignore"):
                    if ln.startswith("CLIENT_LIST"):
                        pts = ln.strip().split(",")
                        if len(pts) >= 3 and pts[1] in valid_set:
                            add_peer(pts[2].rsplit(":", 1)[0], "OPENVPN", pts[1])
            except Exception:
                pass

    # 5) ASSURED UDP conntrack (ZiVPN / UDP-Custom / Hysteria2 / mKCP)
    hy_u = ""
    try:
        with urllib.request.urlopen("http://127.0.0.1:9999/online", timeout=1) as r:
            hy_data = json.loads(r.read().decode())
            hy_u = next((k for k in hy_data if k in valid_set), "")
    except Exception:
        pass
    ssh_active = sorted(set(pid_to_user.values()))
    udp_guess = single_user or (ssh_active[0] if len(ssh_active) == 1 else "")
    if os.path.exists("/proc/net/nf_conntrack"):
        try:
            for ln in open("/proc/net/nf_conntrack", errors="ignore"):
                if "udp" not in ln or "[ASSURED]" not in ln: continue
                m_src = re.search(r"src=([0-9\.]+)\s+dst=[0-9\.]+\s+sport=\d+\s+dport=(\d+)\s+packets=(\d+)", ln)
                if m_src and int(m_src.group(3)) > 15:
                    src_ip, dport = m_src.group(1), m_src.group(2)
                    if not is_real_sim_ip(src_ip): continue
                    if dport == "5667": add_peer(src_ip, "ZIVPN-UDP", udp_guess)
                    elif dport == "36712": add_peer(src_ip, "UDP-CUSTOM", udp_guess)
                    elif dport == "20800" and hy_u: add_peer(src_ip, "HYSTERIA2", hy_u)
                    elif dport == "10014":
                        u = rx_live or single_user
                        if u: add_peer(src_ip, "VLESS-MKCP", u)
        except Exception:
            pass
    return peers

def render(peers, bot_mode):
    if bot_mode:
        return ["- " + ip + " -> " + ",".join(sorted(info["ports"])) for ip, info in sorted(peers.items())]
    return ["%d|%s|%s|%d" % (idx, ip, ",".join(sorted(info["ports"])), info["tunnels"]) for idx, (ip, info) in enumerate(sorted(peers.items()), 1)]

def main():
    bot_mode = "--bot" in sys.argv
    try:
        if os.path.exists(CACHE_FILE) and time.time() - os.path.getmtime(CACHE_FILE) < CACHE_TTL:
            raw = open(CACHE_FILE, errors="ignore").read().splitlines()
            peers = {}
            for ln in raw:
                pts = ln.split("|")
                if len(pts) >= 4:
                    peers[pts[1]] = {"ports": set(x for x in pts[2].split(",") if x), "tunnels": int(pts[3] or 1)}
            out = render(peers, bot_mode)
            if out: print("\n".join(out))
            return
    except Exception:
        pass
    peers = build_peers()
    canonical = render(peers, False)
    try: open(CACHE_FILE, "w").write("\n".join(canonical) + ("\n" if canonical else ""))
    except Exception: pass
    out = render(peers, bot_mode)
    if out: print("\n".join(out))

if __name__ == "__main__":
    main()
LIVEIPS_EOF
    chmod +x /usr/local/bin/zainu-liveips.py 2>/dev/null || true
}

get_live_client_ips_table__legacy_unused() {
    python3 - << 'PY' 2>/dev/null
import os, sys, json, subprocess, re, datetime, ipaddress, pwd, time, urllib.request

USERS_DB = "/etc/aliraza/users.db"
WS_MAP_FILE = "/run/zainu_ws_map.json"
ACTIVE_U_FILE = "/run/zainu_active_users.json"
XRAY_LOG = "/var/log/xray/access.log"

valid_users = []
if os.path.exists(USERS_DB):
    for line in open(USERS_DB):
        pts = line.strip().split("|")
        if len(pts) >= 7 and pts[6] == "UNLOCKED":
            valid_users.append(pts[0])
if not valid_users:
    sys.exit(0)
valid_set = set(valid_users)
def_u = valid_users[0]

vps_ip = open("/etc/aliraza/vps_ip.txt").read().strip() if os.path.exists("/etc/aliraza/vps_ip.txt") else ""

def is_real_sim_ip(ip):
    ip = str(ip).strip().strip("[]").replace("::ffff:", "")
    if not ip or ip == vps_ip:
        return False
    try:
        addr = ipaddress.ip_address(ip)
        return addr.is_global and not (addr.is_private or addr.is_loopback or addr.is_link_local or addr.is_multicast or addr.is_reserved)
    except Exception:
        return False

peers = {}
def add_peer(ip, proto_label, user):
    ip = str(ip).strip().strip("[]").replace("::ffff:", "")
    if not is_real_sim_ip(ip):
        return
    if not user or user not in valid_set:
        user = def_u
    tag = f"{proto_label}({user})"
    if ip not in peers:
        peers[ip] = {"ports": set(), "tunnels": 0}
    if tag not in peers[ip]["ports"]:
        peers[ip]["ports"].add(tag)
        peers[ip]["tunnels"] += 1

ws_map = {}
if os.path.exists(WS_MAP_FILE):
    try: ws_map = json.loads(open(WS_MAP_FILE).read())
    except Exception: ws_map = {}

active_u_map = {}
if os.path.exists(ACTIVE_U_FILE):
    try: active_u_map = json.loads(open(ACTIVE_U_FILE).read())
    except Exception: active_u_map = {}

now_ts = int(time.time())
# rx_live = wahi user jo pichle 30s me Xray se REAL traffic kar raha hai (warna None = fake display nahi)
rx_live = next((u for u, ts in sorted(active_u_map.items(), key=lambda x: -x[1]) if u in valid_set and now_ts - ts < 30), None)
recent_xray_user = rx_live or def_u

pid_to_user = {}
for pid_dir in os.listdir("/proc"):
    if not pid_dir.isdigit(): continue
    p_path = f"/proc/{pid_dir}"
    try:
        uid = os.stat(p_path).st_uid
        if uid >= 1000:
            uname = pwd.getpwuid(uid).pw_name
            if uname in valid_set:
                pid_to_user[pid_dir] = uname
                continue
    except Exception:
        pass
    try:
        cmd = open(f"{p_path}/cmdline", "rb").read().replace(b"\x00", b" ").decode("utf-8", errors="ignore").strip()
        m = re.search(r"sshd(?:-session)?:\s*([a-zA-Z0-9_-]+)", cmd)
        if m and m.group(1) in valid_set:
            pid_to_user[pid_dir] = m.group(1)
    except Exception:
        pass

auth_by_port, auth_by_pid = {}, {}
log_lines = []
if os.path.exists("/var/log/auth.log"):
    try: log_lines.extend(subprocess.check_output(["tail", "-n", "250", "/var/log/auth.log"], text=True, stderr=subprocess.DEVNULL).splitlines())
    except Exception: pass
if not log_lines:
    try: log_lines.extend(subprocess.check_output(["journalctl", "-u", "ssh", "-u", "dropbear", "-n", "150", "--no-pager"], text=True, stderr=subprocess.DEVNULL).splitlines())
    except Exception: pass

for ln in log_lines:
    if "Password auth succeeded" in ln or "Accepted password for" in ln:
        m_u = re.search(r"for '([^']+)'", ln) or re.search(r"for (\S+)", ln)
        m_prt = re.search(r"from [0-9a-fA-F:\.]+(?::| port )(\d+)", ln)
        m_pid = re.search(r"\[(\d+)\]:", ln)
        if m_u and m_u.group(1) in valid_set:
            if m_prt: auth_by_port[m_prt.group(1)] = m_u.group(1)
            if m_pid: auth_by_pid[m_pid.group(1)] = m_u.group(1)

if os.path.exists(XRAY_LOG):
    try:
        now_dt = datetime.datetime.now()
        for ln in reversed(subprocess.check_output(["tail", "-n", "250", XRAY_LOG], text=True, stderr=subprocess.DEVNULL).splitlines()):
            if "accepted" not in ln: continue
            m_ts = re.match(r"^(\d{4}/\d{2}/\d{2} \d{2}:\d{2}:\d{2})", ln)
            if m_ts and abs((now_dt - datetime.datetime.strptime(m_ts.group(1), "%Y/%m/%d %H:%M:%S")).total_seconds()) > 45:
                continue
            u = ln.split("email:")[-1].strip().split()[0] if "email:" in ln else recent_xray_user
            if u in valid_set:
                recent_xray_user = u
                m_tag = re.search(r"\[([a-z0-9-]+)\s*(?:->|>>)", ln)
                m_ip = re.search(r"from (?:tcp:|udp:)?([0-9a-fA-F:\.]+):\d+", ln)
                if m_ip and is_real_sim_ip(m_ip.group(1)):
                    add_peer(m_ip.group(1), m_tag.group(1).upper() if m_tag else "XRAY", u)
    except Exception:
        pass

# 1. All active tunnels tracked by Golang WS/SSL/BunnyCDN/Xray Engine
for lport_key, wentry in ws_map.items():
    if not wentry.get("open", True): continue
    wip = wentry.get("ip", "")
    wmode = wentry.get("mode", "SSH-WS")
    if any(k in wmode for k in ("XRAY", "VLESS", "VMESS", "TROJAN")):
        if rx_live:
            add_peer(wip, wmode, rx_live)
    else:
        u = auth_by_port.get(lport_key)
        if not u and now_ts - int(wentry.get("ts", now_ts) or now_ts) < 15:
            u = def_u
        if u:
            add_peer(wip, wmode, u)

# 2. Established TCP sockets (Direct SSH, Dropbear, Stunnel, Vision, Reality, Socks5, SS)
stunnel_ips = []
try:
    ss_out = subprocess.check_output(["ss", "-tnp", "state", "established"], text=True, stderr=subprocess.DEVNULL)
    for ln in ss_out.splitlines()[1:]:
        cols = ln.split()
        if len(cols) < 5: continue
        loc, peer = cols[3], cols[4]
        lport = loc.rsplit(":", 1)[-1]
        p_ip = peer.rsplit(":", 1)[0].strip("[]").replace("::ffff:", "")
        p_port = peer.rsplit(":", 1)[-1]
        pids = re.findall(r"pid=(\d+)", ln)

        if lport in ("444", "8443", "992") and is_real_sim_ip(p_ip):
            stunnel_ips.append((p_ip, lport))
        elif lport in ("22", "2222", "109", "143", "447"):
            u = next((pid_to_user.get(p) or auth_by_pid.get(p) for p in pids if p in pid_to_user or p in auth_by_pid), None) or auth_by_port.get(p_port)
            if not u: continue
            if p_port in ws_map and ws_map[p_port].get("open", True):
                add_peer(ws_map[p_port].get("ip", ""), ws_map[p_port].get("mode", "SSH-WS"), u)
            elif is_real_sim_ip(p_ip):
                add_peer(p_ip, "DROPBEAR" if lport in ("109", "143", "447") else f"SSH-{lport}", u)
            elif p_ip == "127.0.0.1" and stunnel_ips:
                add_peer(stunnel_ips[0][0], f"STUNNEL-{stunnel_ips[0][1]}", u)
        elif lport in ("8444", "10013", "10015", "8888", "10808", "10809") and is_real_sim_ip(p_ip):
            if rx_live:
                lbl = "VLESS-VISION" if lport == "8444" else ("VLESS-REALITY" if lport == "10013" else ("SOCKS5" if lport == "10808" else "SS/PROXY"))
                add_peer(p_ip, lbl, rx_live)
except Exception:
    pass

for st_ip, st_prt in stunnel_ips:
    if st_ip not in peers and pid_to_user:
        add_peer(st_ip, f"STUNNEL-{st_prt}", next(iter(pid_to_user.values()), None))

# 3. OpenVPN status logs
for ovpn_log in ("/var/log/openvpn-tcp.log", "/var/log/openvpn-udp.log"):
    if os.path.exists(ovpn_log):
        try:
            for ln in open(ovpn_log):
                if ln.startswith("CLIENT_LIST"):
                    pts = ln.strip().split(",")
                    if len(pts) >= 3 and pts[1] in valid_set:
                        add_peer(pts[2].rsplit(":", 1)[0], "OPENVPN", pts[1])
        except Exception:
            pass

# 4. Hysteria2 online API & ASSURED UDP Conntrack (ZiVPN, UDP-Custom, HY2, mKCP)
hy_u = None
try:
    with urllib.request.urlopen("http://127.0.0.1:9999/online", timeout=1) as r:
        hy_data = json.loads(r.read().decode())
        hy_u = next((k for k in hy_data if k in valid_set), None)
except Exception:
    pass

if os.path.exists("/proc/net/nf_conntrack"):
    try:
        for ln in open("/proc/net/nf_conntrack"):
            if "udp" not in ln or "[ASSURED]" not in ln: continue
            m_src = re.search(r"src=([0-9\.]+)\s+dst=[0-9\.]+\s+sport=\d+\s+dport=(\d+)\s+packets=(\d+)", ln)
            if m_src and is_real_sim_ip(m_src.group(1)) and int(m_src.group(3)) > 15:
                src_ip, dport = m_src.group(1), m_src.group(2)
                if dport == "5667": add_peer(src_ip, "ZIVPN-UDP", def_u)
                elif dport == "36712": add_peer(src_ip, "UDP-CUSTOM", def_u)
                elif dport == "20800" and hy_u: add_peer(src_ip, "HYSTERIA2", hy_u)
                elif dport == "10014" and rx_live: add_peer(src_ip, "VLESS-MKCP", rx_live)
    except Exception:
        pass

for idx, (ip, info) in enumerate(sorted(peers.items()), 1):
    print(f"{idx}|{ip}|{','.join(sorted(info['ports']))}|{info['tunnels']}")
PY
}

install_badvpn_gateway() {
    local force_replace="${1:-0}"
    [[ "$force_replace" == "1" ]] && rm -f /usr/bin/badvpn-udpgw 2>/dev/null || true
    if [[ ! -x /usr/bin/badvpn-udpgw ]]; then
        for url in "https://raw.githubusercontent.com/daybreakersx/premscript/master/badvpn-udpgw64" \
                   "https://github.com/ambrop72/badvpn/releases/download/1.999.130/badvpn-udpgw"; do
            curl -sL --max-time 15 "$url" -o /usr/bin/badvpn-udpgw 2>/dev/null && chmod +x /usr/bin/badvpn-udpgw 2>/dev/null || true
            [[ -x /usr/bin/badvpn-udpgw ]] && /usr/bin/badvpn-udpgw --help 2>&1 | grep -qi "listen-addr" && break || rm -f /usr/bin/badvpn-udpgw
        done
    fi
    cat << 'EOF' > /usr/local/bin/zainu-badvpn-multi
#!/usr/bin/env bash
pkill -9 badvpn-udpgw 2>/dev/null || true
/usr/bin/badvpn-udpgw --listen-addr 0.0.0.0:7100 --max-clients 1000 --max-connections-for-client 100 &
/usr/bin/badvpn-udpgw --listen-addr 0.0.0.0:7200 --max-clients 1000 --max-connections-for-client 100 &
exec /usr/bin/badvpn-udpgw --listen-addr 0.0.0.0:7300 --max-clients 1000 --max-connections-for-client 100
EOF
    chmod +x /usr/local/bin/zainu-badvpn-multi
    cat << 'EOF' > /etc/systemd/system/badvpn.service
[Unit]
Description=BadVPN UDPGW (7100-7300)
After=network.target
[Service]
User=root
ExecStart=/usr/local/bin/zainu-badvpn-multi
Restart=always
RestartSec=2s
[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload && systemctl enable badvpn 2>/dev/null && systemctl restart badvpn 2>/dev/null || true
}

install_zivpn_and_hysteria() {
    local force_replace="${1:-0}"
    mkdir -p "$ZIVPN_DIR" "$HY2_DIR"
    generate_fallback_cert
    local ARCH=$(uname -m)
    [[ "$force_replace" == "1" ]] && rm -f "$ZIVPN_DIR/zivpn" /usr/local/bin/hysteria 2>/dev/null || true

    if [[ ! -x "$ZIVPN_DIR/zivpn" ]]; then
        local ZI_URL="https://github.com/zahidbd2/udp-zivpn/releases/download/udp-zivpn_1.4.9/udp-zivpn-linux-amd64"
        [[ "$ARCH" == "aarch64" || "$ARCH" == "arm64" ]] && ZI_URL="https://github.com/zahidbd2/udp-zivpn/releases/download/udp-zivpn_1.4.9/udp-zivpn-linux-arm64"
        curl -sL --max-time 15 "$ZI_URL" -o "$ZIVPN_DIR/zivpn" 2>/dev/null || true
        chmod +x "$ZIVPN_DIR/zivpn" 2>/dev/null || true
    fi

    if [[ ! -x /usr/local/bin/hysteria ]]; then
        local HY_A="amd64"
        [[ "$ARCH" == "aarch64" || "$ARCH" == "arm64" ]] && HY_A="arm64"
        curl -sL --max-time 15 "https://github.com/apernet/hysteria/releases/latest/download/hysteria-linux-${HY_A}" -o /usr/local/bin/hysteria 2>/dev/null || true
        chmod +x /usr/local/bin/hysteria 2>/dev/null || true
    fi

    sync_all_users_to_engines

    cat << EOF > /etc/systemd/system/zivpn.service
[Unit]
Description=ZiVPN Official UDP Server (5667 & 6000-19999)
After=network.target
[Service]
User=root
Nice=-15
ExecStart=$ZIVPN_DIR/zivpn server -c $ZIVPN_DIR/config.json
Restart=always
RestartSec=2s
LimitNOFILE=1000000
[Install]
WantedBy=multi-user.target
EOF

    cat << EOF > /etc/systemd/system/hysteria.service
[Unit]
Description=Hysteria 2 High-Speed QUIC UDP Server (20800)
After=network.target
[Service]
User=root
Nice=-15
ExecStart=/usr/local/bin/hysteria server -c $HY2_DIR/config.yaml
Restart=always
RestartSec=2s
LimitNOFILE=1000000
[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable zivpn hysteria 2>/dev/null || true
    systemctl restart zivpn hysteria 2>/dev/null || true
}

install_udp_custom() {
    local force_replace="${1:-0}"
    mkdir -p "$UDP_DIR"
    [[ "$force_replace" == "1" ]] && rm -f "$UDP_DIR/udp-custom" 2>/dev/null || true
    if [[ ! -x "$UDP_DIR/udp-custom" ]]; then
        for url in "https://github.com/noobconner21/UDP-Custom-Script/raw/main/udp-custom-linux-amd64" \
                   "https://raw.githubusercontent.com/rudi9999/Herramientas/main/UDP/udp-custom-linux-amd64"; do
            curl -sL --max-time 15 "$url" -o "$UDP_DIR/udp-custom" 2>/dev/null && chmod +x "$UDP_DIR/udp-custom" 2>/dev/null || true
            [[ $(stat -c%s "$UDP_DIR/udp-custom" 2>/dev/null || echo 0) -gt 1000000 ]] && break || rm -f "$UDP_DIR/udp-custom"
        done
    fi
    printf '{"listen":":36712","stream_buffer":33554432,"receive_buffer":83886080,"auth":{"mode":"passwords"}}\n' > "$UDP_DIR/config.json"
    cat << EOF > /etc/systemd/system/udp-custom.service
[Unit]
Description=UDP Custom Server
After=network.target
[Service]
User=root
ExecStart=$UDP_DIR/udp-custom server -exclude 53,2200,5300,5667,7100,7200,7300,8888,10014,10015,10808,20800
WorkingDirectory=$UDP_DIR/
Restart=always
RestartSec=2s
[Install]
WantedBy=multi-user.target
EOF
    install_zivpn_and_hysteria "$force_replace"
    setup_slowdns_and_udp_nat
    systemctl daemon-reload && systemctl enable udp-custom 2>/dev/null && systemctl restart udp-custom 2>/dev/null || true
}

configure_slowdns_service() {
    local force_rebuild="${1:-0}"
    local NS_DOMAIN=$(head -n1 "$DATA_DIR/ns_domain.txt" 2>/dev/null | tr -d '[:space:]'); [[ -z "$NS_DOMAIN" ]] && NS_DOMAIN="nr.aliraza.com"
    fix_dns_resolver
    if ! verify_real_dnstt_binary; then
        ensure_golang_compiler
        local GO_BIN=$(command -v go || echo "/usr/local/go/bin/go")
        export GOPATH="/tmp/go-dnstt" GOCACHE="/tmp/go-dnstt-cache"
        rm -rf /tmp/dnstt-src
        timeout 90 git clone https://www.bamsoftware.com/git/dnstt.git /tmp/dnstt-src 2>/dev/null || timeout 90 git clone https://github.com/Mygod/dnstt.git /tmp/dnstt-src 2>/dev/null || true
        [[ -d /tmp/dnstt-src/dnstt-server ]] && (cd /tmp/dnstt-src/dnstt-server && timeout 240 "$GO_BIN" build -o "$SLOWDNS_DIR/dnstt-server" 2>/dev/null && chmod +x "$SLOWDNS_DIR/dnstt-server")
        rm -rf /tmp/dnstt-src
    fi
    if verify_real_dnstt_binary && [[ ! -s "$SLOWDNS_DIR/server.pub" || ! -s "$SLOWDNS_DIR/server.key" ]]; then
        "$SLOWDNS_DIR/dnstt-server" -gen-key -privkey-file "$SLOWDNS_DIR/server.key" -pubkey-file "$SLOWDNS_DIR/server.pub" >/dev/null 2>&1 || true
    fi
    if ! verify_real_dnstt_binary; then
        echo -e "${RED}[X] SlowDNS (dnstt-server) build FAIL - internet/git check kar ke Panel ke Auto-Doctor / Tools se dobara try karein.${NC}"
        systemctl stop slowdns >/dev/null 2>&1 || true
        return 1
    fi
    local SDNS_TARGET="127.0.0.1:2222"
    [[ -s "$DATA_DIR/slowdns_target.txt" ]] && SDNS_TARGET=$(head -n1 "$DATA_DIR/slowdns_target.txt" | tr -d '[:space:]')
    cat << EOF > /etc/systemd/system/slowdns.service
[Unit]
Description=SlowDNS DNSTT Server
After=network.target
[Service]
ExecStart=$SLOWDNS_DIR/dnstt-server -udp 0.0.0.0:5300 -mtu 1100 -privkey-file $SLOWDNS_DIR/server.key $NS_DOMAIN ${SDNS_TARGET}
Restart=always
RestartSec=2s
[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload && systemctl enable slowdns 2>/dev/null && systemctl restart slowdns 2>/dev/null || true
}

# ============================================================================
# 100% ZERO-GHOST-KB REAL AUTHENTICATED DATA TRACKER (`zainu-enforcer`)
# - ONLY counts authenticated user sessions (Xray UUID/Email, SSH/WS PID, HY2, OVPN)
# - NEVER counts unauthenticated UDP conntrack loops or port scanners!
# ============================================================================
setup_realtime_monitor_service() {
    cat << 'EOF' > /usr/local/bin/zainu-enforcer
#!/usr/bin/env python3
import os, sys, json, time, re, subprocess, datetime, pwd, urllib.request

USERS_DB = "/etc/aliraza/users.db"
USAGE_DIR = "/etc/aliraza/usage"
USER_CONF_DIR = "/etc/aliraza/users"
XRAY_CONF = "/usr/local/etc/xray/config.json"
WS_MAP_FILE = "/run/zainu_ws_map.json"
STATE_FILE = "/run/zainu_tracker_state.json"
ACTIVE_U_FILE = "/run/zainu_active_users.json"

os.makedirs(USAGE_DIR, exist_ok=True)
os.makedirs(USER_CONF_DIR, exist_ok=True)

PROTECTED_USERS = {"root", "ubuntu", "debian", "admin", "ec2-user", "centos", "rocky", "almalinux", "fedora", "sshd", "nobody", "haproxy", "www-data"}

def load_state():
    if os.path.exists(STATE_FILE):
        try: return json.load(open(STATE_FILE))
        except Exception: pass
    return {"ws": {}, "sock": {}, "ovpn": {}}

def save_state(st):
    try: json.dump(st, open(STATE_FILE, "w"))
    except Exception: pass

def read_int(path):
    try: return int(open(path).read().strip() or 0)
    except Exception: return 0

def write_int(path, val):
    try: open(path, "w").write(str(max(0, int(val))))
    except Exception: pass

def get_ssh_and_ws_deltas(valid_set, ws_map, state):
    deltas = {}
    pid_to_user = {}
    for pid_dir in os.listdir("/proc"):
        if not pid_dir.isdigit(): continue
        p_path = f"/proc/{pid_dir}"
        try:
            uid = os.stat(p_path).st_uid
            if uid >= 1000:
                uname = pwd.getpwuid(uid).pw_name
                if uname in valid_set:
                    pid_to_user[pid_dir] = uname
                    continue
        except Exception:
            pass
        try:
            cmd = open(f"{p_path}/cmdline", "rb").read().replace(b"\x00", b" ").decode("utf-8", errors="ignore").strip()
            m = re.search(r"sshd(?:-session)?:\s*([a-zA-Z0-9_-]+)", cmd)
            if m and m.group(1) in valid_set:
                pid_to_user[pid_dir] = m.group(1)
        except Exception:
            pass

    auth_by_pid, auth_by_port = {}, {}
    log_lines = []
    if os.path.exists("/var/log/auth.log"):
        try: log_lines.extend(subprocess.check_output(["tail", "-n", "200", "/var/log/auth.log"], text=True, stderr=subprocess.DEVNULL).splitlines())
        except Exception: pass
    for ln in log_lines:
        if "Password auth succeeded" in ln or "Accepted password for" in ln:
            m_u = re.search(r"for '([^']+)'", ln) or re.search(r"for (\S+)", ln)
            m_prt = re.search(r"from [0-9a-fA-F:\.]+(?::| port )(\d+)", ln)
            m_pid = re.search(r"\[(\d+)\]:", ln)
            if m_u and m_u.group(1) in valid_set:
                if m_prt: auth_by_port[m_prt.group(1)] = m_u.group(1)
                if m_pid: auth_by_pid[m_pid.group(1)] = m_u.group(1)

    active_ws_keys = set()
    active_sock_keys = set()

    try:
        ss_out = subprocess.check_output(["ss", "-tnpi", "state", "established"], text=True, stderr=subprocess.DEVNULL)
        lines = ss_out.splitlines()[1:]
        i = 0
        while i < len(lines):
            ln = lines[i]
            info_ln = lines[i + 1] if (i + 1 < len(lines) and lines[i + 1].startswith("\t")) else ""
            i += 2 if info_ln else 1
            cols = ln.split()
            if len(cols) < 5: continue
            loc, peer = cols[3], cols[4]
            lport = loc.rsplit(":", 1)[-1]
            p_port = peer.rsplit(":", 1)[-1]
            pids = re.findall(r"pid=(\d+)", ln)
            if lport in ("22", "2222", "109", "143", "447"):
                u = next((pid_to_user.get(p) or auth_by_pid.get(p) for p in pids if p in pid_to_user or p in auth_by_pid), None) or auth_by_port.get(p_port)
                if not u: continue
                if p_port in ws_map:
                    w_entry = ws_map[p_port]
                    w_key = f"{p_port}:{w_entry.get('ip','')}"
                    active_ws_keys.add(w_key)
                    cur_b = int(w_entry.get("bytes", 0))
                    prev_b = state["ws"].get(w_key)
                    if prev_b is not None and cur_b > prev_b:
                        diff = cur_b - prev_b
                        if diff > 512:
                            deltas[u] = deltas.get(u, 0) + diff
                    state["ws"][w_key] = cur_b
                else:
                    s_key = f"{loc}->{peer}"
                    active_sock_keys.add(s_key)
                    m_ack = re.search(r"bytes_acked:(\d+)", info_ln)
                    m_rcv = re.search(r"bytes_received:(\d+)", info_ln)
                    cur_b = (int(m_ack.group(1)) if m_ack else 0) + (int(m_rcv.group(1)) if m_rcv else 0)
                    prev_b = state["sock"].get(s_key)
                    if prev_b is not None and cur_b > prev_b:
                        diff = cur_b - prev_b
                        if diff > 512:
                            deltas[u] = deltas.get(u, 0) + diff
                    state["sock"][s_key] = cur_b
    except Exception:
        pass

    state["ws"] = {k: v for k, v in state["ws"].items() if k in active_ws_keys}
    state["sock"] = {k: v for k, v in state["sock"].items() if k in active_sock_keys}
    return deltas

def query_xray_user_delta(valid_set):
    deltas = {}
    try:
        out = subprocess.check_output(["/usr/local/bin/xray", "api", "statsquery", "--server=127.0.0.1:10085", "-reset=true"], stderr=subprocess.DEVNULL, timeout=3).decode("utf-8", errors="ignore")
        for item in json.loads(out).get("stat", []):
            pts = item.get("name", "").split(">>>")
            val = int(item.get("value", 0))
            if val <= 0: continue
            if len(pts) == 4 and pts[0] == "user" and pts[1] in valid_set and pts[2] == "traffic":
                deltas[pts[1]] = deltas.get(pts[1], 0) + val
    except Exception:
        pass
    return deltas

def query_hysteria2_user_delta(valid_set):
    deltas = {}
    try:
        with urllib.request.urlopen("http://127.0.0.1:9999/traffic?clear=1", timeout=2) as r:
            for u, st in json.loads(r.read().decode()).items():
                if u in valid_set:
                    val = int(st.get("tx", 0)) + int(st.get("rx", 0))
                    if val > 0: deltas[u] = deltas.get(u, 0) + val
    except Exception:
        pass
    return deltas

def query_openvpn_user_delta(valid_set, state):
    deltas = {}
    active_keys = set()
    for ovpn_log in ("/var/log/openvpn-tcp.log", "/var/log/openvpn-udp.log"):
        if os.path.exists(ovpn_log):
            try:
                for ln in open(ovpn_log):
                    if ln.startswith("CLIENT_LIST"):
                        pts = ln.strip().split(",")
                        if len(pts) >= 7 and pts[1] in valid_set:
                            u, raddr, cur_b = pts[1], pts[2], int(pts[5]) + int(pts[6])
                            key = f"{ovpn_log}:{u}:{raddr}"
                            active_keys.add(key)
                            prev_b = state["ovpn"].get(key)
                            if prev_b is not None and cur_b > prev_b:
                                deltas[u] = deltas.get(u, 0) + (cur_b - prev_b)
                            state["ovpn"][key] = cur_b
            except Exception:
                pass
    state["ovpn"] = {k: v for k, v in state["ovpn"].items() if k in active_keys}
    return deltas

def hard_lock_user(uname):
    if uname in PROTECTED_USERS: return
    subprocess.call(["passwd", "-l", uname], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    subprocess.call(["usermod", "-s", "/usr/sbin/nologin", uname], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    subprocess.call(["pkill", "-9", "-u", uname], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

state = load_state()
active_users_ts = {}
while True:
    try:
        if os.path.exists(USERS_DB):
            rows = [l.strip().split("|") for l in open(USERS_DB) if "|" in l]
            unlocked_list = [r[0] for r in rows if len(r) >= 7 and r[6] == "UNLOCKED" and r[0] not in PROTECTED_USERS]
            if unlocked_list:
                valid_set = set(unlocked_list)
                ws_map = {}
                if os.path.exists(WS_MAP_FILE):
                    try: ws_map = json.loads(open(WS_MAP_FILE).read())
                    except Exception: ws_map = {}

                ssh_deltas = get_ssh_and_ws_deltas(valid_set, ws_map, state)
                xray_deltas = query_xray_user_delta(valid_set)
                hy2_deltas = query_hysteria2_user_delta(valid_set)
                ovpn_deltas = query_openvpn_user_delta(valid_set, state)
                save_state(state)

                now_ts = int(time.time())
                for u, val in xray_deltas.items():
                    if val > 0: active_users_ts[u] = now_ts
                try: json.dump(active_users_ts, open(ACTIVE_U_FILE, "w"))
                except Exception: pass

                today_str = datetime.date.today().strftime("%Y-%m-%d")
                need_xray_restart = False
                new_rows = []

                for r in rows:
                    if len(r) < 7: continue
                    uname, upass, uuid, q_gb, ip_lim, exp_date, status = r[:7]
                    if uname in PROTECTED_USERS: continue
                    u_file = os.path.join(USAGE_DIR, f"{uname}.bytes")
                    accum = read_int(u_file)

                    if status == "UNLOCKED":
                        real_delta = (
                            ssh_deltas.get(uname, 0)
                            + xray_deltas.get(uname, 0)
                            + hy2_deltas.get(uname, 0)
                            + ovpn_deltas.get(uname, 0)
                        )
                        if real_delta > 0:
                            accum += real_delta
                            write_int(u_file, accum)

                        if real_delta > 0 or not os.path.exists(os.path.join(USER_CONF_DIR, f"{uname}.conf")):
                            try:
                                open(os.path.join(USER_CONF_DIR, f"{uname}.conf"), "w").write(f"IP_LIMIT={ip_lim}\nGB_LIMIT={q_gb}\nUSED_MB={accum/(1024.0*1024.0):.2f}\n")
                            except Exception:
                                pass

                        if today_str > exp_date:
                            hard_lock_user(uname)
                            status = "EXPIRED"
                            need_xray_restart = True

                        try: q_f = float(q_gb or 0)
                        except Exception: q_f = 0.0
                        if status == "UNLOCKED" and q_f > 0 and accum >= int(q_f * 1073741824):
                            hard_lock_user(uname)
                            status = "QUOTA_FULL"
                            need_xray_restart = True

                    new_rows.append(f"{uname}|{upass}|{uuid}|{q_gb}|{ip_lim}|{exp_date}|{status}")
                _new_db = "\n".join(new_rows) + "\n"
                try: _old_db = open(USERS_DB).read()
                except Exception: _old_db = None
                if _old_db != _new_db:
                    open(USERS_DB, "w").write(_new_db)

                if need_xray_restart and os.path.exists(XRAY_CONF):
                    try:
                        unlock_rows2 = [r.split("|") for r in new_rows if r.endswith("|UNLOCKED")]
                        cfg = json.load(open(XRAY_CONF))
                        locked_set = {r.split("|")[0] for r in new_rows if not r.endswith("|UNLOCKED")}
                        for inb in cfg.get("inbounds", []):
                            clients = inb.get("settings", {}).get("clients", [])
                            if clients:
                                inb["settings"]["clients"] = [c for c in clients if c.get("email") not in locked_set]
                        json.dump(cfg, open(XRAY_CONF, "w"), indent=2)
                        subprocess.run(["systemctl", "restart", "xray"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                        # ZiVPN & Hysteria2 se bhi locked users hatao (warna UDP par locked user chalta rehta)
                        pws2 = []
                        for r2 in unlock_rows2:
                            if r2[1] not in pws2: pws2.append(r2[1])
                        if not pws2: pws2 = ["aliraza"]
                        json.dump({"listen": ":5667", "cert": "/etc/ssl/xray/fullchain.pem", "key": "/etc/ssl/xray/privkey.pem", "obfs": "zivpn", "auth": {"mode": "passwords", "config": pws2}}, open("/etc/zivpn/config.json", "w"), indent=2)
                        with open("/etc/hysteria/config.yaml", "w") as hf2:
                            hf2.write("listen: :20800\ntls:\n  cert: /etc/ssl/xray/fullchain.pem\n  key: /etc/ssl/xray/privkey.pem\nbandwidth:\n  up: 1 gbps\n  down: 1 gbps\ntrafficStats:\n  listen: 127.0.0.1:9999\nauth:\n  type: userpass\n  userpass:\n")
                            for r2 in (unlock_rows2 or [["aliraza", "aliraza"]]):
                                hf2.write(f"    {r2[0]}: {r2[1]}\n")
                        subprocess.run(["systemctl", "restart", "zivpn", "hysteria"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                    except Exception:
                        pass
    except Exception:
        pass
    time.sleep(2)
EOF
    chmod +x /usr/local/bin/zainu-enforcer
    cp -f /usr/local/bin/zainu-enforcer /usr/local/bin/autokill.py 2>/dev/null || true
    cat << 'EOF' > /etc/systemd/system/zainu-monitor.service
[Unit]
Description=ZAINU X BRAND Real Kernel Bandwidth & Auto-Lock Daemon
After=network.target
[Service]
Type=simple
User=root
ExecStart=/usr/bin/python3 /usr/local/bin/zainu-enforcer
Restart=always
RestartSec=2s
[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload && systemctl enable zainu-monitor 2>/dev/null && systemctl restart zainu-monitor 2>/dev/null || true
    legacy_cleanup_user_services
}

# Purane panel versions ka autokill.service (agar installed ho) GB double-count karta hai
legacy_cleanup_user_services() {
    systemctl stop autokill >/dev/null 2>&1 || true
    systemctl disable autokill >/dev/null 2>&1 || true
    rm -f /etc/systemd/system/autokill.service >/dev/null 2>&1 || true
    rm -f /etc/systemd/system/multi-user.target.wants/autokill.service >/dev/null 2>&1 || true
    systemctl daemon-reload >/dev/null 2>&1 || true
}
setup_cli_account_helper() {
    cat << 'EOF' > /usr/local/bin/zainu-cli
#!/usr/bin/env bash
ACTION="$1"
DATA_DIR="/etc/aliraza"; USAGE_DIR="/etc/aliraza/usage"; USERS_CONF_DIR="/etc/aliraza/users"
CLIENTS_DIR="/root/zainu-configs"; BUNNY_DIR="/root/zainu-configs/bunnycdn"; USERS_DB="/etc/aliraza/users.db"
XRAY_CONF="/usr/local/etc/xray/config.json"; SLOWDNS_DIR="/etc/slowdns"
mkdir -p "$USAGE_DIR" "$USERS_CONF_DIR" "$CLIENTS_DIR" "$BUNNY_DIR" /var/www/html

B3=$'\x60\x60\x60'; B1=$'\x60'

is_protected_user() {
    local u="$1"
    [[ -z "$u" ]] && return 0
    case "$u" in root|ubuntu|debian|admin|ec2-user|centos|rocky|almalinux|fedora|sshd|nobody|systemd-*|daemon|bin|sys|sync|haproxy|www-data) return 0 ;; esac
    id "$u" >/dev/null 2>&1 && [[ $(id -u "$u" 2>/dev/null || echo 0) -lt 1000 ]] && return 0
    return 1
}

sync_engines_py() {
    python3 - << 'PY' 2>/dev/null || true
import json, os
users_db = "/etc/aliraza/users.db"
xray_cfg = "/usr/local/etc/xray/config.json"
users, pws = [], []
if os.path.exists(users_db):
    for ln in open(users_db):
        pts = ln.strip().split("|")
        if len(pts) >= 7 and pts[6] == "UNLOCKED":
            users.append({"u": pts[0], "pw": pts[1], "uuid": pts[2]})
            if pts[1] not in pws: pws.append(pts[1])
if os.path.exists(xray_cfg):
    cfg = json.load(open(xray_cfg))
    for idx, ib in enumerate(cfg.get("inbounds", [])):
        if idx in (0, 1, 3, 4, 6, 7, 9, 10, 14, 15):
            ib["settings"]["clients"] = [{"id": x["uuid"], "email": x["u"], "level": 0} for x in users]
        elif idx in (2, 5, 8, 11):
            ib["settings"]["clients"] = [{"password": x["pw"], "email": x["u"], "level": 0} for x in users]
        elif idx in (12, 13):
            ib["settings"]["clients"] = [{"id": x["uuid"], "email": x["u"], "flow": "xtls-rprx-vision", "level": 0} for x in users]
        elif idx in (17, 18):
            ib["settings"]["accounts"] = [{"user": x["u"], "pass": x["pw"]} for x in users]
        elif idx == 19:
            ib["settings"]["clients"] = [{"password": x["pw"], "method": "chacha20-ietf-poly1305", "email": x["u"], "level": 0} for x in users]
    json.dump(cfg, open(xray_cfg, "w"), indent=2)
if not pws: pws = ["aliraza"]
os.makedirs("/etc/zivpn", exist_ok=True)
json.dump({"listen": ":5667", "cert": "/etc/ssl/xray/fullchain.pem", "key": "/etc/ssl/xray/privkey.pem", "obfs": "zivpn", "auth": {"mode": "passwords", "config": pws}}, open("/etc/zivpn/config.json", "w"), indent=2)
os.makedirs("/etc/hysteria", exist_ok=True)
with open("/etc/hysteria/config.yaml", "w") as hf:
    hf.write("listen: :20800\ntls:\n  cert: /etc/ssl/xray/fullchain.pem\n  key: /etc/ssl/xray/privkey.pem\nbandwidth:\n  up: 1 gbps\n  down: 1 gbps\ntrafficStats:\n  listen: 127.0.0.1:9999\nauth:\n  type: userpass\n  userpass:\n")
    for x in (users or [{"u": "aliraza", "pw": "aliraza"}]): hf.write(f"    {x['u']}: {x['pw']}\n")
PY
    systemctl restart xray zivpn hysteria >/dev/null 2>&1 || true
}

if [[ "$ACTION" == "create" || "$ACTION" == "regen" ]]; then
    USER_NAME=$(echo "$2" | tr -dc 'a-zA-Z0-9_-')
    USER_PASS="${3:-1234}"; QUOTA_GB="${4:-0}"; IP_LIMIT="${5:-2}"; VALID_DAYS="${6:-30}"
    is_protected_user "$USER_NAME" && { echo "[!] Protected user!"; exit 1; }
    OLD_LINE=$(grep "^${USER_NAME}|" "$USERS_DB" 2>/dev/null | head -n1 || true)
    if [[ "$ACTION" == "regen" && -n "$OLD_LINE" ]]; then
        UUID=$(echo "$OLD_LINE" | cut -d'|' -f3); EXP_DATE=$(echo "$OLD_LINE" | cut -d'|' -f6)
    else
        EXP_DATE=$(date -d "+${VALID_DAYS} days" +"%Y-%m-%d")
        [[ -n "$OLD_LINE" ]] && UUID=$(echo "$OLD_LINE" | cut -d'|' -f3) || UUID=$(/usr/local/bin/xray uuid 2>/dev/null || cat /proc/sys/kernel/random/uuid)
        echo "0" > "$USAGE_DIR/${USER_NAME}.bytes"
        printf "IP_LIMIT=%s\nGB_LIMIT=%s\nUSED_MB=0.00\n" "$IP_LIMIT" "$QUOTA_GB" > "$USERS_CONF_DIR/${USER_NAME}.conf"
        EXP_SYS=$(date -d "$EXP_DATE + 1 day" +"%Y-%m-%d" 2>/dev/null || echo "$EXP_DATE")
        useradd -e "$EXP_SYS" -M -s /bin/bash "$USER_NAME" >/dev/null 2>&1 || true
        usermod -s /bin/bash -p "$(openssl passwd -6 "$USER_PASS")" "$USER_NAME" >/dev/null 2>&1 || echo "$USER_NAME:$USER_PASS" | chpasswd -c SHA512 >/dev/null 2>&1
        passwd -u "$USER_NAME" >/dev/null 2>&1 || true
        chage -E "$EXP_SYS" "$USER_NAME" >/dev/null 2>&1 || true
        sed -i "/^${USER_NAME}|/d" "$USERS_DB" 2>/dev/null || true
        echo "${USER_NAME}|${USER_PASS}|${UUID}|${QUOTA_GB}|${IP_LIMIT}|${EXP_DATE}|UNLOCKED" >> "$USERS_DB"
        sync_engines_py
    fi

    VPS_IP=$(head -n1 "$DATA_DIR/vps_ip.txt" 2>/dev/null | tr -d '[:space:]'); [[ -z "$VPS_IP" ]] && VPS_IP=$(curl -s4 api.ipify.org)
    DOMAIN=$(head -n1 "$DATA_DIR/domain.txt" 2>/dev/null | tr -d '[:space:]'); [[ -z "$DOMAIN" ]] && DOMAIN="$VPS_IP"
    NS_DOMAIN=$(head -n1 "$DATA_DIR/ns_domain.txt" 2>/dev/null | tr -d '[:space:]'); [[ -z "$NS_DOMAIN" ]] && NS_DOMAIN="$DOMAIN"
    BUNNY_HOST=$(head -n1 "$DATA_DIR/bunny_host.txt" 2>/dev/null | tr -d '[:space:]'); [[ -z "$BUNNY_HOST" ]] && BUNNY_HOST="$DOMAIN"
    SLOWDNS_PUBKEY=$(head -n1 "$SLOWDNS_DIR/server.pub" 2>/dev/null | tr -d '[:space:]')
    REALITY_PUB=$(head -n1 "$DATA_DIR/reality_pub.txt" 2>/dev/null | tr -d '[:space:]')
    SS22_KEY=$(head -n1 "$DATA_DIR/ss2022_key.txt" 2>/dev/null | tr -d '[:space:]')

    VLESS_WS_TLS="vless://${UUID}@${DOMAIN}:443?path=%2Fvless&security=tls&encryption=none&host=${DOMAIN}&type=ws&sni=${DOMAIN}#${USER_NAME}-tls"
    VLESS_WS_80="vless://${UUID}@${DOMAIN}:80?path=%2Fvless&security=none&encryption=none&host=${DOMAIN}&type=ws&sni=${DOMAIN}#${USER_NAME}-ntls"
    VLESS_HUP_443="vless://${UUID}@${DOMAIN}:443?path=%2Fvless-hup&security=tls&encryption=none&host=${DOMAIN}&type=httpupgrade&sni=${DOMAIN}#${USER_NAME}-hup-tls"
    VLESS_HUP_80="vless://${UUID}@${DOMAIN}:80?path=%2Fvless-hup&security=none&encryption=none&host=${DOMAIN}&type=httpupgrade&sni=${DOMAIN}#${USER_NAME}-hup-ntls"
    VLESS_GRPC="vless://${UUID}@${DOMAIN}:443?mode=gun&security=tls&encryption=none&type=grpc&serviceName=zainu-vless-grpc&sni=${DOMAIN}#${USER_NAME}-grpc"
    VLESS_XHTTP_443="vless://${UUID}@${DOMAIN}:443?path=%2Fzainu-vless-xhttp&security=tls&encryption=none&mode=auto&type=xhttp&host=${DOMAIN}&sni=${DOMAIN}#${USER_NAME}-xhttp-tls"
    VLESS_XHTTP_80="vless://${UUID}@${DOMAIN}:80?path=%2Fzainu-vless-xhttp&security=none&encryption=none&mode=auto&type=xhttp&host=${DOMAIN}#${USER_NAME}-xhttp-ntls"
    VLESS_VISION_443="vless://${UUID}@${VPS_IP}:443?security=tls&encryption=none&flow=xtls-rprx-vision&type=tcp&sni=vision.${DOMAIN}&fp=chrome&allowInsecure=1#${USER_NAME}-vision"
    VLESS_REALITY_443="vless://${UUID}@${VPS_IP}:443?security=reality&encryption=none&pbk=${REALITY_PUB}&fp=chrome&type=tcp&flow=xtls-rprx-vision&sni=reality.${DOMAIN}&sid=6ba85179e30d4fc2#${USER_NAME}-reality"
    VLESS_MKCP_UDP="vless://${UUID}@${VPS_IP}:10014?security=none&encryption=none&type=kcp&headerType=none#${USER_NAME}-mkcp-udp"

    VMESS_WS_TLS="vmess://$(echo -n "{\"v\":\"2\",\"ps\":\"${USER_NAME}-vmess-tls\",\"add\":\"${DOMAIN}\",\"port\":\"443\",\"id\":\"${UUID}\",\"aid\":\"0\",\"net\":\"ws\",\"path\":\"/vmess\",\"type\":\"none\",\"host\":\"${DOMAIN}\",\"tls\":\"tls\",\"sni\":\"${DOMAIN}\"}" | base64 -w 0)"
    VMESS_WS_80="vmess://$(echo -n "{\"v\":\"2\",\"ps\":\"${USER_NAME}-vmess-ntls\",\"add\":\"${DOMAIN}\",\"port\":\"80\",\"id\":\"${UUID}\",\"aid\":\"0\",\"net\":\"ws\",\"path\":\"/vmess\",\"type\":\"none\",\"host\":\"${DOMAIN}\",\"tls\":\"none\"}" | base64 -w 0)"
    VMESS_HUP="vmess://$(echo -n "{\"v\":\"2\",\"ps\":\"${USER_NAME}-vmess-hup-tls\",\"add\":\"${DOMAIN}\",\"port\":\"443\",\"id\":\"${UUID}\",\"aid\":\"0\",\"net\":\"httpupgrade\",\"path\":\"/vmess-hup\",\"type\":\"none\",\"host\":\"${DOMAIN}\",\"tls\":\"tls\",\"sni\":\"${DOMAIN}\"}" | base64 -w 0)"
    VMESS_GRPC="vmess://$(echo -n "{\"v\":\"2\",\"ps\":\"${USER_NAME}-vmess-grpc\",\"add\":\"${DOMAIN}\",\"port\":\"443\",\"id\":\"${UUID}\",\"aid\":\"0\",\"net\":\"grpc\",\"path\":\"zainu-vmess-grpc\",\"type\":\"gun\",\"host\":\"${DOMAIN}\",\"tls\":\"tls\",\"sni\":\"${DOMAIN}\"}" | base64 -w 0)"
    VMESS_XHTTP="vmess://$(echo -n "{\"v\":\"2\",\"ps\":\"${USER_NAME}-vmess-xhttp\",\"add\":\"${DOMAIN}\",\"port\":\"443\",\"id\":\"${UUID}\",\"aid\":\"0\",\"net\":\"xhttp\",\"path\":\"/zainu-vmess-xhttp\",\"type\":\"auto\",\"host\":\"${DOMAIN}\",\"tls\":\"tls\",\"sni\":\"${DOMAIN}\"}" | base64 -w 0)"

    TROJAN_WS_TLS="trojan://${USER_PASS}@${DOMAIN}:443?path=%2Ftrojan&security=tls&host=${DOMAIN}&type=ws&sni=${DOMAIN}#${USER_NAME}-trojan-tls"
    TROJAN_WS_80="trojan://${USER_PASS}@${DOMAIN}:80?path=%2Ftrojan&security=none&host=${DOMAIN}&type=ws&sni=${DOMAIN}#${USER_NAME}-trojan-ntls"
    TROJAN_HUP="trojan://${USER_PASS}@${DOMAIN}:443?path=%2Ftrojan-hup&security=tls&host=${DOMAIN}&type=httpupgrade&sni=${DOMAIN}#${USER_NAME}-trojan-hup-tls"
    TROJAN_GRPC="trojan://${USER_PASS}@${DOMAIN}:443?mode=gun&security=tls&type=grpc&serviceName=zainu-trojan-grpc&sni=${DOMAIN}#${USER_NAME}-trojan-grpc"
    TROJAN_XHTTP="trojan://${USER_PASS}@${DOMAIN}:443?path=%2Fzainu-trojan-xhttp&security=tls&mode=auto&type=xhttp&host=${DOMAIN}&sni=${DOMAIN}#${USER_NAME}-trojan-xhttp"
    SS_LINK="ss://$(echo -n "chacha20-ietf-poly1305:${USER_PASS}" | base64 -w 0)@${DOMAIN}:8888#${USER_NAME}-ss"
    SS2022_LINK="ss://$(echo -n "2022-blake3-aes-128-gcm:${SS22_KEY}" | base64 -w 0)@${VPS_IP}:10015#${USER_NAME}-ss2022"
    HY2_LINK="hysteria2://${USER_NAME}:${USER_PASS}@${DOMAIN}:20800?insecure=1&sni=${DOMAIN}#${USER_NAME}-hysteria2"

    OUT_FILE="${CLIENTS_DIR}/${USER_NAME}.txt"
    blk() { printf "━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n   %s\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n%s\n%s\n%s\n\n" "$1" "$B3" "$2" "$B3"; }
    {
        printf "━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n   👑 ZAINU X BRAND VIP 👑\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n"
        printf "• Username : %s%s%s\n• Password : %s%s%s\n• UUID     : %s%s%s\n" "$B1" "$USER_NAME" "$B1" "$B1" "$USER_PASS" "$B1" "$B1" "$UUID" "$B1"
        printf "• Quota GB : %s GB (0=Unlim)\n• IP Limit : %s Devices\n• Expiry   : %s\n" "$QUOTA_GB" "$IP_LIMIT" "$EXP_DATE"
        printf "• Host/SNI : %s%s%s\n• BunnyCDN : %s%s%s\n• Server IP: %s%s%s\n\n" "$B1" "$DOMAIN" "$B1" "$B1" "$BUNNY_HOST" "$B1" "$B1" "$VPS_IP" "$B1"
        blk "SSH SSL / TLS 443" "${DOMAIN}:443@${USER_NAME}:${USER_PASS}"
        blk "SSH NTLS / HTTP 80" "${DOMAIN}:80@${USER_NAME}:${USER_PASS}"
        blk "ZiVPN UDP & UDP Custom" "ZiVPN Host/IP : ${VPS_IP} (Ports: 5667 / 6000-19999)
ZiVPN Pass    : ${USER_PASS}
UDP Custom    : ${VPS_IP}:22@${USER_NAME}:${USER_PASS} (Port 1-32767)"
        blk "SSH WS Payload" "GET / HTTP/1.1[crlf]Host: ${DOMAIN}[crlf]Upgrade: websocket[crlf]Connection: Keep-Alive[crlf][crlf]"
        blk "SlowDNS (DNSTT)" "DNS : https://dns.google/dns-query
NS  : ${NS_DOMAIN}
Key : ${SLOWDNS_PUBKEY}"
        blk "Link TLS" "$VLESS_WS_TLS"
        blk "Link NTLS" "$VLESS_WS_80"
        blk "Link HUP-TLS" "$VLESS_HUP_443"
        blk "Link HUP-NTLS" "$VLESS_HUP_80"
        blk "Link gRPC-TLS" "$VLESS_GRPC"
        blk "Link XHTTP-TLS" "$VLESS_XHTTP_443"
        blk "Link XHTTP-NTLS" "$VLESS_XHTTP_80"
        blk "VLESS Vision TLS (443)" "$VLESS_VISION_443"
        blk "VLESS Reality (443)" "$VLESS_REALITY_443"
        blk "VLESS mKCP UDP (10014)" "$VLESS_MKCP_UDP"
        blk "VMess Link TLS" "$VMESS_WS_TLS"
        blk "VMess Link NTLS" "$VMESS_WS_80"
        blk "VMess Link HUP-TLS" "$VMESS_HUP"
        blk "VMess Link gRPC-TLS" "$VMESS_GRPC"
        blk "VMess Link XHTTP-TLS" "$VMESS_XHTTP"
        blk "Trojan Link TLS" "$TROJAN_WS_TLS"
        blk "Trojan Link NTLS" "$TROJAN_WS_80"
        blk "Trojan Link HUP-TLS" "$TROJAN_HUP"
        blk "Trojan Link gRPC-TLS" "$TROJAN_GRPC"
        blk "Trojan Link XHTTP-TLS" "$TROJAN_XHTTP"
        blk "Hysteria2 / SS2022 / Socks5" "${HY2_LINK}
${SS2022_LINK}
${SS_LINK}
Socks5: ${VPS_IP}:10808@${USER_NAME}:${USER_PASS}
HTTP  : ${VPS_IP}:10809@${USER_NAME}:${USER_PASS}"
        printf "━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n📢 Telegram: @aliraza\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n"
    } > "$OUT_FILE"

    BUNNY_FILE="${BUNNY_DIR}/${USER_NAME}-bunnycdn.txt"
    B_VMESS_TLS="vmess://$(echo -n "{\"v\":\"2\",\"ps\":\"${USER_NAME}-bunny-tls\",\"add\":\"${BUNNY_HOST}\",\"port\":\"443\",\"id\":\"${UUID}\",\"aid\":\"0\",\"net\":\"ws\",\"path\":\"/vmess\",\"type\":\"none\",\"host\":\"${BUNNY_HOST}\",\"tls\":\"tls\",\"sni\":\"${BUNNY_HOST}\"}" | base64 -w 0)"
    B_VMESS_80="vmess://$(echo -n "{\"v\":\"2\",\"ps\":\"${USER_NAME}-bunny-80\",\"add\":\"${BUNNY_HOST}\",\"port\":\"80\",\"id\":\"${UUID}\",\"aid\":\"0\",\"net\":\"ws\",\"path\":\"/vmess\",\"type\":\"none\",\"host\":\"${BUNNY_HOST}\",\"tls\":\"none\"}" | base64 -w 0)"
    {
        printf "━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n  🐰 ZAINU X BRAND BUNNY-CDN 🐰\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n"
        printf "• Username   : %s%s%s\n• Password   : %s%s%s\n• UUID       : %s%s%s\n" "$B1" "$USER_NAME" "$B1" "$B1" "$USER_PASS" "$B1" "$B1" "$UUID" "$B1"
        printf "• Bunny Host : %s%s%s\n• Origin IP  : %s%s%s\n• Expiry     : %s\n\n" "$B1" "$BUNNY_HOST" "$B1" "$B1" "$VPS_IP" "$B1" "$EXP_DATE"
        blk "BunnyCDN SSH-SSL (443)" "${BUNNY_HOST}:443@${USER_NAME}:${USER_PASS}"
        blk "BunnyCDN SSH-WS (80)" "${BUNNY_HOST}:80@${USER_NAME}:${USER_PASS}"
        blk "BunnyCDN WS Payload" "GET / HTTP/1.1[crlf]Host: ${BUNNY_HOST}[crlf]Upgrade: websocket[crlf]Connection: Upgrade[crlf][crlf]"
        blk "BunnyCDN VLESS-WS TLS (443)" "vless://${UUID}@${BUNNY_HOST}:443?path=%2Fvless&security=tls&encryption=none&host=${BUNNY_HOST}&type=ws&sni=${BUNNY_HOST}#${USER_NAME}-Bunny-TLS"
        blk "BunnyCDN VLESS-WS HTTP (80)" "vless://${UUID}@${BUNNY_HOST}:80?path=%2Fvless&security=none&encryption=none&host=${BUNNY_HOST}&type=ws#${USER_NAME}-Bunny-80"
        blk "BunnyCDN VLESS-HUP TLS (443)" "vless://${UUID}@${BUNNY_HOST}:443?path=%2Fvless-hup&security=tls&encryption=none&host=${BUNNY_HOST}&type=httpupgrade&sni=${BUNNY_HOST}#${USER_NAME}-Bunny-HUP"
        blk "BunnyCDN VLESS-XHTTP (443)" "vless://${UUID}@${BUNNY_HOST}:443?path=%2Fzainu-vless-xhttp&security=tls&encryption=none&mode=auto&type=xhttp&host=${BUNNY_HOST}&sni=${BUNNY_HOST}#${USER_NAME}-Bunny-XHTTP"
        blk "BunnyCDN VMess-WS TLS (443)" "$B_VMESS_TLS"
        blk "BunnyCDN VMess-WS HTTP (80)" "$B_VMESS_80"
        blk "BunnyCDN Trojan-WS TLS (443)" "trojan://${USER_PASS}@${BUNNY_HOST}:443?path=%2Ftrojan&security=tls&host=${BUNNY_HOST}&type=ws&sni=${BUNNY_HOST}#${USER_NAME}-Bunny-Trojan"
        printf "━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n📢 Telegram: @aliraza\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n"
    } > "$BUNNY_FILE"

    python3 - "$OUT_FILE" "/var/www/html/zainu-${USER_NAME}.html" "$USER_NAME" << 'PY' 2>/dev/null || true
import sys, html, json
txt = open(sys.argv[1]).read()
page = f"""<!DOCTYPE html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>ZAINU X BRAND - {sys.argv[3]}</title><style>body{{background:#0d0221;color:#fff;font-family:sans-serif;padding:15px;margin:0}}.btn{{display:block;width:100%;padding:16px;background:linear-gradient(90deg,#ff007f,#7928ca);color:#fff;font-size:17px;font-weight:bold;border:none;border-radius:10px;cursor:pointer;margin-bottom:15px}}pre{{background:#190a36;padding:12px;border-radius:8px;overflow-x:auto;font-size:12px;border:1px solid #7928ca;white-space:pre}}</style></head><body><button class="btn" onclick="navigator.clipboard.writeText({json.dumps(txt)}).then(()=>this.innerText='✅ COPIED!')">📋 1-CLICK COPY FULL TELEGRAM POST</button><pre>{html.escape(txt)}</pre></body></html>"""
open(sys.argv[2], "w").write(page)
PY
    python3 - "$BUNNY_FILE" "/var/www/html/zainu-${USER_NAME}-bunny.html" "${USER_NAME} (BunnyCDN)" << 'PY' 2>/dev/null || true
import sys, html, json
txt = open(sys.argv[1]).read()
page = f"""<!DOCTYPE html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>BUNNY CDN - {sys.argv[3]}</title><style>body{{background:#0d0221;color:#fff;font-family:sans-serif;padding:15px;margin:0}}.btn{{display:block;width:100%;padding:16px;background:linear-gradient(90deg,#ff7700,#ff0055);color:#fff;font-size:17px;font-weight:bold;border:none;border-radius:10px;cursor:pointer;margin-bottom:15px}}pre{{background:#190a36;padding:12px;border-radius:8px;overflow-x:auto;font-size:12px;border:1px solid #ff7700;white-space:pre}}</style></head><body><button class="btn" onclick="navigator.clipboard.writeText({json.dumps(txt)}).then(()=>this.innerText='✅ BUNNY CDN COPIED!')">🐰 1-CLICK COPY BUNNY-CDN CONFIG</button><pre>{html.escape(txt)}</pre></body></html>"""
open(sys.argv[2], "w").write(page)
PY

    if [[ "$ACTION" == "create" ]]; then
        cat "$OUT_FILE"
        echo -e "\n\033[1;92m[★] MAIN 1-CLICK COPY LINK  : \033[1;96mhttp://${DOMAIN}/zainu-${USER_NAME}.html\033[0m"
        echo -e "\033[1;93m[🐰] BUNNY-CDN SEPARATE FILE : \033[1;92m${BUNNY_FILE}\033[0m"
        echo -e "\033[1;93m[🐰] BUNNY-CDN 1-CLICK LINK  : \033[1;96mhttp://${DOMAIN}/zainu-${USER_NAME}-bunny.html\033[0m"
    fi
elif [[ "$ACTION" == "lock" ]]; then
    L_USER="$2"; is_protected_user "$L_USER" && exit 1
    passwd -l "$L_USER" >/dev/null 2>&1 || true; usermod -s /usr/sbin/nologin "$L_USER" >/dev/null 2>&1 || true; pkill -9 -u "$L_USER" >/dev/null 2>&1 || true
    sed -i "s/^\(${L_USER}|.*|\)UNLOCKED/\1LOCKED/" "$USERS_DB" 2>/dev/null || true
    sync_engines_py
    echo "LOCKED:$L_USER"
elif [[ "$ACTION" == "unlock" ]]; then
    U_USER="$2"; NEW_DAYS="${3:-30}"; is_protected_user "$U_USER" && exit 1
    LINE=$(grep "^${U_USER}|" "$USERS_DB" 2>/dev/null | head -n1 || true)
    if [[ -n "$LINE" ]]; then
        UPASS=$(echo "$LINE" | cut -d'|' -f2); UUID=$(echo "$LINE" | cut -d'|' -f3); OLD_QUOTA="${4:-$(echo "$LINE" | cut -d'|' -f4)}"; OLD_IPLIM="${5:-$(echo "$LINE" | cut -d'|' -f5)}"
        NEW_EXP=$(date -d "+${NEW_DAYS} days" +"%Y-%m-%d")
        echo "0" > "$USAGE_DIR/${U_USER}.bytes"
        usermod -s /bin/bash -p "$(openssl passwd -6 "$UPASS")" "$U_USER" >/dev/null 2>&1 || true
        passwd -u "$U_USER" >/dev/null 2>&1 || true
        chage -E "$(date -d "$NEW_EXP + 1 day" +"%Y-%m-%d" 2>/dev/null || echo "$NEW_EXP")" "$U_USER" >/dev/null 2>&1 || true
        sed -i "s/^${U_USER}|.*/${U_USER}|${UPASS}|${UUID}|${OLD_QUOTA}|${OLD_IPLIM}|${NEW_EXP}|UNLOCKED/" "$USERS_DB"
        sync_engines_py
        /usr/local/bin/zainu-cli regen "$U_USER" "$UPASS" "$OLD_QUOTA" "$OLD_IPLIM" >/dev/null 2>&1 || true
        echo "UNLOCKED:$U_USER:$NEW_EXP"
    fi
elif [[ "$ACTION" == "delete" ]]; then
    D_USER="$2"; is_protected_user "$D_USER" && exit 1
    pkill -9 -u "$D_USER" >/dev/null 2>&1 || true; userdel -rf "$D_USER" >/dev/null 2>&1 || true
    sed -i "/^${D_USER}|/d" "$USERS_DB" 2>/dev/null || true
    sync_engines_py
    rm -f "${CLIENTS_DIR}/${D_USER}.txt" "${CLIENTS_DIR}/${D_USER}-bunnycdn.txt" "${BUNNY_DIR}/${D_USER}-bunnycdn.txt" "$USAGE_DIR/${D_USER}.bytes" "$USERS_CONF_DIR/${D_USER}.conf" "/var/www/html/zainu-${D_USER}.html" "/var/www/html/zainu-${D_USER}-bunny.html"
    echo "DELETED:$D_USER"
fi
EOF
    chmod +x /usr/local/bin/zainu-cli
}

regenerate_all_user_files() {
    rm -f "$CLIENTS_DIR"/*-bunnycdn.txt 2>/dev/null || true
    if [[ -s "$USERS_DB" ]]; then
        while IFS='|' read -r uname upass uuid q_gb ip_lim exp_date status; do
            [[ -n "$uname" ]] && /usr/local/bin/zainu-cli regen "$uname" "$upass" "$q_gb" "$ip_lim" >/dev/null 2>&1 || true
        done < "$USERS_DB"
    fi
}

# ============================================================================
# STYLISH VIP TELEGRAM BOT (HYBRID TAP-BUTTONS + CUSTOM TEXT INPUT WIZARD!)
# ============================================================================
setup_telegram_bot_daemon() {
    cat << 'EOF' > /usr/local/bin/zainu-tgbot.py
#!/usr/bin/env python3
import os, time, json, urllib.request, subprocess, random

TG_CONF = "/etc/aliraza/tgbot.conf"
TG_ADMINS = "/etc/aliraza/tg_admins.txt"
USERS_DB = "/etc/aliraza/users.db"
USAGE_DIR = "/etc/aliraza/usage"
CLIENTS_DIR = "/root/zainu-configs"
BUNNY_DIR = "/root/zainu-configs/bunnycdn"

def load_conf():
    if os.path.exists(TG_CONF):
        for l in open(TG_CONF):
            if l.startswith("TOKEN="): return l.strip().split("=", 1)[1]
    return ""

def get_admins():
    return {int(l.strip()) for l in open(TG_ADMINS) if l.strip().isdigit()} if os.path.exists(TG_ADMINS) else set()

def api_call(token, method, data=None):
    try:
        req = urllib.request.Request(
            f"https://api.telegram.org/bot{token}/{method}",
            data=json.dumps(data).encode() if data else None,
            headers={"Content-Type": "application/json"} if data else {}
        )
        with urllib.request.urlopen(req, timeout=35) as r:
            return json.loads(r.read().decode())
    except Exception:
        return {}

def send_msg(token, cid, text, reply_markup=None, parse_mode="Markdown"):
    payload = {"chat_id": cid, "text": text}
    if parse_mode: payload["parse_mode"] = parse_mode
    if reply_markup: payload["reply_markup"] = reply_markup
    res = api_call(token, "sendMessage", payload)
    if not res.get("ok") and parse_mode:
        payload.pop("parse_mode", None)
        api_call(token, "sendMessage", payload)

def send_long_markdown(token, cid, text, reply_markup=None):
    chunks, cur = [], ""
    for block in text.split("\n\n"):
        if len(cur) + len(block) + 2 > 3800:
            chunks.append(cur)
            cur = block
        else:
            cur = (cur + "\n\n" + block) if cur else block
    if cur: chunks.append(cur)
    for i, ch in enumerate(chunks):
        rm = reply_markup if i == len(chunks) - 1 else None
        send_msg(token, cid, ch, rm, "Markdown")

def fmt_b(b):
    b = float(b or 0)
    if b >= 1073741824: return f"{b/1073741824:.2f} GB"
    if b >= 1048576: return f"{b/1048576:.2f} MB"
    if b >= 1024: return f"{b/1024:.2f} KB"
    return f"{int(b)} B"

def main_kb():
    return {"inline_keyboard": [
        [{"text": "⚡ Create VIP Account", "callback_data": "create_vip"}, {"text": "⏱️ Fast 24h Trial", "callback_data": "create_trial"}],
        [{"text": "📊 Real GB & Live SIM IPs", "callback_data": "live_stats"}, {"text": "📋 All Accounts List", "callback_data": "list_users"}],
        [{"text": "📂 View User / Bunny Config", "callback_data": "view_cfg"}, {"text": "🔄 Renew / Edit GB", "callback_data": "renew_user"}],
        [{"text": "🔒 Lock User", "callback_data": "lock_user"}, {"text": "🔓 Unlock User", "callback_data": "unlock_user"}, {"text": "🗑️ Delete User", "callback_data": "del_user"}],
        [{"text": "🖥️ Server Status", "callback_data": "srv_status"}, {"text": "♻️ Restart All", "callback_data": "restart_all"}, {"text": "🧹 Clean RAM", "callback_data": "clean_ram"}]
    ]}

def cancel_kb(rows=None):
    kb = list(rows) if rows else []
    kb.append([{"text": "🔙 Cancel / Main Menu", "callback_data": "menu_home"}])
    return {"inline_keyboard": kb}

def user_buttons_kb(prefix):
    rows, cur = [], []
    if os.path.exists(USERS_DB):
        for ln in open(USERS_DB):
            pts = ln.strip().split("|")
            if len(pts) >= 7 and pts[0]:
                cur.append({"text": f"👤 {pts[0]}", "callback_data": f"{prefix}:{pts[0]}"})
                if len(cur) == 3:
                    rows.append(cur); cur = []
    if cur: rows.append(cur)
    return cancel_kb(rows)

def get_pass_kb(uname):
    return cancel_kb([
        [{"text": "🔑 1234", "callback_data": "set_pass:1234"}, {"text": "🔑 1122", "callback_data": "set_pass:1122"}, {"text": f"🔑 {uname}", "callback_data": f"set_pass:{uname}"}]
    ])

def get_gb_kb():
    return cancel_kb([
        [{"text": "📦 5 GB", "callback_data": "set_gb:5"}, {"text": "📦 10 GB", "callback_data": "set_gb:10"}, {"text": "📦 25 GB", "callback_data": "set_gb:25"}],
        [{"text": "📦 50 GB", "callback_data": "set_gb:50"}, {"text": "📦 100 GB", "callback_data": "set_gb:100"}, {"text": "♾️ Unlimited (0)", "callback_data": "set_gb:0"}]
    ])

def get_ip_kb():
    return cancel_kb([
        [{"text": "📱 1 IP", "callback_data": "set_ip:1"}, {"text": "📱 2 IPs", "callback_data": "set_ip:2"}, {"text": "📱 3 IPs", "callback_data": "set_ip:3"}],
        [{"text": "📱 5 IPs", "callback_data": "set_ip:5"}, {"text": "📱 10 IPs", "callback_data": "set_ip:10"}, {"text": "📱 50 IPs", "callback_data": "set_ip:50"}]
    ])

def get_days_kb():
    return cancel_kb([
        [{"text": "📅 1 Day", "callback_data": "set_days:1"}, {"text": "📅 3 Days", "callback_data": "set_days:3"}, {"text": "📅 7 Days", "callback_data": "set_days:7"}],
        [{"text": "📅 15 Days", "callback_data": "set_days:15"}, {"text": "📅 30 Days", "callback_data": "set_days:30"}, {"text": "📅 60 Days", "callback_data": "set_days:60"}]
    ])

def get_live_ips():
    # v55.4: shared AUTH-ONLY REAL SIM IP engine (fake CDN IPs filtered)
    try:
        out = subprocess.getoutput("python3 /usr/local/bin/zainu-liveips.py --bot 2>/dev/null").strip()
        if out:
            return out
        return out
    except Exception:
        pass
    cmd = r"""python3 -c '
import os, json, subprocess, re, datetime, ipaddress, pwd, time
USERS_DB="/etc/aliraza/users.db"; WS_MAP="/run/zainu_ws_map.json"; ACT_U="/run/zainu_active_users.json"
vu=[l.strip().split("|")[0] for l in open(USERS_DB) if len(l.strip().split("|"))>=7 and l.strip().split("|")[6]=="UNLOCKED"] if os.path.exists(USERS_DB) else []
if not vu: raise SystemExit()
vset=set(vu); du=vu[0]
vip=open("/etc/aliraza/vps_ip.txt").read().strip() if os.path.exists("/etc/aliraza/vps_ip.txt") else ""
def ok(ip):
    ip=str(ip).strip().strip("[]").replace("::ffff:","")
    if not ip or ip==vip: return False
    try: a=ipaddress.ip_address(ip); return a.is_global and not (a.is_private or a.is_loopback)
    except: return False
peers={}
def add(ip,pr,u):
    ip=str(ip).strip().strip("[]").replace("::ffff:","")
    if ok(ip): peers.setdefault(ip,set()).add(f"{pr}({u if u in vset else du})")
wm=json.loads(open(WS_MAP).read()) if os.path.exists(WS_MAP) else {}
am=json.loads(open(ACT_U).read()) if os.path.exists(ACT_U) else {}
now_ts=int(time.time())
rx_u=next((u for u,ts in sorted(am.items(),key=lambda x:-x[1]) if u in vset and now_ts-ts<30),None)
_ap={}
for _ln2 in subprocess.getoutput("tail -n 200 /var/log/auth.log 2>/dev/null").splitlines():
    if "Accepted password for" in _ln2 or "Password auth succeeded" in _ln2:
        _mu=re.search(r"for '([^']+)'",_ln2) or re.search(r"for (\S+)",_ln2)
        _mp=re.search(r"from [0-9a-fA-F:\.]+(?::| port )(\d+)",_ln2)
        if _mu and _mp and _mu.group(1) in vset: _ap[_mp.group(1)]=_mu.group(1)
for k,we in wm.items():
    if we.get("open",True):
        m=we.get("mode","SSH-WS")
        if any(x in m for x in ("XRAY","VLESS","VMESS","TROJAN")):
            if rx_u: add(we.get("ip",""),m,rx_u)
        else:
            uu=_ap.get(k) or (du if now_ts-int(we.get("ts",now_ts) or now_ts)<15 else None)
            if uu: add(we.get("ip",""),m,uu)
for ln in subprocess.getoutput("ss -tnp state established").splitlines()[1:]:
    cs=ln.split()
    if len(cs)>=5:
        lp=cs[3].rsplit(":",1)[-1]; pip=cs[4].rsplit(":",1)[0].strip("[]").replace("::ffff:","")
        if lp in ("22","2222","109","143","447","444","8443","8444","10013") and ok(pip):
            add(pip,f"PORT-{lp}",rx_u or du)
for ip,prs in sorted(peers.items()): print(f"• {ip} -> {','.join(sorted(prs))}")
'"""
    return subprocess.getoutput(cmd).strip()

def finish_wizard(token, cid, st):
    act = st.get("act", "create")
    u = st["u"]; pw = st.get("pw", "1234"); gb = st.get("gb", "0"); ip = st.get("ip", "2"); days = st.get("days", "30")
    if act == "create":
        subprocess.getoutput(f"/usr/local/bin/zainu-cli create {u} {pw} {gb} {ip} {days}")
        cfg_p = f"{CLIENTS_DIR}/{u}.txt"
        if os.path.exists(cfg_p):
            kb = {"inline_keyboard": [
                [{"text": f"🐰 View {u} BunnyCDN File", "callback_data": f"show_bunny:{u}"}],
                [{"text": "🏠 Back to Main Menu", "callback_data": "menu_home"}]
            ]}
            send_long_markdown(token, cid, open(cfg_p).read(), kb)
        else:
            send_msg(token, cid, "❌ Account create nahi ho saka!", main_kb())
    elif act == "renew":
        subprocess.getoutput(f"/usr/local/bin/zainu-cli unlock {u} {days} {gb} {ip}")
        send_msg(token, cid, f"✅ *Account Renewed & Quota Reset!*\n• User: `{u}`\n• Quota: `{gb} GB` | Max IP: `{ip}` | Days: `{days}`", main_kb())

def handle_step_input(token, cid, uid, state, val):
    st = state.get(uid)
    if not st: return False
    step = st.get("step", "")
    if step == "c_user":
        u = "".join(c for c in val if c.isalnum() or c in "_-")
        if not u or u in ("root", "ubuntu", "admin", "sshd"):
            send_msg(token, cid, "⚠️ Invalid ya protected username! Dusra naam likhein:", cancel_kb())
            return True
        st["u"] = u
        if st.get("act") == "renew":
            st["step"] = "c_gb"
            send_msg(token, cid, f"👤 User: `{u}`\n📦 *Step 2/4:* Naya GB Limit button tap karein ya chat me number likhein (0 = Unlimited):", get_gb_kb())
        else:
            st["step"] = "c_pass"
            send_msg(token, cid, f"👤 Username: `{u}`\n🔑 *Step 2/5:* Password button tap karein ya apni marzi ka password likh kar bhejein:", get_pass_kb(u))
        return True
    elif step == "c_pass":
        st["pw"] = val.strip() or "1234"
        st["step"] = "c_gb"
        send_msg(token, cid, f"🔑 Password: `{st['pw']}`\n📦 *Step 3/5:* Total GB Limit button tap karein ya khud number likh kar bhejein (0 = Unlimited):", get_gb_kb())
        return True
    elif step == "c_gb":
        gb = "".join(c for c in val if c.isdigit() or c == ".") or "0"
        st["gb"] = gb
        st["step"] = "c_ip"
        send_msg(token, cid, f"📦 Quota: `{gb} GB`\n📱 *Step 4/5:* Max IP / Device Limit button tap karein ya khud number likh kar bhejein:", get_ip_kb())
        return True
    elif step == "c_ip":
        ip_l = "".join(c for c in val if c.isdigit()) or "2"
        st["ip"] = ip_l
        st["step"] = "c_days"
        send_msg(token, cid, f"📱 IP Limit: `{ip_l} Devices`\n📅 *Step 5/5:* Validity Days button tap karein ya khud din likh kar bhejein:", get_days_kb())
        return True
    elif step == "c_days":
        days = "".join(c for c in val if c.isdigit()) or "30"
        st["days"] = days
        state.pop(uid, None)
        finish_wizard(token, cid, st)
        return True
    elif step in ("lock_user", "unlock_user", "del_user", "view_cfg"):
        u = val.strip().split()[0]
        state.pop(uid, None)
        if step == "lock_user":
            out = subprocess.getoutput(f"/usr/local/bin/zainu-cli lock {u}")
            send_msg(token, cid, f"🔒 `{out}`", main_kb())
        elif step == "unlock_user":
            out = subprocess.getoutput(f"/usr/local/bin/zainu-cli unlock {u} 30")
            send_msg(token, cid, f"🔓 `{out}`", main_kb())
        elif step == "del_user":
            out = subprocess.getoutput(f"/usr/local/bin/zainu-cli delete {u}")
            send_msg(token, cid, f"🗑️ `{out}`", main_kb())
        elif step == "view_cfg":
            kb = {"inline_keyboard": [
                [{"text": f"📄 {u} Main Config", "callback_data": f"show_main:{u}"}, {"text": f"🐰 {u} BunnyCDN File", "callback_data": f"show_bunny:{u}"}],
                [{"text": "🏠 Main Menu", "callback_data": "menu_home"}]
            ]}
            send_msg(token, cid, f"📂 Select Config File for `{u}`:", kb)
        return True
    return False

def main():
    state, offset = {}, 0
    while True:
        token = load_conf()
        if not token:
            time.sleep(5); continue
        for upd in api_call(token, "getUpdates", {"offset": offset, "timeout": 25}).get("result", []):
            offset = upd["update_id"] + 1
            admins = get_admins()
            if "callback_query" in upd:
                cb = upd["callback_query"]
                uid = cb["from"]["id"]
                cid = cb["message"]["chat"]["id"]
                d = cb.get("data", "")
                api_call(token, "answerCallbackQuery", {"callback_query_id": cb["id"]})
                if uid not in admins: continue

                if d == "menu_home":
                    state.pop(uid, None)
                    send_msg(token, cid, "👑 *ZAINU X BRAND VIP BOT PANEL*\nNeeche diye gaye buttons se control karein:", main_kb())
                elif d == "create_vip":
                    state[uid] = {"act": "create", "step": "c_user"}
                    kb = cancel_kb([[{"text": "🎲 Generate Random Username", "callback_data": f"set_user:vip{random.randint(1000,9999)}"}]])
                    send_msg(token, cid, "👤 *Step 1/5:* Naya Username chat me likh kar bhejein (ya Random button tap karein):", kb)
                elif d == "renew_user":
                    state[uid] = {"act": "renew", "step": "c_user"}
                    send_msg(token, cid, "🔄 *Renew / Edit Account:*\nNeeche user button tap karein ya username likh kar bhejein:", user_buttons_kb("set_user"))
                elif d.startswith("set_user:"):
                    handle_step_input(token, cid, uid, state, d.split(":", 1)[1])
                elif d.startswith("set_pass:"):
                    handle_step_input(token, cid, uid, state, d.split(":", 1)[1])
                elif d.startswith("set_gb:"):
                    handle_step_input(token, cid, uid, state, d.split(":", 1)[1])
                elif d.startswith("set_ip:"):
                    handle_step_input(token, cid, uid, state, d.split(":", 1)[1])
                elif d.startswith("set_days:"):
                    handle_step_input(token, cid, uid, state, d.split(":", 1)[1])
                elif d == "create_trial":
                    uname = f"trial{random.randint(1000,9999)}"
                    subprocess.getoutput(f"/usr/local/bin/zainu-cli create {uname} 1234 2 1 1")
                    kb = {"inline_keyboard": [
                        [{"text": f"🐰 View {uname} BunnyCDN File", "callback_data": f"show_bunny:{uname}"}],
                        [{"text": "🏠 Main Menu", "callback_data": "menu_home"}]
                    ]}
                    send_long_markdown(token, cid, open(f"{CLIENTS_DIR}/{uname}.txt").read(), kb)
                elif d in ("live_stats", "list_users"):
                    lines = ["📊 *REAL-TIME GB & LIVE SIM IPs:*"]
                    if os.path.exists(USERS_DB):
                        for r in open(USERS_DB):
                            pts = r.strip().split("|")
                            if len(pts) >= 7 and pts[0]:
                                ub = int(open(f"{USAGE_DIR}/{pts[0]}.bytes").read().strip() or 0) if os.path.exists(f"{USAGE_DIR}/{pts[0]}.bytes") else 0
                                lim = f"{pts[3]} GB" if float(pts[3] or 0) > 0 else "Unlim"
                                lines.append(f"👤 `{pts[0]}` ({pts[6]}) ➔ `{fmt_b(ub)} / {lim}` (Exp: {pts[5]})")
                    ips_txt = get_live_ips()
                    lines.append("\n🌐 *LIVE CONNECTED SIM IPs:*")
                    lines.append(f"```\n{ips_txt if ips_txt else '0 Clients Connected'}\n```")
                    send_msg(token, cid, "\n".join(lines), main_kb())
                elif d == "view_cfg":
                    state[uid] = {"step": "view_cfg"}
                    send_msg(token, cid, "📂 *View Config:* User button tap karein ya username likh kar bhejein:", user_buttons_kb("pick_cfg"))
                elif d.startswith("pick_cfg:"):
                    handle_step_input(token, cid, uid, state, d.split(":", 1)[1])
                elif d.startswith("show_main:"):
                    u = d.split(":", 1)[1]
                    p = f"{CLIENTS_DIR}/{u}.txt"
                    if os.path.exists(p): send_long_markdown(token, cid, open(p).read(), main_kb())
                    else: send_msg(token, cid, "❌ File nahi mili!", main_kb())
                elif d.startswith("show_bunny:"):
                    u = d.split(":", 1)[1]
                    p = f"{BUNNY_DIR}/{u}-bunnycdn.txt"
                    if os.path.exists(p): send_long_markdown(token, cid, open(p).read(), main_kb())
                    else: send_msg(token, cid, "❌ BunnyCDN file nahi mili!", main_kb())
                elif d in ("lock_user", "unlock_user", "del_user"):
                    state[uid] = {"step": d}
                    send_msg(token, cid, f"👤 Neeche user button tap karein ya username likh kar bhejein:", user_buttons_kb(f"do_{d}"))
                elif d.startswith("do_lock_user:") or d.startswith("do_unlock_user:") or d.startswith("do_del_user:"):
                    act_k, u = d.split(":", 1)
                    state[uid] = {"step": act_k.replace("do_", "")}
                    handle_step_input(token, cid, uid, state, u)
                elif d == "srv_status":
                    ram = subprocess.getoutput("free -m | awk '/Mem:/ {print $3\"/\"$2\" MB\"}'")
                    up = subprocess.getoutput("uptime -p")
                    dom = open("/etc/aliraza/domain.txt").read().strip() if os.path.exists("/etc/aliraza/domain.txt") else "Not-Set"
                    vip = open("/etc/aliraza/vps_ip.txt").read().strip() if os.path.exists("/etc/aliraza/vps_ip.txt") else ""
                    send_msg(token, cid, f"🖥️ *SERVER LIVE STATUS:*\n• IP: `{vip}`\n• Domain: `{dom}`\n• RAM: `{ram}`\n• Uptime: `{up}`", main_kb())
                elif d == "restart_all":
                    subprocess.Popen("systemctl restart dropbear nginx zainu-ws haproxy xray zivpn hysteria udp-custom badvpn slowdns stunnel4 zainu-monitor", shell=True)
                    send_msg(token, cid, "♻️ *All Services Restarted Successfully!*", main_kb())
                elif d == "clean_ram":
                    subprocess.Popen("sync; echo 3 > /proc/sys/vm/drop_caches; > /var/log/xray/access.log", shell=True)
                    send_msg(token, cid, "🧹 *RAM Cache & Logs Cleaned Safely!*", main_kb())
                continue

            msg = upd.get("message", {})
            if not msg or "text" not in msg: continue
            uid = msg["from"]["id"]
            cid = msg["chat"]["id"]
            txt = msg["text"].strip()
            if uid not in admins: continue
            if txt in ("/start", "/menu"):
                state.pop(uid, None)
                send_msg(token, cid, "👑 *ZAINU X BRAND VIP BOT PANEL*\nNeeche diye gaye buttons se control karein:", main_kb())
                continue
            if not handle_step_input(token, cid, uid, state, txt):
                send_msg(token, cid, "👑 *ZAINU X BRAND VIP BOT PANEL*", main_kb())

if __name__ == "__main__":
    main()
EOF
    chmod +x /usr/local/bin/zainu-tgbot.py
    cat << 'EOF' > /etc/systemd/system/zainu-tgbot.service
[Unit]
Description=ZAINU X BRAND Telegram Bot
After=network.target
[Service]
Type=simple
User=root
ExecStart=/usr/bin/python3 /usr/local/bin/zainu-tgbot.py
Restart=always
RestartSec=3s
[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    [[ -s "$TG_CONF" ]] && systemctl restart zainu-tgbot 2>/dev/null || true
}
# ============================================================================
# ALIRAZA WEB PANEL LAYER
# ============================================================================
SELF_PATH="$(readlink -f "$0" 2>/dev/null || echo "$0")"
CORE_PATH="/usr/local/bin/aliraza-core.sh"
PANEL_BIN="/usr/local/bin/aliraza-panel.py"
PANEL_CONF="/etc/aliraza/panel.conf"
RESERVED_PORTS=" 22 53 80 109 143 443 444 447 992 1194 2052 2053 2082 2083 2086 2087 2095 2096 2200 2222 5300 5667 7100 7200 7300 8080 8081 8082 8442 8443 8880 9999 10000 10001 10002 10003 10004 10005 10006 10007 10008 10009 10010 10011 10012 10013 10014 10015 10808 20010 20800 36712 "

panel_conf_get() { grep -m1 "^$1=" "$PANEL_CONF" 2>/dev/null | cut -d= -f2-; }

panel_port_ok() {
    local p="$1"
    [[ "$p" =~ ^[0-9]+$ ]] && (( p >= 1024 && p <= 65535 )) || { echo "Port 1024-65535 ke beech hona chahiye"; return 1; }
    [[ "$RESERVED_PORTS" == *" $p "* ]] && { echo "Port $p VPN protocols ke liye reserved hai"; return 1; }
    if ss -tln 2>/dev/null | grep -qE ":${p}\b"; then
        [[ "$(panel_conf_get PANEL_PORT)" == "$p" ]] && systemctl is-active --quiet aliraza-panel 2>/dev/null && return 0
        echo "Port $p pehle se kisi aur service ne use kiya hua hai"; return 1
    fi
    return 0
}

panel_hash_pw() { # $1 password -> prints "salt hash"
    PW="$1" python3 -c 'import os,secrets,hashlib;s=secrets.token_hex(16);print(s,hashlib.pbkdf2_hmac("sha256",os.environ["PW"].encode(),bytes.fromhex(s),200000).hex())'
}

panel_save_conf() { # user port pass
    local U="$1" P="$2" PW="$3" S H TLS
    read -r S H < <(panel_hash_pw "$PW")
    TLS=$(panel_conf_get PANEL_TLS); TLS="${TLS:-1}"
    mkdir -p "$DATA_DIR"
    printf 'PANEL_USER=%s\nPANEL_PORT=%s\nPANEL_TLS=%s\nPANEL_SALT=%s\nPANEL_HASH=%s\n' "$U" "$P" "$TLS" "$S" "$H" > "$PANEL_CONF"
    chmod 600 "$PANEL_CONF"
}

ask_panel_credentials() {
    local IN_PORT IN_USER IN_P1 IN_P2 MSG
    while true; do
        read -rp " • Panel Port [8686]: " IN_PORT || exit 1
        IN_PORT="${IN_PORT:-8686}"
        MSG=$(panel_port_ok "$IN_PORT") && break
        echo -e "   ${RED}[!] ${MSG}${NC}"
    done
    while true; do
        read -rp " • Panel Username [admin]: " IN_USER || exit 1
        IN_USER="${IN_USER:-admin}"
        [[ "$IN_USER" =~ ^[a-zA-Z0-9_-]{3,32}$ ]] && break
        echo -e "   ${RED}[!] Username 3-32 chars: a-z A-Z 0-9 _ -${NC}"
    done
    while true; do
        read -rsp " • Panel Password (min 6): " IN_P1 || exit 1; echo ""
        [[ ${#IN_P1} -lt 6 ]] && { echo -e "   ${RED}[!] Password kam az kam 6 characters ka ho${NC}"; continue; }
        read -rsp " • Password dobara likhein : " IN_P2 || exit 1; echo ""
        [[ "$IN_P1" == "$IN_P2" ]] && break
        echo -e "   ${RED}[!] Dono password match nahi hue${NC}"
    done
    PANEL_PORT_IN="$IN_PORT"; PANEL_USER_IN="$IN_USER"; PANEL_PASS_IN="$IN_P1"
    panel_save_conf "$IN_USER" "$IN_PORT" "$IN_P1"
}

install_web_panel() {
    mkdir -p /var/log/aliraza-panel
    cat << 'PANEL_PY_EOF' > "$PANEL_BIN"
#!/usr/bin/env python3
# AliRaza Web Panel - stdlib only (no pip needed)
import os, sys, json, time, re, hmac, hashlib, secrets, subprocess, threading, ssl, shutil, socket
from http.server import ThreadingHTTPServer, BaseHTTPRequestHandler
from urllib.parse import urlparse, parse_qs

ZDATA = os.environ.get("ZDATA", "/etc/aliraza")
CONF = os.environ.get("PANEL_CONF", ZDATA + "/panel.conf")
CORE = os.environ.get("ZCORE", "/usr/local/bin/aliraza-core.sh")
ZCLI = os.environ.get("ZCLI", "/usr/local/bin/zainu-cli")
LIVEIPS = os.environ.get("ZLIVEIPS", "/usr/local/bin/zainu-liveips.py")
USERS_DB = ZDATA + "/users.db"
USAGE = ZDATA + "/usage"
CLIENTS = os.environ.get("ZCLIENTS", "/root/zainu-configs")
BUNNY = CLIENTS + "/bunnycdn"
JOB_DIR = os.environ.get("JOB_DIR", "/var/log/aliraza-panel")
CERT, KEY = "/etc/ssl/xray/fullchain.pem", "/etc/ssl/xray/privkey.pem"
ANSI = re.compile(r"\x1b\[[0-9;?]*[a-zA-Z]")
RE_USER = re.compile(r"^[a-zA-Z0-9_-]{1,32}$")
RE_PASS = re.compile(r"^[A-Za-z0-9_@#%+=:.-]{1,64}$")
RE_HOST = re.compile(r"^[A-Za-z0-9]([A-Za-z0-9.-]{0,250}[A-Za-z0-9])?$")
os.makedirs(JOB_DIR, exist_ok=True)

SERVICES = [
    ("ssh", "tcp", 22, "OpenSSH (22/2222)"), ("dropbear", "tcp", 109, "AliRaza+server Dropbear (109/143/447)"),
    ("stunnel4", "tcp", 444, "Stunnel SSL (444/8443/992)"), ("zainu-ws", "tcp", 10000, "Golang WS Engine (10000)"),
    ("haproxy", "tcp", 80, "HAProxy HTTP Mux (80/8080/8880/2052/2082)"), ("haproxy", "tcp", 443, "HAProxy TLS Mux (443/2053/2083/2087/2096)"),
    ("xray", "tcp", 10001, "Xray WS/gRPC/HUP"), ("xray", "tcp", 10010, "Xray Native XHTTP"),
    ("xray", "tcp", 10013, "Xray Reality & Vision"), ("xray", "udp", 10014, "Xray VLESS mKCP UDP"),
    ("xray", "tcp", 10015, "Shadowsocks-2022 & AEAD"), ("xray", "tcp", 10808, "Socks5 & HTTP Proxy"),
    ("openvpn-server@server-tcp", "tcp", 1194, "OpenVPN TCP/UDP (1194/2200)"), ("zivpn", "udp", 5667, "ZiVPN UDP (5667)"),
    ("udp-custom", "udp", 36712, "SSH UDP Custom (36712)"), ("hysteria", "udp", 20800, "Hysteria 2 QUIC (20800)"),
    ("slowdns", "udp", 5300, "SlowDNS Server (53/5300)"),
]
RESTARTABLE = {"ssh", "dropbear", "stunnel4", "zainu-ws", "haproxy", "nginx", "xray", "zivpn", "hysteria",
               "udp-custom", "badvpn", "slowdns", "zainu-monitor", "zainu-tgbot", "openvpn-server@server-tcp", "openvpn-server@server-udp"}

# ---------------- helpers ----------------
def clean(s): return ANSI.sub("", s or "").replace("\r", "")

def sh(args, timeout=60, shell=False):
    try:
        p = subprocess.run(args, shell=shell, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=timeout)
        return p.returncode, clean(p.stdout.decode("utf-8", "replace"))
    except subprocess.TimeoutExpired:
        return 124, "Timeout"
    except Exception as e:
        return 1, str(e)

def core(fn, *args, timeout=180): return sh(["bash", CORE, "--fn", fn] + [str(a) for a in args], timeout=timeout)

def rd(path, default=""):
    try:
        with open(path, errors="ignore") as f: return f.read().strip()
    except Exception: return default

def rd1(path, default=""):
    return (rd(path, default).splitlines() or [default])[0].strip()

def load_conf():
    d = {}
    for ln in rd(CONF).splitlines():
        if "=" in ln and not ln.startswith("#"):
            k, v = ln.split("=", 1); d[k.strip()] = v.strip()
    return d

def hash_pw(pw, salt): return hashlib.pbkdf2_hmac("sha256", pw.encode(), bytes.fromhex(salt), 200000).hex()

def save_conf(d):
    tmp = CONF + ".tmp"
    with open(tmp, "w") as f:
        for k, v in d.items(): f.write("%s=%s\n" % (k, v))
    os.chmod(tmp, 0o600); os.replace(tmp, CONF)

_cache = {}
def cached(key, ttl, fn):
    now = time.time(); c = _cache.get(key)
    if c and now - c[0] < ttl: return c[1]
    v = fn(); _cache[key] = (now, v); return v

# ---------------- data ----------------
def vps_ip():
    ip = rd1(ZDATA + "/vps_ip.txt")
    if ip and ip != "127.0.0.1": return ip
    rc, out = sh("curl -s4 --max-time 3 api.ipify.org", timeout=6, shell=True)
    return out.strip() if rc == 0 and out.strip() else "Unknown"

def ping_ms():
    rc, out = sh(["ping", "-c", "1", "-W", "1", "8.8.8.8"], timeout=4)
    m = re.search(r"time=([0-9.]+)", out)
    return float(m.group(1)) if m else None

def dns_a(host):
    rc, out = sh(["dig", "+short", "+time=2", "+tries=1", "A", host, "@8.8.8.8"], timeout=6)
    ips = [x for x in out.split() if re.match(r"^\d+\.\d+\.\d+\.\d+$", x)]
    return ips[-1] if ips else ""

def dom_status(dom, ip):
    if not dom or dom == "Not-Set": return "NOT SET"
    if dom == ip: return "IP ONLY"
    a = cached("dom:" + dom, 60, lambda: dns_a(dom))
    if not a: return "NOT POINTED"
    return "POINTED" if a == ip else "OTHER IP (%s)" % a

def load_users():
    rows = []
    for ln in rd(USERS_DB).splitlines():
        p = ln.strip().split("|")
        if len(p) >= 7 and p[0]:
            try: used = int(re.sub(r"\D", "", rd1("%s/%s.bytes" % (USAGE, p[0]), "0")) or 0)
            except Exception: used = 0
            try: q = int(p[3])
            except Exception: q = 0
            rows.append({"username": p[0], "password": p[1], "quota_gb": q, "ip_limit": p[4], "expiry": p[5], "status": p[6], "used": used})
    return rows

def live_ips():
    def f():
        rc, out = sh(["python3", LIVEIPS], timeout=20)
        res = []
        for ln in out.splitlines():
            p = ln.split("|")
            if len(p) >= 4 and re.match(r"^[0-9a-fA-F:.]+$", p[1]): res.append({"ip": p[1], "ports": p[2], "tunnels": p[3]})
        return res
    return cached("live", 4, f)

def svc_status():
    def f():
        rc, tcp = sh("ss -tln", timeout=5, shell=True); rc, udp = sh("ss -uln", timeout=5, shell=True)
        res = []
        for svc, proto, port, label in SERVICES:
            rc, _ = sh(["systemctl", "is-active", "--quiet", svc], timeout=5)
            listen = re.search(r":%d\b" % port, tcp if proto == "tcp" else udp) is not None
            res.append({"service": svc, "label": label, "port": port, "proto": proto, "live": rc == 0 and listen})
        return res
    return cached("svc", 5, f)

def sysinfo():
    mem = {}
    for ln in rd("/proc/meminfo").splitlines():
        k, _, v = ln.partition(":"); mem[k] = int(v.split()[0]) // 1024 if v.split() else 0
    total = mem.get("MemTotal", 0); used = total - mem.get("MemAvailable", 0)
    du = shutil.disk_usage("/")
    up = float((rd("/proc/uptime") or "0 0").split()[0])
    la = (rd("/proc/loadavg") or "0 0 0").split()[:3]
    ip = vps_ip()
    dom = rd1(ZDATA + "/domain.txt", "Not-Set") or "Not-Set"
    ns = rd1(ZDATA + "/ns_domain.txt", "Not-Set") or "Not-Set"
    bh = rd1(ZDATA + "/bunny_host.txt", "Not-Set") or "Not-Set"
    users = load_users(); live = live_ips()
    return {
        "ip": ip, "provider": cached("prov", 3600, lambda: rd1(ZDATA + "/provider.txt", "Cloud VPS")),
        "ping": cached("ping", 15, ping_ms), "cpus": os.cpu_count() or 1, "load": la,
        "ram_used": used, "ram_total": total, "disk_used": du.used // 2**30, "disk_total": du.total // 2**30,
        "uptime": int(up), "domain": dom, "domain_status": dom_status(dom, ip), "ns": ns, "bunny": bh,
        "users": len(users), "locked": sum(1 for u in users if u["status"] != "UNLOCKED"),
        "used_bytes": sum(u["used"] for u in users), "limit_gb": sum(u["quota_gb"] for u in users),
        "live": len(live), "tg": os.path.exists(ZDATA + "/tgbot.conf"),
    }

# ---------------- jobs ----------------
JOBS = {}
JLOCK = threading.Lock()

def start_job(title, fn, *args):
    with JLOCK:
        for j in JOBS.values():
            if j["running"]: return None, j["id"]
        jid = secrets.token_hex(4)
        log = "%s/job-%s.log" % (JOB_DIR, jid)
        cmd = "bash %s --fn %s %s </dev/null >%s 2>&1; echo \"::EXIT:$?\" >>%s" % (
            CORE, fn, " ".join(shlex_quote(a) for a in args), log, log)
        JOBS[jid] = {"id": jid, "title": title, "log": log, "running": True, "started": time.time()}
        open(log, "w").close()
        if shutil.which("systemd-run"):
            rc, out = sh(["systemd-run", "--quiet", "--collect", "--unit=aliraza-job-" + jid, "bash", "-c", cmd], timeout=15)
            if rc != 0: subprocess.Popen(["bash", "-c", cmd], start_new_session=True)
        else:
            subprocess.Popen(["bash", "-c", cmd], start_new_session=True)
        return jid, None

def shlex_quote(s):
    return "'" + str(s).replace("'", "'\"'\"'") + "'"

def job_state(jid):
    j = JOBS.get(jid)
    if not j: return None
    txt = clean(rd(j["log"]))
    done = re.search(r"::EXIT:(\d+)", txt)
    if done or (time.time() - j["started"] > 3600): j["running"] = False
    txt = re.sub(r"\n?::EXIT:\d+\s*$", "", txt)
    return {"id": jid, "title": j["title"], "running": j["running"], "exit": int(done.group(1)) if done else None, "log": txt[-20000:]}

# ---------------- auth ----------------
SESS = {}; FAILS = {}
SLOCK = threading.Lock()

def new_session():
    t = secrets.token_urlsafe(32)
    with SLOCK:
        SESS[t] = time.time() + 12 * 3600
        for k in [k for k, v in SESS.items() if v < time.time()]: SESS.pop(k, None)
    return t

# ---------------- API ----------------
def api(h, method, path, q, body):
    P = lambda k, d="": str(body.get(k, d)).strip()
    if path == "/api/dashboard": return 200, sysinfo()
    if path == "/api/users":
        us = load_users(); live = live_ips()
        for u in us:
            u["live"] = sum(1 for l in live if "(%s)" % u["username"] in l["ports"])
            u.pop("password", None)
        return 200, {"users": us}
    if path == "/api/user/create":
        u, p = P("username"), P("password", "1234") or "1234"
        if not RE_USER.match(u): return 400, {"error": "Username: sirf a-z A-Z 0-9 _ - (max 32)"}
        if not RE_PASS.match(p): return 400, {"error": "Password me sirf A-Z a-z 0-9 _ @ # % + = : . - allowed hain"}
        if any(x["username"] == u for x in load_users()): return 400, {"error": "Username pehle se maujood hai"}
        try: gb, ipl, days = int(P("quota", 0) or 0), int(P("ip_limit", 2) or 2), int(P("days", 30) or 30)
        except ValueError: return 400, {"error": "GB / IP / Days numbers hone chahiye"}
        rc, out = sh([ZCLI, "create", u, p, str(gb), str(ipl), str(days)], timeout=120)
        return 200, {"ok": rc == 0, "output": out}
    if path == "/api/user/trial":
        u = "trial%d" % (secrets.randbelow(9000) + 1000)
        rc, out = sh([ZCLI, "create", u, "1234", "2", "1", "1"], timeout=120)
        return 200, {"ok": rc == 0, "output": out}
    if path in ("/api/user/lock", "/api/user/unlock", "/api/user/delete", "/api/user/renew"):
        u = P("username")
        if not RE_USER.match(u) or not any(x["username"] == u for x in load_users()): return 400, {"error": "User nahi mila"}
        act = path.rsplit("/", 1)[1]
        try: days = int(P("days", 30) or 30)
        except ValueError: return 400, {"error": "Days number hona chahiye"}
        if act == "lock": rc, out = sh([ZCLI, "lock", u], timeout=60)
        elif act == "delete": rc, out = sh([ZCLI, "delete", u], timeout=60)
        elif act == "unlock": rc, out = sh([ZCLI, "unlock", u, str(days)], timeout=120)
        else:
            try: gb, ipl = int(P("quota", 0) or 0), int(P("ip_limit", 2) or 2)
            except ValueError: return 400, {"error": "GB / IP numbers hone chahiye"}
            rc, out = core("panel_renew_user", u, gb, ipl, days, "1" if body.get("reset", True) else "0")
        return 200, {"ok": rc == 0, "output": out}
    if path == "/api/user/config":
        u, kind = q.get("username", [""])[0], q.get("type", ["main"])[0]
        if not RE_USER.match(u) or not any(x["username"] == u for x in load_users()): return 400, {"error": "User nahi mila"}
        f = "%s/%s-bunnycdn.txt" % (BUNNY, u) if kind == "bunny" else "%s/%s.txt" % (CLIENTS, u)
        dom = rd1(ZDATA + "/domain.txt")
        link = "http://%s/zainu-%s%s.html" % (dom, u, "-bunny" if kind == "bunny" else "")
        return 200, {"config": rd(f, "Config file nahi mili"), "link": link}
    if path == "/api/live": return 200, {"live": live_ips()}
    if path == "/api/services": return 200, {"services": svc_status()}
    if path == "/api/service/restart":
        s = P("name")
        if s not in RESTARTABLE: return 400, {"error": "Invalid service"}
        rc, out = sh(["systemctl", "restart", s], timeout=60); _cache.pop("svc", None)
        return 200, {"ok": rc == 0, "output": out or "Restarted: " + s}
    if path == "/api/domain":
        ip = vps_ip(); dom = rd1(ZDATA + "/domain.txt"); ns = rd1(ZDATA + "/ns_domain.txt")
        rc, cert = sh("openssl x509 -in /etc/ssl/xray/fullchain.pem -noout -issuer -enddate 2>/dev/null", timeout=8, shell=True)
        return 200, {"ip": ip, "domain": dom, "domain_status": dom_status(dom, ip), "ns": ns, "cert": cert.strip()}
    if path == "/api/domain/set":
        d, n = P("domain"), P("ns")
        if d and not RE_HOST.match(d): return 400, {"error": "Domain galat hai"}
        if n and not RE_HOST.match(n): return 400, {"error": "NS domain galat hai"}
        jid, busy = start_job("Domain / SSL apply", "panel_apply_domain", d, n)
        return 200, {"job": jid} if jid else (409, {"error": "Pehle se ek job chal raha hai", "job": busy})
    if path == "/api/ssl/renew":
        jid, busy = start_job("SSL Renew", "panel_renew_ssl")
        return 200, {"job": jid} if jid else (409, {"error": "Pehle se ek job chal raha hai", "job": busy})
    if path == "/api/banner":
        return 200, {"banner": rd("/etc/issue.net")}
    if path == "/api/banner/set":
        txt = str(body.get("banner", ""))
        if len(txt) > 20000: return 400, {"error": "Banner bohat bara hai"}
        with open("/etc/issue.net", "w") as f: f.write(txt + "\n")
        os.chmod("/etc/issue.net", 0o644)
        rc, out = core("panel_apply_banner")
        return 200, {"ok": rc == 0, "output": out or "Banner apply ho gaya (SSH + Dropbear)"}
    if path == "/api/banner/default":
        rc, out = core("panel_default_banner")
        return 200, {"ok": rc == 0, "output": out or "Default AliRaza+server banner apply ho gaya", "banner": rd("/etc/issue.net")}
    if path == "/api/bunny":
        return 200, {"host": rd1(ZDATA + "/bunny_host.txt"), "ip": vps_ip(), "guide": rd(ZDATA + "/bunnycdn.conf")}
    if path == "/api/bunny/set":
        h_ = P("host")
        if not RE_HOST.match(h_): return 400, {"error": "Hostname galat hai"}
        jid, busy = start_job("Bunny CDN setup", "panel_set_bunny", h_)
        return 200, {"job": jid} if jid else (409, {"error": "Pehle se ek job chal raha hai", "job": busy})
    if path == "/api/bunny/regen":
        jid, busy = start_job("Regenerate user files", "panel_regen_files")
        return 200, {"job": jid} if jid else (409, {"error": "Pehle se ek job chal raha hai", "job": busy})
    if path == "/api/telegram":
        rc, act = sh(["systemctl", "is-active", "zainu-tgbot"], timeout=5)
        return 200, {"configured": os.path.exists(ZDATA + "/tgbot.conf"), "active": act.strip() == "active", "admin": rd1(ZDATA + "/tg_admins.txt")}
    if path == "/api/telegram/set":
        t, uid = P("token"), P("uid")
        if not re.match(r"^\d{6,12}:[A-Za-z0-9_-]{30,50}$", t) or not re.match(r"^\d{5,15}$", uid): return 400, {"error": "Token ya UID ka format galat hai"}
        rc, out = core("panel_set_tg", t, uid, timeout=120)
        return 200, {"ok": rc == 0, "output": out or "Telegram bot connected. Telegram par /start bhejein."}
    if path == "/api/telegram/ctl":
        a = P("action")
        if a not in ("restart", "stop"): return 400, {"error": "Invalid"}
        rc, out = sh(["systemctl", a, "zainu-tgbot"], timeout=30)
        return 200, {"ok": rc == 0, "output": out or a + " done"}
    if path == "/api/action":
        a = P("name")
        table = {"restart_all": ("Restart All Services", "restart_all_services_menu", []),
                 "autodoctor": ("Auto-Doctor Fix", "smart_auto_doctor", []),
                 "clean": ("Clean RAM / Logs", "clean_ram_and_logs", []),
                 "reinstall": ("Re-Install All", "panel_reinstall", []),
                 "udp_test": ("UDP Firewall Test (15s)", "panel_udp_test", []),
                 "speedtest": ("VPS Speedtest", "panel_speedtest", []),
                 "uninstall": ("Clean Uninstall", "panel_uninstall", [])}
        if a.startswith("slowdns_"):
            opt = a.split("_", 1)[1]
            if opt not in ("1", "2", "3"): return 400, {"error": "Invalid"}
            ent = ("SlowDNS / UDP Reinstall", "panel_slowdns_target", [opt])
        elif a in table: ent = table[a]
        else: return 400, {"error": "Invalid action"}
        if a == "uninstall" and P("confirm") != "DELETE": return 400, {"error": "Confirm ke liye DELETE likhein"}
        jid, busy = start_job(ent[0], ent[1], *ent[2])
        return 200, {"job": jid} if jid else (409, {"error": "Pehle se ek job chal raha hai", "job": busy})
    if path == "/api/job":
        jid = q.get("id", [""])[0]
        if not jid:
            run = [j for j in JOBS.values()]
            jid = sorted(run, key=lambda j: j["started"])[-1]["id"] if run else ""
        st = job_state(jid) if jid else None
        return 200, st or {"none": True}
    if path == "/api/password":
        c = load_conf()
        if not hmac.compare_digest(hash_pw(P("current"), c.get("PANEL_SALT", "00")), c.get("PANEL_HASH", "")): return 403, {"error": "Current password galat hai"}
        nu, np_ = P("new_username") or c.get("PANEL_USER"), P("new")
        if not RE_USER.match(nu): return 400, {"error": "Username galat hai"}
        if len(np_) < 6: return 400, {"error": "Naya password kam az kam 6 characters ka ho"}
        salt = secrets.token_hex(16); c.update({"PANEL_USER": nu, "PANEL_SALT": salt, "PANEL_HASH": hash_pw(np_, salt)}); save_conf(c)
        with SLOCK: SESS.clear()
        return 200, {"ok": True, "output": "Credentials update ho gaye. Dobara login karein."}
    return 404, {"error": "Not found"}

# ---------------- HTTP ----------------
class H(BaseHTTPRequestHandler):
    server_version = "AliRazaPanel"
    timeout = 60
    def log_message(self, *a): pass
    def _send(self, code, data, ctype="application/json", extra=None):
        b = data if isinstance(data, bytes) else (json.dumps(data) if ctype == "application/json" else data).encode()
        self.send_response(code)
        self.send_header("Content-Type", ctype + "; charset=utf-8"); self.send_header("Content-Length", str(len(b)))
        self.send_header("Cache-Control", "no-store"); self.send_header("X-Frame-Options", "DENY")
        self.send_header("X-Content-Type-Options", "nosniff"); self.send_header("Referrer-Policy", "no-referrer")
        self.send_header("Content-Security-Policy", "default-src 'self'; style-src 'unsafe-inline'; script-src 'unsafe-inline'; img-src data:")
        for k, v in (extra or {}).items(): self.send_header(k, v)
        self.end_headers(); self.wfile.write(b)
    def _tok(self):
        for part in (self.headers.get("Cookie") or "").split(";"):
            k, _, v = part.strip().partition("=")
            if k == "ar_sess": return v
        return ""
    def _authed(self):
        t = self._tok()
        with SLOCK: return SESS.get(t, 0) > time.time()
    def _ip(self): return self.client_address[0]
    def do_GET(self):
        u = urlparse(self.path)
        if u.path == "/": return self._send(200, PAGE, "text/html")
        if not u.path.startswith("/api/") or u.path in ("/api/login",): return self._send(404, {"error": "Not found"})
        if not self._authed(): return self._send(401, {"error": "Login required"})
        try: code, data = api(self, "GET", u.path, parse_qs(u.query), {})
        except Exception as e: code, data = 500, {"error": str(e)}
        self._send(code, data)
    def do_POST(self):
        u = urlparse(self.path)
        if "application/json" not in (self.headers.get("Content-Type") or "") or self.headers.get("X-Requested-With") != "AliRazaPanel":
            return self._send(400, {"error": "Bad request"})
        try:
            n = int(self.headers.get("Content-Length") or 0)
            body = json.loads(self.rfile.read(min(n, 200000)) or b"{}")
        except Exception: return self._send(400, {"error": "Bad JSON"})
        if u.path == "/api/login":
            ip = self._ip(); now = time.time()
            with SLOCK:
                f = [t for t in FAILS.get(ip, []) if now - t < 300]; FAILS[ip] = f
            if len(f) >= 5: return self._send(429, {"error": "Bohat ghalat koshishen. 5 minute baad try karein."})
            c = load_conf()
            ok = hmac.compare_digest(str(body.get("username", "")), c.get("PANEL_USER", "")) and \
                 hmac.compare_digest(hash_pw(str(body.get("password", "")), c.get("PANEL_SALT", "00")), c.get("PANEL_HASH", ""))
            if not ok:
                with SLOCK: FAILS[ip].append(now)
                time.sleep(1); return self._send(403, {"error": "Username ya password galat hai"})
            t = new_session(); flags = "; Secure" if self.server.is_tls else ""
            return self._send(200, {"ok": True}, extra={"Set-Cookie": "ar_sess=%s; Path=/; HttpOnly; SameSite=Strict; Max-Age=43200%s" % (t, flags)})
        if u.path == "/api/logout":
            with SLOCK: SESS.pop(self._tok(), None)
            return self._send(200, {"ok": True}, extra={"Set-Cookie": "ar_sess=; Path=/; Max-Age=0"})
        if not self._authed(): return self._send(401, {"error": "Login required"})
        try: code, data = api(self, "POST", u.path, parse_qs(u.query), body)
        except Exception as e: code, data = 500, {"error": str(e)}
        self._send(code, data)

class Srv(ThreadingHTTPServer):
    daemon_threads = True; allow_reuse_address = True; is_tls = False
    address_family = socket.AF_INET6
    def server_bind(self):
        try: self.socket.setsockopt(socket.IPPROTO_IPV6, socket.IPV6_V6ONLY, 0)
        except Exception: pass
        super().server_bind()

def main():
    c = load_conf(); port = int(os.environ.get("PANEL_PORT") or c.get("PANEL_PORT", "8686"))
    try: srv = Srv(("::", port), H)
    except Exception:
        Srv.address_family = socket.AF_INET; srv = Srv(("0.0.0.0", port), H)
    if c.get("PANEL_TLS", "1") == "1" and os.path.exists(CERT) and os.path.exists(KEY):
        try:
            ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER); ctx.minimum_version = ssl.TLSVersion.TLSv1_2
            ctx.load_cert_chain(CERT, KEY); srv.socket = ctx.wrap_socket(srv.socket, server_side=True, do_handshake_on_connect=False); srv.is_tls = True
        except Exception as e: print("TLS disabled:", e, flush=True)
    print("AliRaza Panel on port %d (%s)" % (port, "HTTPS" if srv.is_tls else "HTTP"), flush=True)
    srv.serve_forever()

PAGE = r'''<!DOCTYPE html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>AliRaza Panel</title>
<style>
:root{--bg:#0b0f1a;--card:#141a2b;--line:#222b44;--tx:#e8ecf6;--mut:#8f9ab8;--ac:#7c5cff;--ac2:#00d4ff;--ok:#2ecc71;--bad:#ff4d5e;--warn:#ffb020}
*{box-sizing:border-box}body{margin:0;background:var(--bg);color:var(--tx);font:14px/1.45 system-ui,Segoe UI,Roboto,sans-serif}
a{color:var(--ac2)}button,input,select,textarea{font:inherit}
.top{position:sticky;top:0;z-index:5;background:#0b0f1aee;backdrop-filter:blur(8px);border-bottom:1px solid var(--line);display:flex;align-items:center;gap:10px;padding:10px 14px}
.logo{font-weight:800;font-size:17px;background:linear-gradient(90deg,var(--ac),var(--ac2));-webkit-background-clip:text;background-clip:text;color:transparent}
.sp{flex:1}.nav{display:flex;gap:6px;overflow-x:auto;padding:10px 14px;border-bottom:1px solid var(--line);scrollbar-width:none}
.nav button{white-space:nowrap;background:var(--card);color:var(--mut);border:1px solid var(--line);padding:7px 13px;border-radius:20px;cursor:pointer}
.nav button.on{background:linear-gradient(90deg,var(--ac),#5a3fd6);color:#fff;border-color:transparent}
main{max-width:1100px;margin:0 auto;padding:14px}
.grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(160px,1fr));gap:10px}
.card{background:var(--card);border:1px solid var(--line);border-radius:12px;padding:14px;margin-bottom:12px}
.stat .k{color:var(--mut);font-size:12px}.stat .v{font-size:19px;font-weight:700;margin-top:2px;word-break:break-all}
h2{margin:4px 0 12px;font-size:16px}h3{margin:0 0 8px;font-size:14px;color:var(--mut)}
.btn{background:linear-gradient(90deg,var(--ac),#5a3fd6);color:#fff;border:0;padding:9px 15px;border-radius:9px;cursor:pointer;font-weight:600}
.btn.g{background:var(--card);border:1px solid var(--line);color:var(--tx)}.btn.r{background:var(--bad)}.btn.s{padding:5px 10px;font-size:12px}.btn.o{background:var(--ok);color:#04210f}
.btn:disabled{opacity:.5}
input,select,textarea{width:100%;background:#0d1322;color:var(--tx);border:1px solid var(--line);border-radius:8px;padding:9px 11px;margin:3px 0 10px}
label{font-size:12px;color:var(--mut)}.row{display:grid;grid-template-columns:repeat(auto-fit,minmax(150px,1fr));gap:0 10px}
table{width:100%;border-collapse:collapse}th,td{text-align:left;padding:8px 6px;border-bottom:1px solid var(--line);white-space:nowrap}th{color:var(--mut);font-size:12px;font-weight:600}
.tw{overflow-x:auto}.pill{display:inline-block;padding:2px 9px;border-radius:12px;font-size:12px;font-weight:600}
.on_{background:#2ecc7122;color:var(--ok)}.off_{background:#ff4d5e22;color:var(--bad)}.warn_{background:#ffb02022;color:var(--warn)}
pre{background:#080c16;border:1px solid var(--line);border-radius:8px;padding:11px;overflow:auto;max-height:420px;white-space:pre-wrap;word-break:break-word;font:12px/1.5 ui-monospace,Menlo,Consolas,monospace}
.bar{height:7px;background:#0d1322;border-radius:5px;overflow:hidden;margin-top:6px}.bar i{display:block;height:100%;background:linear-gradient(90deg,var(--ac),var(--ac2))}
.login{max-width:360px;margin:12vh auto;padding:0 16px}.err{color:var(--bad);min-height:18px;margin:4px 0}
.modal{position:fixed;inset:0;background:#000a;display:none;align-items:center;justify-content:center;padding:14px;z-index:20}.modal.show{display:flex}
.modal .card{max-width:640px;width:100%;max-height:88vh;overflow:auto;margin:0}
.acts{display:flex;gap:5px;flex-wrap:wrap}.toast{position:fixed;bottom:16px;left:50%;transform:translateX(-50%);background:#1d2742;border:1px solid var(--ac);padding:10px 16px;border-radius:10px;display:none;z-index:30;max-width:90vw}
.hide{display:none}.mut{color:var(--mut)}
</style></head><body>
<div id="login" class="login hide"><div class="card"><div class="logo" style="font-size:22px;margin-bottom:12px">AliRaza Panel</div>
<label>Username</label><input id="lu" autocomplete="username"><label>Password</label><input id="lp" type="password" autocomplete="current-password">
<div class="err" id="le"></div><button class="btn" style="width:100%" onclick="doLogin()">Login</button></div></div>

<div id="app" class="hide">
<div class="top"><span class="logo">★ AliRaza Panel</span><span class="sp"></span><button class="btn g s" onclick="logout()">Logout</button></div>
<div class="nav" id="nav"></div><main id="main"></main></div>
<div class="modal" id="modal"><div class="card"><div id="mbody"></div><div style="text-align:right;margin-top:10px"><button class="btn g" onclick="closeM()">Close</button></div></div></div>
<div class="toast" id="toast"></div>
<script>
const $=id=>document.getElementById(id);
const esc=s=>String(s??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
async function api(path,body){
  const o=body===undefined?{}:{method:'POST',headers:{'Content-Type':'application/json','X-Requested-With':'AliRazaPanel'},body:JSON.stringify(body)};
  try{const r=await fetch(path,o);const d=await r.json().catch(()=>({error:'Bad response'}));
    if(r.status===401&&path!=='/api/login'){showLogin();throw 0}
    if(!r.ok)d.error=d.error||('HTTP '+r.status);return d}catch(e){if(e===0)throw e;return{error:'Network error'}}}
function toast(m){const t=$('toast');t.textContent=m;t.style.display='block';clearTimeout(t._t);t._t=setTimeout(()=>t.style.display='none',3500)}
function showLogin(){$('app').classList.add('hide');$('login').classList.remove('hide');stopPoll()}
async function doLogin(){const d=await api('/api/login',{username:$('lu').value,password:$('lp').value});
  if(d.ok){$('login').classList.add('hide');$('app').classList.remove('hide');$('lp').value='';go(cur)}else $('le').textContent=d.error||'Error'}
async function logout(){await api('/api/logout',{});showLogin()}
$('lp').addEventListener('keydown',e=>{if(e.key==='Enter')doLogin()});
const fb=b=>{b=+b||0;if(b>=2**40)return(b/2**40).toFixed(2)+' TB';if(b>=2**30)return(b/2**30).toFixed(2)+' GB';if(b>=2**20)return(b/2**20).toFixed(1)+' MB';return(b/1024).toFixed(0)+' KB'};
const fu=s=>{const d=Math.floor(s/86400),h=Math.floor(s%86400/3600),m=Math.floor(s%3600/60);return(d?d+'d ':'')+h+'h '+m+'m'};
const pill=(ok,a='ON',b='OFF')=>`<span class="pill ${ok?'on_':'off_'}">${ok?a:b}</span>`;
function openM(h){$('mbody').innerHTML=h;$('modal').classList.add('show')}function closeM(){$('modal').classList.remove('show')}
const TABS=[['dash','Dashboard'],['users','Users'],['live','Live IPs'],['svc','Services'],['domain','Domain & SSL'],['banner','SSH Banner'],['bunny','Bunny CDN'],['tg','Telegram'],['tools','Tools'],['set','Settings']];
let cur='dash',poll=null;
$('nav').innerHTML=TABS.map(t=>`<button id="t_${t[0]}" onclick="go('${t[0]}')">${t[1]}</button>`).join('');
function stopPoll(){clearInterval(poll);poll=null}
function go(t){cur=t;stopPoll();TABS.forEach(x=>$('t_'+x[0]).classList.toggle('on',x[0]===t));$('main').innerHTML='<div class="mut">Loading...</div>';V[t]()}
const V={};
V.dash=async()=>{const render=async()=>{const d=await api('/api/dashboard');if(d.error)return;
 const rp=d.ram_total?Math.round(d.ram_used*100/d.ram_total):0,dp=d.disk_total?Math.round(d.disk_used*100/d.disk_total):0;
 const st=(k,v,x='')=>`<div class="card stat"><div class="k">${k}</div><div class="v">${v}</div>${x}</div>`;
 $('main').innerHTML=`<div class="grid">
 ${st('Server IP',esc(d.ip),`<div class="k">${esc(d.provider)}</div>`)}
 ${st('Google Ping',d.ping==null?'n/a':d.ping+' ms',`<div class="k">${d.cpus}-Core · load ${esc(d.load.join(' '))}</div>`)}
 ${st('RAM',d.ram_used+' / '+d.ram_total+' MB',`<div class="bar"><i style="width:${rp}%"></i></div>`)}
 ${st('Disk',d.disk_used+' / '+d.disk_total+' GB',`<div class="bar"><i style="width:${dp}%"></i></div>`)}
 ${st('Uptime',fu(d.uptime))}
 ${st('Accounts',d.users,`<div class="k">${d.locked} locked</div>`)}
 ${st('Real Used',fb(d.used_bytes),`<div class="k">Total limit: ${d.limit_gb?d.limit_gb+' GB':'Unlimited'}</div>`)}
 ${st('Live SIM IPs',d.live,'<div class="k">Auth-only, CDN-fake filtered</div>')}</div>
 <div class="card"><h3>Hosts</h3><table><tr><td class="mut">Main Domain</td><td>${esc(d.domain)} <span class="pill ${d.domain_status==='POINTED'?'on_':'warn_'}">${esc(d.domain_status)}</span></td></tr>
 <tr><td class="mut">SlowDNS NS</td><td>${esc(d.ns)}</td></tr><tr><td class="mut">Bunny CDN</td><td>${esc(d.bunny)}</td></tr>
 <tr><td class="mut">Telegram Bot</td><td>${pill(d.tg,'Configured','Not set')}</td></tr></table></div>
 <div class="card"><h3>Quick actions</h3><div class="acts"><button class="btn s" onclick="act('restart_all','Restart all services?')">Restart All</button>
 <button class="btn s g" onclick="act('autodoctor','Auto-Doctor chalayein?')">Auto-Doctor</button><button class="btn s g" onclick="act('clean','RAM/Logs clean karein?')">Clean RAM/Logs</button></div></div>`};
 await render();poll=setInterval(render,8000)};
function userRow(u){const q=u.quota_gb?u.quota_gb+' GB':'Unlimited';
 return `<tr><td><b>${esc(u.username)}</b></td><td>${pill(u.status==='UNLOCKED','Active','Locked')}</td><td>${fb(u.used)} / ${q}</td><td>${u.live} / ${esc(u.ip_limit)}</td><td>${esc(u.expiry)}</td>
 <td class="acts"><button class="btn s g" onclick="cfg('${esc(u.username)}')">Config</button><button class="btn s g" onclick="renew('${esc(u.username)}',${u.quota_gb},${+u.ip_limit||2})">Renew</button>
 ${u.status==='UNLOCKED'?`<button class="btn s g" onclick="uact('lock','${esc(u.username)}')">Lock</button>`:`<button class="btn s o" onclick="unlock('${esc(u.username)}')">Unlock</button>`}
 <button class="btn s r" onclick="uact('delete','${esc(u.username)}')">Delete</button></td></tr>`}
V.users=async()=>{const render=async()=>{const d=await api('/api/users');if(d.error)return;
 $('main').innerHTML=`<div class="card"><div class="acts" style="margin-bottom:10px"><button class="btn" onclick="newUser()">+ Create Account</button><button class="btn g" onclick="trial()">24h Trial</button></div>
 <div class="tw"><table><tr><th>User</th><th>Status</th><th>Used / Limit</th><th>Live / IPs</th><th>Expiry</th><th></th></tr>${d.users.map(userRow).join('')||'<tr><td colspan=6 class="mut">Koi account nahi.</td></tr>'}</table></div></div>`};
 await render();poll=setInterval(()=>{if(!$('modal').classList.contains('show'))render()},10000)};
function newUser(){openM(`<h2>Create VIP Account</h2><div class="row"><div><label>Username</label><input id="nu"></div><div><label>Password</label><input id="np" value="1234"></div>
 <div><label>GB Limit (0 = unlimited)</label><input id="nq" type="number" value="0"></div><div><label>IP Limit</label><input id="ni" type="number" value="2"></div><div><label>Validity (days)</label><input id="nd" type="number" value="30"></div></div>
 <button class="btn" onclick="createUser()">Create</button>`)}
async function createUser(){const d=await api('/api/user/create',{username:$('nu').value,password:$('np').value,quota:$('nq').value,ip_limit:$('ni').value,days:$('nd').value});
 if(d.error)return toast(d.error);openM(`<h2>Account Created</h2><pre>${esc(d.output)}</pre>`);go('users')}
async function trial(){if(!confirm('24h trial account banayein?'))return;const d=await api('/api/user/trial',{});if(d.error)return toast(d.error);openM(`<h2>Trial Account</h2><pre>${esc(d.output)}</pre>`);go('users')}
async function uact(a,u){if(!confirm(a.toUpperCase()+' '+u+' ?'))return;const d=await api('/api/user/'+a,{username:u});toast(d.error||(a+' done: '+u));go('users')}
function unlock(u){openM(`<h2>Unlock ${esc(u)}</h2><label>Naye din</label><input id="ud" type="number" value="30"><p class="mut">Used GB reset ho jayega.</p><button class="btn" onclick="doUnlock('${esc(u)}')">Unlock</button>`)}
async function doUnlock(u){const d=await api('/api/user/unlock',{username:u,days:$('ud').value});closeM();toast(d.error||'Unlocked');go('users')}
function renew(u,q,i){openM(`<h2>Renew / Edit ${esc(u)}</h2><div class="row"><div><label>GB Limit (0 = unlimited)</label><input id="rq" type="number" value="${q}"></div><div><label>IP Limit</label><input id="ri" type="number" value="${i}"></div><div><label>Din (aaj se)</label><input id="rd" type="number" value="30"></div></div>
 <label><input type="checkbox" id="rr" checked style="width:auto;margin-right:6px">Used GB 0 par reset karein</label><br><br><button class="btn" onclick="doRenew('${esc(u)}')">Save</button>`)}
async function doRenew(u){const d=await api('/api/user/renew',{username:u,quota:$('rq').value,ip_limit:$('ri').value,days:$('rd').value,reset:$('rr').checked});closeM();toast(d.error||'Account updated');go('users')}
async function cfg(u,t='main'){const d=await api('/api/user/config?username='+encodeURIComponent(u)+'&type='+t);if(d.error)return toast(d.error);
 openM(`<h2>${esc(u)} Config</h2><div class="acts" style="margin-bottom:8px"><button class="btn s g" onclick="cfg('${esc(u)}','main')">Main</button><button class="btn s g" onclick="cfg('${esc(u)}','bunny')">Bunny CDN</button><button class="btn s" onclick="copyT()">Copy</button></div>
 <p class="mut">1-click link: <a href="${esc(d.link)}" target="_blank" rel="noopener">${esc(d.link)}</a></p><pre id="cfgtxt">${esc(d.config)}</pre>`)}
function copyT(){navigator.clipboard.writeText($('cfgtxt').textContent).then(()=>toast('Copied'))}
V.live=async()=>{const render=async()=>{const d=await api('/api/live');if(d.error)return;
 $('main').innerHTML=`<div class="card"><h2>Real connected SIM client IPs (${d.live.length})</h2><div class="tw"><table><tr><th>#</th><th>Client IP</th><th>Protocol / User</th><th>Tunnels</th></tr>
 ${d.live.map((l,i)=>`<tr><td>${i+1}</td><td>${esc(l.ip)}</td><td>${esc(l.ports)}</td><td>${esc(l.tunnels)}</td></tr>`).join('')||'<tr><td colspan=4 class="mut">Abhi koi client connected nahi.</td></tr>'}</table></div></div>`};
 await render();poll=setInterval(render,6000)};
V.svc=async()=>{const render=async()=>{const d=await api('/api/services');if(d.error)return;
 $('main').innerHTML=`<div class="card"><h2>All protocols &amp; live status</h2><div class="tw"><table><tr><th>Service</th><th>Port</th><th>Status</th><th></th></tr>
 ${d.services.map(s=>`<tr><td>${esc(s.label)}</td><td>${s.port}/${s.proto}</td><td>${pill(s.live,'LIVE','DOWN')}</td><td><button class="btn s g" onclick="rsvc('${esc(s.service)}')">Restart</button></td></tr>`).join('')}</table></div></div>
 <div class="card"><div class="acts"><button class="btn" onclick="act('restart_all','Sab services restart karein?')">Restart All</button><button class="btn g" onclick="act('autodoctor','Auto-Doctor chalayein?')">Auto-Doctor Fix</button></div></div>`};
 await render();poll=setInterval(render,8000)};
async function rsvc(n){const d=await api('/api/service/restart',{name:n});toast(d.error||('Restarted: '+n));setTimeout(()=>go('svc'),1500)}
V.domain=async()=>{const d=await api('/api/domain');if(d.error)return;
 $('main').innerHTML=`<div class="card"><h2>Domain &amp; SSL</h2><table><tr><td class="mut">Server IP</td><td>${esc(d.ip)}</td></tr><tr><td class="mut">Main Domain</td><td>${esc(d.domain||'Not-Set')} <span class="pill ${d.domain_status==='POINTED'?'on_':'warn_'}">${esc(d.domain_status)}</span></td></tr>
 <tr><td class="mut">SlowDNS NS</td><td>${esc(d.ns||'Not-Set')}</td></tr></table><pre style="margin-top:10px">${esc(d.cert||'No cert info')}</pre></div>
 <div class="card"><h3>Change domain (naya SSL + sab user files auto update)</h3><div class="row"><div><label>Main Domain</label><input id="dd" value="${esc(d.domain)}"></div><div><label>SlowDNS NS Domain</label><input id="dn" value="${esc(d.ns)}"></div></div>
 <div class="acts"><button class="btn" onclick="setDom()">Apply</button><button class="btn g" onclick="act('ssl','Current domain par SSL renew karein?')">Renew SSL</button></div>
 <p class="mut">Domain pehle is VPS IP par point hona chahiye warna self-signed SSL lagega.</p></div>`};
async function setDom(){if(!confirm('Domain apply karein? Services kuch der restart hongi.'))return;const d=await api('/api/domain/set',{domain:$('dd').value,ns:$('dn').value});d.job?watch(d.job):toast(d.error)}
V.banner=async()=>{const d=await api('/api/banner');if(d.error)return;
 $('main').innerHTML=`<div class="card"><h2>SSH / Dropbear Banner (AliRaza+server)</h2><p class="mut">HTML tags (&lt;font&gt;, &lt;br&gt;) allowed hain. Save karne par OpenSSH aur Dropbear dono me apply hoga.</p><textarea id="bt" rows="14" style="font-family:monospace">${esc(d.banner)}</textarea>
 <div class="acts"><button class="btn" onclick="saveB()">Save &amp; Apply</button><button class="btn g" onclick="defB()">Restore Default</button></div></div>`};
async function saveB(){const d=await api('/api/banner/set',{banner:$('bt').value});toast(d.error||'Banner applied')}
async function defB(){if(!confirm('Default banner restore karein?'))return;const d=await api('/api/banner/default',{});if(d.error)return toast(d.error);$('bt').value=d.banner;toast('Default banner applied')}
V.bunny=async()=>{const d=await api('/api/bunny');if(d.error)return;
 $('main').innerHTML=`<div class="card"><h2>Bunny CDN</h2><p class="mut">Origin VPS IP: ${esc(d.ip)} (port 80/443) · WebSockets ON, Forward Host Header ON</p><label>Pull Zone Hostname (e.g. name.b-cdn.net)</label><input id="bh" value="${esc(d.host)}">
 <div class="acts"><button class="btn" onclick="setB()">Set / Change</button><button class="btn g" onclick="act('bunny_regen')">Regenerate all user files</button></div></div>${d.guide?`<div class="card"><h3>Setup guide</h3><pre>${esc(d.guide)}</pre></div>`:''}`};
async function setB(){const d=await api('/api/bunny/set',{host:$('bh').value});d.job?watch(d.job):toast(d.error)}
V.tg=async()=>{const d=await api('/api/telegram');if(d.error)return;
 $('main').innerHTML=`<div class="card"><h2>Telegram Bot</h2><p>Status: ${pill(d.active,'Running','Stopped')} ${d.configured?'· Owner UID: '+esc(d.admin):'· Not configured'}</p>
 <div class="row"><div><label>Bot Token (@BotFather)</label><input id="tt" placeholder="123456:ABC..."></div><div><label>Owner Telegram UID</label><input id="tu" placeholder="123456789"></div></div>
 <div class="acts"><button class="btn" onclick="setTG()">Connect Bot</button><button class="btn g" onclick="tgc('restart')">Restart</button><button class="btn g" onclick="tgc('stop')">Stop</button></div></div>`};
async function setTG(){const d=await api('/api/telegram/set',{token:$('tt').value,uid:$('tu').value});toast(d.error||d.output);if(!d.error)go('tg')}
async function tgc(a){const d=await api('/api/telegram/ctl',{action:a});toast(d.error||('Bot '+a+' done'));setTimeout(()=>go('tg'),800)}
V.tools=()=>{$('main').innerHTML=`<div class="card"><h2>Tools</h2><div class="acts">
 <button class="btn g" onclick="act('autodoctor','Auto-Doctor chalayein?')">Auto-Doctor Fix</button><button class="btn g" onclick="act('restart_all','Restart all?')">Restart All</button><button class="btn g" onclick="act('clean','Clean RAM/Logs?')">Clean RAM/Logs</button>
 <button class="btn g" onclick="act('speedtest')">VPS Speedtest</button><button class="btn g" onclick="act('udp_test','15 second UDP listen test shuru karein? Is dauran mobile se UDP app connect karein.')">UDP Firewall Test</button></div></div>
 <div class="card"><h3>Fix UDP / SlowDNS (SlowDNS target)</h3><div class="acts"><button class="btn g" onclick="act('slowdns_1','SlowDNS -> SSH 22')">SSH 22</button><button class="btn g" onclick="act('slowdns_2','SlowDNS -> SSH 2222 (recommended)')">SSH 2222 (Recommended)</button><button class="btn g" onclick="act('slowdns_3','SlowDNS -> Xray VLESS 20010')">Xray 20010</button></div></div>
 <div class="card"><h3>Danger zone</h3><div class="acts"><button class="btn r" onclick="act('reinstall','Poora Re-Install chalayein? (users safe rehte hain)')">Re-Install All</button><button class="btn r" onclick="uninst()">Clean Uninstall</button></div></div>`};
async function act(name,msg){if(msg&&!confirm(msg))return;let d;
 if(name==='ssl')d=await api('/api/ssl/renew',{});else if(name==='bunny_regen')d=await api('/api/bunny/regen',{});else d=await api('/api/action',{name});
 if(d.job)watch(d.job);else if(d.error)toast(d.error)}
async function uninst(){const c=prompt('Poora panel uninstall hoga. Confirm ke liye DELETE likhein:');if(c!=='DELETE')return;const d=await api('/api/action',{name:'uninstall',confirm:c});d.job?watch(d.job):toast(d.error)}
let wt=null;
function watch(id){openM(`<h2 id="jt">Running...</h2><pre id="jl">Starting...</pre>`);clearInterval(wt);
 const tick=async()=>{const d=await api('/api/job?id='+id);if(d.none||d.error)return;$('jt')&&($('jt').textContent=d.title+(d.running?' (running...)':d.exit===0?' ✔ Done':' ✘ Exit '+d.exit));
  const l=$('jl');if(l){l.textContent=d.log||'...';l.scrollTop=l.scrollHeight}if(!d.running)clearInterval(wt)};
 tick();wt=setInterval(tick,1500)}
V.set=()=>{$('main').innerHTML=`<div class="card"><h2>Panel Login Settings</h2><div class="row"><div><label>Current Password</label><input id="cp" type="password"></div><div><label>New Username (optional)</label><input id="cu"></div><div><label>New Password (min 6)</label><input id="cn" type="password"></div></div>
 <button class="btn" onclick="chPw()">Update</button></div>`};
async function chPw(){const d=await api('/api/password',{current:$('cp').value,new_username:$('cu').value,new:$('cn').value});toast(d.error||d.output);if(d.ok)setTimeout(showLogin,1200)}
(async()=>{const d=await api('/api/dashboard').catch(()=>null);if(d&&!d.error){$('app').classList.remove('hide');go('dash')}})();
</script></body></html>
'''
if __name__ == "__main__": main()

PANEL_PY_EOF
    chmod 700 "$PANEL_BIN"
    if [[ "$SELF_PATH" != "$CORE_PATH" && -f "$SELF_PATH" ]]; then
        cp -f "$SELF_PATH" "$CORE_PATH" 2>/dev/null && chmod 700 "$CORE_PATH" || true
    fi
    [[ ! -s "$CORE_PATH" ]] && echo -e "${RED}[!] Core script copy nahi ho saki ($CORE_PATH). Script ko file ke tor par chalayein (bash install.sh).${NC}"
    printf '#!/bin/bash\nexec bash %s "$@"\n' "$CORE_PATH" > /usr/bin/menu; chmod +x /usr/bin/menu
    cat << UNIT_EOF > /etc/systemd/system/aliraza-panel.service
[Unit]
Description=AliRaza Web Panel
After=network.target

[Service]
Type=simple
ExecStart=/usr/bin/python3 ${PANEL_BIN}
Restart=always
RestartSec=3s
KillMode=process

[Install]
WantedBy=multi-user.target
UNIT_EOF
    local PP; PP=$(panel_conf_get PANEL_PORT)
    command -v ufw >/dev/null 2>&1 && ufw status 2>/dev/null | grep -q "Status: active" && ufw allow "${PP}/tcp" >/dev/null 2>&1 || true
    iptables -C INPUT -p tcp --dport "$PP" -j ACCEPT >/dev/null 2>&1 || iptables -I INPUT -p tcp --dport "$PP" -j ACCEPT >/dev/null 2>&1 || true
    systemctl daemon-reload
    systemctl enable aliraza-panel >/dev/null 2>&1 || true
    systemctl restart aliraza-panel >/dev/null 2>&1 || true
    sleep 2
    systemctl is-active --quiet aliraza-panel && return 0
    echo -e "${RED}[!] Panel start nahi hua. Check: journalctl -u aliraza-panel -n 30${NC}"; return 1
}

show_panel_info() {
    local PU PP TLS DOM IP SCH
    PU=$(panel_conf_get PANEL_USER); PP=$(panel_conf_get PANEL_PORT); TLS=$(panel_conf_get PANEL_TLS)
    DOM=$(head -n1 "$DATA_DIR/domain.txt" 2>/dev/null | tr -d '[:space:]'); IP=$(get_vps_ip)
    SCH="http"; [[ "$TLS" != "0" && -s /etc/ssl/xray/fullchain.pem ]] && SCH="https"
    echo ""
    echo -e "${PURPLE}╭──────────────────────────────────────────────────────╮${NC}"
    echo -e "${PURPLE}│${NC}  ${BG_PURPLE}        ★  A L I R A Z A   W E B   P A N E L  ★        ${NC} ${PURPLE}│${NC}"
    echo -e "${PURPLE}├──────────────────────────────────────────────────────┤${NC}"
    echo -e "${PURPLE}│${NC} ${WHITE}Panel URL (domain):${NC} ${GREEN}${SCH}://${DOM:-$IP}:${PP}${NC}"
    echo -e "${PURPLE}│${NC} ${WHITE}Panel URL (IP)    :${NC} ${CYAN}${SCH}://${IP}:${PP}${NC}"
    echo -e "${PURPLE}│${NC} ${WHITE}Username          :${NC} ${YELLOW}${PU}${NC}"
    [[ -n "${PANEL_PASS_IN:-}" ]] && echo -e "${PURPLE}│${NC} ${WHITE}Password          :${NC} ${YELLOW}${PANEL_PASS_IN}${NC}"
    echo -e "${PURPLE}├──────────────────────────────────────────────────────┤${NC}"
    echo -e "${PURPLE}│${NC} Cloud firewall me TCP port ${PP} OPEN karna na bhulen."
    echo -e "${PURPLE}│${NC} Terminal commands: ${CYAN}menu passwd${NC} | ${CYAN}menu port${NC} | ${CYAN}menu restart${NC}"
    echo -e "${PURPLE}╰──────────────────────────────────────────────────────╯${NC}"
    echo ""
}

panel_reset_credentials() {
    local PP; PP=$(panel_conf_get PANEL_PORT); PP="${PP:-8686}"
    local IN_USER IN_P1 IN_P2
    while true; do read -rp " • Naya Panel Username [$(panel_conf_get PANEL_USER)]: " IN_USER || return 1
        IN_USER="${IN_USER:-$(panel_conf_get PANEL_USER)}"; [[ "$IN_USER" =~ ^[a-zA-Z0-9_-]{3,32}$ ]] && break; echo "   Username galat hai"; done
    while true; do read -rsp " • Naya Password (min 6): " IN_P1 || return 1; echo ""
        [[ ${#IN_P1} -lt 6 ]] && { echo "   Kam az kam 6 characters"; continue; }
        read -rsp " • Dobara likhein: " IN_P2 || return 1; echo ""; [[ "$IN_P1" == "$IN_P2" ]] && break; echo "   Match nahi hua"; done
    panel_save_conf "$IN_USER" "$PP" "$IN_P1"; PANEL_PASS_IN="$IN_P1"
    systemctl restart aliraza-panel >/dev/null 2>&1 || true
    echo -e "${GREEN}[✔] Panel credentials update ho gaye.${NC}"; show_panel_info
}

panel_change_port() {
    local NP MSG PU
    while true; do read -rp " • Naya Panel Port: " NP || return 1; MSG=$(panel_port_ok "$NP") && break; echo -e "   ${RED}[!] ${MSG}${NC}"; done
    sed -i "s/^PANEL_PORT=.*/PANEL_PORT=${NP}/" "$PANEL_CONF"
    command -v ufw >/dev/null 2>&1 && ufw status 2>/dev/null | grep -q "Status: active" && ufw allow "${NP}/tcp" >/dev/null 2>&1 || true
    iptables -C INPUT -p tcp --dport "$NP" -j ACCEPT >/dev/null 2>&1 || iptables -I INPUT -p tcp --dport "$NP" -j ACCEPT >/dev/null 2>&1 || true
    systemctl restart aliraza-panel >/dev/null 2>&1 || true
    echo -e "${GREEN}[✔] Panel port ${NP} par chal raha hai.${NC}"; show_panel_info
}

# ---------------- functions called by the web panel (no prompts) ----------------
panel_renew_user() { # user gb ip days reset(1/0)
    local R_USER="$1" NEW_GB="$2" NEW_IP="$3" NEW_DAYS="$4" RST_GB="${5:-1}"
    [[ "$R_USER" =~ ^[a-zA-Z0-9_-]+$ && "$NEW_GB" =~ ^[0-9]+$ && "$NEW_IP" =~ ^[0-9]+$ && "$NEW_DAYS" =~ ^[0-9]+$ ]] || { echo "Invalid input"; return 1; }
    is_protected_system_user "$R_USER" && { echo "[!] Protected system user"; return 1; }
    local LINE; LINE=$(grep "^${R_USER}|" "$USERS_DB" 2>/dev/null | head -n1 || true)
    [[ -z "$LINE" ]] && { echo "[!] User nahi mila"; return 1; }
    local UPASS UUID NEW_EXP
    UPASS=$(echo "$LINE" | cut -d'|' -f2); UUID=$(echo "$LINE" | cut -d'|' -f3)
    NEW_EXP=$(date -d "+${NEW_DAYS} days" +"%Y-%m-%d")
    [[ "$RST_GB" == "1" ]] && echo "0" > "$USAGE_DIR/${R_USER}.bytes"
    usermod -s /bin/bash -p "$(openssl passwd -6 "$UPASS")" "$R_USER" >/dev/null 2>&1 || true
    chage -E "$(date -d "$NEW_EXP + 1 day" +"%Y-%m-%d" 2>/dev/null || echo "$NEW_EXP")" "$R_USER" >/dev/null 2>&1 || true
    passwd -u "$R_USER" >/dev/null 2>&1 || true
    sed -i "s/^${R_USER}|.*/${R_USER}|${UPASS}|${UUID}|${NEW_GB}|${NEW_IP}|${NEW_EXP}|UNLOCKED/" "$USERS_DB"
    sync_all_users_to_engines
    /usr/local/bin/zainu-cli regen "$R_USER" "$UPASS" "$NEW_GB" "$NEW_IP" >/dev/null 2>&1 || true
    systemctl restart xray >/dev/null 2>&1 || true
    echo "[✔] Account updated (Expiry: ${NEW_EXP})"
}

panel_apply_domain() { # domain ns
    local IN_D="$1" IN_N="$2" CUR_D CUR_N CHG_DOM=0 CHG_NS=0
    CUR_D=$(head -n1 "$DATA_DIR/domain.txt" 2>/dev/null | tr -d '[:space:]'); CUR_N=$(head -n1 "$DATA_DIR/ns_domain.txt" 2>/dev/null | tr -d '[:space:]')
    [[ -n "$IN_D" && "$IN_D" != "$CUR_D" ]] && CHG_DOM=1
    [[ -n "$IN_N" && "$IN_N" != "$CUR_N" ]] && CHG_NS=1
    if [[ "$CHG_DOM" == "0" && "$CHG_NS" == "0" ]]; then
        echo "[*] Domain/NS same hain - sirf SSL renew ho raha hai..."
        [[ -n "$CUR_D" ]] && issue_ssl_cert "$CUR_D"; return 0
    fi
    [[ "$CHG_DOM" == "1" ]] && echo "$IN_D" > "$DATA_DIR/domain.txt"
    [[ "$CHG_NS" == "1" ]] && echo "$IN_N" > "$DATA_DIR/ns_domain.txt"
    rm -f /run/zainu_dom_* /run/zainu_ns_* 2>/dev/null || true
    if [[ "$CHG_DOM" == "1" ]]; then issue_ssl_cert "$IN_D"; configure_nginx_mux; install_ws_ssh_engine; fi
    [[ "$CHG_NS" == "1" ]] && configure_slowdns_service 0
    sync_all_users_to_engines; regenerate_all_user_files
    systemctl restart haproxy 2>/dev/null || true
    echo "[OK] Apply ho gaya! Sab users ki config files naye domain/NS se update ho gayin."
}

panel_renew_ssl() {
    local CUR_D; CUR_D=$(head -n1 "$DATA_DIR/domain.txt" 2>/dev/null | tr -d '[:space:]')
    [[ -z "$CUR_D" ]] && { echo "[!] Pehle domain set karein"; return 1; }
    issue_ssl_cert "$CUR_D"
}

panel_apply_banner() { fix_ssh_auth_and_banner; fix_dropbear_core; echo "[✔] Banner applied (SSH + Dropbear)"; }
panel_default_banner() { write_zainu_vip_banner; fix_ssh_auth_and_banner; fix_dropbear_core; echo "[✔] Default AliRaza+server banner applied"; }

panel_set_bunny() {
    local NEW_BH="$1" MY_IP; MY_IP=$(get_vps_ip)
    [[ -z "$NEW_BH" ]] && return 1
    echo "$NEW_BH" > "$DATA_DIR/bunny_host.txt"; rm -f /run/zainu_dom_* 2>/dev/null || true
    {
        echo "============================================================"
        echo "ALIRAZA - BUNNY CDN PULL ZONE SETUP GUIDE"
        echo "============================================================"
        echo "1. Bunny.net Dashboard -> Pull Zones -> Add Pull Zone"
        echo "   - Pull Zone Hostname : ${NEW_BH}"
        echo "   - Origin Type        : Origin URL"
        echo "   - Origin URL         : http://${MY_IP}:80  (ya https://${MY_IP}:443)"
        echo "2. Pull Zone Settings -> Enable WebSockets: ON | Forward Host Header: ON | Add Canonical Header: OFF"
        echo "3. Har user ki alag Bunny config: /root/zainu-configs/bunnycdn/USERNAME-bunnycdn.txt"
        echo "============================================================"
    } > "$BUNNY_CONF"
    configure_nginx_mux; regenerate_all_user_files
    echo "[✔] Bunny CDN Host (${NEW_BH}) configured & user files generated!"
}

panel_regen_files() { regenerate_all_user_files; echo "[✔] Sab users ki config files regenerate ho gayin."; }

panel_set_tg() {
    local TOK="$1" UID_="$2"
    [[ -z "$TOK" || -z "$UID_" ]] && return 1
    setup_cli_account_helper; setup_telegram_bot_daemon
    echo "TOKEN=${TOK}" > "$TG_CONF"; chmod 600 "$TG_CONF"; echo "$UID_" > "$TG_ADMINS"
    systemctl enable zainu-tgbot >/dev/null 2>&1 || true; systemctl restart zainu-tgbot >/dev/null 2>&1 || true
    echo "[✔] Telegram bot connected."
}

panel_slowdns_target() {
    case "$1" in
        1) echo "127.0.0.1:22" > "$DATA_DIR/slowdns_target.txt" ;;
        2) echo "127.0.0.1:2222" > "$DATA_DIR/slowdns_target.txt" ;;
        3) echo "127.0.0.1:20010" > "$DATA_DIR/slowdns_target.txt" ;;
        *) return 1 ;;
    esac
    install_udp_custom 0; install_badvpn_gateway 0; configure_slowdns_service 0
    echo "[✔] SlowDNS, ZiVPN, Hysteria2 & UDP updated!"
}

panel_udp_test() {
    echo "[*] 15s listening... mobile se UDP app (HTTP Custom / NetMod) connect karein"
    local out; out=$(timeout 15 tcpdump -U -l -ni any "udp and (dst port 5667 or dst port 36712 or dst port 20800 or dst port 5300 or dst port 53)" -c 8 2>/dev/null || true)
    if [[ -n "$out" ]]; then echo "$out"; echo "[✔] UDP PACKETS VPS TAK AA RAHE HAIN (Cloud Firewall Open)"
    else echo "[✘] 0 UDP PACKETS RECEIVED - cloud firewall (Security Group) me Inbound All UDP 0.0.0.0/0 allow karein."; fi
}

panel_speedtest() { speedtest-cli --simple 2>/dev/null || curl -sL https://raw.githubusercontent.com/sivel/speedtest-cli/master/speedtest.py | python3 - --simple; }

panel_uninstall() {
    systemctl stop haproxy zainu-ws zainu-monitor zainu-tgbot zainu-firewall zivpn hysteria udp-custom badvpn slowdns xray nginx dropbear stunnel4 2>/dev/null || true
    [[ -f "$BACKUP_DIR/sshd_config.orig" ]] && cp -pf "$BACKUP_DIR/sshd_config.orig" /etc/ssh/sshd_config 2>/dev/null || true
    systemctl reload ssh 2>/dev/null || systemctl restart ssh 2>/dev/null || systemctl restart sshd 2>/dev/null || true
    rm -rf "$WS_DIR" "$SLOWDNS_DIR" "$UDP_DIR" "$ZIVPN_DIR" "$HY2_DIR" "$CLIENTS_DIR" "$DATA_DIR" /usr/bin/menu /root/install.sh 2>/dev/null || true
    echo "[✔] Uninstall complete. Panel ab band ho raha hai."
    systemctl disable --now aliraza-panel >/dev/null 2>&1 || true
    rm -f /etc/systemd/system/aliraza-panel.service "$PANEL_BIN" "$CORE_PATH" 2>/dev/null || true
    systemctl daemon-reload >/dev/null 2>&1 || true
}

# ---------------- installer ----------------
run_full_install() {
    local DOMAIN; DOMAIN=$(head -n1 "$DATA_DIR/domain.txt" 2>/dev/null | tr -d '[:space:]')
    [[ -z "$DOMAIN" ]] && { echo "[!] Domain set nahi hai"; return 1; }
    rm -f /run/zainu_dom_* /run/zainu_ns_* 2>/dev/null || true
    ensure_base_packages; fix_dns_resolver; setup_slowdns_and_udp_nat; get_vps_ip >/dev/null; get_vps_provider >/dev/null
    write_zainu_vip_banner; fix_ssh_auth_and_banner; fix_dropbear_core
    issue_ssl_cert "$DOMAIN"; setup_openvpn_server; configure_nginx_mux; install_ws_ssh_engine; fix_stunnel_core
    install_xray_binary || true
    write_base_xray_config; fix_xray_systemd_unit; sync_all_users_to_engines
    systemctl enable xray 2>/dev/null && systemctl restart xray 2>/dev/null || true
    install_udp_custom 0; install_badvpn_gateway 0; configure_slowdns_service 0
    setup_slowdns_and_udp_nat; configure_haproxy_c_mux; setup_cli_account_helper; regenerate_all_user_files; setup_realtime_monitor_service; setup_telegram_bot_daemon; install_liveips_helper
    echo "INSTALLED" > "$INSTALLED_FLAG"; echo "READY" > "$V55_FLAG"; echo "READY" > "$V554_FLAG"
    echo ""
    echo -e "${CYAN}[*] FINAL LIVE PORTS VERIFICATION:${NC}"
    for chk in "22:tcp:OpenSSH" "443:tcp:HAProxy-TLS-Mux" "80:tcp:HAProxy-HTTP-Mux" "8442:tcp:TLS-Terminator" "2222:tcp:SSH-Installer-Port" "10010:tcp:Xray-XHTTP" "10013:tcp:Xray-Reality" "10014:udp:Xray-mKCP" "10015:tcp:Shadowsocks-2022" "10808:tcp:Socks5" "1194:tcp:OpenVPN-TCP" "2200:udp:OpenVPN-UDP" "5667:udp:ZiVPN" "36712:udp:UDP-Custom" "20800:udp:Hysteria2" "5300:udp:SlowDNS" "444:tcp:Stunnel" "109:tcp:Dropbear"; do
        IFS=':' read -r cport cproto clabel <<< "$chk"
        cflg="-tln"; [[ "$cproto" == "udp" ]] && cflg="-uln"
        if ss "$cflg" 2>/dev/null | grep -qE ":${cport}\b"; then echo -e "  ${GREEN}[ON ]${NC} ${clabel} (${cport}/${cproto})"
        else echo -e "  ${RED}[OFF]${NC} ${clabel} (${cport}/${cproto}) -> Panel me Auto-Doctor chalayein"; fi
    done
    install_port_watchdog
    self_test_tls_and_repair
}

panel_reinstall() { run_full_install; echo "[OK] Re-install complete."; }

full_auto_installer() {
    clear_screen
    echo -e "${BG_PURPLE}        ★ ALIRAZA WEB PANEL INSTALLER ★        ${NC}"
    echo ""
    local CUR_D CUR_N DOMAIN NS_DOMAIN
    CUR_D=$(head -n1 "$DATA_DIR/domain.txt" 2>/dev/null | tr -d '[:space:]')
    CUR_N=$(head -n1 "$DATA_DIR/ns_domain.txt" 2>/dev/null | tr -d '[:space:]')
    while true; do
        read -rp " • Main VPS Domain${CUR_D:+ [$CUR_D]}: " DOMAIN || exit 1
        DOMAIN="${DOMAIN:-$CUR_D}"
        [[ "$DOMAIN" =~ ^[A-Za-z0-9]([A-Za-z0-9.-]{0,250}[A-Za-z0-9])?$ ]] && break
        echo -e "   ${RED}[!] Valid domain likhein (e.g. vpn.example.com)${NC}"
    done
    read -rp " • SlowDNS NS Domain [${CUR_N:-ns.$DOMAIN}]: " NS_DOMAIN || exit 1
    NS_DOMAIN="${NS_DOMAIN:-${CUR_N:-ns.$DOMAIN}}"
    ask_panel_credentials
    echo "$DOMAIN" > "$DATA_DIR/domain.txt"; echo "$NS_DOMAIN" > "$DATA_DIR/ns_domain.txt"; echo "$DOMAIN" > "$DATA_DIR/bunny_host.txt"
    echo ""; echo -e "${CYAN}[*] Installation shuru... (kuch minute lagenge)${NC}"
    run_full_install || exit 1
    install_web_panel
    echo -e "${GREEN}[OK] INSTALL COMPLETE!${NC}"
    show_panel_info
}








smart_auto_doctor() {
    clear_screen
    echo -e "${BG_PURPLE}   ★ REAL AUTO-DOCTOR & DEEP VERIFICATION (v55.4) ★ ${NC}"
    rm -f /run/zainu_dom_* /run/zainu_ns_* 2>/dev/null || true
    echo -e " ${CYAN}[1/6]${NC} Checking Kernel BBR, Firewall NAT & Base Tools..."
    enable_bbr_and_kernel_speed
    setup_slowdns_and_udp_nat
    echo -e " ${CYAN}[2/6]${NC} Fixing OpenSSH (22/2222), Dropbear (109/143/447) & Stunnel (444/8443)..."
    write_zainu_vip_banner; fix_ssh_auth_and_banner; fix_dropbear_core; setup_openvpn_server; fix_stunnel_core
    echo -e " ${CYAN}[3/6]${NC} Verifying SlowDNS (5300), ZiVPN (5667), Hysteria2 (20800) & UDP-Custom (36712)..."
    configure_slowdns_service 0; install_udp_custom 0; install_badvpn_gateway 0
    echo -e " ${CYAN}[4/6]${NC} Repairing Xray Multi-Protocol Core (WS, gRPC, HUP, XHTTP, Vision, Reality, mKCP)..."
    write_base_xray_config; fix_xray_systemd_unit; sync_all_users_to_engines
    systemctl restart xray 2>/dev/null || true
    echo -e " ${CYAN}[5/6]${NC} Repairing Nginx, Golang WS Engine (10000), Real SIM IP Engine & HAProxy 80/443 Mux..."
    configure_nginx_mux; install_ws_ssh_engine; install_liveips_helper
    echo -e " ${CYAN}[6/6]${NC} Tracker/Bot Sync + Watchdog + 443 TLS Self-Test..."
    setup_cli_account_helper; regenerate_all_user_files; setup_realtime_monitor_service; setup_telegram_bot_daemon
    systemctl restart xray nginx zainu-ws haproxy 2>/dev/null || true
    install_port_watchdog
    self_test_tls_and_repair
    echo "READY" > "$V55_FLAG"
    echo -e "\n${GREEN}[✔] MUBARAK HO! All 17 Services + Zero-Ghost-KB Data Tracker + Real SIM IP Engine 100% LIVE!${NC}"
    read -rp "Enter dabayein..." || true
}








restart_all_services_menu() {
    clear_screen; enable_bbr_and_kernel_speed; generate_fallback_cert
    rm -f /run/zainu_dom_* /run/zainu_ns_* 2>/dev/null || true
    /usr/local/bin/zainu-firewall-restore >/dev/null 2>&1 || true
    configure_haproxy_c_mux
    systemctl restart ssh dropbear nginx zainu-ws haproxy xray openvpn-server@server-tcp openvpn-server@server-udp zivpn hysteria udp-custom badvpn slowdns stunnel4 zainu-monitor zainu-tgbot zainu-watchdog 2>/dev/null || true
    install_port_watchdog
    install_port_watchdog
    echo -e "${GREEN}[✔] All Services (HAProxy 80/443 + Watchdog) Restarted!${NC}"; read -rp "Enter dabayein..." || true
}

clean_ram_and_logs() {
    clear_screen; sync; echo 3 > /proc/sys/vm/drop_caches 2>/dev/null || true
    if [[ -s /var/log/xray/access.log ]]; then
        tail -n 100 /var/log/xray/access.log > /tmp/.xlog_keep 2>/dev/null && cat /tmp/.xlog_keep > /var/log/xray/access.log 2>/dev/null || true
        rm -f /tmp/.xlog_keep 2>/dev/null || true
    fi
    echo -e "${GREEN}[✔] RAM Cache & Logs safely clean ho gaye (User Data & Active SIM IPs 100% Safe)!${NC}"
    read -rp "Enter dabayein..." || true
}


case "${1:-}" in
    --fn)
        shift; FN="${1:-}"; shift || true
        if [[ "$FN" =~ ^(panel_|restart_all_services_menu$|smart_auto_doctor$|clean_ram_and_logs$) ]] && declare -F "$FN" >/dev/null 2>&1; then
            "$FN" "$@"; exit $?
        fi
        echo "Invalid function"; exit 2 ;;
    passwd|password|reset) panel_reset_credentials; exit 0 ;;
    port)                  panel_change_port; exit 0 ;;
    restart)               systemctl restart aliraza-panel; show_panel_info; exit 0 ;;
esac

if [[ ! -f "$INSTALLED_FLAG" || ! -x /usr/local/bin/xray ]]; then
    full_auto_installer
else
    if [[ ! -f "$PANEL_CONF" ]]; then
        echo -e "${CYAN}[*] Purani terminal-panel install mili - ab Web Panel me convert ho rahi hai...${NC}"
        ask_panel_credentials
        write_zainu_vip_banner; fix_ssh_auth_and_banner; fix_dropbear_core
        setup_cli_account_helper; install_liveips_helper
        install_web_panel
    fi
    show_panel_info
fi
