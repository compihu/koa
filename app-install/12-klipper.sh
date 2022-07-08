#!/usr/bin/bash
set -ex

. /tmp/environment

## Installing klipper
VENV=klippy-venv
INSTALL_PATH="${BASE_PATH}/klipper"

sudo pacman -S --noconfirm libusb

if[-d /build/klipper]; then
    cp -r /build/klipper ./
    git -C klipper pull
else
    git clone --depth 1 'https://github.com/Klipper3d/klipper.git'
fi

cp /tmp/klipper_rpi.config klipper/.config
make -C klipper -j$(nproc)
sudo cp klipper/out/klipper.elf /usr/local/bin/klipper_mcu

python3 -m venv "${VENV}"
"${VENV}/bin/python3" -m pip install --upgrade pip
"${VENV}/bin/pip" install -r klipper/scripts/klippy-requirements.txt
pushd klipper
"../${VENV}/bin/python3" -m compileall klippy
"../${VENV}/bin/python3" klippy/chelper/__init__.py
popd

mkdir "${CONFIG_PATH}" "${GCODE_SPOOL}"

sudo tee /etc/systemd/system/klipper.service >>/dev/null <<-EOF
	[Unit]
	Description=3D printer firmware with motion planning on the host
	After=network.target

	[Install]
	WantedBy=multi-user.target

	[Service]
	Type=simple
	User=klipper
	RemainAfterExit=no
	Environment=PYTHONUNBUFFERED=1
	ExecStart=${BASE_PATH}/${VENV}/bin/python3 ${INSTALL_PATH}/klippy/klippy.py ${CONFIG_PATH}/printer.cfg -I /run/klipper/sock -a /run/klipper/ud_sock -l "${LOG_PATH}/klippy.log"
	Nice=-5
	Restart=always
	RestartSec=10
EOF

sudo systemctl enable klipper.service

cat >"${CONFIG_PATH}/printer.cfg" <<-EOF
	# [include webui-klipper.cfg]
	[include moonraker-klipper.cfg]

	########################################
	# Your printer configuration goes here #
	########################################
EOF

sudo tee /etc/tmpfiles.d/klipper.conf >>/dev/null <<-EOF
	d ${LOG_PATH} 2775 klipper klipper - -
	d /run/klipper 0755 klipper tty - -
EOF