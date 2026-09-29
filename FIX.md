# Klingelton-Fix: Poco X3 Pro (vayu) + Phonak Hörgeräte (Bluetooth)

## Problem
- Eingehender Anruf mit verbundenen Phonak-Hörgeräten: Telefon vibriert nur, kein Klingelton (weder Lautsprecher noch Hörgeräte).
- Ohne Bluetooth: Klingelton kommt korrekt aus dem Lautsprecher.

## Ursachen (4 Schichten)
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
4. **Gleicher HAL-Bug bei WhatsApp/VoIP via SCO** (neu, 2026-09-29): WhatsApp ruft beim
   eingehenden Anruf selbst `startBluetoothSco()` auf und setzt MODE_RINGTONE. Sobald
   SCO steht, kombiniert die Engine (LineageOS 22.2 `Engine.cpp`, STRATEGY_SONIFICATION:
   "if SCO headset is connected and comm device is SCO → ringtone over speaker AND SCO")
   Lautsprecher+SCO (0x2|0x8=0xa) im primary-HAL → derselbe "Invalid combo device"-Fehler
   → stummer WhatsApp-Klingelton. Der XML-Fix (Layer 3) greift hier nicht, weil SCO
   zwingend im primary-HAL läuft (HFP über audio_hw_hfp) und nicht ins bluetooth-Modul
   verschoben werden kann.

## Fixes (alle aktiv, Stand 2026-09-29)
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
5. **SCO für Klingelton-Strategie deaktiviert** (neu, 2026-09-29 – WhatsApp/VoIP-Klingelton):
   - `AudioSystem.setDevicesRoleForStrategy(STRATEGY_SONIFICATION=1, DEVICE_ROLE_DISABLED=2,
     [AUDIO_DEVICE_OUT_BLUETOOTH_SCO_HEADSET (0x20), ""])` – via `fix/sco-ring-fix.jar`
     (app_process-Tool, Reflection auf die @hide-API; läuft im permissive su-Kontext).
   - Bewirkt: Die Engine wirft SCO-Geräte aus der available-Liste der SONIFICATION-Strategie →
     der WhatsApp-Klingelton fällt auf Speaker(+A2DP) zurück, der 0xa-Combo-Patch entsteht nie.
   - Gesprächs-Audio (STRATEGY_PHONE, WhatsApp-Anruf) läuft weiter über SCO in die Hörgeräte.
   - Check: `adb shell dumpsys media.audio_policy | grep -A2 'Device role per product strategy'`
     → `Strategy(1) Device Role(2) Devices(AUDIO_DEVICE_OUT_BLUETOOTH_SCO_HEADSET, @:)`
   - **Reboot-sicher gemacht** (2026-09-29): `fix/sco-ring-fix.rc` installiert einen oneshot
     init-Service (`seclabel u:r:su:s0` – nur auf userdebug-Builds erlaubt, siehe
     system/sepolicy `private/init.te`), der nach `sys.boot_completed=1` automatisch
     `fix/sco-ring-fix.sh` startet und die Rolle neu setzt. Kein PC nach Reboot nötig.
     Log: `/data/local/tmp/sco-ring-fix.log`.
     Achtung: Die .rc liegt in /system → OTA wischt sie weg → nach ROM-Update einmal
     `apply-fix.sh` laufen lassen (Schritt 4/6 installiert den Hook neu).

## Ergebnis-Verhalten
- Klingeln (Telefon UND WhatsApp): **Telefon-Lautsprecher** (+ Klingelton in den Hörgeräten via A2DP)
- Anruf annehmen: Gesprächs-Audio automatisch in den Hörgeräten (HFP/SCO)
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
adb push fix/ /data/local/tmp/ringtone-fix/
adb shell sh /data/local/tmp/ringtone-fix/apply-fix.sh   # macht alle 6 Schritte + Reboot
```

## Nach normalen Reboots: nichts tun
Der Boot-Hook (`/system/etc/init/sco-ring-fix.rc` → Service startet
`/data/local/tmp/sco-ring-fix.sh`) setzt Fix 5 nach jedem Boot automatisch.
Kontrolle (optional): `adb shell cat /data/local/tmp/sco-ring-fix.log`

Falls der Hook fehlt (z.B. nach OTA ohne apply-fix.sh): einmalig vom PC
```bash
adb push fix/sco-ring-fix.sh fix/sco-ring-fix.jar /data/local/tmp/
adb shell "chmod 755 /data/local/tmp/sco-ring-fix.sh; sh /data/local/tmp/sco-ring-fix.sh"
# .rc zusätzlich ins /system legen (remount nötig):
adb remount && adb push fix/sco-ring-fix.rc /system/etc/init/sco-ring-fix.rc && adb reboot
```
Manuell ohne Hook (Notfall, gilt bis zum nächsten Reboot):
```bash
adb shell "CLASSPATH=/data/local/tmp/sco-ring-fix.jar app_process / ScoRoleFix 1 2 set '' 32"
adb shell "dumpsys media.audio_policy | grep -A2 'Device role per product strategy'"
```