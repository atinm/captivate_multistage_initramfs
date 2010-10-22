#!/system/bin/sh
# fat.format wrapper
# acts normally if not run by samsung init in Ext4 mode
# partition is $7 when called by /sbin/init

# activate debugging logging
export PATH=/system/bin

data_partition="/dev/block/mmcblk0p2"
dbdata_partition="/dev/block/stl10"
sdcard_partition="/dev/block/mmcblk0p1"
sdcard_ext_partition="/dev/block/mmcblk1"
sdcard='/mnt/sdcard'
sdcard_ext='/mnt/sdcard/external_sd'

mount_() {
    case $1 in
	cache)
	    mount -t rfs -o nosuid,nodev,check=no /dev/block/stl11 /cache
	    ;;
	dbdata)
	    mount -t rfs -o nosuid,nodev,check=no $dbdata_partition /dbdata
	    ;;
	data_rfs)
	    mount -t rfs -o nosuid,nodev,check=no $data_partition /data
	    ;;
	data_ext4)
	    mount -t ext4 -o noatime,nodiratime,barrier=0,noauto_da_alloc $data_partition /data
	    ;;
	sdcard)
	    mount -t vfat -o utf8 $sdcard_partition $sdcard
	    ;;
	sdcard_ext)
	    mount -t vfat -o utf8 $sdcard_ext_partition $sdcard_ext
	    ;;
    esac
}

ext4_check() {
    if /sbin/tune2fs -l $data_partition; then
	# we found an ext2/3/4 partition. but is it real ?
	# if the data partition mounts as rfs, it means
	# that this ext4 partition is just lost bits still here
	if mount_ data_rfs; then
	    return 1
	fi
	return 0
    fi
    return 1
}

# back 2 levels
parent_pid=`cut -d" " -f4 /proc/self/stat`
parent_pid=`cut -d" " -f4 /proc/$parent_pid/stat`
parent_name=`cat /proc/$parent_pid/cmdline`

case $parent_name in
    /sbin/init)
	if ext4_check; then
	    echo "Ext4 activated and fat.format called by samsung's init. nothing done"
	    exit 0
	fi
	;;
esac

fat.format.real $*
