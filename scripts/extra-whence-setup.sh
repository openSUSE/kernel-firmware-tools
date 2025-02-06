#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-or-later

sourcedir="$1"

for f in $sourcedir/extrawhence*; do
    cat "$f" >> WHENCE
    for i in $(grep -E '^(File|RawFile): ' $f | awk '{print $2}'); do
	install -c -D -m 0644 $sourcedir/$(basename "$i") "$i"
    done
done

exit 0
