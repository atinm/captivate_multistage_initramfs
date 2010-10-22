#!/sbin/busybox sh
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
PATH=/sbin:/system/sbin:/system/bin:/system/xbin
export PATH
debug_mode=0
status=0
data_partition="/dev/block/mmcblk0p2"
dbdata_partition="/dev/block/stl10"
sdcard_partition="/dev/block/mmcblk0p1"
sdcard_ext_partition="/dev/block/mmcblk1"
sdcard='/sdcard'
sdcard_ext='/sdcard/sdcard_ext'
data_archive="/sdcard/user-data.tar"


alias check_dbdata="fsck_msdos -y $dbdata_partition"
alias make_backup="/sbin/tar cvf $data_archive /data /dbdata"

mount_() {
    case $1 in
	cache)
	    /sbin/mount -t rfs -o nosuid,nodev,check=no /dev/block/stl11 /cache
	    ;;
	dbdata)
	    /sbin/mount -t rfs -o nosuid,nodev,check=no $dbdata_partition /dbdata
	    ;;
	data_rfs)
	    /sbin/mount -t rfs -o nosuid,nodev,check=no $data_partition /data
	    ;;
	data_ext4)
	    /sbin/mount -t ext4 -o noatime,nodiratime,barrier=0,noauto_da_alloc $data_partition /data
	    ;;
	sdcard)
	    /sbin/mount -t vfat -o utf8 $sdcard_partition $sdcard
	    ;;
	sdcard_ext)
	    /sbin/mount -t vfat -o utf8 $sdcard_ext_partition $sdcard_ext
	    ;;
    esac
}


log() {
    log="init.sh: $1"
    echo `/sbin/date '+%Y-%m-%d %H:%M:%S'` $log >> /init.log
}

check_free() {
    # FIXME: add the check if we have enough space based on the
    # space lost with Ext4 conversion with offset
	
    # read free space on internal SD
    target_free=`/sbin/df $sdcard | /sbin/cut -d' ' -f 6 | /sbin/cut -d K -f 1`

    # read space used by data we need to save
    space_needed=$((`/sbin/df /data | /sbin/cut -d' ' -f 4 | /sbin/cut -d K -f 1` + \
	`/sbin/df /dbdata | /sbin/cut -d' ' -f 4 | /sbin/cut -d K -f 1`))

    log "free space : $target_free"
    log "space needed : $space_needed"
    
    # FIXME: get a % of security
    test $target_free -ge $space_needed
}

wipe_data_filesystem() {
    # ext4 is very hard to wipe due to it's superblock which provide
    # much security, so we wipe the start of the partition (3MB)
    # wich does enouch to prevent blkid to detect Ext4.
    # RFS is also seriously hit by 3MB of zeros ;)
    /sbin/dd if=/dev/zero of=$data_partition bs=1024 count=$((3 * 1024))
    /sbin/sync
}

restore_backup() {
    # clean any previous false dbdata partition
    /sbin/rm -r /dbdata/*
    /sbin/umount /dbdata
    check_dbdata
    mount_ dbdata
    # extract from the backup,
    # with dirty workaround to fix battery level inaccuracy
    # then remove the backup file if everything went smooth
    /sbin/tar xvf $data_archive && /sbin/rm $data_archive
    /sbin/rm /data/system/batterystats.bin
}

ext4_check() {
    log "ext4 filesystem detection"
    if /sbin/tune2fs -l $data_partition; then
	# we found an ext2/3/4 partition. but is it real ?
	# if the data partition mounts as rfs, it means
	# that this ext4 partition is just lost bits still here
	if mount_ data_rfs; then
	    log "ext4 bits found but from an invalid and corrupted filesystem"
	    return 1
	fi
	log "ext4 filesystem detected"
	return 0
    fi
    log "no ext4 filesystem detected"
    return 1
}

do_rfs() {
    if ext4_check; then
	log "lag fix disabled and Ext4 detected"
	# ext4 partition detected, let's convert it back to rfs :'(
	# mount resources
	mount_ data_ext4
	mount_ dbdata
	
	log "run backup of Ext4 /data"
	
	# check if there is enough free space for migration or cancel
	# and boot
	if ! check_free; then
	    log "not enough space to migrate from ext4 to rfs"
	    mount_ data_ext4
	    status=1
	    return $status
	fi
	
	make_backup
	
	# umount data because we will wipe it
	/sbin/umount /data

	# wipe Ext4 filesystem
	log "wipe Ext4 filesystem before formating $data_partition as RFS"
	wipe_data_filesystem

	# format as RFS
	# for some obsure reason, fat.format really won't want to
	# work in this pre-init. That's why we use an alternative technique
	/sbin/zcat /res/configs/rfs_filesystem_data_16GB.gz > $data_partition
	fsck_msdos -y $data_partition

	# restore the data archived
	log "restore backup on rfs /data"
	mount_ data_rfs
	restore_backup
	
	/bin/umount /dbdata
	status=0

    else
	# in this case, we did not detect any valid ext4 partition
	# hopefully this is because $data_partition contains a valid rfs /data
	log "lag fix disabled, rfs present"
	log "mount /data as rfs"
	mount_ data_rfs
	status=0
    fi

    return $status
}

do_lagfix() {
    if ! ext4_check ; then
	log "no ext4 partition detected"
	
	# mount ressources we need
	log "mount resources to backup"
	mount_ data_rfs
	mount_ dbdata

	# check if there is enough free space for migration or cancel
	# and boot
	if ! check_free; then
		log "not enough space to migrate from rfs to ext4"
		mount_ data_rfs
		/sbin/umount /dbdata
		status=1
		return $status
	fi

	# run the backup operation
	log "run the backup operation"
	make_backup
	
	# umount mmcblk0 ressources
	/sbin/umount /sdcard
	/sbin/umount /data
	/sbin/umount /dbdata

	# build the ext4 filesystem
	log "build the ext4 filesystem"
	
	# Ext4 DATA 
	# (empty) /etc/mtab is required for this mkfs.ext4
	/sbin/cat /etc/mke2fs.conf
	/sbin/mkfs.ext4 -F -O sparse_super $data_partition
	# force check the filesystem after 100 mounts or 100 days
	/sbin/tune2fs -c 100 -i 100d -m 0 $data_partition

	mount_ data_ext4
	mount_ dbdata

	mount_ sdcard

	# restore the data archived
	restore_backup

	# clean all these mounts but leave /data mounted
	log "umount what will be re-mounted by Samsung's Android init"
	/sbin/umount /dbdata
	/sbin/umount /sdcard

	status=0
    else
	# seems that we have a ext4 partition ;) just mount it
	log "protected ext4 detected, mounting ext4 /data !"
	/sbin/e2fsck -p $data_partition

	#leave /data mounted
	mount_ data_ext4
	status=0
    fi

    return $status
}

symlink_busybox() {
    # busybox is already a symlink to CWM's recovery. Now create the remaining part
    # We will delete these links including the symlink to busybox when we are done, 
    # so they won't interfere with the installed busybox on the device
    /sbin/busybox ln -s /sbin/busybox "/sbin/["
    /sbin/busybox ln -s /sbin/busybox "/sbin/[["
    /sbin/busybox ln -s /sbin/recovery /sbin/amend
    /sbin/busybox ln -s /sbin/busybox /sbin/ash
    /sbin/busybox ln -s /sbin/busybox /sbin/awk
    /sbin/busybox ln -s /sbin/busybox /sbin/basename
    /sbin/busybox ln -s /sbin/busybox /sbin/bbconfig
    /sbin/busybox ln -s /sbin/busybox /sbin/bunzip2
    /sbin/busybox ln -s /sbin/busybox /sbin/bzcat
    /sbin/busybox ln -s /sbin/busybox /sbin/bzip2
    /sbin/busybox ln -s /sbin/busybox /sbin/cal
    /sbin/busybox ln -s /sbin/busybox /sbin/cat
    /sbin/busybox ln -s /sbin/busybox /sbin/catv
    /sbin/busybox ln -s /sbin/busybox /sbin/chgrp
    /sbin/busybox ln -s /sbin/busybox /sbin/chmod
    /sbin/busybox ln -s /sbin/busybox /sbin/chown
    /sbin/busybox ln -s /sbin/busybox /sbin/chroot
    /sbin/busybox ln -s /sbin/busybox /sbin/cksum
    /sbin/busybox ln -s /sbin/busybox /sbin/clear
    /sbin/busybox ln -s /sbin/busybox /sbin/cmp
    /sbin/busybox ln -s /sbin/busybox /sbin/cp
    /sbin/busybox ln -s /sbin/busybox /sbin/cpio
    /sbin/busybox ln -s /sbin/busybox /sbin/cut
    /sbin/busybox ln -s /sbin/busybox /sbin/date
    /sbin/busybox ln -s /sbin/busybox /sbin/dc
    /sbin/busybox ln -s /sbin/busybox /sbin/dd
    /sbin/busybox ln -s /sbin/busybox /sbin/depmod
    /sbin/busybox ln -s /sbin/busybox /sbin/devmem
    /sbin/busybox ln -s /sbin/busybox /sbin/df
    /sbin/busybox ln -s /sbin/busybox /sbin/diff
    /sbin/busybox ln -s /sbin/busybox /sbin/dirname
    /sbin/busybox ln -s /sbin/busybox /sbin/dmesg
    /sbin/busybox ln -s /sbin/busybox /sbin/dos2unix
    /sbin/busybox ln -s /sbin/busybox /sbin/du
    /sbin/busybox ln -s /sbin/recovery /sbin/dump_image
    /sbin/busybox ln -s /sbin/busybox /sbin/echo
    /sbin/busybox ln -s /sbin/busybox /sbin/egrep
    /sbin/busybox ln -s /sbin/busybox /sbin/env
    /sbin/busybox ln -s /sbin/recovery /sbin/erase_image
    /sbin/busybox ln -s /sbin/busybox /sbin/expr
    /sbin/busybox ln -s /sbin/busybox /sbin/false
    /sbin/busybox ln -s /sbin/busybox /sbin/fdisk
    /sbin/busybox ln -s /sbin/busybox /sbin/fgrep
    /sbin/busybox ln -s /sbin/busybox /sbin/find
    /sbin/busybox ln -s /sbin/recovery /sbin/flash_image
    /sbin/busybox ln -s /sbin/busybox /sbin/fold
    /sbin/busybox ln -s /sbin/busybox /sbin/free
    /sbin/busybox ln -s /sbin/busybox /sbin/freeramdisk
    /sbin/busybox ln -s /sbin/busybox /sbin/fuser
    /sbin/busybox ln -s /sbin/busybox /sbin/getopt
    /sbin/busybox ln -s /sbin/busybox /sbin/grep
    /sbin/busybox ln -s /sbin/busybox /sbin/gunzip
    /sbin/busybox ln -s /sbin/busybox /sbin/gzip
    /sbin/busybox ln -s /sbin/busybox /sbin/head
    /sbin/busybox ln -s /sbin/busybox /sbin/hexdump
    /sbin/busybox ln -s /sbin/busybox /sbin/id
    /sbin/busybox ln -s /sbin/busybox /sbin/insmod
    /sbin/busybox ln -s /sbin/busybox /sbin/install
    /sbin/busybox ln -s /sbin/busybox /sbin/kill
    /sbin/busybox ln -s /sbin/busybox /sbin/killall
    /sbin/busybox ln -s /sbin/busybox /sbin/killall5
    /sbin/busybox ln -s /sbin/busybox /sbin/length
    /sbin/busybox ln -s /sbin/busybox /sbin/less
    /sbin/busybox ln -s /sbin/busybox /sbin/ln
    /sbin/busybox ln -s /sbin/busybox /sbin/losetup
    /sbin/busybox ln -s /sbin/busybox /sbin/ls
    /sbin/busybox ln -s /sbin/busybox /sbin/lsmod
    /sbin/busybox ln -s /sbin/busybox /sbin/lspci
    /sbin/busybox ln -s /sbin/busybox /sbin/lsusb
    /sbin/busybox ln -s /sbin/busybox /sbin/lzop
    /sbin/busybox ln -s /sbin/busybox /sbin/lzopcat
    /sbin/busybox ln -s /sbin/busybox /sbin/md5sum
    /sbin/busybox ln -s /sbin/busybox /sbin/mkdir
    /sbin/busybox ln -s /sbin/busybox /sbin/mkfifo
    /sbin/busybox ln -s /sbin/busybox /sbin/mknod
    /sbin/busybox ln -s /sbin/busybox /sbin/mkswap
    /sbin/busybox ln -s /sbin/busybox /sbin/mktemp
    /sbin/busybox ln -s /sbin/recovery /sbin/mkyaffs2image
    /sbin/busybox ln -s /sbin/busybox /sbin/modprobe
    /sbin/busybox ln -s /sbin/busybox /sbin/more
    /sbin/busybox ln -s /sbin/busybox /sbin/mount
    /sbin/busybox ln -s /sbin/busybox /sbin/mountpoint
    /sbin/busybox ln -s /sbin/busybox /sbin/mv
    /sbin/busybox ln -s /sbin/recovery /sbin/nandroid
    /sbin/busybox ln -s /sbin/busybox /sbin/nice
    /sbin/busybox ln -s /sbin/busybox /sbin/nohup
    /sbin/busybox ln -s /sbin/busybox /sbin/od
    /sbin/busybox ln -s /sbin/busybox /sbin/patch
    /sbin/busybox ln -s /sbin/busybox /sbin/pgrep
    /sbin/busybox ln -s /sbin/busybox /sbin/pidof
    /sbin/busybox ln -s /sbin/busybox /sbin/pkill
    /sbin/busybox ln -s /sbin/busybox /sbin/printenv
    /sbin/busybox ln -s /sbin/busybox /sbin/printf
    /sbin/busybox ln -s /sbin/busybox /sbin/ps
    /sbin/busybox ln -s /sbin/busybox /sbin/pwd
    /sbin/busybox ln -s /sbin/busybox /sbin/rdev
    /sbin/busybox ln -s /sbin/busybox /sbin/readlink
    /sbin/busybox ln -s /sbin/busybox /sbin/realpath
    /sbin/busybox ln -s /sbin/recovery /sbin/reboot
    /sbin/busybox ln -s /sbin/busybox /sbin/renice
    /sbin/busybox ln -s /sbin/busybox /sbin/reset
    /sbin/busybox ln -s /sbin/busybox /sbin/rm
    /sbin/busybox ln -s /sbin/busybox /sbin/rmdir
    /sbin/busybox ln -s /sbin/busybox /sbin/rmmod
    /sbin/busybox ln -s /sbin/busybox /sbin/run-parts
    /sbin/busybox ln -s /sbin/busybox /sbin/sed
    /sbin/busybox ln -s /sbin/busybox /sbin/seq
    /sbin/busybox ln -s /sbin/busybox /sbin/setsid
    /sbin/busybox ln -s /sbin/busybox /sbin/sh
    /sbin/busybox ln -s /sbin/busybox /sbin/sha1sum
    /sbin/busybox ln -s /sbin/busybox /sbin/sha256sum
    /sbin/busybox ln -s /sbin/busybox /sbin/sha512sum
    /sbin/busybox ln -s /sbin/busybox /sbin/sleep
    /sbin/busybox ln -s /sbin/busybox /sbin/sort
    /sbin/busybox ln -s /sbin/busybox /sbin/split
    /sbin/busybox ln -s /sbin/busybox /sbin/stat
    /sbin/busybox ln -s /sbin/busybox /sbin/strings
    /sbin/busybox ln -s /sbin/busybox /sbin/stty
    /sbin/busybox ln -s /sbin/busybox /sbin/swapoff
    /sbin/busybox ln -s /sbin/busybox /sbin/swapon
    /sbin/busybox ln -s /sbin/busybox /sbin/sync
    /sbin/busybox ln -s /sbin/busybox /sbin/sysctl
    /sbin/busybox ln -s /sbin/busybox /sbin/tac
    /sbin/busybox ln -s /sbin/busybox /sbin/tail
    /sbin/busybox ln -s /sbin/busybox /sbin/tar
    /sbin/busybox ln -s /sbin/busybox /sbin/tee
    /sbin/busybox ln -s /sbin/busybox /sbin/test
    /sbin/busybox ln -s /sbin/busybox /sbin/time
    /sbin/busybox ln -s /sbin/busybox /sbin/top
    /sbin/busybox ln -s /sbin/busybox /sbin/touch
    /sbin/busybox ln -s /sbin/busybox /sbin/tr
    /sbin/busybox ln -s /sbin/busybox /sbin/true
    /sbin/busybox ln -s /sbin/recovery /sbin/truncate
    /sbin/busybox ln -s /sbin/busybox /sbin/tty
    /sbin/busybox ln -s /sbin/busybox /sbin/umount
    /sbin/busybox ln -s /sbin/busybox /sbin/uname
    /sbin/busybox ln -s /sbin/busybox /sbin/uniq
    /sbin/busybox ln -s /sbin/busybox /sbin/unix2dos
    /sbin/busybox ln -s /sbin/busybox /sbin/unlzop
    /sbin/busybox ln -s /sbin/recovery /sbin/unyaffs
    /sbin/busybox ln -s /sbin/busybox /sbin/unzip
    /sbin/busybox ln -s /sbin/busybox /sbin/uptime
    /sbin/busybox ln -s /sbin/busybox /sbin/usleep
    /sbin/busybox ln -s /sbin/busybox /sbin/uudecode
    /sbin/busybox ln -s /sbin/busybox /sbin/uuencode
    /sbin/busybox ln -s /sbin/busybox /sbin/watch
    /sbin/busybox ln -s /sbin/busybox /sbin/wc
    /sbin/busybox ln -s /sbin/busybox /sbin/which
    /sbin/busybox ln -s /sbin/busybox /sbin/whoami
    /sbin/busybox ln -s /sbin/busybox /sbin/xargs
    /sbin/busybox ln -s /sbin/busybox /sbin/yes
    /sbin/busybox ln -s /sbin/busybox /sbin/zcat
}

remove_busybox() {
    /sbin/busybox rm /sbin/[
    /sbin/busybox rm /sbin/[[
    /sbin/busybox rm /sbin/amend
    /sbin/busybox rm /sbin/ash
    /sbin/busybox rm /sbin/awk
    /sbin/busybox rm /sbin/basename
    /sbin/busybox rm /sbin/bbconfig
    /sbin/busybox rm /sbin/bunzip2
    /sbin/busybox rm /sbin/bzcat
    /sbin/busybox rm /sbin/bzip2
    /sbin/busybox rm /sbin/cal
    /sbin/busybox rm /sbin/cat
    /sbin/busybox rm /sbin/catv
    /sbin/busybox rm /sbin/chgrp
    /sbin/busybox rm /sbin/chmod
    /sbin/busybox rm /sbin/chown
    /sbin/busybox rm /sbin/chroot
    /sbin/busybox rm /sbin/cksum
    /sbin/busybox rm /sbin/clear
    /sbin/busybox rm /sbin/cmp
    /sbin/busybox rm /sbin/cp
    /sbin/busybox rm /sbin/cpio
    /sbin/busybox rm /sbin/cut
    /sbin/busybox rm /sbin/date
    /sbin/busybox rm /sbin/dc
    /sbin/busybox rm /sbin/dd
    /sbin/busybox rm /sbin/depmod
    /sbin/busybox rm /sbin/devmem
    /sbin/busybox rm /sbin/df
    /sbin/busybox rm /sbin/diff
    /sbin/busybox rm /sbin/dirname
    /sbin/busybox rm /sbin/dmesg
    /sbin/busybox rm /sbin/dos2unix
    /sbin/busybox rm /sbin/du
    /sbin/busybox rm /sbin/dump_image
    /sbin/busybox rm /sbin/echo
    /sbin/busybox rm /sbin/egrep
    /sbin/busybox rm /sbin/env
    /sbin/busybox rm /sbin/erase_image
    /sbin/busybox rm /sbin/expr
    /sbin/busybox rm /sbin/false
    /sbin/busybox rm /sbin/fdisk
    /sbin/busybox rm /sbin/fgrep
    /sbin/busybox rm /sbin/find
    /sbin/busybox rm /sbin/flash_image
    /sbin/busybox rm /sbin/fold
    /sbin/busybox rm /sbin/free
    /sbin/busybox rm /sbin/freeramdisk
    /sbin/busybox rm /sbin/fuser
    /sbin/busybox rm /sbin/getopt
    /sbin/busybox rm /sbin/grep
    /sbin/busybox rm /sbin/gunzip
    /sbin/busybox rm /sbin/gzip
    /sbin/busybox rm /sbin/head
    /sbin/busybox rm /sbin/hexdump
    /sbin/busybox rm /sbin/id
    /sbin/busybox rm /sbin/insmod
    /sbin/busybox rm /sbin/install
    /sbin/busybox rm /sbin/kill
    /sbin/busybox rm /sbin/killall
    /sbin/busybox rm /sbin/killall5
    /sbin/busybox rm /sbin/length
    /sbin/busybox rm /sbin/less
    /sbin/busybox rm /sbin/ln
    /sbin/busybox rm /sbin/losetup
    /sbin/busybox rm /sbin/ls
    /sbin/busybox rm /sbin/lsmod
    /sbin/busybox rm /sbin/lspci
    /sbin/busybox rm /sbin/lsusb
    /sbin/busybox rm /sbin/lzop
    /sbin/busybox rm /sbin/lzopcat
    /sbin/busybox rm /sbin/md5sum
    /sbin/busybox rm /sbin/mkdir
    /sbin/busybox rm /sbin/mkfifo
    /sbin/busybox rm /sbin/mknod
    /sbin/busybox rm /sbin/mkswap
    /sbin/busybox rm /sbin/mktemp
    /sbin/busybox rm /sbin/mkyaffs2image
    /sbin/busybox rm /sbin/modprobe
    /sbin/busybox rm /sbin/more
    /sbin/busybox rm /sbin/mount
    /sbin/busybox rm /sbin/mountpoint
    /sbin/busybox rm /sbin/mv
    /sbin/busybox rm /sbin/nandroid
    /sbin/busybox rm /sbin/nice
    /sbin/busybox rm /sbin/nohup
    /sbin/busybox rm /sbin/od
    /sbin/busybox rm /sbin/patch
    /sbin/busybox rm /sbin/pgrep
    /sbin/busybox rm /sbin/pidof
    /sbin/busybox rm /sbin/pkill
    /sbin/busybox rm /sbin/printenv
    /sbin/busybox rm /sbin/printf
    /sbin/busybox rm /sbin/ps
    /sbin/busybox rm /sbin/pwd
    /sbin/busybox rm /sbin/rdev
    /sbin/busybox rm /sbin/readlink
    /sbin/busybox rm /sbin/realpath
    /sbin/busybox rm /sbin/reboot
    /sbin/busybox rm /sbin/renice
    /sbin/busybox rm /sbin/reset
    /sbin/busybox rm /sbin/rm
    /sbin/busybox rm /sbin/rmdir
    /sbin/busybox rm /sbin/rmmod
    /sbin/busybox rm /sbin/run-parts
    /sbin/busybox rm /sbin/sed
    /sbin/busybox rm /sbin/seq
    /sbin/busybox rm /sbin/setsid
    /sbin/busybox rm /sbin/sh
    /sbin/busybox rm /sbin/sha1sum
    /sbin/busybox rm /sbin/sha256sum
    /sbin/busybox rm /sbin/sha512sum
    /sbin/busybox rm /sbin/sleep
    /sbin/busybox rm /sbin/sort
    /sbin/busybox rm /sbin/split
    /sbin/busybox rm /sbin/stat
    /sbin/busybox rm /sbin/strings
    /sbin/busybox rm /sbin/stty
    /sbin/busybox rm /sbin/swapoff
    /sbin/busybox rm /sbin/swapon
    /sbin/busybox rm /sbin/sync
    /sbin/busybox rm /sbin/sysctl
    /sbin/busybox rm /sbin/tac
    /sbin/busybox rm /sbin/tail
    /sbin/busybox rm /sbin/tar
    /sbin/busybox rm /sbin/tee
    /sbin/busybox rm /sbin/test
    /sbin/busybox rm /sbin/time
    /sbin/busybox rm /sbin/top
    /sbin/busybox rm /sbin/touch
    /sbin/busybox rm /sbin/tr
    /sbin/busybox rm /sbin/true
    /sbin/busybox rm /sbin/truncate
    /sbin/busybox rm /sbin/tty
    /sbin/busybox rm /sbin/umount
    /sbin/busybox rm /sbin/uname
    /sbin/busybox rm /sbin/uniq
    /sbin/busybox rm /sbin/unix2dos
    /sbin/busybox rm /sbin/unlzop
    /sbin/busybox rm /sbin/unyaffs
    /sbin/busybox rm /sbin/unzip
    /sbin/busybox rm /sbin/uptime
    /sbin/busybox rm /sbin/usleep
    /sbin/busybox rm /sbin/uudecode
    /sbin/busybox rm /sbin/uuencode
    /sbin/busybox rm /sbin/watch
    /sbin/busybox rm /sbin/wc
    /sbin/busybox rm /sbin/which
    /sbin/busybox rm /sbin/whoami
    /sbin/busybox rm /sbin/xargs
    /sbin/busybox rm /sbin/yes
    /sbin/busybox rm /sbin/zcat

    # self destruct :)
    /sbin/busybox rm /sbin/busybox
}

install_scripts() {
    if ! /sbin/cmp /res/scripts/fat.format_wrapper.sh /system/bin/fat.format_wrapper.sh; then

	if ! test -L /system/bin/fat.format; then

	    # if fat.format is not a symlink, it means that it's
	    # Samsung's binary. Let's rename it
	    mv /system/bin/fat.format /system/bin/fat.format.real
	    log "fat.format renamed to fat.format.real"
	fi

	/sbin/cat /res/scripts/fat.format_wrapper.sh > /system/bin/fat.format_wrapper.sh
	/sbin/chmod 755 /system/bin/fat.format_wrapper.sh

	/sbin/ln -s /system/bin/fat.format_wrapper.sh /system/bin/fat.format
	log "fat.format wrapper installed"
    else
	log "fat.format wrapper already installed"
    fi
}

letsgo() {
    # dump logs to the sdcard
    if test -d /sdcard/init ; then
	log "running stage1 init !"
	
	if test $debug_mode = 1; then
	    /sbin/cat /init.log > /sdcard/init/init-"`date '+%Y-%m-%d_%H-%M-%S'`".log
	fi
    fi

    /sbin/umount /sdcard
    /sbin/umount /system

    /sbin/rmdir /sdcard 
    /sbin/rm -r /res/configs

    remove_busybox

    # run init and disappear
    exec /sbin/init
}

create_devices() {
    # proc and sys are  used 
    /sbin/mount -t proc proc /proc
    /sbin/mount -t sysfs sys /sys

    # create used devices nodes
    /sbin/mkdir -p /dev/block

    # create used devices nodes
    # standard
    /sbin/mknod /dev/null c 1 3
    /sbin/mknod /dev/zero c 1 5

    # internal & external SD
    /sbin/mknod /dev/block/mmcblk0 b 179 0
    /sbin/mknod /dev/block/mmcblk0p1 b 179 1
    /sbin/mknod /dev/block/mmcblk0p2 b 179 2
    /sbin/mknod /dev/block/mmcblk0p3 b 179 2
    /sbin/mknod /dev/block/mmcblk0p4 b 179 2
    /sbin/mknod /dev/block/stl1 b 138 1
    /sbin/mknod /dev/block/stl2 b 138 2
    /sbin/mknod /dev/block/stl3 b 138 3
    /sbin/mknod /dev/block/stl4 b 138 4
    /sbin/mknod /dev/block/stl5 b 138 5
    /sbin/mknod /dev/block/stl6 b 138 6
    /sbin/mknod /dev/block/stl7 b 138 7
    /sbin/mknod /dev/block/stl8 b 138 8
    /sbin/mknod /dev/block/stl9 b 138 9
    /sbin/mknod /dev/block/stl10 b 138 10
    /sbin/mknod /dev/block/stl11 b 138 11
    /sbin/mknod /dev/block/stl12 b 138 12
}

insert_modules() {
    # ko files for 3D
    /sbin/insmod /modules/pvrsrvkm.ko
    /sbin/insmod /modules/s3c_lcd.ko
    /sbin/insmod /modules/s3c_bc.ko

    # ko files for vibrator
    /sbin/insmod /lib/modules/vibrator.ko

    # ko files for Fm radio
    /sbin/insmod /lib/modules/Si4709_driver.ko

    /sbin/insmod /lib/modules/fsr.ko
    /sbin/insmod /lib/modules/fsr_stl.ko
    /sbin/insmod /lib/modules/rfs_glue.ko
    /sbin/insmod /lib/modules/rfs_fat.ko

# parameter block
    /sbin/insmod /lib/modules/j4fs.ko
    /sbin/insmod /lib/modules/param.ko

# mount modules
    /sbin/insmod /lib/modules/onedram.ko
    /sbin/insmod /lib/modules/svnet.ko
    /sbin/insmod /lib/modules/modemctl.ko
    /sbin/insmod /lib/modules/storage.ko
    /sbin/insmod /lib/modules/bthid.ko
    /sbin/insmod /lib/modules/jbd2.ko
    /sbin/insmod /lib/modules/ext4.ko
}

#first create the symlinks necessary to run
symlink_busybox

#do /sbin/mknods for the devices
create_devices

#/sbin/insmod the things we need
insert_modules

mount_system
mount_sdcard

# debug mode detection
if test -f /sdcard/init/enable-debug ; then
    debug_mode=1
fi

#install fat.format-wrapper.sh
insert_scripts

if test "`/sbin/find $sdcard/Voodoo/ -iname 'disable*lagfix*'`" != "" ; then
    do_rfs
else
    do_lagfix
fi

# clean up and run init
letsgo
