#!/bin/bash
set -ex

. ./koa-common.sh

check_bin()
{
  local binary=$(which "$1"  2>/dev/null || true)
  if [ -z "${binary}" ]; then
    echo "$1 binary cannot be found on PATH, giving up!"
    exit 1
  fi
}

check()
{
  check_bin qemu-arm-static
  check_bin kpartx
  check_bin mkfs.msdos
  check_bin mkfs.btrfs

  if [ ! -f user/mcu.config ]; then
    echo "Create user/mcu.config for compiling MCU firmware"
    exit 1
  fi

  if [ ! -x user/secrets.sh ]; then
    echo "Create user/secrets.sh to set WIFI_SSID and WIFI_PASSWD"
    exit 1
  fi
}


check_var () { if [ -z ${!1} ]; then echo "$1 has no value!"; exit 1; fi; }


check_vars()
{
  check_var "WIFI_SSID"
  check_var "WIFI_PASSWD"
  check_var "TRUSTED_NET"
}


# verifying and downloading the tarball if necessary
get_tarball()
{
  local tgz_ok
  local downloaded

  if [ -f "$ARCHIVE.md5" ]; then
    rm "$ARCHIVE.md5"
  fi
  wget "$URL".md5
  upsmd5=$(cat "$ARCHIVE.md5" | cut -d ' ' -f1)

  if [ -f "$ARCHIVE" ]; then
    imgmd5=$(md5sum "$ARCHIVE" | cut -d ' ' -f1)
    if [ $imgmd5 != $upsmd5 ]; then
      rm "$ARCHIVE"
      wget "${URL}"
      downloaded=1
    fi
  else
    wget "${URL}"
    downloaded=1
  fi

  imgmd5=$(md5sum "${ARCHIVE}"|cut -d ' ' -f1)
  if [ "${imgmd5}" != "${upsmd5}" ]; then
    echo "Image checksum failure, giving up!"
    exit false
  fi
}


prepare_target()
{
  # Creating the image file, partition and mount it
  [ -f "${IMG}" ] && rm "${IMG}"
  truncate -s "${IMGSIZE}" "${IMG}"
  parted "${IMG}" -s -- mklabel msdos \
    mkpart primary fat16 1MiB 150Mib \
    mkpart primary btrfs 150Mib 100%

  parts=( $(sudo kpartx -av "${IMG}"|cut -f3 -d ' ') )
  parts[0]=/dev/mapper/${parts[0]}
  parts[1]=/dev/mapper/${parts[1]}

  sudo mkfs.msdos -n KOA-BOOT ${parts[0]}
  sudo mkfs.btrfs -f -L koa-root ${parts[1]}

  # btrfs snapshot magic
  sudo mount ${parts[1]} "${WD}" -ocompress=zstd:15
  sudo btrfs sub cre "${WD}/$SUBVOL"
  sudo btrfs property set "${WD}/$SUBVOL" compression zstd
  sudo umount "${WD}"
  sudo mount ${parts[1]} "${WD}" "-ocompress=zstd:15,subvol=$SUBVOL"
  sudo mkdir "${WD}"/boot
  sudo mount ${parts[0]} "${WD}"/boot

  # Extracting the tarball and preparing the chroot
  sudo bsdtar -xpf "${ARCHIVE}" -C "${WD}"
  sudo cp $(which qemu-arm-static) "${WD}/usr/local/bin/"

  sudo mkdir "${WD}/mnt/fs_root"
  sudo mount ${parts[1]} "${WD}/mnt/fs_root" -osubvolid=0

  for d in dev proc sys; do sudo mount --bind /$d "$WD/$d"; done

  [ -d "${WD}/run/systemd/resolve" ] || sudo mkdir -p "${WD}/run/systemd/resolve"
  [ -f "${WD}/run/systemd/resolve/resolv.conf" ] || sudo cp -L /etc/resolv.conf "${WD}/run/systemd/resolve/"

  USRID=$(cat "$WD/etc/passwd"|grep ^alarm | cut -d: -f3)
  GRPID=$(cat "$WD/etc/passwd"|grep ^alarm | cut -d: -f4)
}


edit_configs()
{
  sudo tee -a "$WD/etc/fstab" >/dev/null <<-EOF
		/dev/mmcblk0p2 /mnt/fs_root btrfs defaults,compress=zstd:15,noatime 0 0
		/dev/mmcblk0p1 /boot        msdos defaults                          0 2
	EOF

  sudo tee "$WD/etc/systemd/network/wlan.network" >/dev/null <<-EOF
		[Match]
		Name=wlan0

		[Network]
		DHCP=ipv4
		UseDomains=true
	EOF

  sudo tee "$WD/etc/wpa_supplicant/wpa_supplicant-wlan0.conf" >/dev/null <<-EOF
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
    "$WD/etc/locale.gen"
}


# building whatever we can in docker first
prebuild_in_docker()
{
  cp user/mcu.config "$BUILD/"
  docker build -t arch-build docker-env
  #find "$BUILD" -type d -exec sudo chmod 777 {} \;
  docker run -it --rm \
    -v "$(pwd)/$BUILD/:/build/" \
    -v "$(pwd)/$CACHE/:/var/cache/pacman" \
    -v "$(pwd)/docker-env/:/env" \
    arch-build \
    /env/orchestrate.sh
}


ARCHIVE="ArchLinuxARM-rpi-armv7-latest.tar.gz"
URL="http://os.archlinuxarm.org/os/$ARCHIVE"
QEMU="/usr/local/bin/qemu-arm-static"
# K,M,G -> *1024; KB,MB,GB -> *1000

parse_params $@

check

for dir in "${WD}" "${BUILD}" "${CACHE}"; do [ -d "${dir}" ] || mkdir "${dir}"; done

. user/secrets.sh

check_vars
get_tarball
prepare_target

edit_configs
prebuild_in_docker

sudo mkdir "$WD/build"
sudo mount --bind "$BUILD" "$WD/build"
sudo mount --bind "$CACHE" "$WD/var/cache/pacman"
sudo cp koa-setup.sh "$WD/"
cp klipper_rpi.config "$BUILD/"
sudo chroot "$WD" "$QEMU" /bin/bash -c "/koa-setup.sh ${TRUSTED_NET}"
sudo rm "$WD/koa-setup.sh"

[ -d user/files ] && sudo cp -r user/files/* "$WD/"
if [ -d user/scripts ]; then
  for script in user/scripts/*; do
    if [ -f "$script" -a -x "$script" ]; then
      sudo cp "$script" "$WD/user-script.sh"
      sudo chroot "$WD" "$QEMU" /bin/bash -c /user-script.sh
    fi
  done
  sudo rm "$WD/user-script.sh" || true
fi

sudo chroot "$WD" "$QEMU" /usr/bin/chown -R klipper:klipper /etc/klipper
sudo chown -R $(id -u):$(id -g) "$CACHE" "$BUILD"

sudo fuser -k "$WD" || true

sudo btrfs sub snap "$WD/mnt/fs_root/$SUBVOL" "$WD/mnt/fs_root/$SUBVOL.inst"
sudo umount -R "$WD"
sudo kpartx -d "$IMG"
