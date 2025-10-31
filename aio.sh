#!/bin/bash

# GitHub 代理
GH_PROXY="https://gh.feulerloup.com"

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
    wget --no-check-certificate -qO InstallNET.sh "${GH_PROXY}/https://raw.githubusercontent.com/leitbogioro/Tools/master/Linux_reinstall/InstallNET.sh" \
        && chmod a+x InstallNET.sh \
        && bash InstallNET.sh -debian 12 -pwd "$(tr -dc 'A-Za-z0-9' </dev/urandom | head -c 16)"
}

add_swap() {
    bash <(curl -sSL "${GH_PROXY}/https://github.com/FeulerLoup/vps_bash/raw/refs/heads/main/swap.sh")
}

fusion_test() {
    export noninteractive=true
    curl -L "${GH_PROXY}/https://raw.githubusercontent.com/oneclickvirt/ecs/master/goecs.sh" -o goecs.sh
    chmod +x goecs.sh
    ./goecs.sh env
    ./goecs.sh install
    ./goecs.sh
}

install_1panel() {
    bash -c "$(curl -sSL https://resource.fit2cloud.com/1panel/package/v2/quick_start.sh)"
}

install_docker() {
    bash <(curl -sSL 'https://get.docker.com')
}

enable_bbr() {
    bash <(curl -sSL "${GH_PROXY}/https://github.com/FeulerLoup/vps_bash/raw/refs/heads/main/enable_bbr.sh")
}

install_fail2ban() {
    read -p "请输入要保护的 SSH 端口 (默认 22): " port
    port=${port:-22}
    if ! [[ "$port" =~ ^[0-9]+$ && "$port" -ge 1 && "$port" -le 65535 ]]; then
        echo "端口无效，使用默认 22"
        port=22
    fi
    curl -sSL "${GH_PROXY}/https://github.com/FeulerLoup/vps_bash/raw/refs/heads/main/install_fail2ban.sh" | bash -s -- -p "$port"
}

uninstall_aliyun_monitor() {
    bash <(curl -sSL "${GH_PROXY}/https://github.com/FeulerLoup/vps_bash/raw/refs/heads/main/uninstall_ali.sh")
}

uninstall_qcloud_monitor() {
    bash <(curl -sSL "${GH_PROXY}/https://github.com/FeulerLoup/vps_bash/raw/refs/heads/main/uninstall_qcloud.sh")
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
    wget -N "${GH_PROXY}/https://raw.githubusercontent.com/XrayR-project/XrayR-release/master/install.sh" && bash install.sh
    wget "${GH_PROXY}/https://raw.githubusercontent.com/Rakau/blockList/main/blockList" -O /etc/XrayR/rulelist
}

# 主菜单循环
while true; do
    echo ""
    echo "========== VPS 管理菜单 =========="
    echo "1) 一键重装 Debian 12"
    echo "2) 增加交换内存"
    echo "3) 融合测试"
    echo "4) 安装 1Panel"
    echo "5) 安装 Docker"
    echo "6) 开启 BBR"
    echo "7) 安装 Fail2Ban"
    echo "8) 卸载阿里云监控"
    echo "9) 卸载腾讯云监控"
    echo "10) 安装 XrayR"
    echo "0) 退出"
    echo "=================================="
    read -p "请输入选项数字: " choice
    case $choice in
        1) install_debian12 ;;
        2) add_swap ;;
        3) fusion_test ;;
        4) install_1panel ;;
        5) install_docker ;;
        6) enable_bbr ;;
        7) install_fail2ban ;;
        8) uninstall_aliyun_monitor ;;
        9) uninstall_qcloud_monitor ;;
        10) install_xrayr ;;
        0) exit 0 ;;
        *) echo "无效选项" ;;
    esac
done
