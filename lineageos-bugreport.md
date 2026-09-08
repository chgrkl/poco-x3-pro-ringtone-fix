# Fill-in for https://github.com/LineageOS/issues/issues/new?template=bugreport.yml
# (Copy each block into the corresponding template field. Attach both logs + the patch file.)

## Device Codename
vayu

## LineageOS Version
lineage-22.2 (nightly, e.g. 22.2-20260906-NIGHTLY-vayu)

## Build Date
20260906

## Kernel Version
# Fill in from Settings -> About phone -> Android version -> Kernel version
# (device was disconnected while writing this - example format: 4.14.357-perf-gXXXXXXXX)

## Baseband Version
# Fill in from Settings -> About phone -> Android version -> Baseband version

## System Modifications
None relevant to the issue. (USB debugging was enabled for diagnosis only; the bug
reproduces on an unmodified nightly. No Magisk, no system mods.)

## Expected Behavior
When a Bluetooth A2DP audio device (here: Phonak hearing aids, HFP + A2DP) is
connected and an incoming call arrives, the phone should play the ringtone audibly
(loudspeaker and/or the connected device), as it does when Bluetooth is off.

## Current Behavior
With the hearing aids connected, incoming calls only vibrate - no ringtone is audible
anywhere. After answering, call audio is correctly routed to the hearing aids.
With Bluetooth off, the ringtone plays normally from the loudspeaker.

Root cause (diagnosed with root access, but present in stock nightly):

Two independent effects stack:

1. Telecom routes the ringer in-band over BT-SCO because the device supports HFP.
   The hearing aids do not render SCO in-band ringtone, so nothing is audible.
   (While SCO audio is not running, Telecom still suppresses the local ringer,
   leaving only vibration.)

2. Even after disabling in-band ringing (persist.bluetooth.disableinbandringing),
   the phone stays silent. AudioPolicy routes STREAM_RING to
   SPEAKER+A2DP simultaneously (AOSP STRATEGY_SONIFICATION default).
   The Xiaomi primary audio HAL (audio.primary.msmnile.so) cannot handle this
   combined device patch and rejects the stream:

   09-08 20:13:47.771 E/msm8974_platform: platform_get_output_snd_device: Invalid combo device(0xa)
   09-08 20:13:47.771 E/audio_hw_primary: start_output_stream: failed to start ext hw plugin
   09-08 20:13:47.773 E/audio_hw_primary: pcm_open_prepare_helper: pcm_prepare returned -1

   The low-latency playback stream never starts, while A2DP is suspended during
   the call setup, so the ring is completely silent. This repeats for every
   start_output_stream attempt during ringing.

This is not specific to hearing aids: any A2DP sink without usable SCO in-band
ringting (BT speakers, A2DP-only headphones) hits the same HAL failure for the
ringtone, as the ring strategy always combines speaker + last removable media device.
Devices that mask it (HFP headsets with working in-band ringing) make it appear
rare.

## Possible Solution
The A2DP devicePorts are declared in the *primary* HAL module of
vendor/etc/audio_policy_configuration.xml (device tree: android_device_xiaomi_sm8150-common).
Moving A2DP to the separate "bluetooth" module (AOSP standard architecture, as on
Pixel devices) fixes the ringtone:

- Remove the three A2DP devicePorts ("BT A2DP Out/Headphones/Speaker") and their
  routes from the primary module
- Include /vendor/etc/bluetooth_audio_policy_configuration.xml (declares
  "a2dp output" in the bluetooth module, which already exists for hearing aid output)
  instead of bluetooth_hearing_aid_audio_policy_configuration.xml

AudioPolicy then opens a duplicated output (speaker thread + a2dp thread, one device
per HAL stream) for the ringtone instead of the combined speaker+A2DP patch, so the
Xiaomi HAL never receives the broken combo. Verified working: phone rings on the
loudspeaker, ringtone additionally streams into the hearing aids, call audio and
music (A2DP) unaffected.

Full diff against lineage-22.2 of android_device_xiaomi_sm8150-common:
https://github.com/chgrkl/poco-x3-pro-ringtone-fix (patches/audio_policy_configuration.patch)

## Steps to Reproduce
1. Pair a Bluetooth device that supports A2DP but has no usable HFP/SCO in-band
   ringtone (e.g. Phonak/Sonova hearing aids, or an A2DP-only speaker).
   (Reproduction is easiest if the device also connects HFP, as Telecom then
   additionally suppresses the local ringer; but the HAL failure alone is
   sufficient for a silent ring.)
2. Keep the device connected, make sure no other audio is playing.
3. Call the phone.
4. Observe: no ringtone anywhere, only vibration; logs show
   "Invalid combo device(0xa)" + "pcm_prepare returned -1" from audio_hw_primary
   each time the ringtone track starts.
5. Turn Bluetooth off, call again: ringtone plays normally from the loudspeaker.

## Attachments to include
- logs/hal-fail.log (from the linked repo, or your own logcat showing
  "Invalid combo device" during ringing)
- Your own fresh logcat captured right after reproducing, as required by the
  wiki (adb logcat while the call comes in with BT connected)

## Confirmation
- [x] I have read the directions at https://wiki.lineageos.org/how-to/bugreport