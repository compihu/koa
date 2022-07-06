#!/usr/bin/bash
set -ex

. /tmp/environment

## Installing moonraker

mkdir mainsail
tar -C mainsail -xaf /build/mainsail.tar.gz

sudo mv /etc/nginx/nginx.conf /etc/nginx/nginx.conf.ori

sudo tee /etc/nginx/nginx.conf >/dev/null <<-EOF
	user http;
	worker_processes  1;

	events {
	    worker_connections  1024;
	}

	http {
	    types_hash_max_size 2048;
	    include             mime.types;
	    default_type        application/octet-stream;

	    sendfile            on;
	    keepalive_timeout   65;

	    include mjpgstreamers.conf;
	    include mainsail-nginx.conf;
	}
EOF

# Webcam upstreams
sudo tee /etc/nginx/mjpgstreamers.conf >/dev/null <<-EOF
	upstream mjpgstreamer1 {
	    ip_hash;
	    server 127.0.0.1:8080;
	}

	upstream mjpgstreamer2 {
	    ip_hash;
	    server 127.0.0.1:8081;
	}

	upstream mjpgstreamer3 {
	    ip_hash;
	    server 127.0.0.1:8082;
	}

	upstream mjpgstreamer4 {
	    ip_hash;
	    server 127.0.0.1:8083;
	}
EOF

sudo tee /etc/nginx/mainsail-nginx.conf >/dev/null <<- EOF
	map \$http_upgrade \$connection_upgrade {
	    default upgrade;
	    '' close;
	}

	# moonraker
	upstream apiserver {
	    ip_hash;
	    server 127.0.0.1:7125;
	}

	server {
	    listen 80 default_server;
	    listen [::]:80 default_server;

	    access_log /var/log/nginx/mainsail-access.log;
	    error_log /var/log/nginx/mainsail-error.log;

	    #disable this section on smaller hardware like a pi zero
	    gzip on;
	    gzip_vary on;
	    gzip_proxied any;
	    gzip_proxied expired no-cache no-store private auth;
	    gzip_comp_level 4;
	    gzip_buffers 16 8k;
	    gzip_http_version 1.1;
	    gzip_types text/plain text/css text/xml text/javascript application/x-javascript application/json application/xml;

	    #web_path from mainsail static files
	    root ${BASE_PATH}/mainsail;

	    index index.html;
	    server_name _;

	    #disable max upload size
	    client_max_body_size 0;

	    location / {
	        try_files \$uri \$uri/ /index.html;
	    }

	    location = /index.html {
	        add_header Cache-Control "no-store, no-cache, must-revalidate";
	    }

	    location /websocket {
	        proxy_pass http://apiserver/websocket;
	        proxy_http_version 1.1;
	        proxy_set_header Upgrade \$http_upgrade;
	        proxy_set_header Connection \$connection_upgrade;
	        proxy_set_header Host \$http_host;
	        proxy_set_header X-Real-IP \$remote_addr;
	        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
	        proxy_read_timeout 86400;
	    }

	    location ~ ^/(printer|api|access|machine|server)/ {
	        proxy_pass http://apiserver\$request_uri;
	        proxy_set_header Host \$http_host;
	        proxy_set_header X-Real-IP \$remote_addr;
	        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
	        proxy_set_header X-Scheme \$scheme;
	    }

	    location /webcam/ {
	        postpone_output 0;
	        proxy_buffering off;
	        proxy_ignore_headers X-Accel-Buffering;
	        access_log off;
	        error_log off;
	        proxy_pass http://mjpgstreamer1/;
	    }

	    location /webcam2/ {
	        postpone_output 0;
	        proxy_buffering off;
	        proxy_ignore_headers X-Accel-Buffering;
	        access_log off;
	        error_log off;
	        proxy_pass http://mjpgstreamer2/;
	    }

	    location /webcam3/ {
	        postpone_output 0;
	        proxy_buffering off;
	        proxy_ignore_headers X-Accel-Buffering;
	        access_log off;
	        error_log off;
	        proxy_pass http://mjpgstreamer3/;
	    }

	    location /webcam4/ {
	        postpone_output 0;
	        proxy_buffering off;
	        proxy_ignore_headers X-Accel-Buffering;
	        access_log off;
	        error_log off;
	        proxy_pass http://mjpgstreamer4/;
	    }
	}
EOF

cat >klipper-config/mainsail-klipper.cfg <<EOF
	[gcode_macro PAUSE]
	description: Pause the actual running print
	rename_existing: PAUSE_BASE
	gcode:
	        ##### set defaults #####
	        {% set x = params.X|default(230) %}      #edit to your park position
	        {% set y = params.Y|default(230) %}      #edit to your park position
	        {% set z = params.Z|default(10)|float %} #edit to your park position
	        {% set e = params.E|default(1) %}        #edit to your retract length
	        ##### calculate save lift position #####
	        {% set max_z = printer.toolhead.axis_maximum.z|float %}
	        {% set act_z = printer.toolhead.position.z|float %}
	        {% set lift_z = z|abs %}
	        {% if act_z < (max_z - lift_z) %}
	                {% set z_safe = lift_z %}
	        {% else %}
	                {% set z_safe = max_z - act_z %}
	        {% endif %}
	        ##### end of definitions #####
	        PAUSE_BASE
	        G91
	        {% if printer.extruder.can_extrude|lower == 'true' %}
	            G1 E-{e} F2100
	        {% else %}
	            {action_respond_info("Extruder not hot enough")}
	        {% endif %}
	        {% if "xyz" in printer.toolhead.homed_axes %}
	            G1 Z{z_safe}
	            G90
	            G1 X{x} Y{y} F6000
	        {% else %}
	            {action_respond_info("Printer not homed")}
	        {% endif %}

	[gcode_macro RESUME]
	description: Resume the actual running print
	rename_existing: RESUME_BASE
	gcode:
	        ##### set defaults #####
	        {% set e = params.E|default(1) %} #edit to your retract length
	        #### get VELOCITY parameter if specified ####
	        {% if 'VELOCITY' in params|upper %}
            {% set get_params = ('VELOCITY=' + params.VELOCITY)  %}
	        {%else %}
	            {% set get_params = "" %}
	        {% endif %}
	        ##### end of definitions #####
	        G91
	        {% if printer.extruder.can_extrude|lower == 'true' %}
	            G1 E{e} F2100
	        {% else %}
	            {action_respond_info("Extruder not hot enough")}
	        {% endif %}
	        RESUME_BASE {get_params}

	[gcode_macro CANCEL_PRINT]
	description: Cancel the actual running print
	rename_existing: CANCEL_PRINT_BASE
	gcode:
	        TURN_OFF_HEATERS
	        CANCEL_PRINT_BASE
EOF

sudo systemctl enable nginx.service
