#!/usr/bin/env bash

Green="\033[32m"
Font="\033[0m"
Red="\033[31m" 

#root权限
root_need(){
    if [[ $EUID -ne 0 ]]; then
        echo -e "${Red}Error:This script must be run as root!${Font}"
        exit 1
    fi
}

#检测ovz
ovz_no(){
    if [[ -d "/proc/vz" ]]; then
        echo -e "${Red}Your VPS is based on OpenVZ，not supported!${Font}"
        exit 1
    fi
}

add_swap(){
# 获取当前总内存（单位：M）
total_mem=$(free -m | grep Mem | awk '{print $2}')
echo -e "${Green}当前系统总内存: ${total_mem}M${Font}"
echo -e "${Green}请输入需要添加的swap，建议为内存的2倍！${Font}"
read -p "请输入swap数值:" swapsize

#检查是否存在swapfile
grep -q "swapfile" /etc/fstab

#如果不存在将为其创建swap
if [ $? -ne 0 ]; then
	echo -e "${Green}swapfile未发现，正在为其创建swapfile${Font}"
	
	# 尝试使用 fallocate 创建 swap 文件
	fallocate -l ${swapsize}M /swapfile
	
	# 检查 fallocate 是否成功
	if [ $? -ne 0 ]; then
		echo -e "${Red}fallocate 命令失败，尝试使用 dd 命令创建...${Font}"
		# 使用 dd 命令作为备用方案
		dd if=/dev/zero of=/swapfile bs=1M count=${swapsize}
		
		# 检查 dd 是否成功
		if [ $? -ne 0 ]; then
			echo -e "${Red}swap文件创建失败！${Font}"
			exit 1
		fi
	fi
	
	# 检查文件是否创建成功且大小正确
	if [ ! -f /swapfile ] || [ $(stat -c%s /swapfile) -lt 10240 ]; then
		echo -e "${Red}swap文件创建失败或文件过小！${Font}"
		rm -f /swapfile
		exit 1
	fi
	
	chmod 600 /swapfile
	mkswap /swapfile
	
	# 检查 mkswap 是否成功
	if [ $? -ne 0 ]; then
		echo -e "${Red}mkswap 执行失败！${Font}"
		rm -f /swapfile
		exit 1
	fi
	
	swapon /swapfile
	
	# 检查 swapon 是否成功
	if [ $? -ne 0 ]; then
		echo -e "${Red}swapon 执行失败！${Font}"
		rm -f /swapfile
		exit 1
	fi
	
	echo '/swapfile none swap defaults 0 0' >> /etc/fstab
	echo -e "${Green}swap创建成功，并查看信息：${Font}"
	cat /proc/swaps
	cat /proc/meminfo | grep Swap
else
	echo -e "${Red}swapfile已存在，swap设置失败，请先运行脚本删除swap后重新设置！${Font}"
fi
}

del_swap(){
#检查是否存在swapfile
grep -q "swapfile" /etc/fstab

#如果存在就将其移除
if [ $? -eq 0 ]; then
	echo -e "${Green}swapfile已发现，正在将其移除...${Font}"
	sed -i '/swapfile/d' /etc/fstab
	echo "3" > /proc/sys/vm/drop_caches
	swapoff -a
	rm -f /swapfile
    echo -e "${Green}swap已删除！${Font}"
else
	echo -e "${Red}swapfile未发现，swap删除失败！${Font}"
fi
}

#开始菜单
main(){
root_need
ovz_no
clear
echo -e "———————————————————————————————————————"
echo -e "${Green}Linux VPS一键添加/删除swap脚本${Font}"
echo -e "${Green}1、添加swap${Font}"
echo -e "${Green}2、删除swap${Font}"
echo -e "———————————————————————————————————————"
read -p "请输入数字 [1-2]:" num
case "$num" in
    1)
    add_swap
    ;;
    2)
    del_swap
    ;;
    *)
    clear
    echo -e "${Green}请输入正确数字 [1-2]${Font}"
    sleep 2s
    main
    ;;
    esac
}
main