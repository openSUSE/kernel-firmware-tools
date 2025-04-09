#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Update linux-firmware git repo and OBS kernel-firmware subpackages
#

usage () {
    echo "usage: update-firmware-git.sh [-options] [TOPICS...]"
    echo "  -C DIR: git root directory"
    echo "  -c GIT_ID: git ID to look at ('HEAD' as default)"
    echo "  -P org: gitea repo org name ('kernel-firmware' as default)"
    echo "  -V: only verify the changes, not updating"
    echo "  -r: don't pull linux-firmware git tree"
    echo "  -n: don't commit for gitea repo"
    echo "  -f: force to build even if unchanged"
    echo "  -m: additional changelog text"
    exit 1
}

gitroot=linux-firmware
head=HEAD
srcoo=src.opensuse.org
obsgitproj=kernel-firmware
obsgitbranch=main

test -f .projconf && . .projconf

while getopts C:c:P:Vrnfm: opt; do
    case "$opt" in
	C)
	    gitroot="$OPTARG";;
	c)
	    head="$OPTARG";;
	P)
	    obsgitproj="$OPTARG";;
	V)
	    onlyverify=1;;
	r)
	    nopull=1;;
	n)
	    nocommit=1;;
	f)
	    force=1;;
	m)
	    commitmsg="$OPTARG";;
	*)
	    usage;;
    esac
done

shift $(($OPTIND - 1))

if [ ! -d .git ]; then
    echo "ERROR: Must run on kernel-firwmare-tools GIT repo"
    exit 1
fi

if [ ! -d "$gitroot" ]; then
    echo "ERROR: No git root specified for linux-firmware"
    usage
fi

if [ -n "$nopull" ]; then
    newhead=$(git -C "$gitroot" rev-parse "$head")
    echo "GIT hash: $newhead"
else
    oldhead=$(git -C "$gitroot" rev-parse HEAD)
    git -C "$gitroot" pull
    newhead=$(git -C "$gitroot" rev-parse "$head")
    if [ "$oldhead" = "$newhead" -a -z "$force" ]; then
	echo "Nothing changed, exiting"
	exit
    fi
    echo "GIT hash: $oldhead => $newhead"
fi

if ! scripts/kft.py -C "$gitroot" check-whence "$head"; then
    echo "Please update topics data appropriately"
    test -z "$force" && exit 1
fi

cleanup () {
    rm -f /tmp/COMMIT.$$
    exit 1
}
trap cleanup 0

pkgname () {
    if [ "$1" = "ucode-amd" ]; then
	echo "$1"
    else
	echo "kernel-firmware-$1"
    fi
}

get_src () {
    curl -s "https://$srcoo/$obsgitproj/$1/raw/branch/$obsgitbranch/$2"
}

kftver=$(git describe --tags scripts | tr - .)

update_topic () {
    local topic="$1"
    local git_changed=""
    local alias_changed=""

    name=$(pkgname $topic)
    specdir="specs/$name"
    if [ -f "$specdir/git_id" ]; then
	commit=$(cat "$specdir/git_id")
    else
	commit=$(get_src $name git_id)
    fi

    if [ -f "$topic/aliases" ]; then
        if [ -f "$specdir/aliases" ]; then
	    oldalias=$(md5sum "$specdir/aliases" | awk '{print $1}')
	else
	    oldalias=$(get_src $name aliases | md5sum | awk '{print $1}')
	fi

	newalias=$(md5sum "$topic/aliases" | awk '{print $1}')
	test "$oldalias" != "$newalias" && alias_changed=1
    fi

    if [ "$commit" = "$newhead" -a -z "$alias_changed" ]; then
	if [ -z "$force" ]; then
	    echo "Nothing changed for $name, skipping"
	    return
	fi
    fi

    scripts/kft.py -C "$gitroot" changed $topic $commit $newhead
    test $? -eq 0 && git_changed=1

    if [ -z "$git_changed" -a -z "$alias_changed" ]; then
	if [ -z "$force" ]; then
	    echo "No modification since the previous for $name, skipping"
	    return
	fi
    fi

    if [ -n "$git_changed" ]; then
	# update the commit
	speccommit=$newhead
    else
	# keep the old commit
	speccommit=$commit
    fi
    shorthead=${newhead:0:12}

    specver=$(scripts/kft.py -C "$gitroot" commit-version $speccommit)

    if [ -n "$onlyverify" ]; then
	if [ -n "$git_changed" ]; then
	    echo "To be updated version $specver (git commit $shorthead) for $topic:"
	    scripts/kft.py -C "$gitroot" changelog $topic $commit $newhead
	fi
	if [ -n "$alias_changed" ]; then
	    echo "Aliases updated for $topic"
	fi
	return
    fi

    if [ ! -d "$specdir" ]; then
	mkdir -p specs
	(cd specs; git clone -b $obsgitbranch "gitea@$srcoo:$obsgitproj/$name")
    fi

    # add changelog
    rm -f /tmp/COMMIT.$$
    if [ -n "$git_changed" ]; then
	echo "- Update to version $specver (git commit $shorthead):" >> /tmp/COMMIT.$$
	scripts/kft.py -C "$gitroot" changelog $topic $commit $newhead >> /tmp/COMMIT.$$
    fi
    if [ -n "$alias_changed" ]; then
	echo "Aliases updated for $topic"
	echo '- Update aliases' >> /tmp/COMMIT.$$
    fi
    if [ -n "$commitmsg" ]; then
	echo "- $commitmsg" >> /tmp/COMMIT.$$
    fi
    if [ -f /tmp/COMMIT.$$ ]; then
	(cd "$specdir"; osc vc -F /tmp/COMMIT.$$)
    fi

    # generate the new spec file
    scripts/make-topic-spec.sh "$topic" "$specver" "$speccommit" "$specdir" "$kftver"

    # create a new firmware tarball
    if [ -n "$git_changed" ]; then
	# wipe old archive
	rm -f "$specdir/$name"-*.tar.xz
	scripts/kft.py -C "$gitroot" archive "$topic" "$newhead" "$specdir"
    fi

    # create kernel-firmware-tools-*.tar.gz
    rm -f "$specdir"/kernel-firmware-tools*.tar.*
    scripts/kft.py -C "$gitroot" archive-tools "$specdir"

    git -C "$specdir" add .
    if [ -z "$nocommit" ]; then
	rm -f /tmp/COMMIT.$$
	if [ -n "$git_changed" ]; then
	    echo "Update to version $specver (git commit $shorthead)" >> /tmp/COMMIT.$$
	    echo >> /tmp/COMMIT.$$
	    scripts/kft.py -C "$gitroot" gitlog $topic $commit $newhead >> /tmp/COMMIT.$$
	fi
	if [ -n "$alias_changed" ]; then
	    if [ -n "$git_changed" ]; then
		echo >> /tmp/COMMIT.$$
	    fi
	    echo "Aliases updated for $topic" >> /tmp/COMMIT.$$
	fi
	if [ -n "$commitmsg" ]; then
	    if [ -n "$git_changed" -o -n "$alias_changed" ]; then
		echo >> /tmp/COMMIT.$$
	    fi
	    echo "$commitmsg" >> /tmp/COMMIT.$$
	fi
	git -C "$specdir" commit -F /tmp/COMMIT.$$
    fi
}

if [ -z "$1" ]; then
    set -- $(awk '{print $1}' topicdefs)
fi

for topic in "$@"; do
    update_topic $topic
done
