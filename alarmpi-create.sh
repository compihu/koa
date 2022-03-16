#!/bin/bash
set -ex

if [ $(id -u) != 0 ]; then
  echo "This script must be run as root!"
  exit false
fi

IMG="${1:-alarmpi.img}"
DST="${2:-alarmpi}"
CACHE="${3:-cache}"
ARCHIVE="ArchLinuxARM-rpi-armv7-latest.tar.gz"
URL="http://os.archlinuxarm.org/os/$ARCHIVE"

. ./alarmpi-secrets.sh

imgsize_mb=2000

if [ ! -d "$DST" ]; then mkdir "$DST"; fi

unset tgz_ok
unset downloaded

if [ -f "$ARCHIVE.md5" ]; then
  rm "$ARCHIVE.md5"
fi
wget "$URL".md5
upsmd5=$(cat "$ARCHIVE.md5" | cut -d ' ' -f1)

if [ -f "$ARCHIVE" ]; then
  imgmd5=$(md5sum "$ARCHIVE" | cut -d ' ' -f1)
  if [ $imgmd5 != $upsmd5 ]; then
    rm "$ARCHIVE"
    wget "$URL"
    downloaded=1
  fi
else
  wget "$URL"
  downloaded=1
fi

imgmd5=$(md5sum "$ARCHIVE"|cut -d ' ' -f1)
if [ $imgmd5 != $upsmd5 ]; then
  echo "Image checksum failure, giving up!"
  exit false
fi

if [ -f "$IMG" ]; then rm "$IMG"; fi
truncate -s 2000MB "$IMG"
#dd if=/dev/zero bs=1MB count=$imgsize_mb of="$IMG" oflag=sync status=progress
parted "$IMG" -s -- mklabel msdos \
  mkpart primary fat16 1MiB 200Mib \
  mkpart primary btrfs 200Mib 100%

parts=( $(kpartx -av "$IMG"|cut -f3 -d ' ') )
parts[0]=/dev/mapper/${parts[0]}
parts[1]=/dev/mapper/${parts[1]}

mkfs.msdos ${parts[0]}
mkfs.btrfs ${parts[1]}

mount ${parts[1]} "$DST" -ocompress=zstd:15
btrfs sub cre "$DST/@arch_root"
btrfs property set "$DST/@arch_root" compression zstd
umount "$DST"
mount ${parts[1]} "$DST" -ocompress=zstd:15,subvol=@arch_root
mkdir "$DST"/boot
mount ${parts[0]} "$DST"/boot

bsdtar -xpf ArchLinuxARM-rpi-armv7-latest.tar.gz -C "$DST"
sed -i -e 's/rw/rootflags=compress=zstd:15,subvol=@arch_root,relatime rw/' \
  -e 's/ console=serial0,115200//' \
  -e 's/ kgdboc=serial0,115200//' \
  "$DST/boot/cmdline.txt"

cat >>"$DST/boot/config.txt" <<-EOF

	[all]
	gpu_mem=16
	enable_uart=1
EOF

for d in dev run proc sys; do mount --bind /$d "$DST/$d"; done

if [ ! -d /run/systemd/resolve/ ]; then mkdir -p /run/systemd/resolve; fi
if [ ! -f /run/systemd/resolve/resolv.conf ]; then cp -L /etc/resolv.conf /run/systemd/resolve/; fi

cat >"$DST/etc/systemd/network/wlan.network" <<-EOF
	[Match]
	Name=wlan0

	[Network]
	DHCP=ipv4
EOF

cat >"$DST/etc/wpa_supplicant/wpa_supplicant-wlan0.conf" <<-EOF
	ctrl_interface=/var/run/wpa_supplicant
	ctrl_interface_group=0
	update_config=1

	network={

	  ssid="$WIFI_SSID"
	  psk="$WIFI_PASSWD"
	  key_mgmt=WPA-PSK
	  proto=WPA2
	  pairwise=CCMP TKIP
	  group=CCMP TKIP
	  scan_ssid=1
	}
EOF

sed -i -e "s/#en_US.UTF-8/en_US.UTF-8/" \
  -e "s/#hu_HU.UTF-8/hu_HU.UTF-8/" \
  -e "s/#nl_NL.UTF-8/nl_NL.UTF-8/" \
  "$DST/etc/locale.gen"

[ -d "$CACHE" ] || mkdir "$CACHE"
mount --bind "$CACHE" "$DST/var/cache/pacman"

cp alarmpi-setup.sh "$DST/"
chroot "$DST" /alarmpi-setup.sh

fuser -k "$DST"

