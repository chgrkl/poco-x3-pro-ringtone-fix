# Poco X3 Pro (vayu) – Silent Ringtone Fix for Bluetooth Hearing Aids / A2DP

**Device:** POCO X3 Pro (vayu), LineageOS 22.2 (Android 15)  
**Symptom:** Incoming calls only vibrate when Phonak hearing aids (or other A2DP devices
without usable in-band ringing) are connected. Without Bluetooth, the ringtone plays
normally from the loudspeaker. After answering, call audio is routed to the hearing aids.

## Root Cause (three layers)

### 1. Telecom in-band ringing (Telecom)
With HFP connected, Telecom routes the ringtone in-band over BT-SCO into the hearing aids.
Phonak hearing aids (ASHA) do not render SCO ringtone → silence + vibration.
Handled by system property `persist.bluetooth.disableinbandringing=true`.

### 2. Disabled HFP profile
The hearing aids' `hfp_connection_policy` was `0` (FORBIDDEN) in the Bluetooth metadata
database, so call audio could not reach the hearing aids at all.
Fixed in `bluetooth_db` (table `metadata`).

### 3. Xiaomi vendor audio HAL bug (the actual silencing)
Android's audio policy routes the ringtone to **speaker + A2DP simultaneously**
(AOSP default for STRATEGY_SONIFICATION, see `Engine.cpp`).
Xiaomi's `audio.primary.msmnile.so` cannot handle this combined patch:

```
msm8974_platform: platform_get_output_snd_device: enter: output devices(0xa) ...
msm8974_platform: platform_get_output_snd_device: Invalid combo device(0xa)
audio_hw_primary: start_output_stream: failed to start ext hw plugin
audio_hw_primary: pcm_open_prepare_helper: pcm_prepare returned -1   ← stream never starts
```

The speaker stream fails to start, while A2DP is suspended during ringing (HFP/SCO call
setup) → completely silent ring, only vibration.

**Evidence logs:** see `logs/hal-fail.log`, `logs/telecom-ring-silent.log`

## The Fix

Move A2DP from the `primary` HAL module to the separate `bluetooth` module
(this is AOSP's standard architecture, as used on Pixel devices):

* Remove the three A2DP `devicePort`s and their `route`s from the `primary` module in
  `vendor/etc/audio_policy_configuration.xml`
* Include `bluetooth_audio_policy_configuration.xml` (declares `a2dp output` in the
  `bluetooth` module) instead of the hearing-aid-only variant

AudioPolicy then opens a **duplicated output** (speaker thread + A2DP thread, one device
per HAL stream) for the ringtone instead of the combined speaker+A2DP patch.
The broken combo never reaches the Xiaomi HAL.

Result: phone rings on the loudspeaker **and** the ringtone streams into the hearing
aids; music playback via A2DP keeps working; calls are routed to the hearing aids.

Full diff: `patches/audio_policy_configuration.patch`  
Upstream source of the file: `LineageOS/android_device_xiaomi_sm8150-common/audio/audio_policy_configuration.xml`

## Repository layout

```
FIX.md                                      # German write-up of the whole debugging session
fix/apply-fix.sh                            # Re-apply script after LineageOS updates (root)
fix/audio_policy_configuration.fixed.xml    # Fixed XML to push to /vendor
patches/audio_policy_configuration.orig.xml # Original (from device, identical to upstream)
patches/audio_policy_configuration.fixed.xml
patches/audio_policy_configuration.patch    # Unified diff vs. upstream sm8150-common tree
logs/hal-fail.log                           # HAL failure evidence (Invalid combo device 0xa)
logs/telecom-ring-silent.log               # Telecom ring/route evidence
```

## Apply (rooted device, `adb root` available)

```bash
adb disable-verity && adb reboot && adb wait-for-device
adb root && adb remount
adb push fix/audio_policy_configuration.fixed.xml /vendor/etc/audio_policy_configuration.xml
adb shell cmd bluetooth_manager disable; sleep 6
adb shell "kill $(adb shell pidof com.android.bluetooth)"; sleep 3
adb shell "sqlite3 /data/user_de/0/com.android.bluetooth/databases/bluetooth_db \
  \"UPDATE metadata SET hfp_connection_policy=100, pbap_connection_policy=100 WHERE address='2C:53:D7:FE:67:A4';\""
adb shell setprop persist.bluetooth.disableinbandringing true
adb reboot
```

Or push the repo to the device and run `fix/apply-fix.sh` there.

## Affected devices

The vendor HAL bug exists on all sm8150 (vayu/SM8150) devices shipping this
`audio_policy_configuration.xml` (POCO X3 Pro and other sm8150-common Xiaomi devices),
potentially including MIUI/HyperOS. It becomes audible whenever the ringtone must be
played on speaker while an A2DP device is connected — most notably with hearing aids
(no working in-band ringing), but also reproducible with A2DP-only speakers/headsets
that are not SCO-capable.

## Upstream report

Filed against LineageOS device tree `android_device_xiaomi_sm8150-common`
(the `audio_policy_configuration.xml` originates there). The patch in
`patches/` can be applied directly in that repository.

## License

Logs and findings: public domain. The XML file retains its original
Linux Foundation / Android Open Source Project license headers.