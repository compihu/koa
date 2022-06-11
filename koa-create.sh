#!/bin/bash
set -ex

SCRIPTPATH="$( cd -- "$(dirname "$0")" >/dev/null 2>&1 ; pwd -P )"
. "${SCRIPTPATH}/koa-common.sh"


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
    mkpart primary fat16 1MiB "${BOOTSIZE}" \
    mkpart primary btrfs "${BOOTSIZE}" 100%

  loopdev=( $(sudo losetup --find --show --partscan "$IMG") )
  parts=( "${loopdev}p1" "${loopdev}p2" )

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


install_essential()
{
  sudo sed -i -e "s/#en_US.UTF-8/en_US.UTF-8/" \
    -e "s/#hu_HU.UTF-8/hu_HU.UTF-8/" \
    -e "s/#nl_NL.UTF-8/nl_NL.UTF-8/" \
    "${WD}/etc/locale.gen"

  sudo chroot "$WD" "$QEMU" /bin/bash <<-EOF
		set -ex
		pacman-key --init
		pacman-key --populate archlinuxarm

		locale-gen

		pacman --noconfirm -Sy
		pacman --noconfirm -S btrfs-progs
		pacman --noconfirm -Su

		pacman --noconfirm --needed -S vim sudo base-devel git usbutils nginx polkit v4l-utils avahi
		# TODO: remove once development is finished
		pacman --noconfirm -S mc screen pv man-db bash-completion parted
	EOF
}

edit_system_configs()
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

  sudo sed -i -E 's/(^-?session\s+.*pam_systemd.so.*)/#\1/' "${WD}/etc/pam.d/system-login"

  sudo sed -i -e 's/rw/rootflags=compress=zstd:15,subvol=@koa_root,relatime rw/' \
   -e 's/ console=serial0,115200//' \
   -e 's/ kgdboc=serial0,115200//' \
   "${WD}/boot/cmdline.txt"

  sudo tee -a "${WD}/boot/config.txt" >/dev/null <<-EOF

		[all]
		gpu_mem=16
		enable_uart=1
		dtparam=spi=on
	EOF

  echo '%wheel ALL=(ALL:ALL) NOPASSWD: ALL' | sudo tee "${WD}/etc/sudoers.d/wheel-nopasswd" >/dev/null
}


# building whatever we can in docker first
prebuild_in_docker()
{
  docker build -t arch-build docker-env
  #find "$BUILDDIR" -type d -exec sudo chmod 777 {} \;
  cp user/mcu.config "$BUILDDIR/"
  docker run -it --rm \
    -v "$(pwd)/$BUILDDIR/:/build/" \
    -v "$(pwd)/$CACHE/:/var/cache/pacman" \
    -v "$(pwd)/docker-env/:/env" \
    arch-build \
    /env/orchestrate.sh
}


chown_inside()
{
  if [ ! -e "${WD}/$1" ]; then sudo mkdir -p "${WD}/$1"; fi
  sudo chroot "$WD" "$QEMU" /bin/bash -c "/usr/bin/chown -R $2 $1"
}


ARCHIVE="ArchLinuxARM-rpi-armv7-latest.tar.gz"
URL="http://os.archlinuxarm.org/os/$ARCHIVE"
QEMU="/usr/local/bin/qemu-arm-static"
# K,M,G -> *1024; KB,MB,GB -> *1000

parse_params $@

check

for dir in "${WD}" "${BUILDDIR}" "${CACHE}"; do [ -d "${dir}" ] || mkdir "${dir}"; done

. user/secrets.sh
check_vars

prebuild_in_docker

get_tarball
prepare_target

sudo mount --bind "$CACHE" "$WD/var/cache/pacman"

install_essential
edit_system_configs

sudo mkdir "$WD/build"
sudo mount --bind "$BUILDDIR" "$WD/build"
sudo cp koa-setup.sh "$WD/"
cp klipper_rpi.config "$BUILDDIR/"
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

if [ -d user/fileprops ]; then
  while read line; do
    chown_inside $line
  done <user/fileprops
fi

sudo chroot "$WD" "$QEMU" /usr/bin/chown -R klipper:klipper /etc/klipper
sudo chown -R $(id -u):$(id -g) "$CACHE" "$BUILDDIR"

sudo fuser -k "$WD" || true

sudo btrfs sub snap "$WD/mnt/fs_root/$SUBVOL" "$WD/mnt/fs_root/$SUBVOL.inst"
sudo umount -R "$WD"
sudo losetup -D "$IMG"
