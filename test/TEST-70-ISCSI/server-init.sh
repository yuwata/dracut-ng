#!/bin/sh
exec < /dev/console > /dev/console 2>&1
set -x
export PATH=/usr/sbin:/usr/bin:/sbin:/bin
export TERM=linux
export PS1='server:\w\$ '
echo "made it to the rootfs!"
echo server > /proc/sys/kernel/hostname

wait_for_if_link() {
    local cnt=0
    local li
    while [ $cnt -lt 600 ]; do
        li=$(ip -o link show dev "$1" 2> /dev/null)
        [ -n "$li" ] && return 0
        sleep 0.1
        cnt=$((cnt + 1))
    done
    return 1
}

wait_for_if_up() {
    local cnt=0
    local li
    while [ $cnt -lt 200 ]; do
        li=$(ip -o link show up dev "$1")
        [ -n "$li" ] && return 0
        sleep 0.1
        cnt=$((cnt + 1))
    done
    return 1
}

wait_for_route_ok() {
    local cnt=0
    while [ $cnt -lt 200 ]; do
        li=$(ip route show)
        [ -n "$li" ] && [ -z "${li##*"$1"*}" ] && return 0
        sleep 0.1
        cnt=$((cnt + 1))
    done
    return 1
}

linkup() {
    wait_for_if_link "$1" 2> /dev/null && ip link set "$1" up 2> /dev/null && wait_for_if_up "$1" 2> /dev/null
}

wait_for_if_link enx525400123456
wait_for_if_link enx525400123457

ip addr add 127.0.0.1/8 dev lo
ip link set lo up

ip addr add 192.168.50.1/24 dev enx525400123456
linkup enx525400123456

ip addr add 192.168.51.1/24 dev enx525400123457
linkup enx525400123457

modprobe af_packet

: > /var/lib/dhcpd/dhcpd.leases
chmod 777 /var/lib/dhcpd/dhcpd.leases
dhcpd -d -cf /etc/dhcpd.conf -lf /var/lib/dhcpd/dhcpd.leases &

tgtd
tgtadm --lld iscsi --mode target --op new --tid 1 --targetname iqn.2009-06.dracut:target0
tgtadm --lld iscsi --mode target --op new --tid 2 --targetname iqn.2009-06.dracut:target1
tgtadm --lld iscsi --mode target --op new --tid 3 --targetname iqn.2009-06.dracut:target2
tgtadm --lld iscsi --mode logicalunit --op new --tid 1 --lun 1 -b /dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_singleroot
tgtadm --lld iscsi --mode logicalunit --op new --tid 2 --lun 2 -b /dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_raid0-1
tgtadm --lld iscsi --mode logicalunit --op new --tid 3 --lun 3 -b /dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_raid0-2
tgtadm --lld iscsi --mode target --op bind --tid 1 -I 192.168.50.101
tgtadm --lld iscsi --mode target --op bind --tid 2 -I 192.168.51.101
tgtadm --lld iscsi --mode target --op bind --tid 3 -I 192.168.50.101

# Wait forever for the VM to die
echo "Serving iSCSI"
while pidof tgtd > /dev/null; do
    : > /dev/watchdog
    dmesg -c
    sleep 1
done
dmesg -c
mount -n -o remount,ro /
poweroff -f
