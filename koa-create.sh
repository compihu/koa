#!/bin/bash
set -ex

IMG="${1:-koa.img}"
DST="${2:-koa}"
CACHE="${3:-cache}"
BUILD="${4:-build}"
ARCHIVE="ArchLinuxARM-rpi-armv7-latest.tar.gz"
URL="http://os.archlinuxarm.org/os/$ARCHIVE"
QEMU="/usr/local/bin/qemu-arm-static"
# K,M,G -> *1024; KB,MB,GB -> *1000
imgsize=2500M


qemu_local=$(which qemu-arm-static 2>/dev/null || true)
if [ -z "$qemu_local" ]; then
  echo "qemu-arm-static binary cannot be found on PATH, giving up!"
  exit 1
fi

if [ ! -f user/mcu.config ]; then
  echo "Create user/mcu.config for compiling MCU firmware"
  exit 1
fi

if [ ! -x user/secrets.sh ]; then
  echo "Create user/secrets.sh to set WIFI_SSID and WIFI_PASSWD"
  exit 1
fi

. user/secrets.sh

if [ ! -d "$DST" ]; then mkdir "$DST"; fi


# verifying and downloading the tarball if necessary
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


# Creating the image file, partition and mount it
if [ -f "$IMG" ]; then rm "$IMG"; fi
truncate -s ${imgsize} "$IMG"
parted "$IMG" -s -- mklabel msdos \
  mkpart primary fat16 1MiB 150Mib \
  mkpart primary btrfs 150Mib 100%

parts=( $(sudo kpartx -av "$IMG"|cut -f3 -d ' ') )
parts[0]=/dev/mapper/${parts[0]}
parts[1]=/dev/mapper/${parts[1]}

sudo mkfs.msdos -n KOA-BOOT ${parts[0]}
sudo mkfs.btrfs -f -L koa-root ${parts[1]}

sudo mount ${parts[1]} "$DST" -ocompress=zstd:15
sudo btrfs sub cre "$DST/@koa_root"
sudo btrfs property set "$DST/@koa_root" compression zstd
sudo umount "$DST"
sudo mount ${parts[1]} "$DST" -ocompress=zstd:15,subvol=@koa_root
sudo mkdir "$DST"/boot
sudo mount ${parts[0]} "$DST"/boot


# Extracting the tarball and preparing chroot
sudo bsdtar -xpf "$ARCHIVE" -C "$DST"
sudo cp "$qemu_local" "$DST/usr/local/bin/"

for d in dev run proc sys; do sudo mount --bind /$d "$DST/$d"; done

if [ ! -d /run/systemd/resolve/ ]; then sudo mkdir -p /run/systemd/resolve; fi
if [ ! -f /run/systemd/resolve/resolv.conf ]; then sudo cp -L /etc/resolv.conf /run/systemd/resolve/; fi

USRID=$(cat "$DST/etc/passwd"|grep ^alarm | cut -d: -f3)
GRPID=$(cat "$DST/etc/passwd"|grep ^alarm | cut -d: -f4)

sudo mkdir "$DST/mnt/fsroot"
sudo tee -a "$DST/etc/fstab" >/dev/null <<-EOF
	/dev/mmcblk0p2 /mnt/fsroot btrfs defaults,compress=zstd:15,noatime 0 0
EOF

sudo tee "$DST/etc/systemd/network/wlan.network" >/dev/null <<-EOF
	[Match]
	Name=wlan0

	[Network]
	DHCP=ipv4
	UseDomains=true
EOF

sudo tee "$DST/etc/wpa_supplicant/wpa_supplicant-wlan0.conf" >/dev/null <<-EOF
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

sudo sed -i -e "s/#en_US.UTF-8/en_US.UTF-8/" \
  -e "s/#hu_HU.UTF-8/hu_HU.UTF-8/" \
  -e "s/#nl_NL.UTF-8/nl_NL.UTF-8/" \
  "$DST/etc/locale.gen"

[ -d "$CACHE" ] || mkdir "$CACHE"
[ -d "$BUILD" ] || mkdir "$BUILD"

# building whatever we can in docker first
cp user/mcu.config "$BUILD/"
docker build -t arch-build docker-env
#find "$BUILD" -type d -exec sudo chmod 777 {} \;
docker run -it --rm \
  -v "$(pwd)/$BUILD/:/build/" \
  -v "$(pwd)/$CACHE/:/var/cache/pacman" \
  -v "$(pwd)/docker-env/:/env" \
  arch-build \
  /env/orchestrate.sh

sudo mkdir "$DST/build"
sudo mount --bind "$BUILD" "$DST/build"
sudo mount --bind "$CACHE" "$DST/var/cache/pacman"
sudo cp koa-setup.sh "$DST/"
cp klipper_rpi.config "$BUILD/"
sudo chroot "$DST" "$QEMU" /bin/bash -c /koa-setup.sh $TRUSTED_NET
sudo rm "$DST/koa-setup.sh"

[ -d user/files ] && sudo cp -r user/files/* "$DST/"
if [ -d user/scripts ]; then
  for script in user/scripts/*; do
    if [ -f "$script" -a -x "$script" ]; then
      sudo cp "$script" "$DST/user-script.sh"
      sudo chroot "$DST" "$QEMU" /bin/bash -c /user-script.sh
    fi
  done
  sudo rm "$DST/user-script.sh" || true
fi

sudo chroot "$DST" "$QEMU" /usr/bin/chown -R klipper:klipper /etc/klipper
sudo chown -R $(id -u):$(id -g) "$CACHE" "$BUILD"

sudo fuser -k "$DST" || true

sudo umount -R "$DST"
sudo mount ${parts[1]} "$DST" -ocompress=zstd:15
sudo btrfs sub snap "$DST/@koa_root" "$DST/@koa_root.inst"
sudo umount "$DST"
sudo kpartx -d "$IMG"
