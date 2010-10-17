#!/bin/sh
set -x
status=0
data_archive='/sdcard/rfs_user-data.tar'
alias mount_data_ext4="mount -t ext4 -o noatime,nodiratime /dev/block/mmcblk0p2 /data"
alias mount_data_rfs="mount -t rfs -o nosuid,nodev,check=no /dev/block/mmcblk0p2 /data"
alias mount_sdcard="mount -t vfat -o utf8 /dev/block/mmcblk0p1 /sdcard"
alias mount_cache="mount -t rfs -o nosuid,nodev,check=no /dev/block/stl11 /cache"
alias mount_dbdata="mount -t rfs -o nosuid,nodev,check=no /dev/block/stl10 /dbdata"
alias make_backup="tar cf $data_archive /data /dbdata"

log() {
    log="stage2.sh: $1"
    echo -e "\n  ###  $log\n" >> /stage2.log
    echo `date '+%Y-%m-%d %H:%M:%S'` $log >> /stage2.log
}

check_free() {
    # read free space on internal SD
    target_free=`df /sdcard | awk '/\/sdcard$/ {print $2}'`
    # read space used by data we need to save
    space_needed=$((`df /data | awk '/ \/data$/ {print $3}'` \
	+ `df /dbdata | awk '/ \/dbdata$/ {print $3}'`))
    log "free space : $target_free"
    log "space needed : $space_needed"
    return `test "$target_free" -ge "$space_needed"`
}

restore_backup() {
    # clean any previous false dbdata partition
    rm -rf /dbdata/*
    # extract from the tar backup,
    # with dirty workaround to fix battery level inaccuracy
    # then remove the backup tarball if everything went smooth
    tar xf $data_archive --exclude=/data/system/batterystats.bin \
	&& rm $data_archive
}

ext4_check() {
    log "ext4 partition detection"
    if dumpe2fs -h /dev/block/mmcblk0p2; then
	log "ext4 partition detected"
	return 0
    fi

    log "no ext4 partition detected"
    return 1
}

do_lagfix()
{
    if ! ext4_check ; then
	log "no ext4 partition detected"
	
	# mount ressources we need
	log "mount resources to backup"
	mount_data_rfs
	mount_dbdata
	mount_sdcard

	# check if there is enough free space for migration or cancel
	# and boot
	if ! check_free; then
		log "not enough space to migrate from rfs to ext4"
		mount_data_rfs
		umount /dbdata
		status=1
		return $status
	fi

	# run the backup operation
	log "run the backup operation"
	make_backup
	
	# umount mmcblk0 ressources
	umount /sdcard
	umount /data
	umount /dbdata

	# build the ext4 filesystem
	log "build the ext4 filesystem"
	
	# (empty) /etc/mtab is required for this mkfs.ext4
	mkfs.ext4 -F -O sparse_super /dev/block/mmcblk0p2
	# force check the filesystem after 100 mounts or 100 days
	tune2fs -c 100 -i 100d -m 0 /dev/block/mmcblk0p2
		
	mount_data_ext4
	mount_dbdata

	mount_sdcard

	# restore the data archived
	restore_backup

	# clean all these mounts but leave /data mounted
	log "umount what will be re-mounted by Samsung's Android init"
	umount /dbdata
	umount /sdcard

    else
	# seems that we have a ext4 partition ;) just mount it
	log "protected ext4 detected, mounting ext4 /data !"
	e2fsck -p /dev/block/mmcblk0p2

	#leave /data mounted
	mount_data_ext4
    fi

    status=0
    return $status
}

insert_modules() {
    # insert the ext4 modules
    insmod /lib/modules/jbd2.ko
    insmod /lib/modules/ext4.ko
}

insert_modules

echo $PATH
mount
ls -l /dev/block
ls -l /usr/sbin
ls -l /usr/lib
do_lagfix

rm -r /etc

exit $status
