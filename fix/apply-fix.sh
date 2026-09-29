#!/system/bin/sh
# Re-apply ringtone fix after a LineageOS update (device must be rooted, adb root works).
# Usage: adb push fix/ /data/local/tmp/ringtone-fix/ && adb shell sh /data/local/tmp/ringtone-fix/apply-fix.sh
# Needs the whole fix/ directory next to this script (see FIX.md for all layers).
set -e

BT_DB=/data/user_de/0/com.android.bluetooth/databases/bluetooth_db
VENDOR_XML=/vendor/etc/audio_policy_configuration.xml
FIXDIR=$(cd "$(dirname "$0")" && pwd)
FIXED_XML=$FIXDIR/audio_policy_configuration.fixed.xml
SCOFIX_JAR=$FIXDIR/sco-ring-fix.jar
# MAC of the right hearing aid (identity address as stored in bluetooth_db)
HA_MAC="2C:53:D7:FE:67:A4"

echo "=== 1/6: audio policy overlay (vendor) ==="
if ! mount | grep -q "overlay.* /vendor "; then
    echo "ERROR: /vendor overlay not active. Run: adb disable-verity && adb reboot && adb root && adb remount"
    exit 1
fi
mount -o rw,remount /vendor 2>/dev/null || true
cp "$FIXED_XML" "$VENDOR_XML"
md5sum "$VENDOR_XML"

echo "=== 2/6: bluetooth profile policies ==="
cmd bluetooth_manager disable
sleep 6
PID=$(pidof com.android.bluetooth)
[ -n "$PID" ] && kill "$PID" && sleep 3
sqlite3 "$BT_DB" "UPDATE metadata SET hfp_connection_policy=100, pbap_connection_policy=100, a2dp_connection_policy=100 WHERE address='$HA_MAC';"
sqlite3 "$BT_DB" "SELECT address, a2dp_connection_policy, hfp_connection_policy, pbap_connection_policy FROM metadata;"

echo "=== 3/6: disable in-band ringing ==="
setprop persist.bluetooth.disableinbandringing true
getprop persist.bluetooth.disableinbandringing

echo "=== 4/6: install SCO boot hook (reboot-persistent WhatsApp/VoIP ring fix) ==="
# The SCO role is in-memory AudioPolicy engine state and does not survive reboots.
# sco-ring-fix.rc installs a oneshot init service (seclabel u:r:su:s0, userdebug only)
# that re-applies it at every boot. The .rc lives in /system, so it needs the remount.
if [ -f "$FIXDIR/sco-ring-fix.rc" ] && [ -f "$FIXDIR/sco-ring-fix.sh" ] && [ -f "$SCOFIX_JAR" ]; then
    mount -o rw,remount /system 2>/dev/null || true
    cp "$FIXDIR/sco-ring-fix.rc" /system/etc/init/sco-ring-fix.rc
    cp "$FIXDIR/sco-ring-fix.sh" /data/local/tmp/sco-ring-fix.sh
    cp "$SCOFIX_JAR" /data/local/tmp/sco-ring-fix.jar
    chmod 755 /data/local/tmp/sco-ring-fix.sh
    ls -la /system/etc/init/sco-ring-fix.rc /data/local/tmp/sco-ring-fix.sh /data/local/tmp/sco-ring-fix.jar
else
    echo "WARN: sco-ring-fix files missing in $FIXDIR - boot hook NOT installed"
fi

echo "=== 5/6: apply SCO role now (no reboot needed for this part) ==="
# strategy 1 = STRATEGY_SONIFICATION, role 2 = DEVICE_ROLE_DISABLED,
# native type 32 (0x20) = AUDIO_DEVICE_OUT_BLUETOOTH_SCO_HEADSET, empty address = all SCO devices.
if [ -f /data/local/tmp/sco-ring-fix.jar ]; then
    CLASSPATH=/data/local/tmp/sco-ring-fix.jar app_process / ScoRoleFix 1 2 set "" 32
    dumpsys media.audio_policy | grep -A2 "Device role per product strategy"
else
    echo "WARN: sco-ring-fix.jar not in /data/local/tmp - run step 4 first"
fi

echo "=== 6/6: reboot to activate vendor overlay ==="
echo "Rebooting in 5s..."
sleep 5
reboot