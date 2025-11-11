#!/bin/bash
# ===============================================
# 脚本说明：
# 该脚本用于清理腾讯云相关组件和定时任务
# ===============================================

echo "开始清理腾讯云相关组件..."

# 1. 删除 crontab 中包含 'qcloud' 的行
echo "正在清理 crontab 中的 qcloud 任务..."
crontab -l 2>/dev/null | grep -v 'qcloud' | crontab -

# 2. 删除定时任务文件
echo "删除 /etc/cron.d/sgagenttask..."
rm -f /etc/cron.d/sgagenttask

# 3. 判断并执行卸载脚本
uninstall_scripts=(
  "/usr/local/qcloud/stargate/admin/uninstall.sh"
  "/usr/local/qcloud/YunJing/uninst.sh"
  "/usr/local/qcloud/monitor/barad/admin/uninstall.sh"
)

for script in "${uninstall_scripts[@]}"; do
  if [ -x "$script" ]; then
    echo "执行卸载脚本: $script"
    "$script"
  fi
done

# 4. 停止并移除 tat_agent 服务（如果存在）
if systemctl list-units --type=service | grep -q "tat_agent.service"; then
  echo "检测到 tat_agent 服务，正在停止并禁用..."
  systemctl stop tat_agent.service
  systemctl disable tat_agent.service
fi

# 删除服务文件
rm -f /etc/systemd/system/tat_agent.service

# 5. 删除相关目录
echo "删除相关目录..."
rm -rf /usr/local/qcloud
rm -rf /usr/local/sa
rm -rf /usr/local/agenttools

# 6. 停止相关进程
echo "终止相关进程..."
process=(sap100 secu-tcs-agent sgagent64 barad_agent agent agentPlugInD pvdriver)
for i in "${process[@]}"; do
  for pid in $(ps aux | grep "$i" | grep -v grep | awk '{print $2}'); do
    echo "终止进程: $i (PID: $pid)"
    kill -9 "$pid" 2>/dev/null
  done
done

echo "清理完成。"
