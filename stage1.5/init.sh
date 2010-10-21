#!/bin/sh
###############################################################################
#                                                                             #
#    Initramfs loader for Samsung Galaxy S                                    #
#                                                                             #
#    Devices supported and tested :                                           #
#      o AT&T Captivate                                                       #
#                                                                             #
#    Credits:                                                                 #
#      Atin Malaviya (atinm @ xda-developers)                                 #
#                                                                             #
#    Released under the GPLv3                                                 #
#                                                                             #
#    This program is free software: you can redistribute it and/or modify     #
#    it under the terms of the GNU General Public License as published by     #
#    the Free Software Foundation, either version 3 of the License, or        #
#    (at your option) any later version.                                      #
#                                                                             #
#    This program is distributed in the hope that it will be useful,          #
#    but WITHOUT ANY WARRANTY; without even the implied warranty of           #
#    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the            #
#    GNU General Public License for more details.                             #
#                                                                             #
#    You should have received a copy of the GNU General Public License        #
#    along with this program.  If not, see <http://www.gnu.org/licenses/>.    #
#                                                                             #
###############################################################################
set -x
PATH=/bin:/sbin:/system/bin:/system/sbin

alias mount_sdcard="mount -t vfat -o utf8 /dev/block/mmcblk0p1 /sdcard"
alias mount_system="mount -t rfs -o rw,check=no /dev/block/stl9 /system"
alias mount_data="mount -t ext4 -o noatime,nodiratime,barrier=0,noauto_da_alloc /dev/block/mmcblk0p2 /data"
debug_mode=0

install_scripts() {
    if ! cmp /res/scripts/fat.format_wrapper.sh /system/bin/fat.format_wrapper.sh; then

	if ! test -L /system/bin/fat.format; then

	    # if fat.format is not a symlink, it means that it's
	    # Samsung's binary. Let's rename it
	    mv /system/bin/fat.format /system/bin/fat.format.real
	    log "fat.format renamed to fat.format.real"
	fi

	cat /res/scripts/fat.format_wrapper.sh > /system/bin/fat.format_wrapper.sh
	chmod 755 /system/bin/fat.format_wrapper.sh

	ln -s /system/bin/fat.format_wrapper.sh /system/bin/fat.format
	log "fat.format wrapper installed"
    else
	log "fat.format wrapper already installed"
    fi
}

letsgo() {
    initrc="/sdcard/init/init.rc"
    if test -f $initrc ; then
	# copy the init.rc file over to /
	log "copying $initrc to /init.rc"
	cp $initrc /init.rc
	chmod 0755 /init.rc
    fi

    init="/sdcard/init/init"
    if test -f $init ; then
    	# copy the init file over to /sbin
    	log "copying $init to /sbin/init"
    	cp $init /sbin/init
    	chmod 0755 /sbin/init
    fi

    # dump logs to the sdcard
    if test -d /sdcard/init ; then
	log "running stage1 init !"
	
	if test $debug_mode = 1; then
	    cat /init.log > /sdcard/init/init-"`date '+%Y-%m-%d_%H-%M-%S'`".log
	fi
    fi

    umount /sdcard
    umount /system

    rmdir /sdcard 
    rm -r /bin

    #mount /data and leave it mounted
    mount_data

    # run init and disappear
    exec /sbin/init
}

create_devices() {
    # proc and sys are  used 
    mount -t proc proc /proc
    mount -t sysfs sys /sys

    # create used devices nodes
    mkdir -p /dev/block

    # create used devices nodes
    # standard
    mknod /dev/null c 1 3
    mknod /dev/zero c 1 5

    # internal & external SD
    mknod /dev/block/mmcblk0 b 179 0
    mknod /dev/block/mmcblk0p1 b 179 1
    mknod /dev/block/mmcblk0p2 b 179 2
    mknod /dev/block/mmcblk0p3 b 179 2
    mknod /dev/block/mmcblk0p4 b 179 2
    mknod /dev/block/stl1 b 138 1
    mknod /dev/block/stl2 b 138 2
    mknod /dev/block/stl3 b 138 3
    mknod /dev/block/stl4 b 138 4
    mknod /dev/block/stl5 b 138 5
    mknod /dev/block/stl6 b 138 6
    mknod /dev/block/stl7 b 138 7
    mknod /dev/block/stl8 b 138 8
    mknod /dev/block/stl9 b 138 9
    mknod /dev/block/stl10 b 138 10
    mknod /dev/block/stl11 b 138 11
    mknod /dev/block/stl12 b 138 12
}

insert_modules() {
    # ko files for 3D
    insmod /modules/pvrsrvkm.ko
    insmod /modules/s3c_lcd.ko
    insmod /modules/s3c_bc.ko

    # ko files for vibrator
    insmod /lib/modules/vibrator.ko

    # ko files for Fm radio
    insmod /lib/modules/Si4709_driver.ko

    insmod /lib/modules/fsr.ko
    insmod /lib/modules/fsr_stl.ko
    insmod /lib/modules/rfs_glue.ko
    insmod /lib/modules/rfs_fat.ko

# parameter block
    insmod /lib/modules/j4fs.ko
    insmod /lib/modules/param.ko

# mount modules
    insmod /lib/modules/onedram.ko
    insmod /lib/modules/svnet.ko
    insmod /lib/modules/modemctl.ko
    insmod /lib/modules/storage.ko
    insmod /lib/modules/bthid.ko
    insmod /lib/modules/jbd2.ko
    insmod /lib/modules/ext4.ko
}

#do mknods for the devices
create_devices

#insmod the things we need
insert_modules

mount_system
mount_sdcard

# debug mode detection
if test -f /sdcard/init/enable-debug ; then
    debug_mode=1
fi

#install fat.format-wrapper.sh
insert_scripts

# clean up and run init
letsgo
