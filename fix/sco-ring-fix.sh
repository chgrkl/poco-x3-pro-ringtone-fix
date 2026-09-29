#!/system/bin/sh
# sco-ring-fix.sh - called by the sco-ring-fix init service at boot
# (see sco-ring-fix.rc). Re-applies the SCO ringtone strategy fix, which is
# in-memory AudioPolicy engine state and does not survive reboots.
#
# Layout on device (kept together in /data/local/tmp):
#   /data/local/tmp/sco-ring-fix.jar   - ScoRoleFix app_process tool
#   /data/local/tmp/sco-ring-fix.sh    - this script
# Log: /data/local/tmp/sco-ring-fix.log

LOG=/data/local/tmp/sco-ring-fix.log
JAR=/data/local/tmp/sco-ring-fix.jar

echo "$(date) sco-ring-fix start" >> "$LOG"

# AudioPolicyService may come up slightly later than boot_completed flag.
i=0
while [ $i -lt 30 ]; do
    dumpsys media.audio_policy >/dev/null 2>&1
    if [ $? -eq 0 ]; then
        break
    fi
    sleep 2
    i=$((i+1))
done

if [ ! -f "$JAR" ]; then
    echo "$(date) ERROR: $JAR missing" >> "$LOG"
    exit 1
fi

# strategy 1 = STRATEGY_SONIFICATION, role 2 = DEVICE_ROLE_DISABLED,
# native type 32 (0x20) = AUDIO_DEVICE_OUT_BLUETOOTH_SCO_HEADSET,
# empty address = matches all SCO devices.
CLASSPATH="$JAR" app_process / ScoRoleFix 1 2 set "" 32 >> "$LOG" 2>&1
echo "$(date) rc=$? waits=$i" >> "$LOG"