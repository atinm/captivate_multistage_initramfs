#!/bin/bash
set -x
if [ -z $1 ] ; then
    echo "Usage: $0 <number> <dir> <initramfs>"
    echo "       number is the stage number (2, 3, ...) for the stage you want to build"
    echo "       dir is the directory where the stage files exist"
    exit -1
elif [ -z $2 ] ; then
    echo "Usage: $0 <number> <dir> <initramfs>"
    echo "       number is the stage number (2, 3, ...) for the stage you want to build"
    echo "       dir is the directory where the stage files exist"
    exit -1
elif [ -z $3 ] ; then
    echo "Usage: $0 <number> <dir> <initramfs>"
    echo "       number is the stage number (2, 3, ...) for the stage you want to build"
    echo "       dir is the directory where the stage files exist"
    echo "       initramfs is the directory where the initramfs files exist"
    exit -1
fi

pushd $2
find . | grep -v ".gitignore" | cpio -o -H newc > ../stage$1.cpio
popd
gzip -9 -f stage$1.cpio
sha1sum stage$1.cpio.gz | cut -d' ' -f 1 > $3/res/signatures/$1.sig
