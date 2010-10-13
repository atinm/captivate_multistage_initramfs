#!/bin/bash
set -x
pushd stage$1
find . | cpio -o -H newc > ../stage$1.cpio
popd
lzma -9 -f stage$1.cpio
sha1sum stage$1.cpio.lzma | cut -d' ' -f 1 > stage$(($1-1))/res/signatures/$1.sig
