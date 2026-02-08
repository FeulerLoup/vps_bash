#!/bin/bash

set -e

# ===== 参数区 =====
TARGET_START_BJ=3   # 北京时间 03:00
TARGET_END_BJ=6     # 北京时间 06:00
SCRIPT_DIR="/opt/traffic"
SCRIPT_PATH="/opt/traffic/night_download.sh"
LOG_FILE="/var/log/night_download.log"

# ===== 检测时区偏移 =====
# 当前系统时间（UTC 偏移，单位小时）
LOCAL_OFFSET=$(date +%z | sed 's/^+//' | awk '{print substr($0,1,2)}')
LOCAL_OFFSET=${LOCAL_OFFSET#0}

# 北京时间 UTC+8
BJ_OFFSET=8

# 计算本地时间下的 cron 小时
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

echo "[\$(date)] night download started" >> "\$LOG_FILE"

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
echo "0 ${START_LOCAL} * * * ${SCRIPT_PATH} >/dev/null 2>&1 &"
echo "0 ${END_LOCAL} * * * pkill -f \"${SCRIPT_PATH}\""
) | crontab -

echo "[OK] Installed successfully"
echo "[OK] Log file: $LOG_FILE"

