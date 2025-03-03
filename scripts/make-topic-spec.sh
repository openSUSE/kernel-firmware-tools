#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-or-later
#
# usage: make-topic-spec.sh TOPIC VERSION GIT_ID DIRECTORY [KFTTAR]
#   e.g. make-topic-spec.sh i915 20250131 1234acde... some/directory
#
# Generate a spec file for the given topic.
#
# The resultant spec file is created on $DIRECTORY/$PACKAGE.spec.
# The topic-specific files are copiedd to $DIRECTORY, too.
#

export LANG=C
topic="$1"
version="$2"
git_id="$3"
specdir="$4"
kfttar="$5"
test -z "$kfttar" && kfttar=kernel-firmware-tools.tar.xz

if [ ! -d "$specdir" ]; then
    echo "No valid topic directory given"
    exit 1
fi

case "$topic" in
    ucode-amd)
	pkgname=$topic;;
    *)
	pkgname=kernel-firmware-$topic;;
esac

declare -A topicdefs

while read drv t mods; do
    case "$drv" in
	\#*) continue;;
	*)
	    drv=${drv%:}
	    topicdefs["$drv"]="$t";;
    esac
done < topics.list

append_to_licenses () {
    local j
    for j in $licenses; do
	test "$j" == "$1" && return
    done
    licenses="$licenses AND $l"
}

get_spdx () {
    licenses="GPL-2.0-or-later AND SUSE-Firmware"
    while read drv args; do
	drv=${drv%:}
	test "${topicdefs[$drv]}" = "$topic" || continue
	for l in $args; do
	    append_to_licenses $l
	done
    done < spdx.list
    echo "License:        $licenses"
}

desc=$(grep '^'"$topic"'[[:space:]]' topicdefs | sed -e's/^[a-zA-Z0-9-]*[[:space:]]*//')

cp rpmlintrc $specdir/$pkgname-rpmlintrc
echo "$git_id" > $specdir/git_id

sed -e"s/@@PKGNAME@@/$pkgname/g" \
    -e"s/@@VERSION@@/$version/g" \
    -e"s/@@TOPIC@@/$topic/g" \
    -e"s/@@GIT_ID@@/$git_id/g" \
    -e"s/@@KFTTAR@@/$kfttar/g" \
    kernel-firmware.spec.in | \
    while read line; do
    if [ "$line" = "@@SUMMARY@@" ]; then
	echo "Summary:        Kernel firmware files for $desc"
	continue
    fi
    if [ "$line" = "@@LICENSE@@" ]; then
	get_spdx
	continue
    fi
    if [ "$line" = "@@EXTRASRCS@@" ]; then
	p=10
	n=10
	for f in common/*; do
	    test -f "$f" || break
	    cp $f $specdir/
	    case $f in
		*.patch)
		    echo "Patch$p:        $b"
		    (( p++ ))
		    ;;
		*)
		    echo "Source$p:       $b"
		    (( n++ ))
		    ;;
	    esac
	done
	for f in $topic/*; do
	    test -f "$f" || break
	    b=$(basename "$f")
	    echo "Source$n:       $b"
	    cp $f $specdir/
	    (( n++ ))
	done
	continue
    fi
    if [ "$line" = "@@TOPICPROVS@@" ]; then
	if [ -f $topic/topicprovs ]; then
	    cat $topic/topicprovs
	fi
	if [ -f $topic/aliases ]; then
	    sed -e's/^.*: \(.*\)$/Supplements:    modalias(\1)/g' $topic/aliases | sort -u
	fi
	echo
	echo "%description"
	echo "This package contains kernel firmware files for $desc."
	echo
	continue
    fi

    if [ "$line" = "@@SETUP@@" ]; then
	if [ -f $topic/setup ]; then
	    cat $topic/setup
	elif compgen -G "$topic/"'extrawhence*' > /dev/null; then
	    echo "scripts/extra-whence-setup.sh %{_sourcedir}"
	fi
	continue
    fi

    if [ "$line" = "@@POST@@" ]; then
	if [ -f $topic/post ]; then
	    cat $topic/post
	    continue
	fi
	echo "%post"
	echo "%{?regenerate_initrd_post}"
	echo
	echo "%postun"
	echo "%{?regenerate_initrd_post}"
	echo
	echo "%posttrans"
	echo "%{?regenerate_initrd_posttrans}"
	continue
    fi

    echo "$line"
done > $specdir/$pkgname.spec

exit 0
