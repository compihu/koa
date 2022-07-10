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
	check_bin xz

	if [ ! -f "${USERDIR}/mcu.config" ]; then
		echo "Create user/mcu.config for compiling MCU firmware"
		exit 1
	fi
}

apply_secrets()
{
	if [ ! -x "${USERDIR}/secrets.sh" ]; then
		echo "Create user/secrets.sh to set WIFI_SSID and WIFI_PASSWD"
		exit 1
	fi
	. "${USERDIR}/secrets.sh"
}


check_var () { if [ -z ${!1} ]; then echo "$1 has no value!"; exit 1; fi; }


check_vars()
{
	check_var "WIFI_SSID"
	check_var "WIFI_PASSWD"
	check_var "TRUSTED_NET"
}


create_snapshot()
{
	[ "${CREATE_SNAPSHOTS}" ] || [ -z "${USE_EXT4}" ] || return

	local snapshot="$1"
	[ -d "${WD}/mnt/fs_root/${SUBVOL}_${snapshot}" ] && sudo btrfs subvolume delete "${WD}/mnt/fs_root/${SUBVOL}_${snapshot}"
	sudo btrfs sub snap "$WD/mnt/fs_root/${SUBVOL}" "${WD}/mnt/fs_root/${SUBVOL}_${snapshot}"
	sudo tar -C "${WD}/boot" -c . | xz -9 >"${SNAPSHOTDIR}/${snapshot}-boot.tar.xz"
}


restore_snapshot()
{
	[ -z "${USE_EXT4}" ] || return
	sudo mount ${PARTS[1]} "${WD}" -ocompress=zstd:15
	MOUNTED=1

	local ourid=${SNAPSHOTS[$SNAPSHOT]}
	local snapshot
	for snapshot in "${!SNAPSHOTS[@]}"; do
		if [ ${SNAPSHOTS[$snapshot]} -gt "${ourid}" ]; then
			echo "Removing shanpshot ${snapshot}"
			[ -d "${WD}/${SUBVOL}_${snapshot}" ] && sudo btrfs subvolume delete "${WD}/${SUBVOL}_${snapshot}"
			[ -f "${SNAPSHOTDIR}/${snapshot}-boot.tar.xz" ] && rm "${SNAPSHOTDIR}/${snapshot}-boot.tar.xz"
		fi
	done

	[ -d "${WD}/${SUBVOL}" ] && sudo btrfs subvolume delete "${WD}/${SUBVOL}"
	sudo btrfs sub snap "${WD}/${SUBVOL}_${SNAPSHOT}" "${WD}/${SUBVOL}"
	sudo btrfs property set "${WD}/${SUBVOL}" compression zstd:15
	sudo umount "${WD}"
	unset MOUNTED
	sudo mkfs.msdos -n KOA-BOOT ${PARTS[0]}
	sudo mount ${PARTS[0]} "${WD}"
	MOUNTED=1
	sudo tar -C "${WD}" -xaf "${SNAPSHOTDIR}/${SNAPSHOT}-boot.tar.xz"
	sudo umount "${WD}"
	unset MOUNTED
}


# verifying and downloading the tarball if necessary
get_tarball()
{
	ARCHIVE="ArchLinuxARM-rpi-armv7-latest.tar.gz"
	URL="http://os.archlinuxarm.org/os/$ARCHIVE"

	local tgz_ok
	local downloaded

	pushd "${SCRIPTDIR}"
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
		popd
		exit false
	fi
	popd
}


populate_root()
{
	sudo bsdtar -xpf "${SCRIPTDIR}/${ARCHIVE}" -C "${WD}"
}


# Creating the image file and partitions
create_imgfile()
{
	[ -f "${IMG}" ] && rm "${IMG}"
	truncate -s "${IMGSIZE}" "${IMG}"
	parted "${IMG}" -s -- mklabel msdos \
		mkpart primary fat16 1MiB "${BOOTSIZE}" \
		mkpart primary btrfs "${BOOTSIZE}" 100%
}


create_loopdev()
{
	LOOPDEV=( $(sudo losetup --find --show --partscan "$IMG") )
	PARTS=( "${LOOPDEV}p1" "${LOOPDEV}p2" )
}


format_filesystems()
{
	sudo mkfs.msdos -n KOA-BOOT ${PARTS[0]}
	if [ -z "${USE_EXT4}" ]; then
		sudo mkfs.btrfs -f -L koa-root ${PARTS[1]}
		sudo mount ${PARTS[1]} "${WD}" -ocompress=zstd:15
		sudo btrfs sub cre "${WD}/$SUBVOL"
		sudo btrfs property set "${WD}/$SUBVOL" compression zstd:15
		sudo umount "${WD}"
	else
		sudo mkfs.ext4 -L koa-root ${PARTS[1]}
	fi
}


mount_filesystems()
{
	if [ -z "${USE_EXT4}" ]; then
		sudo mount ${PARTS[1]} "${WD}" "-ocompress=zstd:15,subvol=$SUBVOL"
		MOUNTED=1
		sudo mkdir -p "${WD}/mnt/fs_root"
		sudo mount ${PARTS[1]} "${WD}/mnt/fs_root" -osubvolid=0
	else
		sudo mount ${PARTS[1]} "${WD}"
		MOUNTED=1
	fi

	[ -d "${WD}/boot" ] || sudo mkdir "${WD}/boot"
	sudo mount ${PARTS[0]} "${WD}/boot"

	for dir in dev proc sys; do
		[ -d "${WD}/${dir}" ] || sudo mkdir "${WD}/${dir}"
		sudo mount --bind /"${dir}" "${WD}/${dir}"
	done

	for dir in run tmp; do
		[ -d "${WD}/${dir}" ] || sudo mkdir "${WD}/${dir}"
		sudo mount none "${WD}/${dir}" -t tmpfs
	done

	[ -d "${WD}/var/cache/pacman" ] || sudo mkdir -p "${WD}/var/cache/pacman"
	sudo mount --bind "${CACHE}" "${WD}/var/cache/pacman"

	[ -d "${WD}/build" ] || sudo mkdir "${WD}/build"
	sudo mount --bind "${BUILDDIR}" "${WD}/build"
}


cleanup_snapshots()
{
	if [ -d "${SNAPSHOTDIR}" ]; then rm "${SNAPSHOTDIR}"/* || true;
	else mkdir "${SNAPSHOTDIR}"; fi
}


setup_resolver()
{
    [ -d "${WD}/run/systemd/resolve" ] || sudo mkdir -p "${WD}/run/systemd/resolve"
    sudo cp -L /etc/resolv.conf "${WD}/run/systemd/resolve/"
}


upgrade()
{
	sudo sed -i \
		-e "s/#en_US.UTF-8/en_US.UTF-8/" \
		-e "s/#hu_HU.UTF-8/hu_HU.UTF-8/" \
		-e "s/#nl_NL.UTF-8/nl_NL.UTF-8/" \
		"${WD}/etc/locale.gen"

	sudo chroot "${WD}" /bin/bash -l <<-EOF
		set -ex
		locale-gen
		pacman-key --init
		pacman-key --populate archlinuxarm

		pacman --noconfirm -Sy
		pacman --noconfirm -S btrfs-progs
		pacman --noconfirm -Su
	EOF
}


system_setup()
{
	sudo chroot "$WD" /bin/bash -l <<-EOF
		set -ex
		pacman --noconfirm --needed -S sudo base-devel python3 python-setuptools git usbutils nginx polkit v4l-utils avahi parted
		# TODO: remove once development is finished
		pacman --noconfirm -S vim mc screen man-db bash-completion

		systemctl enable avahi-daemon.service

		usermod -l "${TARGET_USER}" -d "/home/${TARGET_USER}" -m alarm
		groupmod -n "${TARGET_USER}" alarm
		usermod -a -G tty,video,audio,wheel,uucp "${TARGET_USER}"
		echo "${TARGET_HOSTNAME}" >/etc/hostname

		git clone https://aur.archlinux.org/${AURHELPER}-bin.git
		pushd ${AURHELPER}-bin
		env EUID=1000 makepkg
		pacman --noconfirm -U ${AURHELPER}-bin-*.pkg.*
		popd
		rm -rf ${AURHELPER}-bin
	EOF

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

	sudo chroot "$WD" /bin/bash -l <<-EOF
		systemctl enable wpa_supplicant@wlan0
	EOF

	# seems to fix slow ssh root login problem
	# sudo sed -i -E 's/(^-session\s+.*pam_systemd.so.*)/#\1/' "${WD}/etc/pam.d/system-login"

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

	sudo sed -i -E \
			-e 's/^#?(Storage)=.*$/\1=volatile/' \
			-e 's/^#?(Compress)=.*$/\1=true/' \
			-e 's/^#?(RuntimeMaxUse)=.*$/\1=16M/' \
			"${WD}/etc/systemd/journald.conf"
	
	# TODO: tune this later
	echo '%wheel ALL=(ALL:ALL) NOPASSWD: ALL' | sudo tee "${WD}/etc/sudoers.d/wheel-nopasswd" >/dev/null
	sudo sed -i -e 's/#MAKEFLAGS.*/MAKEFLAGS="-j$(nproc)"/' -e "s/^\(PKGEXT=.*\)xz'/\1zst'/" "${WD}/etc/makepkg.conf"
	# sudo sed -i -e "s/^\(PKGEXT=.*\)xz'/\1zst'/" "${WD}/etc/makepkg.conf"
}


# building whatever we can in docker first
build_in_docker()
{
	pushd "${SCRIPTDIR}"
	docker build -t arch-build docker-env
	cp "${USERDIR}/mcu.config" "$BUILDDIR/"
	docker run -it --rm \
		-u build:build \
		-v "${BUILDDIR}/:/build/" \
		-v "${CACHE}/:/var/cache/pacman" \
		-v "${SCRIPTDIR}/docker-env/:/env" \
		arch-build \
		/env/build.sh
	popd
}


apply_fileprops()
{
	local full_path=$(echo "${WD}/$1" | sed -E 's#/+#/#g' | envsubst)
	local path=$(echo "$1" | envsubst)
	local owner=$(echo "$2" | envsubst)
	if [ ! -e "${full_path}" ]; then sudo mkdir -p "${full_path}"; fi
	sudo chroot "$WD" /bin/bash -c "/usr/bin/chown -R ${owner} ${path}"
	[ -z "$3" ] || sudo chroot "$WD" /bin/bash -c "/usr/bin/chmod $3 ${path}"
}


process_user_dir()
{
	[ -d "${USERDIR}/files" ] && sudo cp -rv "${USERDIR}"/files/* "$WD/"
	if [ -d "${USERDIR}/scripts" ]; then
		for script in "${USERDIR}"/scripts/*; do
			if [ -f "${script}" -a -x "${script}" ]; then
				sudo cp "${script}" "${WD}/user-script.sh"
				sudo chroot "${WD}" /bin/bash -c /user-script.sh
			fi
		done
		sudo rm "${WD}/user-script.sh" || true
	fi

	if [ -f "${USERDIR}"/fileprops ]; then
		while read line; do
			[ -z "${line}" ]  || [[ "${line}" =~ ^[[:space:]]*\#.* ]] || apply_fileprops ${line}
		done <"${USERDIR}"/fileprops
	fi
}


cleanup()
{
	if [ "${LOOPDEV}" ]; then
		if [ "${MOUNTED}" ]; then
			sudo fuser -k "${WD}" || true
			sudo umount -R "${WD}"
		fi
		sudo losetup -d "${LOOPDEV}"
	fi
}


ensure_host_dirs()
{
	for dir in "${WD}" "${BUILDDIR}" "${CACHE}"; do
		if [ ! -d "${dir}" ]; then
			mkdir "${dir}"
			chmod 777 "${dir}"
		fi
	done
}


start_from_scratch()
{
	get_tarball
	cleanup_snapshots
	create_imgfile
	create_loopdev
	format_filesystems
	mount_filesystems
	populate_root
	setup_resolver
}


start_from_snapshot()
{
	create_loopdev
	restore_snapshot
	mount_filesystems
	setup_resolver
}


###############################################################################
export SCRIPTDIR="$( cd -- "$(dirname "$0")" >/dev/null 2>&1 ; pwd -P )"
. "${SCRIPTDIR}/koa-common.sh"

declare -A SNAPSHOTS=( [tarball]=1 [upgrade]=2 [sysconf]=3 )
highest=$(for num in $(echo ${SNAPSHOTS[@]}); do echo $num; done|sort -nr|head -n1)
for script in "${SCRIPTDIR}"/app-install/??-*.sh; do
	let highest++
	SNAPSHOTS[$(echo $(basename ${script}) | sed -r 's/^..-(.*).sh/\1/')]=${highest}
done
let highest++
SNAPSHOTS[inst]=${highest}

unset LOOPDEV
unset MOUNTED

trap cleanup EXIT

parse_userdir $@
apply_secrets
parse_params $@

check
show_environment
check_vars

ensure_host_dirs

if [ "${CHECKPOINT}" -eq 0 ]; then
	build_in_docker
	start_from_scratch
	create_snapshot "tarball"
else
	start_from_snapshot
fi

if [ "${CHECKPOINT}" -lt 2 ]; then
	upgrade
	create_snapshot "upgrade"
fi

if [ "${CHECKPOINT}" -lt 3 ]; then
	system_setup
	create_snapshot "sysconf"
fi

cp "${SCRIPTDIR}/klipper_rpi.config" "${WD}/tmp/"
sudo tee -a "$WD/tmp/environment" >/dev/null <<-EOF
	export TRUSTED_NET="${TRUSTED_NET}"
	export AURHELPER="${AURHELPER}"
	export DEFAULT_UI=mainsail
	export TARGET_USER="${TARGET_USER}"
	export BASE_PATH=/home/"${TARGET_USER}"
	export CONFIG_PATH="\${BASE_PATH}/klipper-config"
	export GCODE_SPOOL="\${BASE_PATH}/gcode-spool"
	export LOG_PATH=/tmp/klipper-logs
EOF

for script in "${SCRIPTDIR}"/app-install/??-*.sh; do
	snapshot=$(echo $(basename ${script}) | sed -r 's/^..-(.*).sh/\1/')
	if [ ${SNAPSHOTS[${snapshot}]} -gt "${CHECKPOINT}" ]; then
		cat "${script}" | sudo chroot "${WD}" su -l "${TARGET_USER}" -c "/bin/env TRUSTED_NET=\"${TRUSTED_NET}\" /bin/bash"
		create_snapshot "${snapshot}"
	fi
done

sudo chroot "$WD" /usr/bin/chown -R "${TARGET_USER}":"${TARGET_USER}" "/home/${TARGET_USER}"

process_user_dir

sudo chown -R $(id -u):$(id -g) "${CACHE}" "${BUILDDIR}"

#sudo btrfs sub snap "$WD/mnt/fs_root/${SUBVOL}" "${WD}/mnt/fs_root/${SUBVOL}_inst"
