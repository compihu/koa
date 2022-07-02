#!/usr/bin/bash
set -ex

AH=yay
DEFAULT_UI=mainsail
TRUSTED_NET="${TRUSTED_NET:-$1}"

# pacman --noconfirm -S etckeeper git
# git config --global init.defaultBranch master
# etckeeper init
# git -C /etc config user.name "EtcKeeper"
# git -C /etc config user.email "root@koa"
# etckeeper commit -m "Initial commit"

# pacman --noconfirm --needed -S vim sudo base-devel git usbutils nginx polkit v4l-utils avahi
# for development purposes
# pacman --noconfirm -S mc screen pv man-db bash-completion parted

sudo sed -i -e 's/#MAKEFLAGS.*/MAKEFLAGS="-j$(nproc)"/' -e "s/^\(PKGEXT=.*\)xz'/\1zst'/" /etc/makepkg.conf
# sudo sed -i -e "s/^\(PKGEXT=.*\)xz'/\1zst'/" /etc/makepkg.conf

# Installing AUR helper of choice
cd
git clone "https://aur.archlinux.org/${AH}-bin.git"
pushd "${AH}-bin"
makepkg
sudo pacman --noconfirm -U "${AH}"-bin-*.pkg.*
popd
rm -rf "${AH}-bin"

## Installing klipper
sudo pacman -S --noconfirm libusb

curl -s 'https://bootstrap.pypa.io/get-pip.py' | python3

git clone --depth 1 'https://github.com/Klipper3d/klipper.git'

cp /build/klipper_rpi.config klipper/.config
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


## Installing moonraker
"${AH}" -S --builddir /build --noconfirm --removemake --norebuild libgpiod

# cat >/home/alarm/koa-user.sh <<-EOF
# 	#!/usr/bin/bash
# 	set -ex

# 	$AH -S --builddir /build --noconfirm --removemake --norebuild --mflags --nocheck klipper-py3-git
# 	$AH -S --builddir /build --noconfirm --removemake --norebuild  --mflags --skipchecksums moonraker-git
# 	$AH -S --builddir /build --noconfirm --removemake --norebuild ustreamer
# EOF
# chmod a+x /home/alarm/koa-user.sh
# chown -R alarm:alarm /build/*
# su -l -c /home/alarm/koa-user.sh alarm
# rm /home/alarm/koa-user.sh
# sed -E 's#(ExecStart=.*) /etc/klipper/klipper.cfg (.*)#\1 /etc/klipper/printer.cfg \2 -l /var/log/klipper/klippy.log\nNice=-5#' /lib/systemd/system/klipper.service >/etc/systemd/system/klipper.service

# pacman -U --noconfirm $(ls -t /build/mainsail-git/*-any.pkg.tar.* | head -n1)
# pacman -U --noconfirm $(ls -t /build/fluidd-git/*-any.pkg.tar.* | head -n1)

# su -s /bin/bash -c /bin/bash <<-EOF
# 	set -ex
# 	cd /usr/lib/klipper
# 	cp /build/klipper_rpi.config .config
# 	make -j$(nproc)
# EOF

# pushd /var/lib/klipper/
# cd /usr/lib/klipper
# make flash
# popd

sudo usermod -a -G tty,video,audio klipper


# ################################################################
# # Configuring Klipper & co.
# ################################################################
# # Nginx main config
# cat >/etc/nginx/nginx.conf <<-EOF
# 	user http;
# 	worker_processes  1;

# 	events {
# 	    worker_connections  1024;
# 	}

# 	http {
# 	    types_hash_max_size 2048;
# 	    include             mime.types;
# 	    default_type        application/octet-stream;

# 	    sendfile            on;
# 	    keepalive_timeout   65;

# 	    include mjpgstreamers.conf;
# 	    include webui.conf;
# 	}
# EOF

# # Webcam upstreams
# cat >/etc/nginx/mjpgstreamers.conf <<-EOF
# 	upstream mjpgstreamer1 {
# 	    ip_hash;
# 	    server 127.0.0.1:8080;
# 	}

# 	upstream mjpgstreamer2 {
# 	    ip_hash;
# 	    server 127.0.0.1:8081;
# 	}

# 	upstream mjpgstreamer3 {
# 	    ip_hash;
# 	    server 127.0.0.1:8082;
# 	}

# 	upstream mjpgstreamer4 {
# 	    ip_hash;
# 	    server 127.0.0.1:8083;
# 	}
# EOF

# Klipper main configuration file
cat >/home/klipper/klipper-config/printer.cfg <<-EOF
	# [include webui-klipper.cfg]
	# [include moonraker-klipper.cfg]

	########################################
	# Your printer configuration goes here #
	########################################
	
EOF

# # copying / editing mainsail config files
# ln=$(sed -n -e '/^\}$/=' /usr/share/doc/mainsail/mainsail-nginx.conf |tail -n1)
# head -n $(($ln - 1)) /usr/share/doc/mainsail/mainsail-nginx.conf >/etc/nginx/mainsail-nginx.conf
# cat >>/etc/nginx/mainsail-nginx.conf <<-EOF

# 	    location /webcam/ {
# 	        postpone_output 0;
# 	        proxy_buffering off;
# 	        proxy_ignore_headers X-Accel-Buffering;
# 	        access_log off;
# 	        error_log off;
# 	        proxy_pass http://mjpgstreamer1/;
# 	    }

# 	    location /webcam2/ {
# 	        postpone_output 0;
# 	        proxy_buffering off;
# 	        proxy_ignore_headers X-Accel-Buffering;
# 	        access_log off;
# 	        error_log off;
# 	        proxy_pass http://mjpgstreamer2/;
# 	    }

# 	    location /webcam3/ {
# 	        postpone_output 0;
# 	        proxy_buffering off;
# 	        proxy_ignore_headers X-Accel-Buffering;
# 	        access_log off;
# 	        error_log off;
# 	        proxy_pass http://mjpgstreamer3/;
# 	    }

# 	    location /webcam4/ {
# 	        postpone_output 0;
# 	        proxy_buffering off;
# 	        proxy_ignore_headers X-Accel-Buffering;
# 	        access_log off;
# 	        error_log off;
# 	        proxy_pass http://mjpgstreamer4/;
# 	    }
# EOF
# tail -n +$ln /usr/share/doc/mainsail/mainsail-nginx.conf >>/etc/nginx/mainsail-nginx.conf

# sed -e 's#^\(path:\).*#\1 /var/cache/klipper/gcode#' \
#   /usr/share/doc/mainsail/mainsail-klipper.cfg >/etc/klipper/mainsail-klipper.cfg


# # Copying / editing fluidd config files
# ln=$(sed -n -e '/^\}$/=' /usr/share/doc/fluidd/fluidd-nginx.conf |tail -n1)
# head -n $(($ln - 1)) /usr/share/doc/fluidd/fluidd-nginx.conf >/etc/nginx/fluidd-nginx.conf
# cat >>/etc/nginx/fluidd-nginx.conf <<-EOF

# 	    location /webcam/ {
# 	        postpone_output 0;
# 	        proxy_buffering off;
# 	        proxy_ignore_headers X-Accel-Buffering;
# 	        access_log off;
# 	        error_log off;
# 	        proxy_pass http://mjpgstreamer1/;
# 	    }

# 	    location /webcam2/ {
# 	        postpone_output 0;
# 	        proxy_buffering off;
# 	        proxy_ignore_headers X-Accel-Buffering;
# 	        access_log off;
# 	        error_log off;
# 	        proxy_pass http://mjpgstreamer2/;
# 	    }

# 	    location /webcam3/ {
# 	        postpone_output 0;
# 	        proxy_buffering off;
# 	        proxy_ignore_headers X-Accel-Buffering;
# 	        access_log off;
# 	        error_log off;
# 	        proxy_pass http://mjpgstreamer3/;
# 	    }

# 	    location /webcam4/ {
# 	        postpone_output 0;
# 	        proxy_buffering off;
# 	        proxy_ignore_headers X-Accel-Buffering;
# 	        access_log off;
# 	        error_log off;
# 	        proxy_pass http://mjpgstreamer4/;
# 	    }
# EOF
# tail -n +$ln /usr/share/doc/fluidd/fluidd-nginx.conf >>/etc/nginx/fluidd-nginx.conf

# sed -e 's#^\(path:\).*#\1 /var/cache/klipper/gcode#' \
#   /usr/share/doc/fluidd/fluidd-klipper.cfg >/etc/klipper/fluidd-klipper.cfg


# # Copying moonraker configs and creating symlinks (instead of editing them)
# sed -e 's#^\(path:\).*#\1 /var/cache/klipper/gcode#' \
#     /usr/share/doc/moonraker/moonraker-klipper.cfg >/etc/klipper/moonraker-klipper.cfg
# mkdir -p /var/cache/klipper/gcode
# chown -R klipper:klipper /var/cache/klipper

# # TODO: is it still needed?
# ln -s /usr/share/klipper/examples /usr/lib/klipper/config
# ln -s /usr/share/doc/klipper /usr/lib/klipper/docs

# sed -i -e "s/^\(host:\).*/\1 0.0.0.0/" \
#     -e "s/^#\(\[authorization\]\)/\1/" \
#     -e "s%^#\?\(trusted_clients:\)%\1\n  $TRUSTED_NET%" \
#     -e "s%^#\?\(cors_domains:\)%\1\n  *.local\n  *://.app.fluidd.xyz%" \
#     -e "s%^#\?\(database_path:\).*%\1 /var/lib/moonraker/db%" \
#     /etc/klipper/moonraker.conf
# mkdir /var/lib/moonraker
# chown klipper:klipper /var/lib/moonraker



# ln -s ${DEFAULT_UI}-nginx.conf /etc/nginx/webui.conf
# ln -s ${DEFAULT_UI}-klipper.cfg /etc/klipper/webui-klipper.cfg

# # Registering services
# cat >/etc/systemd/system/klipper-mcu.service <<-EOF
# 	[Unit]
# 	Description=Klipper MCU on Raspberry Pi
# 	After=local-fs.target
# 	Before=klipper.service

# 	[Install]
# 	WantedBy=klipper.service

# 	[Service]
# 	Type=simple
# 	ExecStart=/usr/local/bin/klipper_mcu -r
# 	Restart=always
# 	RestartSec=10
# EOF

# cat >/etc/systemd/system/ustreamer@.service <<-EOF
# 	[Unit]
# 	Description=uStreamer service
# 	After=network.target

# 	[Service]
# 	Environment="SCRIPT_ARGS=%I"
# 	User=klipper
# 	ExecStart=/usr/bin/ustreamer --process-name-prefix ustreamer-%I --log-level 0 -d /dev/video%I --device-timeout=8 -m mjpeg -r 1920x1080 -f 30 -s 0.0.0.0 -p 808%I
# 	Nice=10

# 	[Install]
# 	WantedBy=klipper.service
# EOF

# cat >/etc/systemd/system/webcamd.service <<-EOF
# 	[Unit]
# 	Description=the MainsailOS webcam daemon (based on OctoPi) with the user specified config

# 	[Service]
# 	WorkingDirectory=/usr/local/bin
# 	StandardOutput=append:/var/log/webcamd.log
# 	StandardError=append:/var/log/webcamd.log
# 	ExecStart=/usr/local/bin/webcamd
# 	Restart=always
# 	Type=forking
# 	User=klipper

# 	[Install]
# 	WantedBy=multi-user.target
# EOF

# systemctl enable wpa_supplicant@wlan0
# systemctl enable systemd-networkd

# systemctl enable klipper.service
# systemctl enable klipper-mcu.service
# systemctl enable moonraker.service
# systemctl enable nginx.service
# systemctl enable ustreamer@0.service
# systemctl enable avahi-daemon

# echo "klipper ALL=(ALL) NOPASSWD: /usr/bin/systemctl restart *, /usr/bin/systemctl start *, /usr/bin/systemctl stop *, /usr/bin/shutdown *" >/etc/sudoers.d/klipper
# cp /build/klipper.bin /var/lib/klipper
