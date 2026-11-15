#!/bin/sh
# Free as much RAM as possible on the ESP32-S31 before compiling.
for s in /etc/init.d/S*ble* /etc/init.d/S*bluetooth* /etc/init.d/S*mdns* /etc/init.d/S*cron* /etc/init.d/S*dropbear* /etc/init.d/S*wifi* /etc/init.d/S*syslog* /etc/init.d/S*thread*; do
  [ -x "$s" ] && "$s" stop >/dev/null 2>&1
done
killall -q wpa_supplicant wpa_cli udhcpc bluetoothd mdnsd crond dropbear syslogd klogd 2>/dev/null
echo 0 > /proc/sys/vm/page-cluster
swapoff /dev/zram0 2>/dev/null
mkdir -p /root/tmp
sync; echo 3 > /proc/sys/vm/drop_caches
free; cat /proc/swaps
