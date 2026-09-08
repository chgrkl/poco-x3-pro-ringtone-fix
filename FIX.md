# Klingelton-Fix: Poco X3 Pro (vayu) + Phonak Hörgeräte (Bluetooth)

## Problem
- Eingehender Anruf mit verbundenen Phonak-Hörgeräten: Telefon vibriert nur, kein Klingelton (weder Lautsprecher noch Hörgeräte).
- Ohne Bluetooth: Klingelton kommt korrekt aus dem Lautsprecher.

## Ursachen (3 Schichten)
1. **Telecom/In-Band-Ringing**: Bei verbundem HFP-Profil routet Telecom den Klingelton
   in-band über BT-SCO in die Hörgeräte. Phonak (ASHA) gibt SCO-Klingeln nicht wieder.
2. **HFP-Profil verboten**: `hfp_connection_policy=0` (FORBIDDEN) für das Phonak in der
   Bluetooth-Metadaten-DB (bluetooth_db) verhinderte die Anruf-Ausgabe in die Hörgeräte.
3. **Xiaomi Vendor-HAL-Bug (eigentliche Stumm-Schaltung)**: Der Klingelton wird von der
   AOSP-Audio-Policy auf Lautsprecher+A2DP *gleichzeitig* geroutet (Standard-Verhalten).
   Xiaomis `audio.primary.msmnile.so` kann diese Kombi nicht:
   `platform_get_output_snd_device: Invalid combo device(0xa)` →
   `pcm_prepare returned -1` → Lautsprecher-Stream startet nie → komplett stumm.
   (A2DP ist zusätzlich beim Klingeln wegen HFP/SCO suspendiert.)

## Fixes (alle aktiv, Stand 2026-09-08)
1. **`persist.bluetooth.disableinbandringing=true`** (Property, reboot-sicher)
   - Deaktiviert In-Band-Ringing global: Telecom klingelt lokal statt in SCO zu routen.
   - Check: `adb shell dumpsys bluetooth_manager | grep -A6 "Profile: HeadsetService"`
     → `isInbandRingingEnabled: false`
2. **Bluetooth-DB gepatcht** (`/data/user_de/0/com.android.bluetooth/databases/bluetooth_db`,
   Tabelle `metadata`, Adresse `2C:53:D7:FE:67:A4`):
   - `hfp_connection_policy=100`  (Anruf-Audio in die Hörgeräte)
   - `pbap_connection_policy=100` (Anrufer-ID in den Hörgeräten)
   - `a2dp_connection_policy=100` (Musik-Streaming)
   - Achtung: BT-Prozess vorher stoppen, sonst überschreibt der Shutdown-Flush die Werte!
3. **Vendor-Audio-Policy gepatcht** (`/vendor/etc/audio_policy_configuration.xml`,
   via `adb disable-verity` + Reboot + `adb root && adb remount` → OverlayFS):
   - A2DP-DevicePorts (`BT A2DP Out/Headphones/Speaker`) + zugehörige Routes aus dem
     Modul `primary` entfernt.
   - Statt `bluetooth_hearing_aid_audio_policy_configuration.xml` wird
     `bluetooth_audio_policy_configuration.xml` eingebunden (enthält A2DP + Hearing Aid).
   - Effekt: A2DP läuft im separaten `bluetooth`-HAL-Modul. Die Policy erzeugt für den
     Klingelton einen *duplicated output* (Lautsprecher-Thread + A2DP-Thread, je 1 Gerät)
     statt der kombinierten Lautsprecher+A2DP-Route an einer HAL → HAL-Bug umgangen.
   - Ergebnis: Telefon klingelt am Lautsprecher, Klingelton/Musik zusätzlich in den Hörgeräten.
4. **A2DP-Offload deaktiviert** (`vendor.audio.feature.a2dp_offload.enable=false`, odm-Build.prop
   sagt `true`) – optional; ohne Offload läuft A2DP über das Bluetooth-Modul (Software-Encoding).

## Ergebnis-Verhalten
- Klingeln: **Telefon-Lautsprecher** (+ Klingelton in den Hörgeräten via A2DP)
- Anruf annehmen: Gesprächs-Audio automatisch in den Hörgeräten (HFP)
- Musik: weiter per A2DP in den Hörgeräten

## Bekannte Einschränkungen
- **LineageOS-Nightly-Update überschreibt Fix 3** (und evtl. 1, wenn /data persist bleibt nein –
  persist-Props und bluetooth_db überleben Updates; nur die vendor-XML im Overlay wird beim
  ROM-Flash zurückgesetzt, OverlayFS-Scratch wird geleert). Nach jedem Nightly: Re-Patch nötig.
- Testanruf-Verifikation: 20:43 Uhr – Telefon klingelte (siehe `dumpsys telecom`, START_RINGER
  + lokale Ringtone-Player mit `deviceIds:[3]` = Speaker).
- Falls Klingelton in Hörgeräten zu leise: Anruf/A2DP-Lautstärke separat einstellen
  (Lautstärke-Taste während Klingeln/Musik).

## Wiederverwendung nach ROM-Update
```bash
adb disable-verity && adb reboot            # nur nach Flash neu nötig
adb root && adb remount
adb push audio_policy_configuration.xml /vendor/etc/audio_policy_configuration.xml
adb shell cmd bluetooth_manager disable; adb shell kill $(adb shell pidof com.android.bluetooth)
adb shell sqlite3 /data/user_de/0/com.android.bluetooth/databases/bluetooth_db \
  "UPDATE metadata SET hfp_connection_policy=100, pbap_connection_policy=100 WHERE address='2C:53:D7:FE:67:A4';"
adb shell setprop persist.bluetooth.disableinbandringing true
adb reboot
```