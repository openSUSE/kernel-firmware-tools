#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Install the license files for a single topic
#   % install-licenses.sh [-v] $topic $DIR
#

verbose=:

if [ x"$1" = x"-v" ]; then
    verbose=echo
    shift
fi

topic_choice="$1"
dir="$2"

declare -A topicdefs

while read drv t mods; do
    case "$drv" in
	\#*) continue;;
	*)
	    drv=${drv%:}
	    topicdefs["$drv"]="$t";;
    esac
done < topics.list

list_license () {
    while read drv licenses; do
	test -z "$licenses" && continue
	drv=${drv%:}
	if [ "$topic_choice" != "${topicdefs[$drv]}" ]; then
	    continue
	fi
	for l in $licenses; do
	    echo $l
	done
    done | sort -u | uniq
} < licenses.list

list=$(list_license)
for l in $list; do
    b=$(basename $l)
    $verbose "Copying $l for license"
    install -c -D -m 0644 $l $dir/$b
done

exit 0
