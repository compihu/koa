#!/bin/bash

apply_fileprops()
{
	readarray -d ' ' -t params <<< "$1"
	local path=$(echo "${params[0]}" | envsubst)
	local owner=$(echo "${params[1]%$'\n'}" | envsubst) # removing trailing \n possibly added by here document (<<<"$1")
	local mode=${params[2]%$'\n'} # removing trailing \n from the end of the last param added by here document (<<<"$1")

	[ ${owner} == '-' ] || /usr/bin/chown -R ${owner} ${path}
	[ -z "${mode}" ] || chmod ${mode} ${path}
}


process_user_dir()
{
	[ -d "${USERDIR}/files" ] && sudo cp -rv "${USERDIR}"/files/* "$WD/"
	if [ -d "${USERDIR}/scripts" ]; then
		for script in "${USERDIR}"/scripts/*; do
			if [ -f "${script}" -a -x "${script}" ]; then
				cp "${script}" "/tmp/user-script.sh"
				/tmp/user-script.sh
			fi
		done
		rm "/tmp/user-script.sh" || true
	fi

	if [ -f "${USERDIR}"/fileprops ]; then
		while read line; do
			[ -z "${line}" ]  || [[ "${line}" =~ ^[[:space:]]*\#.* ]] || apply_fileprops "$(echo "${line}" | sed -E 's/\s+/ /g')"
		done <"${USERDIR}"/fileprops
	fi
}


cleanup()
{
	[ "${USERDIR}" ] && rm -rf "${USERDIR}"
}


[ -f /boot/environment ] && [ -f /boot/user.zip ] || exit 0
. /boot/environment

trap cleanup EXIT
USERDIR=$(mktemp -d)

unzip -qq -d "${USERDIR}" /boot/user.zip

process_user_dir

mv -f /boot/user.zip /boot/user.done
