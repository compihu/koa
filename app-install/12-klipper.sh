#!/usr/bin/bash
set -ex

. /tmp/environment

## Installing klipper
sudo pacman -S --noconfirm libusb

curl -s 'https://bootstrap.pypa.io/get-pip.py' | python3

git clone --depth 1 'https://github.com/Klipper3d/klipper.git'

cp /tmp/klipper_rpi.config klipper/.config
make -C klipper -j$(nproc)
sudo cp klipper/out/klipper.elf /usr/local/bin/klipper_mcu

python3 -m venv klipper-venv
klipper-venv/bin/python3 -m pip install --upgrade pip
klipper-venv/bin/pip install -r klipper/scripts/klippy-requirements.txt
pushd klipper
../klipper-venv/bin/python3 -m compileall klippy
../klipper-venv/bin/python3 klippy/chelper/__init__.py
popd

pwd
mkdir klipper-config gcode-files

sudo tee /etc/systemd/system/klipper.service <<-EOF
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
	ExecStart=/home/klipper/klipper-venv/bin/python /home/klipper/klipper/klippy/klippy.py /home/klipper/klipper-config/printer.cfg -I /run/klipper/sock -a /run/klipper/ud_sock -l /tmp/klippy.log
	Nice=-5
	Restart=always
	RestartSec=10
EOF

sudo systemctl enable klipper.service
