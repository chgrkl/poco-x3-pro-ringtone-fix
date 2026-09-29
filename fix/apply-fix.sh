#!/system/bin/sh
# Re-apply ringtone fix after a LineageOS update (device must be rooted, adb root works).
# Usage: adb push apply-fix.sh /data/local/tmp/ && adb shell sh /data/local/tmp/apply-fix.sh
# Needs ScoRoleFix.jar next to this script (fixes WhatsApp/VoIP silent ring, see FIX.md layer 4).
set -e

BT_DB=/data/user_de/0/com.android.bluetooth/databases/bluetooth_db
VENDOR_XML=/vendor/etc/audio_policy_configuration.xml
FIXDIR=$(cd "$(dirname "$0")" && pwd)
FIXED_XML=$FIXDIR/audio_policy_configuration.fixed.xml
SCOFIX_JAR=$FIXDIR/ScoRoleFix.jar
# MAC of the right hearing aid (identity address as stored in bluetooth_db)
HA_MAC="2C:53:D7:FE:67:A4"

echo "=== 1/5: audio policy overlay (vendor) ==="
if ! mount | grep -q "overlay.* /vendor "; then
    echo "ERROR: /vendor overlay not active. Run: adb disable-verity && adb reboot && adb root && adb remount"
    exit 1
fi
mount -o rw,remount /vendor 2>/dev/null || true
cp "$FIXED_XML" "$VENDOR_XML"
md5sum "$VENDOR_XML"

echo "=== 2/5: bluetooth profile policies ==="
cmd bluetooth_manager disable
sleep 6
PID=$(pidof com.android.bluetooth)
[ -n "$PID" ] && kill "$PID" && sleep 3
sqlite3 "$BT_DB" "UPDATE metadata SET hfp_connection_policy=100, pbap_connection_policy=100, a2dp_connection_policy=100 WHERE address='$HA_MAC';"
sqlite3 "$BT_DB" "SELECT address, a2dp_connection_policy, hfp_connection_policy, pbap_connection_policy FROM metadata;"

echo "=== 3/5: disable in-band ringing ==="
setprop persist.bluetooth.disableinbandringing true
getprop persist.bluetooth.disableinbandringing

echo "=== 4/5: disable SCO for SONIFICATION (WhatsApp/VoIP ring fix) ==="
# AudioPolicy engine: with SCO connected, STRATEGY_SONIFICATION routes the ringtone to
# SPEAKER+SCO simultaneously -> Xiaomi primary HAL fails ("Invalid combo device(0xa)")
# -> silence. Excluding SCO devices for the sonification strategy makes the ringtone
# fall back to SPEAKER(+A2DP). Call audio (STRATEGY_PHONE) is NOT affected.
# strategy 1 = STRATEGY_SONIFICATION, role 2 = DEVICE_ROLE_DISABLED,
# native type 32 (0x20) = AUDIO_DEVICE_OUT_BLUETOOTH_SCO_HEADSET, empty address = all SCO devices.
if [ -f "$SCOFIX_JAR" ]; then
    CLASSPATH="$SCOFIX_JAR" app_process / ScoRoleFix 1 2 set "" 32
else
    echo "WARN: ScoRoleFix.jar missing - WhatsApp ring fix skipped"
fi

echo "=== 5/5: reboot to activate ==="
echo "Rebooting in 5s..."
sleep 5
reboot