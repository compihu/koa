#!/usr/bin/bash
set -ex

. /tmp/environment

## Installing moonraker
VENV=moonraker-env
INSTALL_PATH="${BASE_PATH}/moonraker"

sudo pacman --noconfirm --needed -S libsodium packagekit
"${AURHELPER}" -S --needed --builddir /build --noconfirm --removemake --norebuild libgpiod

sudo groupadd -f -r moonraker-admin

git clone 'https://github.com/Arksine/moonraker.git'

python3 -m venv "${VENV}"
"${VENV}/bin/python3" -m pip install --upgrade pip
"${VENV}/bin/pip" install -r moonraker/scripts/moonraker-requirements.txt
pushd moonraker
"../${VENV}/bin/python3" -m compileall -o 0 -o 1 moonraker
popd

moonraker/scripts/set-policykit-rules.sh

sudo tee /etc/systemd/system/moonraker.service <<-EOF
	[Unit]
	Description=Moonraker Klipper HTTP Server
	Requires=klipper.service
	After=network.target klipper.service

	[Service]
	Type=simple
	User=${TARGET_USER}
	SupplementaryGroups=moonraker-admin
	SyslogIdentifier=moonraker
	RemainAfterExit=yes
	ExecStart=${BASE_PATH}/${VENV}/bin/python3 ${INSTALL_PATH}/moonraker/moonraker.py -c ${CONFIG_PATH}/moonraker.conf -n
	Restart=always
	RestartSec=10

	[Install]
	WantedBy=multi-user.target
EOF

sudo systemctl enable moonraker.service

cat >${CONFIG_PATH}/moonraker.conf <<-EOF
	[server]
	#  The host address in which to bind the HTTP server.
	host: 0.0.0.0
	#   The port the HTTP server will listen on.
	port: 7125
	#   The port to listen on for SSS (HTTPS) connections.  Note that the HTTPS
	#   server will only be started of the certificate and key options outlined
	#   below are provied.  The default is 7130.
	#ssl_port: 7130
	#   The path to a self signed ssl certificate.  The default is no path, which
	#   disables HTTPS.
	#ssl_certificate_path:
	#   The path to the private key used to signed the certificate.  The default
	#   is no path, which disables HTTPS.
	#ssl_key_path:
	#   The address of Unix Domain Socket used to communicate with Klipper.
	klippy_uds_address: /run/klipper/ud_sock
	#   The maximum size allowed for a file upload.
	#max_upload_size: 200
	#   When set to True Moonraker will log in verbose mode.  During this stage
	#   of development the default is True.  In the future this will change.
	enable_debug_logging: True

	[file_manager]
	#   The path to a directory where configuration files are located. This
	#   directory may contain Klipper config files (printer.cfg) or Moonraker
	#   config files (moonraker.conf).  Clients may also write their own config
	#   files to this directory.  Note that this may not be the system root
	#   (ie: "/") and moonraker must have read and write access permissions
	#   for this directory.
	config_path: ${BASE_PATH}/klipper-config
	#   An optional path to a directory where log files are located.  Users may
	#   configure various applications to store logs here and Moonraker will serve
	#   them at "/server/files/logs/*".  The default is no log paths.
	log_path: /tmp/klipper-logs
	#   When set to True the file manager will add uploads to the job_queue when
	#   the `start_print` flag has been set.  The default if False.
	#queue_gcode_uploads: False
	#   When set to True gcode files will be run through a "preprocessor"
	#   during metdata extraction if object tags are detected.  This preprocessor
	#   replaces object tags with G-Code commands compatible with Klipper's
	#   "cancel object" functionality.  Note that this process is file I/O intensive,
	#   it is not recommended for usage on low resource SBCs such as a Pi Zero.
	#   The default is False.
	#enable_object_processing: False

	[machine]
	#   The provider implementation used to collect system service information
	#   and run service actions (ie: start, restart, stop).  This can be "none",
	#   "systemd_dbus", or "systemd_cli".  If the provider is set to "none" service
	#   action APIs will be disabled.  The default is systemd_dbus.
	provider: systemd_cli

	[database]
	#   The path to the folder that stores Moonraker's lmdb database files.
	#   It is NOT recommended to place this file in a location that is served by
	#   Moonraker (such as the "config_path" or the location where gcode
	#   files are stored).  If the folder does not exist an attempt will be made
	#   to create it.  The default is ~/.moonraker_database.
	#database_path: /var/opt/moonraker/db
	#   For developer use only.  End users should leave this option set to False.
	#enable_database_debug: False

	[data_store]
	#   The maximum number of temperature values to store for each sensor. Note
	#   that this value also applies to the "target", "power", and "fan_speed"
	#   if the sensor reports them.  The default is 1200, which is enough to
	#   store approximately 20 minutes of data at one value per second.
	#temperature_store_size: 1200
	#   The maximum number "gcode lines" to store.
	#gcode_store_size:  1000

	#[job_queue]
	#   When set to true the job queue will attempt to load the next
	#   pending job when Klipper reports as "Ready".  If the queue has
	#   been paused it will automatically resume.  Note that neither
	#   the job_transition_delay nor the job_transition_gcode are
	#   applied in this case.  The default is False.
	#load_on_startup: False
	#   The amount of time to delay after completion of a job before
	#   loading the next job on the queue.  The default is no delay.
	#job_transition_delay:
	#   A gcode to execute after the completion of a job before the next
	#   job is loaded.  If a "job_transition_delay" has been configured
	#   this gcode will run after the delay.  The default is no gcode.
	#job_transition_gcode:

	[authorization]
	#   A list of newline separated ip addresses and/or ip ranges that are
	#   trusted. Trusted clients are given full access to the API.  Both IPv4
	#   and IPv6 addresses and ranges are supported. Ranges must be expressed
	#   in CIDR notation (see http://ip.sb/cidr for more info).  For example, an
	#   entry of 192.168.1.0/24 will authorize IPs in the range of 192.168.1.1 -
	#   192.168.1.254.  Note that when specifying IPv4 ranges the last segment
	#   of the ip address must be 0. The default is no clients or ranges are
	#   trusted.
	trusted_clients:
	  ${TRUSTED_NET}
	# 192.168.1.30
	# 192.168.1.0/24
	#   Enables CORS for the specified domains.  One may specify * if they wish
	#   to allow all domains.
	cors_domains:
	  *.local
	  *://.app.fluidd.xyz
	#  http://klipper-printer.local
	#  http://second-printer.local:7125

	#[octoprint_compat]

	[history]
EOF

cat >"${CONFIG_PATH}/moonraker-klipper.cfg" <<-EOF
    [pause_resume]

    [display_status]

    [virtual_sdcard]
    path: ${GCODE_SPOOL}
EOF
