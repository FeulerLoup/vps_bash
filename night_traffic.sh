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

# ===== 创建主脚本 =====
mkdir -p "$SCRIPT_DIR"

cat << 'SCRIPT_EOF' > "$SCRIPT_PATH"
#!/bin/bash

LOG_FILE="/var/log/night_download.log"
LIMIT_RATE="5m"

URLS=(
  "https://sin-speed.hetzner.com/100MB.bin"
  "https://ash-speed.hetzner.com/100MB.bin"
  "https://fsn1-speed.hetzner.com/100MB.bin"
  "https://nbg1-speed.hetzner.com/100MB.bin"
  "https://hel1-speed.hetzner.com/100MB.bin"
  "https://hil-speed.hetzner.com/100MB.bin"
  "https://dlied4.myapp.com/myapp/1104466820/cos.release-40109/10040714_com.tencent.tmgp.sgame_a2480356_8.2.1.9_F0BvnI.apk"
)

touch "$LOG_FILE"

get_pid() {
    pgrep -f "$0 run" | head -n1
}

start() {
    if [ -n "$(get_pid)" ]; then
        echo "[$(date)] already running" >> "$LOG_FILE"
        exit 0
    fi

    echo "[$(date)] starting night download" >> "$LOG_FILE"
    setsid "$0" run >/dev/null 2>&1 &
}

stop() {
    PID=$(get_pid)
    if [ -z "$PID" ]; then
        echo "[$(date)] not running" >> "$LOG_FILE"
        exit 0
    fi

    PGID=$(ps -o pgid= -p "$PID" | tr -d ' ')
    echo "[$(date)] stopping night download pgid=$PGID" >> "$LOG_FILE"
    kill -TERM -"$PGID"
}

status() {
    if [ -n "$(get_pid)" ]; then
        echo "running"
    else
        echo "stopped"
    fi
}

run() {
    trap 'exit 0' SIGTERM SIGINT
    echo "[$(date)] night download running, pid=$$" >> "$LOG_FILE"

    while true; do
        URL=${URLS[$RANDOM % ${#URLS[@]}]}
        echo "[$(date)] downloading $URL" >> "$LOG_FILE"

        wget \
            --limit-rate="$LIMIT_RATE" \
            --timeout=15 \
            --tries=3 \
            -O /dev/null \
            "$URL" >/dev/null 2>&1

        sleep $((RANDOM % 8 + 3))
    done
}

case "$1" in
    start) start ;;
    stop) stop ;;
    status) status ;;
    run) run ;;
    *)
        echo "usage: $0 {start|stop|status}"
        exit 1
        ;;
esac
SCRIPT_EOF

chmod +x "$SCRIPT_PATH"

# ===== 写入 cron =====
crontab -l 2>/dev/null | grep -v night_download.sh | crontab -

(
crontab -l 2>/dev/null
echo "0 ${START_LOCAL} * * * ${SCRIPT_PATH} start"
echo "0 ${END_LOCAL} * * * ${SCRIPT_PATH} stop"
) | crontab -

echo "[OK] Installed successfully"
echo "[OK] Script: $SCRIPT_PATH"
echo "[OK] Log file: $LOG_FILE"
