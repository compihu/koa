#!/usr/bin/bash
set -ex

. /tmp/environment

pushd /tmp
git clone --depth 1 'https://github.com/pikvm/ustreamer.git'
mkdir ustreamer-build
cp "ustreamer/pkg/arch/PKGBUILD" "ustreamer-build/"
rm -rf "ustreamer"
pushd "ustreamer-build"
makepkg -sir --noconfirm
popd
rm -rf "ustreamer-build"
popd

sudo tee /etc/systemd/system/ustreamer@.service >/dev/null <<-EOF
	[Unit]
	Description=uStreamer service
	After=network.target

	[Service]
	Environment="SCRIPT_ARGS=%I"
	User=${TARGET_USER}
	ExecStart=/usr/bin/ustreamer --process-name-prefix ustreamer-%I --log-level 0 -d /dev/video%I --device-timeout=8 -m mjpeg -r 1920x1080 -f 30 -s 0.0.0.0 -p 808%I
	Nice=10

	[Install]
	WantedBy=klipper.service
EOF

sudo systemctl enable ustreamer@0.service
