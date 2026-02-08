#!/bin/bash

set -e

# ===== 参数区 =====
TARGET_START_BJ=3
TARGET_END_BJ=6
SCRIPT_DIR="/opt/traffic"
SCRIPT_PATH="/opt/traffic/night_download.sh"
LOG_FILE="/var/log/night_download.log"

# ===== 检测时区偏移 =====
LOCAL_OFFSET=$(date +%z | sed 's/^+//' | awk '{print substr($0,1,2)}')
LOCAL_OFFSET=${LOCAL_OFFSET#0}
BJ_OFFSET=8

START_LOCAL=$(( (TARGET_START_BJ - BJ_OFFSET + LOCAL_OFFSET + 24) % 24 ))
END_LOCAL=$(( (TARGET_END_BJ - BJ_OFFSET + LOCAL_OFFSET + 24) % 24 ))

echo "[INFO] Local timezone UTC+${LOCAL_OFFSET}"
echo "[INFO] Beijing 03:00 => Local ${START_LOCAL}:00"
echo "[INFO] Beijing 06:00 => Local ${END_LOCAL}:00"

# ===== 创建下载脚本 =====
mkdir -p "$SCRIPT_DIR"

cat << 'SCRIPT_EOF' > "$SCRIPT_PATH"
#!/bin/bash

URLS=(
  "https://sin-speed.hetzner.com/10GB.bin"
  "https://sgp.proof.ovh.net/files/10Gb.dat"
  "https://dlied4.myapp.com/myapp/1104466820/cos.release-40109/10040714_com.tencent.tmgp.sgame_a2480356_8.2.1.9_F0BvnI.apk"
)

LIMIT_RATE="5m"
LOG_FILE="/var/log/night_download.log"

touch "$LOG_FILE"
echo "[\$(date)] night download started, pid=\$$" >> "\$LOG_FILE"

# 关键：确保 wget 继承同一进程组
trap 'exit 0' SIGTERM SIGINT

while true; do
    URL=\${URLS[\$RANDOM % \${#URLS[@]}]}
    echo "[\$(date)] downloading \$URL" >> "\$LOG_FILE"

    wget \
        --limit-rate=\$LIMIT_RATE \
        --timeout=15 \
        --tries=3 \
        -O /dev/null \
        "\$URL" >> "\$LOG_FILE" 2>&1

    sleep \$((RANDOM % 8 + 3))
done
SCRIPT_EOF

chmod +x "$SCRIPT_PATH"

# ===== 写入 cron（去重） =====
crontab -l 2>/dev/null | grep -v night_download.sh | crontab -

(
crontab -l 2>/dev/null
# 启动：setsid，创建新进程组
echo "0 ${START_LOCAL} * * * setsid ${SCRIPT_PATH} >/dev/null 2>&1 &"

# 停止：按进程组 kill
echo "0 ${END_LOCAL} * * * PGID=\$(ps -o pgid= -p \$(pgrep -f ${SCRIPT_PATH} | head -n1) | tr -d ' ') && [ -n \"\$PGID\" ] && kill -TERM -\$PGID"
) | crontab -

echo "[OK] Installed successfully"
echo "[OK] Log file: $LOG_FILE"
