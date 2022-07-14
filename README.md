# Klipper on Arch
## What?
A couple of poorly written BASH scripts to create a SD-card firmware image for Raspberry pi running Klipper on top of Arch Linux ARM 
## Why?
Because using Debian (based image) on a resource constrainted small SBC is like assembing a 2 metric ton ski box on the top of your VW golf. Debian is a decent generic-purpose operating system but not ideal for embedded devices.
## For the impatient
- Install **docker** in case you spent the last 10 years on an unhabitated island
- Create a folder named **user**
- Copy the content of the **user.example** folder to **user**
- Edit the files inside **user** according to your needs
- Run **koa-create.sh**
- Find something to keep yourself entertrained until the scripts does its magic
- Flash your MCU with MCU firmware (**build/klipper.bin**)
- Run **koa-shrink.sh** *(This will shrink your image to the minimum possible to make the next step faster)*
- Write the image to an SD-card (`dd if=koa.img of=/dev/sd# bs=64k oflag=sync status=progress`)
- Expand the filesystem on the SD (`./koa-expand.sh -i /dev/sd#`)
- Insert the SD card into the SD slot of the RPi of your printer
- Switch the printer on
##Known issues
Login on SSH as root is slow (sometimes... sometimes it is lightning fast). Quick workaround is commenting out the line `-session   optional   pam_systemd.so` in */etc/pam.d/system-login*. Unfortunately local login (with a keyboard and monitor) will stop working after that. This problem exists on multiple Systemd based ARMv7 Linux distributions.