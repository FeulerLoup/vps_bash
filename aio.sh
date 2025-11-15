#!/bin/bash

# 检查系统类型
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$ID
else
    echo "无法识别操作系统"
    exit 1
fi

# 安装 curl 如果不存在
install_curl_if_missing() {
    if ! command -v curl &>/dev/null; then
        echo "curl 未安装，尝试自动安装..."
        case $OS in
            debian|ubuntu)
                apt-get update && apt-get install -y curl
                ;;
            centos|rhel|rocky|almalinux)
                yum install -y curl
                ;;
            *)
                echo "未支持的系统，请手动安装 curl"
                exit 1
                ;;
        esac
    fi
}

install_curl_if_missing

# 函数定义
install_debian12() {
    echo "⚠️  一键重装 Debian 12 会清空系统数据！"
    read -p "确认继续？输入 YES 才执行: " confirm
    if [ "$confirm" != "YES" ]; then
        echo "已取消操作"
        return
    fi
    wget --no-check-certificate -qO InstallNET.sh "https://raw.githubusercontent.com/leitbogioro/Tools/master/Linux_reinstall/InstallNET.sh" \
        && chmod a+x InstallNET.sh \
        && bash InstallNET.sh -debian 12 -pwd "$(tr -dc 'A-Za-z0-9' </dev/urandom | head -c 16)"
}

add_swap() {
    bash <(curl -sSL "https://github.com/FeulerLoup/vps_bash/raw/refs/heads/main/swap.sh")
}

nodequality_test() {
    bash <(curl -sL https://run.NodeQuality.com)
}

install_1panel() {
    bash -c "$(curl -sSL https://resource.fit2cloud.com/1panel/package/v2/quick_start.sh)"
}

install_docker() {
    bash <(curl -sSL 'https://get.docker.com')
}

enable_bbr() {
    bash <(curl -sSL "https://github.com/FeulerLoup/vps_bash/raw/refs/heads/main/enable_bbr.sh")
}

install_fail2ban() {
    read -p "请输入要保护的 SSH 端口 (默认 22): " port
    port=${port:-22}
    if ! [[ "$port" =~ ^[0-9]+$ && "$port" -ge 1 && "$port" -le 65535 ]]; then
        echo "端口无效，使用默认 22"
        port=22
    fi
    curl -sSL "https://github.com/FeulerLoup/vps_bash/raw/refs/heads/main/install_fail2ban.sh" | bash -s -- -p "$port"
}

uninstall_aliyun_monitor() {
    bash <(curl -sSL "https://github.com/FeulerLoup/vps_bash/raw/refs/heads/main/uninstall_ali.sh")
}

uninstall_qcloud_monitor() {
    bash <(curl -sSL "https://github.com/FeulerLoup/vps_bash/raw/refs/heads/main/uninstall_qcloud.sh")
}

install_xrayr() {
    case $OS in
        debian|ubuntu)
            apt-get update
            apt-get install -y curl net-tools
            ;;
        centos|rhel|rocky|almalinux)
            yum install -y curl net-tools
            ;;
    esac
    wget -N "https://raw.githubusercontent.com/XrayR-project/XrayR-release/master/install.sh" && bash install.sh
    wget "https://raw.githubusercontent.com/Rakau/blockList/main/blockList" -O /etc/XrayR/rulelist
}

cleanup_journal_logs() {
    echo "开始检查日志清理功能..."
    
    # 检查 journalctl 命令是否存在
    if ! command -v journalctl &>/dev/null; then
        echo "❌ 未找到 journalctl 命令，此系统可能未使用 systemd 日志管理"
        echo "此功能仅适用于使用 systemd 的系统"
        return 1
    fi
    
    echo "✅ 检测到 journalctl 命令"
    
    # 显示当前日志占用空间
    echo ""
    echo "当前日志占用空间："
    journalctl --disk-usage
    
    # 清理7天前的日志
    echo ""
    read -p "是否立即清理7天前的日志？(Y/n): " confirm
    if [[ ! "$confirm" =~ ^[Nn]$ ]]; then
        echo "正在清理7天前的日志..."
        journalctl --vacuum-time=7d
        echo "✅ 日志清理完成"
        echo ""
        echo "清理后日志占用空间："
        journalctl --disk-usage
    else
        echo "已跳过立即清理"
    fi
    
    # 检查并添加定时任务
    echo ""
    echo "检查定时任务..."
    
    # 定时任务命令
    CRON_CMD="journalctl --vacuum-time=7d"
    CRON_JOB="0 0 * * 1 $CRON_CMD >/dev/null 2>&1"
    
    # 检查是否已存在相关定时任务
    if crontab -l 2>/dev/null | grep -q "journalctl.*vacuum"; then
        echo "✅ 已存在 journalctl 日志清理定时任务："
        crontab -l 2>/dev/null | grep "journalctl.*vacuum"
        echo ""
        read -p "是否需要更新为每周一0点执行？(Y/n): " update_confirm
        if [[ ! "$update_confirm" =~ ^[Nn]$ ]]; then
            # 删除旧的 journalctl vacuum 任务
            crontab -l 2>/dev/null | grep -v "journalctl.*vacuum" | crontab -
            # 添加新任务
            (crontab -l 2>/dev/null; echo "$CRON_JOB") | crontab -
            echo "✅ 定时任务已更新为每周一0点执行"
        else
            echo "保持现有定时任务不变"
        fi
    else
        echo "未找到相关定时任务"
        read -p "是否添加每周一0点自动清理7天前日志的定时任务？(Y/n): " add_confirm
        if [[ ! "$add_confirm" =~ ^[Nn]$ ]]; then
            # 添加新的定时任务
            (crontab -l 2>/dev/null; echo "$CRON_JOB") | crontab -
            echo "✅ 已添加定时任务：每周一0点自动清理7天前的日志"
            echo "定时任务详情："
            echo "$CRON_JOB"
        else
            echo "已取消添加定时任务"
        fi
    fi
    
    echo ""
    echo "当前所有定时任务："
    crontab -l 2>/dev/null || echo "无定时任务"
}

# 主菜单循环
while true; do
    echo ""
    echo "========== VPS 管理菜单 =========="
    echo "1) 一键重装 Debian 12"
    echo "2) 增加交换内存"
    echo "3) NodeQuality测试"
    echo "4) 安装 1Panel"
    echo "5) 安装 Docker"
    echo "6) 开启 BBR"
    echo "7) 安装 Fail2Ban"
    echo "8) 卸载阿里云监控"
    echo "9) 卸载腾讯云监控"
    echo "10) 安装 XrayR"
    echo "11) 清理系统日志"
    echo "0) 退出"
    echo "=================================="
    read -p "请输入选项数字: " choice
    case $choice in
        1) install_debian12 ;;
        2) add_swap ;;
        3) nodequality_test ;;
        4) install_1panel ;;
        5) install_docker ;;
        6) enable_bbr ;;
        7) install_fail2ban ;;
        8) uninstall_aliyun_monitor ;;
        9) uninstall_qcloud_monitor ;;
        10) install_xrayr ;;
        11) cleanup_journal_logs ;;
        0) exit 0 ;;
        *) echo "无效选项" ;;
    esac
done
