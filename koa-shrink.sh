#!/bin/bash
set -ex

cleanup()
{
	if [ ${loopdev} ]; then
		[ ${mounted} ] && umount -R "${WD}"
		losetup -d "${loopdev}"
	fi
}


export SCRIPTDIR="$( cd -- "$(dirname "$0")" >/dev/null 2>&1 ; pwd -P )"
. "${SCRIPTDIR}/koa-common.sh"

parse_params $@

if [ ! -f "${IMG}" ]; then
	echo "Input is not a regular file!"
	exit 1
fi

[ -d "${WD}" ] || mkdir "${WD}"

unset loopdev mounted
trap cleanup EXIT
loopdev=( $(sudo losetup --find --show --partscan "${IMG}") )
parts=( "${loopdev}p1" "${loopdev}p2" )

sudo mount ${parts[1]} "${WD}" -ocompress=zstd:15

deleted=0
for subvol in "${WD}"/*; do
	sv=$(basename "${subvol}")
	[ -d "${subvol}" ] && [ "${sv}" != "${SUBVOL}" ] && sudo btrfs subvolume delete "${subvol}" && let ++deleted
done

if [ ${deleted} -gt 0 ]; then
	sync
	avail="$(df -h --output=avail ${WD} | tail -n1)"
	echo -n "Waiting for BTRFS to free up deleted subvolumes "
	count=0
	while [ ${count} -lt 12 ] && [ "$(df -h --output=avail ${WD} | tail -n1)" == "${avail}" ]; do
		echo -n '#'
		sleep 10
		let ++count
	done
	sleep 5
	echo " done in" $(( count * 10 + 5 )) "secods"
	sudo btrfs filesystem defragment -r -czstd "${WD}/${SUBVOL}"
fi

# [ -d "${WD}/${SUBVOL}_inst" ] || sudo btrfs subvolume snapshot "${WD}/${SUBVOL}" "${WD}/${SUBVOL}_inst"

while sudo btrfs filesystem resize -100M "${WD}"; do sleep 1; done
while sudo btrfs filesystem resize -10M "${WD}"; do sleep 1; done

fssize=$(($(df -hk "${WD}"|tail -n 1 | awk '{print $2}')/1024))

sudo umount --recursive "${WD}"
unset mounted
losetup -d "${loopdev}"
unset loopdev

partstart=$(sudo parted -m "${IMG}" unit B print | tail -n 1 | sed 's/B//g' | cut -d: -f2)
partend=$((${partstart}/1024/1024+"${fssize}"))
sudo parted --script "${IMG}" rm 2
truncate --size "${partend}MiB" "${IMG}"
sudo parted --script "${IMG}" mkpart primary btrfs "${partstart}B" 100%
