#!/system/bin/sh
# Re-apply ringtone fix after a LineageOS update (device must be rooted, adb root works).
# Usage: adb push apply-fix.sh /data/local/tmp/ && adb shell sh /data/local/tmp/apply-fix.sh
set -e

BT_DB=/data/user_de/0/com.android.bluetooth/databases/bluetooth_db
VENDOR_XML=/vendor/etc/audio_policy_configuration.xml
FIXED_XML=$(dirname "$0")/audio_policy_configuration.fixed.xml
# MAC of the right hearing aid (identity address as stored in bluetooth_db)
HA_MAC="2C:53:D7:FE:67:A4"

echo "=== 1/4: audio policy overlay (vendor) ==="
if ! mount | grep -q "overlay.* /vendor "; then
    echo "ERROR: /vendor overlay not active. Run: adb disable-verity && adb reboot && adb root && adb remount"
    exit 1
fi
mount -o rw,remount /vendor 2>/dev/null || true
cp "$FIXED_XML" "$VENDOR_XML"
md5sum "$VENDOR_XML"

echo "=== 2/4: bluetooth profile policies ==="
cmd bluetooth_manager disable
sleep 6
PID=$(pidof com.android.bluetooth)
[ -n "$PID" ] && kill "$PID" && sleep 3
sqlite3 "$BT_DB" "UPDATE metadata SET hfp_connection_policy=100, pbap_connection_policy=100, a2dp_connection_policy=100 WHERE address='$HA_MAC';"
sqlite3 "$BT_DB" "SELECT address, a2dp_connection_policy, hfp_connection_policy, pbap_connection_policy FROM metadata;"

echo "=== 3/4: disable in-band ringing ==="
setprop persist.bluetooth.disableinbandringing true
getprop persist.bluetooth.disableinbandringing

echo "=== 4/4: reboot to activate ==="
echo "Rebooting in 5s..."
sleep 5
reboot