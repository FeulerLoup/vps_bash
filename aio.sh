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

reinstall_debian13_leitbogioro() {
    reinstall_warning
    bash <(curl -sSL "https://raw.githubusercontent.com/leitbogioro/Tools/master/Linux_reinstall/InstallNET.sh") -debian 13 -pwd "$reinstall_password"
}

reinstall_debian13_bin456789() {
    reinstall_warning
    bash <(curl -sSL "https://cnb.cool/bin456789/reinstall/-/git/raw/main/reinstall.sh") debian 13 --password "$reinstall_password"
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
    bash <(curl -sL https://run.NodeQuality.com)
}

tcpquality() {
    bash <(curl -fsSL https://raw.githubusercontent.com/ibsgss/TcpQuality/main/runTcpQuality.sh)
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
    if [[ $EUID -ne 0 ]]; then
        echo "需要管理员权限"
        return 1
    fi

    # 自动识别当前 SSH 端口
    local DETECTED_PORT=""
    local PORT_CFG PORT_SOCK PORT_CONN PORT_LISTEN
    PORT_CFG=$(grep -ihE '^[[:space:]]*Port[[:space:]]+[0-9]+' /etc/ssh/sshd_config.d/*.conf /etc/ssh/sshd_config 2>/dev/null | awk '{print $2}' | head -n1)
    PORT_SOCK=$(grep -ihE '^[[:space:]]*ListenStream[[:space:]]*=[[:space:]]*.*[0-9]+[[:space:]]*$' /etc/systemd/system/ssh.socket.d/*.conf /etc/systemd/system/sshd.socket.d/*.conf 2>/dev/null | grep -oE '[0-9]+[[:space:]]*$' | tr -d '[:space:]' | tail -n1)
    [ -n "$SSH_CONNECTION" ] && PORT_CONN=$(awk '{print $4}' <<< "$SSH_CONNECTION")
    if command -v ss >/dev/null 2>&1; then
        PORT_LISTEN=$(ss -tlnp 2>/dev/null | awk '/sshd|dropbear/{if (match($4, /:[0-9]+$/)) {print substr($4, RSTART+1); exit}}')
    elif command -v netstat >/dev/null 2>&1; then
        PORT_LISTEN=$(netstat -tlnp 2>/dev/null | awk '/sshd|dropbear/{if (match($4, /:[0-9]+$/)) {print substr($4, RSTART+1); exit}}')
    fi

    for p in "$PORT_CFG" "$PORT_SOCK" "$PORT_CONN" "$PORT_LISTEN"; do
        if [[ "$p" =~ ^[0-9]+$ && "$p" -ge 1 && "$p" -le 65535 ]]; then
            [ -z "$DETECTED_PORT" ] && DETECTED_PORT="$p"
            if [ "$p" -ne 22 ]; then
                DETECTED_PORT="$p"
                break
            fi
        fi
    done
    [ -z "$DETECTED_PORT" ] && DETECTED_PORT=22

    read -p "请输入要保护的 SSH 端口 (默认 $DETECTED_PORT): " SSH_PORT
    SSH_PORT=${SSH_PORT:-$DETECTED_PORT}
    if ! [[ "$SSH_PORT" =~ ^[0-9]+$ && "$SSH_PORT" -ge 1 && "$SSH_PORT" -le 65535 ]]; then
        echo "端口无效，使用默认 $DETECTED_PORT"
        SSH_PORT=$DETECTED_PORT
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
            if ! command -v iptables >/dev/null 2>&1 && ! command -v nft >/dev/null 2>&1; then
                apt-get install -y iptables
            fi
            apt-get install -y fail2ban
            systemctl enable --now rsyslog 2>/dev/null || true
            ;;
        centos|rhel|fedora|rocky|almalinux|ol)
            if command -v dnf >/dev/null 2>&1; then
                [ "$OS" != "fedora" ] && dnf install -y epel-release
                dnf install -y fail2ban
            else
                [ "$OS" != "fedora" ] && yum install -y epel-release
                yum install -y fail2ban
            fi
            ;;
        alpine)
            apk add --no-cache fail2ban iptables
            ;;
        arch)
            pacman -Sy --noconfirm fail2ban
            ;;
        *)
            echo -e "Unsupported system: $OS"
            return 1
            ;;
    esac

    # configure_fail2ban
    echo -e "Configure Fail2ban..."
    
    FAIL2BAN_CONF="/etc/fail2ban/jail.local"
    LOG_FILE=""
    BAN_ACTION=""

    if systemctl is-active --quiet firewalld 2>/dev/null; then
        BAN_ACTION="firewallcmd-ipset"
    elif command -v ufw >/dev/null 2>&1 && ufw status 2>/dev/null | grep -q "Status: active"; then
        BAN_ACTION="ufw"
    elif ! command -v iptables >/dev/null 2>&1 && command -v nft >/dev/null 2>&1; then
        BAN_ACTION="nftables-allports"
    else
        BAN_ACTION="iptables-allports"
    fi

    if [ -f /var/log/secure ]; then
        LOG_FILE="/var/log/secure"
    elif [ "$OS" = "alpine" ] && [ ! -f /var/log/auth.log ]; then
        LOG_FILE="/var/log/messages"
        [ -f "$LOG_FILE" ] || touch "$LOG_FILE"
    else
        LOG_FILE="/var/log/auth.log"
        [ -f "$LOG_FILE" ] || touch "$LOG_FILE"
    fi

    cat <<EOF > "$FAIL2BAN_CONF"
[DEFAULT]
bantime   = 3600
findtime  = 300
maxretry  = 3
banaction = $BAN_ACTION
action    = %(action_)s

[sshd]
enabled   = true
filter    = sshd[mode=aggressive]
port      = $SSH_PORT
logpath   = $LOG_FILE
ignoreip  = 127.0.0.1/8 ::1
EOF

    # start_service
    echo -e "Start Fail2ban..."
    
    case "$OS" in
        ubuntu|debian|centos|rhel|fedora|rocky|almalinux|ol|arch)
            systemctl enable fail2ban
            systemctl restart fail2ban
            ;;
        alpine)
            rc-update add fail2ban default 2>/dev/null || rc-update add fail2ban
            rc-service fail2ban restart
            ;;
        *)
            echo -e "The service cannot be started automatically. Please start manually!"
            ;;
    esac

    if command -v systemctl &> /dev/null; then
        systemctl status fail2ban --no-pager -l || true
    else
        rc-service fail2ban status || true
    fi

    echo -e "Fail2ban is installed and started (SSH port: $SSH_PORT, banaction: $BAN_ACTION, logpath: $LOG_FILE)"
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
    if [[ $EUID -ne 0 ]]; then
        echo "需要管理员权限"
        return 1
    fi

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
    local PID_FILE="/var/run/tat_agent.pid"
    local TAT_AGENT="tat_agent"
    local TAT_INSTALL_SERVICE="tat_install"

    # 停止并清理 systemd 服务 (tat_agent.service & tat_install.service)
    if command -v systemctl >/dev/null 2>&1; then
        for svc in "${TAT_AGENT}.service" "${TAT_INSTALL_SERVICE}.service"; do
            if [ -e "/etc/systemd/system/${svc}" ] || systemctl list-unit-files "${svc}" >/dev/null 2>&1; then
                echo "Stopping and disabling systemd service: ${svc}"
                systemctl stop "${svc}" 2>/dev/null || true
                systemctl disable "${svc}" 2>/dev/null || true
                rm -f "/etc/systemd/system/${svc}"
                rm -f "/etc/systemd/system/multi-user.target.wants/${svc}"
                rm -f "/usr/lib/systemd/system/${svc}"
                rm -f "/lib/systemd/system/${svc}"
            fi
        done
        systemctl daemon-reload 2>/dev/null || true
        systemctl reset-failed 2>/dev/null || true
    fi

    # 停止并清理 upstart 服务 (tat_agent_service & tat_install)
    if [ -e /etc/init/tat_agent_service.conf ]; then
        echo "Stopping and removing upstart service: tat_agent_service"
        command -v initctl >/dev/null 2>&1 && initctl stop tat_agent_service 2>/dev/null || true
        rm -f /etc/init/tat_agent_service.conf
    fi

    if [ -e "/etc/init/${TAT_INSTALL_SERVICE}.conf" ]; then
        echo "Stopping and removing upstart service: ${TAT_INSTALL_SERVICE}"
        command -v stop >/dev/null 2>&1 && stop "${TAT_INSTALL_SERVICE}" 2>/dev/null || true
        command -v initctl >/dev/null 2>&1 && initctl stop "${TAT_INSTALL_SERVICE}" 2>/dev/null || true
        rm -f "/etc/init/${TAT_INSTALL_SERVICE}.conf"
    fi

    # 停止并清理 sysvinit 服务 (tat_agent_service & tat_install)
    for init_svc in "tat_agent_service" "${TAT_INSTALL_SERVICE}"; do
        if [ -e "/etc/init.d/${init_svc}" ]; then
            echo "Stopping and removing sysvinit service: ${init_svc}"
            "/etc/init.d/${init_svc}" stop 2>/dev/null || true
            if command -v chkconfig >/dev/null 2>&1; then
                chkconfig "${init_svc}" off 2>/dev/null || true
                chkconfig --del "${init_svc}" 2>/dev/null || true
            elif command -v update-rc.d >/dev/null 2>&1; then
                update-rc.d -f "${init_svc}" remove 2>/dev/null || true
            fi
            rm -f "/etc/init.d/${init_svc}"
        fi
    done

    # 终止残留进程并清理 PID 文件
    if [ -f "${PID_FILE}" ]; then
        local PID
        PID=$(cat "${PID_FILE}" 2>/dev/null || echo 0)
        if [ -n "${PID}" ] && [ "${PID}" -gt 0 ] 2>/dev/null; then
            if ps -p "${PID}" 2>/dev/null | grep -q "${TAT_AGENT}"; then
                echo "Killing ${TAT_AGENT} process (PID: ${PID})"
                kill -9 "${PID}" 2>/dev/null || true
            fi
        fi
        rm -f "${PID_FILE}"
    fi
    rm -f /run/tat_agent.pid

    # 兜底清理可能未写入 PID 文件的残留进程
    if command -v pkill >/dev/null 2>&1; then
        pkill -9 -x "${TAT_AGENT}" 2>/dev/null || true
        pkill -9 -f "/qcloud/tat_agent/install/init_install.sh" 2>/dev/null || true
    fi

    # 清理二进制软链接、安装目录、运行日志、自更新缓存及安装包临时目录
    rm -f "/usr/local/bin/${TAT_AGENT}"
    rm -f "/opt/bin/${TAT_AGENT}"
    rm -f "/usr/sbin/${TAT_AGENT}"
    rm -rf /usr/local/qcloud/tat_agent
    rm -rf /var/lib/qcloud/tat_agent
    rm -rf /usr/local/qcloud/tat_agent_install
    rm -rf /var/lib/qcloud/tat_agent_install
    rm -f /tmp/tat_agent_install.tar.gz

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
    rm -rf /var/lib/qcloud
    rm -rf /usr/local/sa
    rm -rf /usr/local/agenttools

    echo "卸载完成"
}

echo ""
echo "========== 功能菜单 =========="
echo "1) 一键重装 Debian 13 (leitbogioro)"
echo "2) 一键重装 Debian 13 (bin456789)"
echo "3) 一键重装 alpine (leitbogioro)"
echo "4) 一键重装 alpine (bin456789)"
echo "5) 设置交换内存"
echo "6) NodeQuality"
echo "7) TcpQuality"
echo "8) 安装 1Panel"
echo "9) 安装 Docker"
echo "10) 开启 BBR"
echo "11) 安装 Fail2Ban"
echo "12) 卸载阿里云监控"
echo "13) 卸载腾讯云监控"
echo "=================================="
read -p "请输入选项数字: " choice
case $choice in
    1) reinstall_debian13_leitbogioro ;;
    2) reinstall_debian13_bin456789 ;;
    3) reinstall_alpine_leitbogioro ;;
    4) reinstall_alpine_bin456789 ;;
    5) setup_swap ;;
    6) nodequality ;;
    7) tcpquality ;;
    8) install_1panel ;;
    9) install_docker ;;
    10) enable_bbr ;;
    11) install_fail2ban ;;
    12) uninstall_aliyun_monitor ;;
    13) uninstall_qcloud_monitor ;;
    *) echo "无效选项" ;;
esac
