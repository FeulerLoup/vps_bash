#!/bin/bash
# =========================================================
# 阿里云盾卸载与屏蔽脚本 (优化版)
# 支持 firewalld / nftables / iptables
# =========================================================

set -euo pipefail

AEGIS_INSTALL_DIR="/usr/local/aegis"
AEGIS_SYSTEMD_SERVICE_PATH="/etc/systemd/system/aegis.service"

log() { printf "[%s] %s\n" "$1" "$2"; }
ok() { printf "%-40s %40s\n" "$1" "[  OK  ]"; }

# ------------------------------
# 检测系统类型
# ------------------------------
detect_system() {
    local var=""
    if command -v lsb_release >/dev/null 2>&1; then
        var=$(lsb_release -a 2>/dev/null | grep Gentoo || true)
    fi
    if [ -z "$var" ] && [ -f /etc/issue ]; then
        var=$(grep Gentoo /etc/issue || true)
    fi

    local checkCoreos
    checkCoreos=$(grep -i coreos /etc/os-release 2>/dev/null || true)

    if [ -d "/etc/runlevels/default" ] && [ -n "$var" ]; then
        LINUX_RELEASE="GENTOO"
    elif [ -f "/etc/os-release" ] && [ -n "$checkCoreos" ]; then
        LINUX_RELEASE="COREOS"
        AEGIS_INSTALL_DIR="/opt/aegis"
    else
        LINUX_RELEASE="OTHER"
    fi
    log INFO "Detected system type: $LINUX_RELEASE"
}

# ------------------------------
# 停止 aegis 相关进程与驱动
# ------------------------------
stop_aegis() {
    log INFO "Stopping aegis processes..."
    pkill -9 AliHips 2>/dev/null || true
    "${AEGIS_INSTALL_DIR}/alihips/AliHips" --stopdriver 2>/dev/null || true

    for p in AliYunDun AliYunDunMonitor AliYunDunUpdate AliNet AliWebGuard AliDetect AliSecCheck; do
        pkill -9 "$p" 2>/dev/null || true
    done

    "${AEGIS_INSTALL_DIR}/AliNet/AliNet" --stopdriver 2>/dev/null || true
    "${AEGIS_INSTALL_DIR}/AliWebguard/AliWebGuard" --stopdriver 2>/dev/null || true

    DRIVER_OWNER_FILE_PATH="${AEGIS_INSTALL_DIR}/AliSecGuard/driver_owner.txt"
    if [ -f "$DRIVER_OWNER_FILE_PATH" ]; then
        local owner
        owner=$(cat "$DRIVER_OWNER_FILE_PATH")
        "$owner" --stopdriver 2>/dev/null || true
    fi

    pkill -9 aegis_cli aegis_update 2>/dev/null || true
    ok "Stopping aegis"
}

# ------------------------------
# 停止 aegis_quartz
# ------------------------------
stop_quartz() {
    pkill -9 aegis_quartz 2>/dev/null || true
    ok "Stopping quartz"
}

# ------------------------------
# 等待进程退出
# ------------------------------
wait_aegis_exit() {
    log INFO "Waiting aegis_client exit..."
    local retry=0
    while [ $retry -lt 10 ]; do
        if pgrep aegis_client >/dev/null 2>&1; then
            sleep 1
            ((retry++))
        else
            return 0
        fi
    done
    log ERROR "aegis_client still running after 10s, may be self-protected."
    exit 6
}

# ------------------------------
# 卸载服务
# ------------------------------
uninstall_service() {
    log INFO "Removing aegis service entries..."
    if [ -f "/etc/init.d/aegis" ]; then
        /etc/init.d/aegis stop >/dev/null 2>&1 || true
        rm -f /etc/init.d/aegis
    fi

    if [ "$LINUX_RELEASE" = "GENTOO" ]; then
        rc-update del aegis default 2>/dev/null || true
        rm -f /etc/runlevels/default/aegis >/dev/null 2>&1 || true
    else
        for ((i = 2; i <= 5; i++)); do
            rm -f "/etc/rc${i}.d/S80aegis" "/etc/rc.d/rc${i}.d/S80aegis" 2>/dev/null || true
        done
    fi

    # systemd
    if [ -f "$AEGIS_SYSTEMD_SERVICE_PATH" ]; then
        systemctl stop aegis 2>/dev/null || true
        systemctl disable aegis --no-reload 2>/dev/null || true
        rm -f "$AEGIS_SYSTEMD_SERVICE_PATH"
    fi
    ok "Removed aegis service"
}

# ------------------------------
# 删除 aegis 文件与挂载点
# ------------------------------
remove_aegis() {
    log INFO "Cleaning aegis directories..."

    local kprobe_paths=(
        "/sys/kernel/debug/tracing/instances/aegis_do_sys_open/set_event"
        "/sys/kernel/debug/tracing/instances/aegis_inet_csk_accept/set_event"
        "/sys/kernel/debug/tracing/instances/aegis_tcp_connect/set_event"
        "/sys/kernel/debug/tracing/instances/aegis/set_event"
        "/sys/kernel/debug/tracing/instances/aegis_/set_event"
        "/sys/kernel/debug/tracing/instances/aegis_accept/set_event"
        "/sys/kernel/debug/tracing/kprobe_events"
        "${AEGIS_INSTALL_DIR}/aegis_debug/tracing/set_event"
        "${AEGIS_INSTALL_DIR}/aegis_debug/tracing/kprobe_events"
    )
    for f in "${kprobe_paths[@]}"; do
        [ -f "$f" ] && echo >"$f"
    done

    mountpoint -q "${AEGIS_INSTALL_DIR}/aegis_debug" && umount "${AEGIS_INSTALL_DIR}/aegis_debug"
    [ -d "${AEGIS_INSTALL_DIR}/cgroup/cpu" ] && umount "${AEGIS_INSTALL_DIR}/cgroup/cpu" 2>/dev/null || true
    [ -d "${AEGIS_INSTALL_DIR}/cgroup" ] && umount "${AEGIS_INSTALL_DIR}/cgroup" 2>/dev/null || true

    if [[ -d "$AEGIS_INSTALL_DIR" && "$AEGIS_INSTALL_DIR" == /usr/local/aegis* ]]; then
        rm -rf "${AEGIS_INSTALL_DIR}/"{aegis_client,aegis_update,alihids}
        rm -f "${AEGIS_INSTALL_DIR}/globalcfg/"{install_info.ini,domaincfg.ini}
    fi

    ok "Removed aegis files"
}

# ------------------------------
# 清理 Aliyun 服务残余
# ------------------------------
remove_aliyun_residue() {
    log INFO "Cleaning aliyun-service residues..."
    pkill aliyun-service 2>/dev/null || true
    rm -f /etc/init.d/agentwatch /usr/sbin/aliyun-service /lib/systemd/system/aliyun.service
    rm -rf /usr/local/aegis*
    ok "Aliyun residue cleaned"
}

# ------------------------------
# 防火墙规则配置
# ------------------------------
BLOCK_IPS=(
  "140.205.201.0/28"
  "140.205.201.16/29"
  "140.205.201.32/28"
  "140.205.225.192/29"
  "140.205.225.200/30"
  "140.205.225.184/29"
  "140.205.225.183/32"
  "140.205.225.206/32"
  "140.205.225.205/32"
  "140.205.225.195/32"
  "140.205.225.204/32"
  "106.11.222.0/23"
  "106.11.224.0/24"
  "106.11.228.0/22"
)

apply_firewalld() {
    log INFO "Applying firewalld rules..."
    systemctl enable firewalld --now 2>/dev/null || true
    for ip in "${BLOCK_IPS[@]}"; do
        firewall-cmd --permanent --add-rich-rule="rule family='ipv4' source address='${ip}' drop" >/dev/null 2>&1 || true
    done
    firewall-cmd --reload || true
    ok "firewalld rules applied"
}

apply_nftables() {
    log INFO "Applying nftables rules..."
    systemctl enable nftables --now 2>/dev/null || true
    local conf_dir="/etc/nftables.d"
    mkdir -p "$conf_dir"
    local conf_file="$conf_dir/ali-block.nft"
    {
        echo "table inet filter {"
        echo " chain input {"
        for ip in "${BLOCK_IPS[@]}"; do
            echo "  ip saddr $ip drop"
        done
        echo " }"
        echo "}"
    } >"$conf_file"
    echo "include \"$conf_file\"" >>/etc/nftables.conf 2>/dev/null || true
    systemctl restart nftables || true
    ok "nftables rules applied"
}

apply_iptables() {
    log INFO "Applying iptables rules..."
    for ip in "${BLOCK_IPS[@]}"; do
        iptables -C INPUT -s "$ip" -j DROP 2>/dev/null || iptables -I INPUT -s "$ip" -j DROP
    done
    service iptables save 2>/dev/null || true
    ok "iptables rules applied"
}

apply_firewall_rules() {
    log INFO "Detecting firewall type..."
    if command -v firewall-cmd >/dev/null 2>&1; then
        apply_firewalld
    elif command -v nft >/dev/null 2>&1; then
        apply_nftables
    elif command -v iptables >/dev/null 2>&1; then
        apply_iptables
    else
        log ERROR "No supported firewall detected."
    fi
}

# ------------------------------
# 主流程
# ------------------------------
main() {
    if [ "$(id -u)" -ne 0 ]; then
        log ERROR "This script must be run as root."
        exit 8
    fi

    detect_system
    stop_aegis
    stop_quartz
    wait_aegis_exit
    uninstall_service
    remove_aegis
    remove_aliyun_residue
    apply_firewall_rules
    ok "Uninstalling aegis complete"
}

main
