#!/sbin/busybox sh
###############################################################################
#                                                                             #
#    Stage 1 initramfs loader for Samsung Galaxy S                            #
#                                                                             #
#    Devices supported and tested :                                           #
#      o AT&T Captivate                                                       #
#                                                                             #
#    Credits:                                                                 #
#      Atin Malaviya (atinm @ xda-developers)                                 #
#      Francois Simond *supercurio @ xda-developers)                          #
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
PATH=/sbin:/system/bin:/system/sbin

alias mount_sdcard="/sbin/busybox mount -t vfat -o utf8 /dev/block/mmcblk0p1 /sdcard"
alias mount_system="/sbin/busybox mount -t rfs -o rw,check=no /dev/block/stl9 /system"
debug_mode=1

load_stage() {
    # don't reload a stage already in memory
    if ! test -f /tmp/stage$1_loaded; then
	stagefile="/sdcard/init/stage$1.cpio.gz"

	if test -f $stagefile ; then
	    # load the designated stage after verifying it's
	    # signature to prevent security exploit from sdcard
	    #signature=`/sbin/busybox sha1sum $stagefile | /sbin/busybox cut -d' ' -f 1`
	    #for x in `/sbin/busybox cat /res/signatures/$1.sig`; do
		#if test "$x" = "$signature"  ; then
		    /sbin/busybox rm stage-init.sh
		    log "load stage $1 from SD"
		    /sbin/busybox zcat -dc $stagefile | /sbin/busybox cpio -diuv
		    echo 1 > /tmp/stage$1_loaded
		    #break
		#fi
	    #done
	    #if ! test -f /tmp/stage$1_loaded ; then
		#log "stage $1 not loaded, signature mismatch"
	    #fi
	else
	    log "stage $1 not loaded, $stagefile not found"
	fi

	if test -f /tmp/stage$1_loaded ; then
	    if test -f /stage-init.sh ; then
		log "running /stage-init.sh for stage $1"
		/stage-init.sh >> /init-$1.log 2>&1
		return $?
	    fi
	fi
    fi

    return 1
}

log() {
    log="init.sh: $1"
    echo `date '+%Y-%m-%d %H:%M:%S'` $log >> /init.log
}

letsgo() {
    # dump logs to the sdcard
    if test -d /sdcard/init ; then
	log "running init !"
	
	if test $debug_mode = 1; then
	    /sbin/busybox cat /init.log > /sdcard/init/init-"`date '+%Y-%m-%d_%H-%M-%S'`".log
	fi
    fi

    /sbin/busybox umount /sdcard
    /sbin/busybox umount /system

    /sbin/busybox rmdir /sdcard 

    # remove busybox link so as not to interfere with user installed busybox
    /sbin/busybox rm /sbin/busybox

    # run init and disappear
    exec /sbin/init
}

create_devices() {
    # proc and sys are  used 
    /sbin/busybox mount -t proc proc /proc
    /sbin/busybox mount -t sysfs sys /sys

    # create used devices nodes
    /sbin/busybox mkdir -p /dev/block

    # create used devices nodes
    # standard
    /sbin/busybox mknod /dev/null c 1 3
    /sbin/busybox mknod /dev/zero c 1 5

    # internal & external SD
    /sbin/busybox mknod /dev/block/mmcblk0 b 179 0
    /sbin/busybox mknod /dev/block/mmcblk0p1 b 179 1
    /sbin/busybox mknod /dev/block/mmcblk0p2 b 179 2
    /sbin/busybox mknod /dev/block/mmcblk0p3 b 179 2
    /sbin/busybox mknod /dev/block/mmcblk0p4 b 179 2
    /sbin/busybox mknod /dev/block/stl1 b 138 1
    /sbin/busybox mknod /dev/block/stl2 b 138 2
    /sbin/busybox mknod /dev/block/stl3 b 138 3
    /sbin/busybox mknod /dev/block/stl4 b 138 4
    /sbin/busybox mknod /dev/block/stl5 b 138 5
    /sbin/busybox mknod /dev/block/stl6 b 138 6
    /sbin/busybox mknod /dev/block/stl7 b 138 7
    /sbin/busybox mknod /dev/block/stl8 b 138 8
    /sbin/busybox mknod /dev/block/stl9 b 138 9
    /sbin/busybox mknod /dev/block/stl10 b 138 10
    /sbin/busybox mknod /dev/block/stl11 b 138 11
    /sbin/busybox mknod /dev/block/stl12 b 138 12
}

insert_modules() {
    # ko files for 3D
    /sbin/busybox insmod /modules/pvrsrvkm.ko
    /sbin/busybox insmod /modules/s3c_lcd.ko
    /sbin/busybox insmod /modules/s3c_bc.ko

    # ko files for vibrator
    /sbin/busybox insmod /lib/modules/vibrator.ko

    # ko files for Fm radio
    /sbin/busybox insmod /lib/modules/Si4709_driver.ko

    /sbin/busybox insmod /lib/modules/fsr.ko
    /sbin/busybox insmod /lib/modules/fsr_stl.ko
    /sbin/busybox insmod /lib/modules/rfs_glue.ko
    /sbin/busybox insmod /lib/modules/rfs_fat.ko

# parameter block
    /sbin/busybox insmod /lib/modules/j4fs.ko
    /sbin/busybox insmod /lib/modules/param.ko

# mount modules
    /sbin/busybox insmod /lib/modules/onedram.ko
    /sbin/busybox insmod /lib/modules/svnet.ko
    /sbin/busybox insmod /lib/modules/modemctl.ko
    /sbin/busybox insmod /lib/modules/storage.ko
    /sbin/busybox insmod /lib/modules/bthid.ko
}

#do mknods for the devices
create_devices

#insmod the things we need
insert_modules

# new in beta5, using /system
mount_system
mount_sdcard

# debug mode detection
if test -f /sdcard/init/enable-debug ; then
    debug_mode=1
fi

# Load stages - starting at 2 (we are 1)
num=2
while test -f /sdcard/init/stage$num.cpio.gz
do
    load_stage $num
    num=$(($num+1))
done

# clean up and run init
letsgo
