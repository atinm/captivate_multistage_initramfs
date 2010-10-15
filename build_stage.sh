#!/bin/bash
set -x
if [ -z $1 ] ; then
    echo "Usage: $0 number"
    echo "       where number is the stage number (2, 3, ...) for the stage you want to build"
    exit -1
fi
pushd stage$1
find . | cpio -o -H newc > ../stage$1.cpio
popd
lzma -9 -f stage$1.cpio
sha1sum stage$1.cpio.lzma | cut -d' ' -f 1 > stage$(($1-1))/res/signatures/$1.sig
