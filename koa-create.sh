#!/bin/bash
set -ex

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
  check_bin mkfs.msdos
  check_bin mkfs.btrfs
  check_bin curl
  check_bin jq

  if [ ! -f "${USERDIR}/mcu.config" ]; then
    echo "Create user/mcu.config for compiling MCU firmware"
    exit 1
  fi
}

check_secrets()
{
  if [ ! -x "${USERDIR}/secrets.sh" ]; then
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


prepare_target()
{
  # Creating the image file, partition and mount it
  [ -f "${IMG}" ] && rm "${IMG}"
  truncate -s "${IMGSIZE}" "${IMG}"
  parted "${IMG}" -s -- mklabel msdos \
    mkpart primary fat16 1MiB "${BOOTSIZE}" \
    mkpart primary btrfs "${BOOTSIZE}" 100%

  LOOPDEV=( $(sudo losetup --find --show --partscan "$IMG") )
  PARTS=( "${LOOPDEV}p1" "${LOOPDEV}p2" )

  sudo mkfs.msdos -n KOA-BOOT ${PARTS[0]}

  if [ -z "${USE_EXT4}" ]; then
    sudo mkfs.btrfs -f -L koa-root ${PARTS[1]}
    ## btrfs snapshot magic
    sudo mount ${PARTS[1]} "${WD}" -ocompress=zstd:15
    sudo btrfs sub cre "${WD}/$SUBVOL"
    sudo btrfs property set "${WD}/$SUBVOL" compression zstd
    sudo umount "${WD}"
    sudo mount ${PARTS[1]} "${WD}" "-ocompress=zstd:15,subvol=$SUBVOL"
  else
    sudo mkfs.ext4 -L koa-root ${PARTS[1]}
    sudo mount ${PARTS[1]} "${WD}"
  fi

  sudo mkdir "${WD}/boot"
  sudo mount ${PARTS[0]} "${WD}/boot"

  for dir in dev proc sys run tmp; do
    [ -d "${WD}/${dir}" ] || sudo mkdir "${WD}/${dir}"
    sudo mount --bind /"${dir}" "${WD}/${dir}"
  done

  [ -d "${CACHE}" ] || mkdir "${CACHE}"
  sudo mkdir -p "${WD}/var/cache/apk"
  sudo mount --bind "${CACHE}" "${WD}/var/cache/apk"

  sudo mkdir "$WD/build"
  sudo mount --bind "$BUILDDIR" "$WD/build"
}


install_os()
{
  local alpine_branch="latest-stable"
  local alpine_mirror="http://dl-cdn.alpinelinux.org/alpine"
  local alpine_arch="armv7"
  
  pkg=$(curl -s ${alpine_mirror}/${alpine_branch}/main/armv7/ | grep apk-tools-static | sed -E 's/.*href=".*(apk-tools-static.*\.apk)".*/\1/')
  temp_dir=$(mktemp -d)
  [ -e "${CACHE}/${pkg}" ] ||  curl -s -o "${CACHE}/${pkg}" "${alpine_mirror}/${alpine_branch}/main/armv7/${pkg}"
  tar -C "${temp_dir}" -xzf "${CACHE}/${pkg}"

  sudo mkdir -p "${WD}/etc/apk"
  sudo ln -s  "${WD}/var/cache/apk" "${WD}/etc/apk/cache"

  sudo "${temp_dir}/sbin/apk.static" -X "${alpine_mirror}/${alpine_branch}/main" -U --allow-untrusted -p "${WD}" --arch armv7 --initdb add alpine-keys
  sudo "${temp_dir}/sbin/apk.static" -X "${alpine_mirror}/${alpine_branch}/main" -p "${WD}" --arch armv7 add alpine-base
  
  # removing local apk.static
  sudo rm "${WD}/etc/apk/cache"
  sudo ln -sf  "/var/cache/apk" "${WD}/etc/apk/cache"
  sudo rm -rf "${temp_dir}"

  # configuring apk repositories
  printf '%s\n' \
    "$alpine_mirror/$alpine_branch/main" \
    "$alpine_mirror/$alpine_branch/community" \
	  | sudo tee "${WD}/etc/apk/repositories" >/dev/null
  sudo cp /etc/resolv.conf "${WD}/etc/"
  sudo chroot "${WD}" /bin/ash -lc "apk update && apk add mkinitfs zram-init"

  sudo sed -Ei 's/^(features=")/\1btrfs /' "${WD}/etc/mkinitfs/mkinitfs.conf"

  sudo chroot "${WD}" /bin/ash -l -c "apk add linux-rpi2 linux-rpi4 raspberrypi-bootloader openrc busybox-initscripts"

  sudo chroot "${WD}" /bin/ash -l -c 'rc-update add zram-init boot'

  echo "modules=loop,squashfs,sd-mod,usb-storage,btrfs" \
    "root=/dev/mmcblk0p2" \
    "rw" \
    "rootflags=subvol=@koa_root,compress=zstd:15,noatime" \
    "elevator=deadline" \
    "fsck.repair=yes" \
    "console=tty1" \
    "rootwait" \
    | sudo tee "${WD}/boot/cmdline.txt" >/dev/null

  sudo tee "${WD}/boot/config.txt" >/dev/null <<-EOF
		kernel=vmlinuz-rpi2
		initramfs initramfs-rpi2

		[pi4]
		enable_gic=1
		kernel=vmlinuz-rpi4
		initramfs initramfs-rpi4

		[all]
		gpu_mem=32
		enable_uart=1
		dtparam=spi=on

		include usercfg.txt
	EOF

  sudo tee "${WD}/boot/usercfg.txt" > /dev/null <<-EOF
	EOF

  sudo tee "${WD}/etc/fstab" > /dev/null <<-EOF
		/dev/mmcblk0p1  /boot           vfat     defaults                                            0 2
		/dev/mmcblk0p2  /               btrfs    defaults,subvol=${SUBVOL},compress=zstd:15,noatime  0 0
	EOF

  sudo tee "${WD}/etc/sysctl.conf" >/dev/null <<-EOF
		vm.vfs_cache_pressure=500
		vm.swappiness=100
		vm.dirty_background_ratio=1
		vm.dirty_ratio=50
	EOF

  sudo tee "${WD}/etc/local.d/cpufreq.start" >/dev/null <<-EOF
		#!/bin/sh
		for cpu in /sys/devices/system/cpu/cpufreq/policy*; do
		  echo performance > ${cpu}/scaling_governor
		done
	EOF

  sudo chmod +x "${WD}/etc/local.d/cpufreq.start"
  sudo chroot "${WD}" /bin/ash -l -c 'rc-update add local default'
}


essential_setup()
{
  ## System setup
  sudo chroot "${WD}" /bin/ash -l -c "apk add chrony alpine-conf tzdata shadow nano htop curl wget bash bash-completion findutils ca-certificates"

  local ipdata=$(curl -s ipinfo.io)
  local ip=$(jq -r .ip <<< "$ipdata")
  local country=$(jq -r .country <<< "$ipdata")
  local tz=$(jq -r .timezone <<< "$ipdata")

  sudo chroot "${WD}" /bin/ash -l <<-EOF
		set -ex
		update-ca-certificates
		setup-timezone -z "${tz}"
		echo "root:${ROOT_PASSWORD:-topsecret}" | chpasswd
		setup-keymap us us-altgr-intl
		sed -i 's/\/bin\/ash/\/bin\/bash/g' /etc/passwd
	EOF

  sudo chroot "${WD}" /bin/ash -l -c "setup-hostname ${TARGET_HOSTNAME}"
  sudo chroot "${WD}" /bin/ash -l -c "apk add wpa_supplicant wireless-tools wireless-regdb iw"
  sudo sed -i 's/wpa_supplicant_args=\"/wpa_supplicant_args=\" -u -Dwext,nl80211/' "${WD}/etc/conf.d/wpa_supplicant"

  echo -e 'brcmfmac' | sudo tee "${WD}/etc/modules" >/dev/null

  sudo tee "${WD}/boot/wpa_supplicant.conf" >/dev/null <<-EOF
		network={
		  ssid="${WIFI_SSID}"
		  psk="${WIFI_PASSWD}"
		}

		ap_scan=1
		autoscan=periodic:10
		disable_scan_offload=1
	EOF

  sudo ln -s "/boot/wpa_supplicant.conf" "${WD}/etc/wpa_supplicant/wpa_supplicant.conf"

  sudo tee "${WD}/etc/network/interfaces" >/dev/null <<-EOF
		auto lo
		iface lo inet loopback

		auto eth0
		iface eth0 inet dhcp

		auto wlan0
		iface wlan0 inet dhcp
		  up iwconfig wlan0 power off
	EOF

  sudo chroot "${WD}" /bin/ash -l -c "apk add dbus polkit avahi"

  sudo chroot "${WD}" /bin/ash -l <<-EOF
		set -ex
		apk add eudev openssh haveged

		for service in devfs dmesg; do
			rc-update add "\${service}" sysinit
		done

		for service in modules sysctl hostname bootmisc swclock syslog swap; do
			rc-update add "\${service}" boot
		done

		for service in dbus haveged sshd chronyd local networking avahi-daemon wpa_supplicant wpa_cli; do
			rc-update add "\${service}" default
		done

		setup-udev -n

		for service in mount-ro killprocs savecache; do
			rc-update add "\${service}" shutdown
		done
	EOF

  # USRID=$(cat "$WD/etc/passwd"|grep ^alarm | cut -d: -f3)
  # GRPID=$(cat "$WD/etc/passwd"|grep ^alarm | cut -d: -f4)
  # sudo sed -i -e "s/#en_US.UTF-8/en_US.UTF-8/" \
  #   -e "s/#hu_HU.UTF-8/hu_HU.UTF-8/" \
  #   -e "s/#nl_NL.UTF-8/nl_NL.UTF-8/" \
  #   "${WD}/etc/locale.gen"

  # sudo chroot "$WD" /bin/bash <<-EOF
	# 	set -ex
	# 	pacman-key --init
	# 	pacman-key --populate archlinuxarm

	# 	locale-gen

	# 	pacman --noconfirm -Sy
	# 	pacman --noconfirm -S btrfs-progs
	# 	pacman --noconfirm -Su

	# 	pacman --noconfirm --needed -S vim sudo base-devel git usbutils nginx polkit v4l-utils avahi
	# 	# TODO: remove once development is finished
	# 	pacman --noconfirm -S mc screen pv man-db bash-completion parted

	# 	usermod -aG wheel alarm
}


build_klipper()
{
  sudo chroot "${WD}" /bin/ash -l -c "apk add gcc make gcc-arm-none-eabi python3 git vim sudo"
  sudo chroot "${WD}" /bin/ash -l -c "musl-dev linux-headers python3-dev libffi-dev"
  sudo chroot "${WD}" /bin/ash -l -c "adduser -D klipper && adduser klipper wheel && echo '%wheel ALL=(ALL:ALL) NOPASSWD: ALL' >/etc/sudoers.d/wheel-nopasswd"
  sudo chroot "${WD}" su -l klipper -c <<-EOF
		set -ex
		git clone --depth 1 https://github.com/Klipper3d/klipper.git
		git clone --depth 1 https://github.com/Arksine/moonraker.git
		git clone --depth 1 https://github.com/mainsail-crew/mainsail.git
		git clone --depth 1 https://github.com/fluidd-core/fluidd.git

		python3 -m venv klipper-venv
		klipper-venv/bin/python3 -m pip install --upgrade pip
		klipper-venv/bin/pip install -r klipper/scripts/klippy-requirements.txt
		pushd klipper
		../klipper-venv/bin/python3 -m compileall klippy
		../klipper-venv/bin/python3 klippy/chelper/__init__.py
		popd
	EOF

  sudo tee "${WD}/etc/init.d/klipper" <<-EOF
		#!/sbin/openrc-run
		command="$KLIPPY_VENV_PATH/bin/python"
		command_args="$KLIPPER_PATH/klippy/klippy.py $CONFIG_PATH/printer.cfg -l /tmp/klippy.log -a /tmp/klippy_uds"
		command_background=true
		command_user="$USER"
		pidfile="/run/klipper.pid"
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

}


# building whatever we can in docker first
prebuild_in_docker()
{
  pushd "${SCRIPTDIR}"
  docker build -t alpine-build docker-env
  #find "$BUILDDIR" -type d -exec sudo chmod 777 {} \;
  cp "${USERDIR}/mcu.config" "$BUILDDIR/"
  docker run -it --rm \
    -v "${BUILDDIR}/:/build/" \
    -v "${CACHE}/:/var/cache/pacman" \
    -v "${SCRIPTDIR}/docker-env/:/env" \
    arch-build \
    /env/orchestrate.sh
    popd
}


apply_fileprops()
{
  local path=$(echo "${WD}/$1" | sed -E 's#/+#/#g')
  if [ ! -e "${path}" ]; then sudo mkdir -p "${path}"; fi
  sudo chroot "$WD" /bin/bash -l -c "chown -R $2 $1"
  [ -z "$3" ] || sudo chroot "$WD" /bin/bash -l -c "chmod $3 $1"
}


process_user_dir()
{
  [ -d "${USERDIR}/files" ] && sudo cp -r "${USERDIR}"/files/* "$WD/"
  if [ -d "${USERDIR}/scripts" ]; then
    for script in "${USERDIR}"/scripts/*; do
      if [ -f "$script" -a -x "$script" ]; then
        sudo cp "$script" "$WD/user-script.sh"
        sudo chroot "$WD" /bin/bash -c /user-script.sh
      fi
    done
    sudo rm "$WD/user-script.sh" || true
  fi

  if [ -f "${USERDIR}"/fileprops ]; then
    while read line; do
      [ -z "${line}" ]  || [[ "${line}" =~ ^[[:space:]]*\#.* ]] || apply_fileprops ${line}
    done <"${USERDIR}"/fileprops
  fi
}


cleanup()
{
  sudo chroot "${WD}" /bin/ash -l -c "rm /etc/apk/cache"
}


###############################################################################
export SCRIPTDIR="$( cd -- "$(dirname "$0")" >/dev/null 2>&1 ; pwd -P )"
. "${SCRIPTDIR}/koa-common.sh"
parse_userdir $@

check_secrets
. "${USERDIR}/secrets.sh"
parse_params $@
check

show_environment

for dir in "${WD}" "${BUILDDIR}" "${CACHE}"; do [ -d "${dir}" ] || mkdir "${dir}"; done

check_vars

# prebuild_in_docker

prepare_target
install_os
essential_setup

# edit_system_configs

# sudo mkdir "$WD/build"
# sudo mount --bind "$BUILDDIR" "$WD/build"
# sudo cp "${SCRIPTDIR}/koa-setup.sh" "$WD/"
# cp "${SCRIPTDIR}/klipper_rpi.config" "$BUILDDIR/"
# sudo chroot "$WD" /bin/bash -c "/koa-setup.sh ${TRUSTED_NET}"
# sudo rm "$WD/koa-setup.sh"

# sudo chroot "$WD" /usr/bin/chown -R klipper:klipper /etc/klipper /var/cache/klipper /var/lib/moonraker

process_user_dir
cleanup

sudo chown -R $(id -u):$(id -g) "$CACHE" "$BUILDDIR"

sudo fuser -k "$WD" || true
if [ -z "${USE_EXT4}" ] ; then
  sudo mkdir -p "${WD}/mnt/fs_root"
  sudo mount ${PARTS[1]} "${WD}/mnt/fs_root" -osubvolid=0
  sudo btrfs sub snap "${WD}/mnt/fs_root/${SUBVOL}" "$WD/mnt/fs_root/${SUBVOL}.inst"
fi

sleep 1
sudo umount -R "$WD"
sudo losetup -d "${LOOPDEV}"
