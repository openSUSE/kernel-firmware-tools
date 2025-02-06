#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Strip WHENCE only for the given topic
#
# usage: strip-topic-whence.sh $TOPIC < WHENCE
#

chosen="$1"
list="$2"

declare -A topicdefs

while read drv t mods; do
    case "$drv" in
	\#*) continue;;
	*)
	    drv=${drv%:}
	    topicdefs["$drv"]="$t";;
    esac
done < topics.list

sub="xxx"
while IFS="" read -r l; do
    case "$l" in
	----*)
	    sub=""
	    topic=""
	    continue
	    ;;
	File:\ */README)
	    continue
	    ;;
    esac
    if [ "$topic" = "$chosen" -o "$sub" = "xxx" ]; then
	echo "$l"
	continue
    fi
    case "$l" in
	Driver:*)
	    set -- ${l#*:}
	    sub="$1"
	    sub="${sub%:}"
	    topic="${topicdefs[$sub]}"
	    if [ "$topic" = "$chosen" ]; then
		echo "--------------------------------------------------------------------------"
		echo
		echo "$l"
	    fi
	    ;;
    esac
done

exit 0
