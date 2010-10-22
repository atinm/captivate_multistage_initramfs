#!/system/bin/sh
# fat.format null wrapper
# acts normally if not run by samsung init - but do not allow samsung init
# to munge the partitions!

# back 2 levels
parent_pid=`cut -d" " -f4 /proc/self/stat`
parent_pid=`cut -d" " -f4 /proc/$parent_pid/stat`
parent_name=`cat /proc/$parent_pid/cmdline`

case $parent_name in
    /sbin/init)
	exit 0

	;;
esac

fat.format.real $*
