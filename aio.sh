#!/usr/bin/env bash

reinstall_warning() {
    echo ""
    echo "警告：此操作将重装系统，所有数据将丢失！"
    read -p "确认继续？(y/N): " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        echo "已取消"
        exit 0
    fi

    reinstall_password=$(tr -dc 'A-Za-z0-9' </dev/urandom | head -c 16)
    echo ""
    echo "=========================================="
    echo "新系统 root 密码: $reinstall_password"
    echo "请务必保存此密码！重装后需要用它登录"
    echo "=========================================="
    echo ""
}

reinstall_debian12_leitbogioro() {
    reinstall_warning
    bash <(curl -sSL "https://raw.githubusercontent.com/leitbogioro/Tools/master/Linux_reinstall/InstallNET.sh") -debian 12 -pwd "$reinstall_password"
}

reinstall_debian12_bin456789() {
    reinstall_warning
    bash <(curl -sSL "https://cnb.cool/bin456789/reinstall/-/git/raw/main/reinstall.sh") debian 12 --password "$reinstall_password"
}

reinstall_alpine_leitbogioro() {
    reinstall_warning
    bash <(curl -sSL "https://raw.githubusercontent.com/leitbogioro/Tools/master/Linux_reinstall/InstallNET.sh") -alpine -pwd "$reinstall_password"
}

reinstall_alpine_bin456789() {
    reinstall_warning
    bash <(curl -sSL "https://cnb.cool/bin456789/reinstall/-/git/raw/main/reinstall.sh") alpine 3.23 --password "$reinstall_password"
}

setup_swap() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "需要管理员权限"
        return 1
    fi

    if grep -qa "swapfile" /etc/fstab 2>/dev/null; then
        read -p "已存在swapfile，是否移除？(y/N): " confirm
        if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
            echo "已取消"
            return 0
        fi
        sed -i '/swapfile/d' /etc/fstab
        echo "3" > /proc/sys/vm/drop_caches
        swapoff -a
        rm -f /swapfile
        echo -e "swapfile已删除"
    fi

    local total_mem=$(free -m | grep Mem | awk '{print $2}')
    echo -e "当前系统内存: ${total_mem}M"
    read -p "请输入swapfile大小(MB):" swapsize
    if ! [[ "$swapsize" =~ ^[0-9]+$ ]] || [ "$swapsize" -lt 1 ]; then
        echo "无效输入"
        return 1
    fi

    local swap_ok=false
    for method in fallocate dd btrfs; do
        rm -f /swapfile
        if [ "$method" = "fallocate" ]; then
            if ! fallocate -l "${swapsize}M" /swapfile 2>/dev/null; then
                echo -e "fallocate 不可用，尝试 dd..."
                continue
            fi
        elif [ "$method" = "btrfs" ]; then
            if ! btrfs filesystem mkswapfile --size "${swapsize}M" /swapfile 2>/dev/null; then
                echo -e "btrfs 不可用，尝试 dd..."
                continue
            fi
        else
            echo -e "使用 dd 创建 swapfile..."
            if ! dd if=/dev/zero of=/swapfile bs=1M count="${swapsize}" status=progress 2>&1; then
                echo -e "dd 创建 swapfile 失败"
                rm -f /swapfile
                return 1
            fi
        fi

        if [ ! -f /swapfile ] || [ "$(stat -c%s /swapfile)" -lt 10240 ]; then
            echo -e "swapfile 文件异常，尝试其他方式..."
            continue
        fi

        chmod 600 /swapfile
        if ! mkswap /swapfile; then
            echo -e "mkswap 执行失败"
            continue
        fi

        if swapon /swapfile; then
            swap_ok=true
            break
        fi
        echo -e "swapon 失败（method=$method），尝试其他方式..."
    done

    if ! $swap_ok; then
        echo -e "所有方式均失败，无法创建 swap"
        rm -f /swapfile
        return 1
    fi

    echo '/swapfile none swap defaults 0 0' >> /etc/fstab
    echo -e "swap创建成功，并查看信息："
    cat /proc/swaps
    cat /proc/meminfo | grep Swap
}

nodequality() {
    bash <(curl -sL https://run.NodeQuality.com) <<< $'f\ny\nl\ny\n'
}

install_1panel() {
    bash -c "$(curl -sSL https://resource.fit2cloud.com/1panel/package/v2/quick_start.sh)"
}

install_docker() {
    bash <(curl -sSL 'https://get.docker.com')
}

enable_bbr() {
    grep -q "net.core.default_qdisc=fq" /etc/sysctl.conf || echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf
    grep -q "net.ipv4.tcp_congestion_control=bbr" /etc/sysctl.conf || echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf
    sysctl -p
    sysctl net.ipv4.tcp_available_congestion_control
    lsmod | grep bbr
}

install_fail2ban() {
    read -p "请输入要保护的 SSH 端口 (默认 22): " SSH_PORT
    SSH_PORT=${SSH_PORT:-22}
    if ! [[ "$SSH_PORT" =~ ^[0-9]+$ && "$SSH_PORT" -ge 1 && "$SSH_PORT" -le 65535 ]]; then
        echo "端口无效，使用默认 22"
        SSH_PORT=22
    fi

    # detect_os
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
        VERSION=$VERSION_ID
    elif type lsb_release >/dev/null 2>&1; then
        OS=$(lsb_release -si | tr '[:upper:]' '[:lower:]')
        VERSION=$(lsb_release -sr)
    elif [ -f /etc/redhat-release ]; then
        OS="rhel"
        VERSION=$(grep -oE '[0-9]+\.[0-9]+' /etc/redhat-release)
    elif [ -f /etc/alpine-release ]; then
        OS="alpine"
        VERSION=$(cat /etc/alpine-release)
    else
        OS=$(uname -s | tr '[:upper:]' '[:lower:]')
        VERSION=$(uname -r)
    fi


    # install_fail2ban
    echo -e "Detected system: $OS $VERSION"
    case "$OS" in
        ubuntu|debian)
            apt-get update
            if ! command -v rsyslogd >/dev/null 2>&1; then
                echo -e "rsyslog not installed. installing rsyslog..."
                apt-get install -y rsyslog
            else
                echo -e "rsyslog is already installed."
            fi
            apt-get install -y fail2ban
            ;;
        centos|rhel|fedora)
            if [ "$OS" = "rhel" ] && [ "${VERSION%%.*}" -ge 8 ]; then
                dnf install -y epel-release
                dnf install -y fail2ban
            else
                yum install -y epel-release
                yum install -y fail2ban
            fi
            ;;
        alpine)
            apk add --no-cache fail2ban
            ;;
        arch)
            pacman -Sy --noconfirm fail2ban
            ;;
        *)
            echo -e "Unsupported system"
            exit 1
            ;;
    esac

    # configure_fail2ban
    echo -e "Configure Fail2ban..."
    
    FAIL2BAN_CONF="/etc/fail2ban/jail.local"
    LOG_FILE=""
    BAN_ACTION=""

    if systemctl is-active --quiet firewalld 2>/dev/null; then
        BAN_ACTION="firewallcmd-ipset"
    elif systemctl is-active --quiet ufw 2>/dev/null || service ufw status 2>/dev/null | grep -q "active"; then
        BAN_ACTION="ufw"
    else
        BAN_ACTION="iptables-allports"
    fi

    if [ -f /var/log/secure ]; then
        LOG_FILE="/var/log/secure"
    else
        LOG_FILE="/var/log/auth.log"
        [ -f "$LOG_FILE" ] || touch "$LOG_FILE"
    fi

    cat <<EOF > "$FAIL2BAN_CONF"
[DEFAULT]
bantime = 3600
findtime = 300
maxretry = 5
banaction = $BAN_ACTION
action = %(action_)s

[sshd]
enabled = true
filter = sshd[mode=aggressive]
port = $SSH_PORT
logpath = $LOG_FILE
ignoreip = 127.0.0.1/8 ::1
EOF

    # start_service
    echo -e "Start Fail2ban..."
    
    case "$OS" in
        ubuntu|debian|centos|rhel|fedora|arch)
            systemctl enable fail2ban
            systemctl restart fail2ban
            ;;
        alpine)
            rc-update add fail2ban
            rc-service fail2ban start
            ;;
        *)
            echo -e "The service cannot be started automatically. Please start manually!"
            ;;
    esac

    if command -v systemctl &> /dev/null; then
        systemctl status fail2ban || true
    else
        rc-service fail2ban status || true
    fi

    echo -e "Fail2ban is installed and started"
}

uninstall_aliyun_monitor() {
    # https://help.aliyun.com/zh/security-center/user-guide/uninstall-the-security-center-agent#title-i7w-8p7-2bm

    echo "卸载云盾..."
    # 阿里云ECS服务器
    bash <(curl -sSL "http://update2.aegis.aliyun.com/download/uninstall.sh")
    # 非阿里云服务器（包括IDC机房、其他云厂商的服务器）
    bash <(curl -sSL "http://update.aegis.aliyun.com/download/uninstall.sh")


    # https://help.aliyun.com/zh/ecs/user-guide/stop-and-uninstall-the-cloud-assistant-agent#34fe9e2252yfj
    echo "停止云助手Agent守护进程..."
    if [ -f /usr/local/share/assist-daemon/assist_daemon ]; then
        /usr/local/share/assist-daemon/assist_daemon --stop
    fi

    echo "停止云助手Agent..."
    if command -v systemctl &> /dev/null; then
        systemctl stop aliyun.service 2>/dev/null
        systemctl disable aliyun.service 2>/dev/null
    elif [ -f /sbin/initctl ]; then
        /sbin/initctl stop aliyun-service
        /sbin/initctl disable aliyun-service
    elif [ -f /etc/init.d/aliyun-service ]; then
        /etc/init.d/aliyun-service stop
        /etc/init.d/aliyun-service disable
    fi

    echo "删除云助手守护进程..."
    if [ -f /usr/local/share/assist-daemon/assist_daemon ]; then
        /usr/local/share/assist-daemon/assist_daemon --delete
    fi

    echo "卸载云助手Agent..."
    if command -v rpm &> /dev/null; then
        rpm -qa | grep aliyun_assist | xargs -r sudo rpm -e
    elif command -v apt-get &> /dev/null; then
        apt-get purge -y aliyun-assist
    elif command -v dpkg &> /dev/null; then
        dpkg -r aliyun-assist
    fi

    echo "删除云助手残留文件..."
    rm -rf /usr/local/share/aliyun-assist
    rm -rf /usr/local/share/assist-daemon
    rm -f /etc/systemd/system/aliyun.service
    rm -f /etc/init.d/aliyun-service

    # https://help.aliyun.com/zh/cms/cloudmonitor-1-0/user-guide/install-and-uninstall-the-cloudmonitor-agent-for-cpp#section-hdw-doi-fv4
    echo "删除云监控..."
    if [ -f /usr/local/cloudmonitor/cloudmonitorCtl.sh ]; then
        bash /usr/local/cloudmonitor/cloudmonitorCtl.sh stop
        bash /usr/local/cloudmonitor/cloudmonitorCtl.sh uninstall
        rm -rf /usr/local/cloudmonitor
    fi

    echo "卸载完成"
}

uninstall_qcloud_monitor() {
    echo "开始清理腾讯云相关组件..."

    # https://www.tencentcloud.com/zh/document/product/248/39810

    echo "清理 qcloud相关定时任务..."
    crontab -l 2>/dev/null | grep -v 'qcloud' | crontab -

    echo "卸载 BaradAgent..."
    if [ -d /usr/local/qcloud/monitor/barad/admin ]; then
        if [ -f /usr/local/qcloud/monitor/barad/admin/stop.sh ]; then
            bash /usr/local/qcloud/monitor/barad/admin/stop.sh
        fi
        if [ -f /usr/local/qcloud/monitor/barad/admin/uninstall.sh ]; then
            bash /usr/local/qcloud/monitor/barad/admin/uninstall.sh
        fi
        rm -rf /usr/local/qcloud/monitor/barad
    fi

    echo "卸载 Sgagent..."
    if [ -f /etc/cron.d/sgagenttask ]; then
        rm -f /etc/cron.d/sgagenttask
    fi
    crontab -l 2>/dev/null | grep -v 'stargate' | crontab -
    if [ -d /usr/local/qcloud/stargate/admin ]; then
        if [ -f /usr/local/qcloud/stargate/admin/stop.sh ]; then
            bash /usr/local/qcloud/stargate/admin/stop.sh
        fi
        if [ -f /usr/local/qcloud/stargate/admin/uninstall.sh ]; then
            bash /usr/local/qcloud/stargate/admin/uninstall.sh
        fi
        rm -rf /usr/local/qcloud/stargate
    fi

    echo "卸载 YunJing..."
    if [ -f /usr/local/qcloud/YunJing/uninst.sh ]; then
        bash /usr/local/qcloud/YunJing/uninst.sh
        rm -rf /usr/local/qcloud/YunJing
    fi

    echo "卸载 tat_agent..."
    if [ -f /etc/systemd/system/tat_agent.service ]; then
        systemctl stop tat_agent.service
        systemctl disable tat_agent.service
        rm -f /etc/systemd/system/tat_agent.service
        rm -f /var/run/tat_agent.pid
    fi

    echo "终止相关进程..."
    process=(sap100 secu-tcs-agent sgagent barad_agent tat_agent agentPlugInD pvdriver)
    for i in "${process[@]}"; do
        for pid in $(ps aux | grep "$i" | grep -v grep | awk '{print $2}'); do
            echo "终止进程: $i (PID: $pid)"
            kill -9 "$pid" 2>/dev/null
        done
    done

    echo "删除相关目录..."
    rm -rf /usr/local/qcloud
    rm -rf /usr/local/sa
    rm -rf /usr/local/agenttools

    echo "卸载完成"
}

install_shadowsocks_rust() {
    if [[ $EUID -ne 0 ]]; then
        echo "需要管理员权限"
        return 1
    fi

    # detect_os
    local OS=""
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
    elif [ -f /etc/alpine-release ]; then
        OS="alpine"
    else
        OS=$(uname -s | tr '[:upper:]' '[:lower:]')
    fi

    local IS_ALPINE=false
    case "$OS" in
        debian|ubuntu)
            IS_ALPINE=false
            ;;
        alpine)
            IS_ALPINE=true
            ;;
        *)
            echo "仅支持 debian/ubuntu 和 alpine 系统 (当前: $OS)"
            return 1
            ;;
    esac

    # install_deps
    echo "==> 安装依赖..."
    if $IS_ALPINE; then
        apk update >/dev/null
        apk add --no-cache curl tar xz openssl ca-certificates openrc >/dev/null
    else
        export DEBIAN_FRONTEND=noninteractive
        apt-get update -qq
        apt-get install -y -qq curl tar xz-utils openssl ca-certificates >/dev/null
    fi

    # detect_arch
    local ARCH SS_ARCH
    ARCH=$(uname -m)
    case "$ARCH" in
        x86_64|amd64)   SS_ARCH="x86_64-unknown-linux-musl" ;;
        aarch64|arm64)  SS_ARCH="aarch64-unknown-linux-musl" ;;
        armv7l|armv7)   SS_ARCH="armv7-unknown-linux-musleabihf" ;;
        i686|i386)      SS_ARCH="i686-unknown-linux-musl" ;;
        *)
            echo "不支持的架构: $ARCH"
            return 1
            ;;
    esac

    # get_latest_version
    echo "==> 获取最新版本..."
    local LATEST_VERSION
    LATEST_VERSION=$(curl -fsSL --max-time 15 https://api.github.com/repos/shadowsocks/shadowsocks-rust/releases/latest \
        | grep -oE '"tag_name"[[:space:]]*:[[:space:]]*"[^"]+"' \
        | head -n1 \
        | sed -E 's/.*"([^"]+)"$/\1/')
    if [ -z "$LATEST_VERSION" ]; then
        echo "获取最新版本失败，请检查网络"
        return 1
    fi
    echo "最新版本: $LATEST_VERSION"

    local DOWNLOAD_URL="https://github.com/shadowsocks/shadowsocks-rust/releases/download/${LATEST_VERSION}/shadowsocks-${LATEST_VERSION}.${SS_ARCH}.tar.xz"
    echo "==> 下载: $DOWNLOAD_URL"

    local TMPDIR
    TMPDIR=$(mktemp -d)
    if ! curl -fL --retry 3 --max-time 300 -o "$TMPDIR/ss.tar.xz" "$DOWNLOAD_URL"; then
        echo "下载失败"
        rm -rf "$TMPDIR"
        return 1
    fi

    if ! tar -xJf "$TMPDIR/ss.tar.xz" -C "$TMPDIR"; then
        echo "解压失败"
        rm -rf "$TMPDIR"
        return 1
    fi

    # install_binaries
    echo "==> 安装二进制文件到 /usr/local/bin ..."
    local bin
    for bin in sslocal ssserver ssservice ssurl ssmanager; do
        if [ -f "$TMPDIR/$bin" ]; then
            install -m 755 "$TMPDIR/$bin" "/usr/local/bin/$bin"
        fi
    done
    rm -rf "$TMPDIR"

    if [ ! -x /usr/local/bin/ssserver ]; then
        echo "安装失败: 未找到 ssserver"
        return 1
    fi

    # generate_port_and_password
    local SS_PORT SS_PASSWORD SS_METHOD
    SS_PORT=$(shuf -i 10000-65000 -n 1 2>/dev/null \
        || awk -v min=10000 -v max=65000 'BEGIN{srand(); print int(min+rand()*(max-min+1))}')
    SS_PASSWORD=$(openssl rand -base64 16 2>/dev/null \
        || tr -dc 'A-Za-z0-9' </dev/urandom | head -c 22)
    SS_METHOD="2022-blake3-aes-128-gcm"

    # write_config
    echo "==> 生成配置文件..."
    mkdir -p /etc/shadowsocks-rust
    cat > /etc/shadowsocks-rust/config.json <<EOF
{
    "server": "::",
    "server_port": ${SS_PORT},
    "password": "${SS_PASSWORD}",
    "method": "${SS_METHOD}",
    "mode": "tcp_and_udp",
    "timeout": 300,
    "no_delay": true,
    "fast_open": false,
    "ipv6_first": false,
    "nofile": 51200
}
EOF
    chmod 600 /etc/shadowsocks-rust/config.json

    # setup_service
    if $IS_ALPINE; then
        echo "==> 创建 OpenRC 服务..."
        cat > /etc/init.d/shadowsocks-rust <<'EOF'
#!/sbin/openrc-run

name="shadowsocks-rust"
description="Shadowsocks-rust Server"
command="/usr/local/bin/ssserver"
command_args="-c /etc/shadowsocks-rust/config.json"
command_background="yes"
pidfile="/run/shadowsocks-rust.pid"
output_log="/var/log/shadowsocks-rust.log"
error_log="/var/log/shadowsocks-rust.log"
rc_ulimit="-n 51200"

depend() {
    need net
    after firewall
}
EOF
        chmod +x /etc/init.d/shadowsocks-rust
        rc-update add shadowsocks-rust default >/dev/null 2>&1
        rc-service shadowsocks-rust restart
        sleep 1
        rc-service shadowsocks-rust status || true
    else
        echo "==> 创建 systemd 服务..."
        cat > /etc/systemd/system/shadowsocks-rust.service <<EOF
[Unit]
Description=Shadowsocks-rust Server
Documentation=https://github.com/shadowsocks/shadowsocks-rust
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=/usr/local/bin/ssserver -c /etc/shadowsocks-rust/config.json
Restart=on-failure
RestartSec=3
LimitNOFILE=1048576
AmbientCapabilities=CAP_NET_BIND_SERVICE
CapabilityBoundingSet=CAP_NET_BIND_SERVICE
NoNewPrivileges=true
ProtectSystem=full
ProtectHome=true
PrivateTmp=true

[Install]
WantedBy=multi-user.target
EOF
        systemctl daemon-reload
        systemctl enable shadowsocks-rust >/dev/null 2>&1
        systemctl restart shadowsocks-rust
        sleep 1
        systemctl status shadowsocks-rust --no-pager -l || true
    fi

    # get_public_ip
    local PUBLIC_IP
    PUBLIC_IP=$(curl -fsSL --max-time 5 https://api.ipify.org 2>/dev/null \
        || curl -fsSL --max-time 5 https://ifconfig.me 2>/dev/null \
        || curl -fsSL --max-time 5 https://ipinfo.io/ip 2>/dev/null \
        || echo "YOUR_SERVER_IP")

    # build ss:// URL (SIP002, base64url without padding)
    local SS_USERINFO SS_USERINFO_B64 SS_URL
    SS_USERINFO="${SS_METHOD}:${SS_PASSWORD}"
    SS_USERINFO_B64=$(printf '%s' "$SS_USERINFO" | base64 | tr -d '\n=' | tr '/+' '_-')
    SS_URL="ss://${SS_USERINFO_B64}@${PUBLIC_IP}:${SS_PORT}#shadowsocks-rust"

    echo ""
    echo "=========================================="
    echo "shadowsocks-rust 安装完成"
    echo "=========================================="
    echo "版本:       ${LATEST_VERSION}"
    echo "服务器地址: ${PUBLIC_IP}"
    echo "服务器端口: ${SS_PORT}"
    echo "密码:       ${SS_PASSWORD}"
    echo "加密方式:   ${SS_METHOD}"
    echo "模式:       tcp_and_udp"
    echo ""
    echo "ss:// 链接:"
    echo "${SS_URL}"
    echo "=========================================="
    echo "配置文件: /etc/shadowsocks-rust/config.json"
    if $IS_ALPINE; then
        echo "服务管理: rc-service shadowsocks-rust {start|stop|restart|status}"
        echo "日志文件: /var/log/shadowsocks-rust.log"
    else
        echo "服务管理: systemctl {start|stop|restart|status} shadowsocks-rust"
        echo "查看日志: journalctl -u shadowsocks-rust -f"
    fi
    echo "=========================================="
}

install_vless_enc() {
    if [[ $EUID -ne 0 ]]; then
        echo "需要管理员权限"
        return 1
    fi

    # detect_os
    local OS=""
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
    elif [ -f /etc/alpine-release ]; then
        OS="alpine"
    else
        OS=$(uname -s | tr '[:upper:]' '[:lower:]')
    fi

    local IS_ALPINE=false
    case "$OS" in
        debian|ubuntu)
            IS_ALPINE=false
            ;;
        alpine)
            IS_ALPINE=true
            ;;
        *)
            echo "仅支持 debian/ubuntu 和 alpine 系统 (当前: $OS)"
            return 1
            ;;
    esac

    # install_deps
    echo "==> 安装依赖..."
    if $IS_ALPINE; then
        apk update >/dev/null
        apk add --no-cache curl unzip openssl ca-certificates openrc >/dev/null
    else
        export DEBIAN_FRONTEND=noninteractive
        apt-get update -qq
        apt-get install -y -qq curl unzip openssl ca-certificates >/dev/null
    fi

    # detect_arch
    local ARCH XRAY_ASSET
    ARCH=$(uname -m)
    case "$ARCH" in
        x86_64|amd64)   XRAY_ASSET="Xray-linux-64.zip" ;;
        aarch64|arm64)  XRAY_ASSET="Xray-linux-arm64-v8a.zip" ;;
        armv7l|armv7)   XRAY_ASSET="Xray-linux-arm32-v7a.zip" ;;
        i686|i386)      XRAY_ASSET="Xray-linux-32.zip" ;;
        *)
            echo "不支持的架构: $ARCH"
            return 1
            ;;
    esac

    # get_latest_version
    echo "==> 获取 Xray-core 最新版本..."
    local LATEST_VERSION
    LATEST_VERSION=$(curl -fsSL --max-time 15 https://api.github.com/repos/XTLS/Xray-core/releases/latest \
        | grep -oE '"tag_name"[[:space:]]*:[[:space:]]*"[^"]+"' \
        | head -n1 \
        | sed -E 's/.*"([^"]+)"$/\1/')
    if [ -z "$LATEST_VERSION" ]; then
        echo "获取最新版本失败，请检查网络"
        return 1
    fi
    echo "最新版本: $LATEST_VERSION"

    local DOWNLOAD_URL="https://github.com/XTLS/Xray-core/releases/download/${LATEST_VERSION}/${XRAY_ASSET}"
    echo "==> 下载: $DOWNLOAD_URL"

    local TMPDIR
    TMPDIR=$(mktemp -d)
    if ! curl -fL --retry 3 --max-time 300 -o "$TMPDIR/xray.zip" "$DOWNLOAD_URL"; then
        echo "下载失败"
        rm -rf "$TMPDIR"
        return 1
    fi

    if ! unzip -o "$TMPDIR/xray.zip" -d "$TMPDIR/xray" >/dev/null; then
        echo "解压失败"
        rm -rf "$TMPDIR"
        return 1
    fi

    # install_binary_and_geodata
    echo "==> 安装 xray 到 /usr/local/bin ..."
    if [ ! -f "$TMPDIR/xray/xray" ]; then
        echo "安装失败: 压缩包内未找到 xray 二进制"
        rm -rf "$TMPDIR"
        return 1
    fi
    install -m 755 "$TMPDIR/xray/xray" /usr/local/bin/xray

    mkdir -p /usr/local/share/xray
    local dat
    for dat in geoip.dat geosite.dat; do
        [ -f "$TMPDIR/xray/$dat" ] && install -m 644 "$TMPDIR/xray/$dat" "/usr/local/share/xray/$dat"
    done
    rm -rf "$TMPDIR"

    if [ ! -x /usr/local/bin/xray ]; then
        echo "安装失败: 未找到 xray"
        return 1
    fi

    # generate_credentials
    echo "==> 生成 UUID 与 VLESS Encryption 密钥..."
    local UUID
    UUID=$(/usr/local/bin/xray uuid 2>/dev/null || cat /proc/sys/kernel/random/uuid)

    # 使用 `xray vlessenc` 生成配对的 decryption / encryption
    # 采用 ML-KEM-768(后量子, Post-Quantum) 认证组；密钥串仅含 [A-Za-z0-9._-]，可直接用于 URL
    local ENC_OUT PQ_OUT DECRYPTION ENCRYPTION
    ENC_OUT=$(/usr/local/bin/xray vlessenc 2>/dev/null)
    # 定位输出中的 "ML-KEM-768" 段落(后量子)；若解析失败则回退到全部输出并取最后一组
    PQ_OUT=$(printf '%s\n' "$ENC_OUT" | awk '/ML-KEM-768/{flag=1} flag')
    [ -z "$PQ_OUT" ] && PQ_OUT="$ENC_OUT"
    ENCRYPTION=$(printf '%s\n' "$PQ_OUT" | grep -oE 'mlkem768x25519plus\.[^"[:space:]]+' | grep '\.0rtt\.' | tail -n1)
    DECRYPTION=$(printf '%s\n' "$PQ_OUT" | grep -oE 'mlkem768x25519plus\.[^"[:space:]]+' | grep -v '\.0rtt\.' | tail -n1)

    if [ -z "$DECRYPTION" ] || [ -z "$ENCRYPTION" ]; then
        echo "生成 VLESS Encryption 密钥失败（当前 Xray 版本可能过旧，未提供 vlessenc 命令）"
        return 1
    fi

    # generate_port
    local PORT
    PORT=$(shuf -i 10000-65000 -n 1 2>/dev/null \
        || awk -v min=10000 -v max=65000 'BEGIN{srand(); print int(min+rand()*(max-min+1))}')

    # write_config
    echo "==> 生成配置文件..."
    mkdir -p /usr/local/etc/xray
    cat > /usr/local/etc/xray/config.json <<EOF
{
    "log": {
        "loglevel": "warning"
    },
    "inbounds": [
        {
            "listen": "::",
            "port": ${PORT},
            "protocol": "vless",
            "settings": {
                "clients": [
                    {
                        "id": "${UUID}",
                        "flow": "xtls-rprx-vision"
                    }
                ],
                "decryption": "${DECRYPTION}"
            },
            "streamSettings": {
                "network": "tcp",
                "security": "none"
            }
        }
    ],
    "outbounds": [
        {
            "protocol": "freedom",
            "tag": "direct"
        }
    ]
}
EOF
    chmod 600 /usr/local/etc/xray/config.json

    # setup_service
    if $IS_ALPINE; then
        echo "==> 创建 OpenRC 服务..."
        cat > /etc/init.d/xray <<'EOF'
#!/sbin/openrc-run

name="xray"
description="Xray Service (VLESS Encryption)"
command="/usr/local/bin/xray"
command_args="run -c /usr/local/etc/xray/config.json"
command_background="yes"
pidfile="/run/xray.pid"
output_log="/var/log/xray.log"
error_log="/var/log/xray.log"
rc_ulimit="-n 51200"

export XRAY_LOCATION_ASSET=/usr/local/share/xray

depend() {
    need net
    after firewall
}
EOF
        chmod +x /etc/init.d/xray
        rc-update add xray default >/dev/null 2>&1
        rc-service xray restart
        sleep 1
        rc-service xray status || true
    else
        echo "==> 创建 systemd 服务..."
        cat > /etc/systemd/system/xray.service <<EOF
[Unit]
Description=Xray Service (VLESS Encryption)
Documentation=https://github.com/XTLS/Xray-core
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
Environment=XRAY_LOCATION_ASSET=/usr/local/share/xray
ExecStart=/usr/local/bin/xray run -c /usr/local/etc/xray/config.json
Restart=on-failure
RestartSec=3
LimitNOFILE=1048576
AmbientCapabilities=CAP_NET_BIND_SERVICE
CapabilityBoundingSet=CAP_NET_BIND_SERVICE
NoNewPrivileges=true
ProtectSystem=full
ProtectHome=true
PrivateTmp=true

[Install]
WantedBy=multi-user.target
EOF
        systemctl daemon-reload
        systemctl enable xray >/dev/null 2>&1
        systemctl restart xray
        sleep 1
        systemctl status xray --no-pager -l || true
    fi

    # get_public_ip
    local PUBLIC_IP
    PUBLIC_IP=$(curl -fsSL --max-time 5 https://api.ipify.org 2>/dev/null \
        || curl -fsSL --max-time 5 https://ifconfig.me 2>/dev/null \
        || curl -fsSL --max-time 5 https://ipinfo.io/ip 2>/dev/null \
        || echo "YOUR_SERVER_IP")

    # build vless:// share link (encryption 串仅含 URL 安全字符，无需转义)
    local VLESS_URL
    VLESS_URL="vless://${UUID}@${PUBLIC_IP}:${PORT}?encryption=${ENCRYPTION}&flow=xtls-rprx-vision&security=none&type=tcp#vless-enc-pq"

    echo ""
    echo "=========================================="
    echo "vless-enc (Xray-core) 安装完成"
    echo "=========================================="
    echo "版本:        ${LATEST_VERSION}"
    echo "服务器地址:  ${PUBLIC_IP}"
    echo "端口:        ${PORT}"
    echo "UUID:        ${UUID}"
    echo "传输:        tcp (RAW)"
    echo "流控 flow:   xtls-rprx-vision"
    echo "认证方式:    ML-KEM-768 (后量子 Post-Quantum)"
    echo "外层安全:    none (加密由 VLESS Encryption 提供，无需 TLS 证书)"
    echo ""
    echo "服务端 decryption:"
    echo "${DECRYPTION}"
    echo ""
    echo "客户端 encryption:"
    echo "${ENCRYPTION}"
    echo ""
    echo "vless:// 链接:"
    echo "${VLESS_URL}"
    echo "=========================================="
    echo "配置文件: /usr/local/etc/xray/config.json"
    if $IS_ALPINE; then
        echo "服务管理: rc-service xray {start|stop|restart|status}"
        echo "日志文件: /var/log/xray.log"
    else
        echo "服务管理: systemctl {start|stop|restart|status} xray"
        echo "查看日志: journalctl -u xray -f"
    fi
    echo "提示: 客户端两端 flow 均需为 xtls-rprx-vision，请使用支持 VLESS Encryption 的最新客户端(如 v2rayN、sing-box 等最新版)"
    echo "提示: VLESS Encryption 主要面向 CDN/中转/non-TLS 场景，若需直接抗封锁建议叠加 REALITY"
    echo "=========================================="
}

uninstall_vless_enc() {
    if [[ $EUID -ne 0 ]]; then
        echo "需要管理员权限"
        return 1
    fi

    read -p "确认卸载 vless-enc (Xray-core)？(y/N): " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        echo "已取消"
        return 0
    fi

    # remove_systemd_service
    if command -v systemctl >/dev/null 2>&1 && [ -f /etc/systemd/system/xray.service ]; then
        echo "==> 停止并移除 systemd 服务..."
        systemctl stop xray 2>/dev/null
        systemctl disable xray 2>/dev/null
        rm -f /etc/systemd/system/xray.service
        systemctl daemon-reload
        systemctl reset-failed xray 2>/dev/null || true
    fi

    # remove_openrc_service
    if command -v rc-service >/dev/null 2>&1 && [ -f /etc/init.d/xray ]; then
        echo "==> 停止并移除 OpenRC 服务..."
        rc-service xray stop 2>/dev/null
        rc-update del xray default 2>/dev/null
        rm -f /etc/init.d/xray
    fi

    # remove_binary_config_data_logs
    echo "==> 删除二进制/配置/数据/日志..."
    rm -f /usr/local/bin/xray
    rm -rf /usr/local/etc/xray
    rm -rf /usr/local/share/xray
    rm -f /var/log/xray.log

    echo ""
    echo "vless-enc (Xray-core) 已卸载完成"
}

setup_clean_journal() {
    if ! command -v journalctl &>/dev/null; then
        echo "未找到 journalctl 命令，此系统可能未使用 systemd 日志管理"
        echo "此功能仅适用于使用 systemd 的系统"
        return 1
    fi

    echo "当前日志占用空间："
    journalctl --disk-usage

    read -p "是否立即清理7天前的日志？(Y/n): " confirm
    confirm=${confirm:-y} 
    if [[ "$confirm" =~ ^[yY]$ ]]; then
        journalctl --vacuum-time=7d
        echo "日志清理完成"
    fi

    read -p "是否添加每周一0点自动清理7天前日志的定时任务？(Y/n): " add_confirm
    add_confirm=${add_confirm:-y} 
    if [[ "$add_confirm" =~ ^[yY]$ ]]; then
        crontab -l 2>/dev/null | grep -v "journalctl.*vacuum" | crontab -
        (
        crontab -l 2>/dev/null
        echo "0 0 * * 1 journalctl --vacuum-time=7d >/dev/null 2>&1"
        ) | crontab -
        echo "已添加定时任务"
    fi
}

schedule_traffic() {
    local SCRIPT_NAME="night_download"
    local SCRIPT_DIR="/opt/traffic"
    local SCRIPT_PATH="/opt/traffic/${SCRIPT_NAME}.sh"
    local LOG_FILE="/var/log/${SCRIPT_NAME}.log"

    mkdir -p "$SCRIPT_DIR"

cat > "$SCRIPT_PATH" << EOF
#!/bin/bash

LOG_FILE="$LOG_FILE"
EOF

cat << 'SCRIPT_EOF' >> "$SCRIPT_PATH"
LIMIT_RATE="5m"

URLS=(
  "https://sin-speed.hetzner.com/100MB.bin"
  "https://ash-speed.hetzner.com/100MB.bin"
  "https://fsn1-speed.hetzner.com/100MB.bin"
  "https://nbg1-speed.hetzner.com/100MB.bin"
  "https://hel1-speed.hetzner.com/100MB.bin"
  "https://hil-speed.hetzner.com/100MB.bin"
)

touch "$LOG_FILE"

get_pid() {
    pgrep -f "$0 run" | head -n1
}

download_one() {
    URL=${URLS[$RANDOM % ${#URLS[@]}]}
    echo "[$(date)] start downloading $URL" >> "$LOG_FILE"
    wget \
        --limit-rate="$LIMIT_RATE" \
        --timeout=15 \
        --tries=3 \
        -O /dev/null \
        "$URL" >/dev/null 2>&1
    echo "[$(date)] finish download $URL" >> "$LOG_FILE"
}

run() {
    trap 'exit 0' SIGTERM SIGINT
    echo "[$(date)] continuous download running, pid=$$" >> "$LOG_FILE"

    while true; do
        download_one
        sleep $((RANDOM % 8 + 3))
    done
}

run_once() {
    trap 'exit 0' SIGTERM SIGINT
    echo "[$(date)] single download running, pid=$$" >> "$LOG_FILE"
    download_one
    echo "[$(date)] single download finished" >> "$LOG_FILE"
}

start() {
    stop
    setsid "$0" run >/dev/null 2>&1 &
}

once() {
    stop
    setsid "$0" run_once >/dev/null 2>&1 &
}

stop() {
    PID=$(get_pid)
    if [ -n "$PID" ]; then
        PGID=$(ps -o pgid= -p "$PID" | tr -d ' ')
        echo "[$(date)] stopping download pgid=$PGID" >> "$LOG_FILE"
        kill -TERM -"$PGID" 2>/dev/null
    fi
}

status() {
    if [ -n "$(get_pid)" ]; then
        echo "running"
    else
        echo "stopped"
    fi
}

case "$1" in
    start)    start ;;
    once)     once ;;
    stop)     stop ;;
    status)   status ;;
    run)      run ;;
    run_once) run_once ;;
    *)
        echo "usage: $0 {start|once|stop|status}"
        echo "  start  - continuous download"
        echo "  once   - single download"
        echo "  stop   - stop any running download"
        echo "  status - check running status"
        exit 1
        ;;
esac
SCRIPT_EOF

    chmod +x "$SCRIPT_PATH"

    echo ""
    echo "Select cron mode:"
    echo "  1) Hourly once   - execute 'once' every hour"
    echo "  2) Nightly range - start at 03:00, stop at 06:00"
    read -r -p "Enter choice [1/2]: " CRON_MODE

    crontab -l 2>/dev/null | grep -vF "${SCRIPT_NAME}.sh" | crontab -

    case "$CRON_MODE" in
        1)
            (
            crontab -l 2>/dev/null
            echo "0 * * * * ${SCRIPT_PATH} once"
            ) | crontab -
            echo "[OK] Cron: hourly once"
            ;;
        2)
            (
            crontab -l 2>/dev/null
            echo "0 3 * * * ${SCRIPT_PATH} start"
            echo "0 6 * * * ${SCRIPT_PATH} stop"
            ) | crontab -
            echo "[OK] Cron: nightly 3:00-6:00"
            ;;
        *)
            echo "[WARN] Invalid choice, no cron installed"
            ;;
    esac

    echo "[OK] Installed successfully"
    echo "[OK] Script: $SCRIPT_PATH"
    echo "[OK] Log file: $LOG_FILE"
}

echo ""
echo "========== 功能菜单 =========="
echo "1) 一键重装 Debian 12 (leitbogioro)"
echo "2) 一键重装 Debian 12 (bin456789)"
echo "3) 一键重装 alpine (leitbogioro)"
echo "4) 一键重装 alpine (bin456789)"
echo "5) 设置交换内存"
echo "6) NodeQuality (快速硬件低流量)"
echo "7) 安装 1Panel"
echo "8) 安装 Docker"
echo "9) 开启 BBR"
echo "10) 安装 Fail2Ban"
echo "11) 卸载阿里云监控"
echo "12) 卸载腾讯云监控"
echo "13) 安装 vless-enc (Xray-core)"
echo "14) 卸载 vless-enc (Xray-core)"
echo "15) 设置自动清理系统日志"
echo "16) 定时跑下行流量"
echo "=================================="
read -p "请输入选项数字: " choice
case $choice in
    1) reinstall_debian12_leitbogioro ;;
    2) reinstall_debian12_bin456789 ;;
    3) reinstall_alpine_leitbogioro ;;
    4) reinstall_alpine_bin456789 ;;
    5) setup_swap ;;
    6) nodequality ;;
    7) install_1panel ;;
    8) install_docker ;;
    9) enable_bbr ;;
    10) install_fail2ban ;;
    11) uninstall_aliyun_monitor ;;
    12) uninstall_qcloud_monitor ;;
    13) install_vless_enc ;;
    14) uninstall_vless_enc ;;
    15) setup_clean_journal ;;
    16) schedule_traffic ;;
    *) echo "无效选项" ;;
esac
