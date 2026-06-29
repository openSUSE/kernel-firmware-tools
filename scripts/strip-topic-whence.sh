#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Strip WHENCE only for the given topic
#
# usage: strip-topic-whence.sh [-t DOCDIR] $TOPIC < WHENCE
#   -t = install the documents like README to the given directory
#

if [ x"$1" = x"-t" ]; then
    text_target=$2
    shift 2
fi

chosen="$1"

declare -A topicdefs

while read drv t mods; do
    case "$drv" in
	\#*) continue;;
	*)
	    drv=${drv%:}
	    topicdefs["$drv"]="$t";;
    esac
done < topics.list

install_text () {
    test -n "$text_target" || return
    local l="$1"
    l="${l#File: }"
    test -f $l || return
    local d=$(echo $l | tr / -)
    install -c -m 0644 $l "$text_target/$d"
}

sub="xxx"
while IFS="" read -r l; do
    case "$l" in
	----*)
	    sub=""
	    topic=""
	    continue
	    ;;
    esac
    if [ "$topic" = "$chosen" -o "$sub" = "xxx" ]; then
	case "$l" in
	    File:\ */README*)
		install_text "$l";;
	    File:\ */notice_ath*.txt)
		install_text "$l";;
	    File:\ */notice.txt_wlanmdsp)
		install_text "$l";;
	    File:\ */Notice.txt)
		install_text "$l";;
	    File:\ */.notice)
		install_text "$l";;
	    *)
		test -z "$text_target" && echo "$l" ;;
	esac
	continue
    fi
    case "$l" in
	Driver:*)
	    set -- ${l#*:}
	    sub="$1"
	    sub="${sub%:}"
	    topic="${topicdefs[$sub]}"
	    test -n "$text_target" && continue
	    if [ "$topic" = "$chosen" ]; then
		echo "--------------------------------------------------------------------------"
		echo
		echo "$l"
	    fi
	    ;;
    esac
done

exit 0
