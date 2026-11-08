#!/bin/bash
# Install a large APK over a flaky usbip link: push 4MB chunks with retries,
# reassemble on device, verify md5, pm install.
APK=${1:-/home/tukinga/workspace/xiaozhi-android-client/build/app/outputs/flutter-apk/app-debug.apk}
S=$(mktemp -d)
rm -rf "$S"; mkdir -p "$S"
split -b 4M -d "$APK" "$S/p"
ok() { adb reconnect offline >/dev/null 2>&1; timeout 20 adb wait-for-device; }
ok; adb shell 'rm -rf /data/local/tmp/apkparts; mkdir -p /data/local/tmp/apkparts'
for f in "$S"/p*; do
  n=$(basename "$f"); sz=$(stat -c %s "$f")
  for t in 1 2 3 4 5 6 7 8; do
    adb shell "ls -l /data/local/tmp/apkparts/$n" 2>/dev/null | grep -q " $sz " && break
    ok; timeout 60 adb push "$f" "/data/local/tmp/apkparts/$n" >/dev/null 2>&1 || sleep 3
  done
done
ok
adb shell 'cat /data/local/tmp/apkparts/p* > /data/local/tmp/app.apk'
want=$(md5sum "$APK" | cut -d' ' -f1)
got=$(adb shell md5sum /data/local/tmp/app.apk | cut -d' ' -f1)
[ "$want" = "$got" ] || { echo "md5 mismatch $want $got"; exit 1; }
adb shell pm install -r /data/local/tmp/app.apk
adb shell 'rm -rf /data/local/tmp/apkparts /data/local/tmp/app.apk'
