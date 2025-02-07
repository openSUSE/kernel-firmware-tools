#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Update linux-firmware git repo and OBS kernel-firmware subpackages
#

usage () {
    echo "usage: update-firmware-git.sh [-options] [TOPICS...]"
    echo "  -C DIR: git root directory"
    echo "  -c GIT_ID: git ID to look at (HEAD as default)"
    echo "  -P proj: OBS project name"
    echo "  -r: don't pull linux-firmware git tree"
    echo "  -n: don't commit for OBS"
    echo "  -b: branch packages at updating"
    echo "  -f: force to build even if unchanged"
    echo "  -m: additional changelog text"
    exit 1
}

gitroot=linux-firmware
head=HEAD

test -f .projconf && . .projconf

while getopts C:c:P:rnbfm: opt; do
    case "$opt" in
	C)
	    gitroot="$OPTARG";;
	c)
	    head="$OPTARG";;
	P)
	    obsproj="$OPTARG";;
	r)
	    nopull=1;;
	n)
	    nocommit=1;;
	b)
	    dobranch=1;;
	f)
	    force=1;;
	m)
	    commitmsg="$OPTARG";;
	*)
	    usage;;
    esac
done

shift $(($OPTIND - 1))

if [ ! -d "$gitroot" ]; then
    echo "ERROR: No git root specified for linux-firmware"
    usage
fi

if [ -z "$obsproj" ]; then
    echo "ERROR: Missing OBS project name"
    usage
fi

oscuser=$(osc user)
username=${oscuser%%:*}

if [ -z "$username" ]; then
    echo "No OBS user available"
    exit 1
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

pkgname () {
    if [ "$1" = "ucode-amd" ]; then
	echo "$1"
    else
	echo "kernel-firmware-$1"
    fi
}

if [ -d .git ]; then
    kftpfx=$(git describe --tags HEAD | tr - .)
    kfttar=kernel-firmware-tools-$kftpfx.tar.xz
else
    kfttar=kernel-firmware-tools.tar.xz
fi

update_topic () {
    local topic="$1"
    local git_changed=""
    local alias_changed=""

    name=$(pkgname $topic)
    if [ -n "$dobranch" ]; then
	specdir="specs/home:$username:branches:$obsproj/$name"
    else
	specdir="specs/$obsproj/$name"
    fi
    if [ -f "$specdir/git_id" ]; then
	commit=$(cat "$specdir/git_id")
    else
	commit=$(osc cat "$obsproj/$name/git_id")
    fi

    if [ -f "$topic/aliases" ]; then
        if [ -f "$specdir/aliases" ]; then
	    oldalias=$(md5sum "$specdir/aliases" | awk '{print $1}')
	else
	    oldalias=$(osc cat "$obsproj/$name/aliases" | awk '{print $1}')
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

    if [ ! -d "$specdir" ]; then
	mkdir -p specs
	if [ -n "$dobranch" ]; then
	    (cd specs; osc bco "$obsproj/$name")
	else
	    (cd specs; osc co "$obsproj/$name")
	fi
    fi

    specver=$(scripts/kft.py -C "$gitroot" commit-version $speccommit)

    # add changelog
    rm -f /tmp/COMMIT.$$
    if [ -n "$git_changed" ]; then
	shorthead=${newhead:0:12}
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
	rm -f /tmp/COMMIT.$$
    fi

    # generate the new spec file
    scripts/make-topic-spec.sh "$topic" "$specver" "$speccommit" "$specdir" "$kfttar"

    # create a new firmware tarball
    if [ -n "$git_changed" ]; then
	# wipe old archive
	rm -f "$specdir/$name"-*.tar.xz
	scripts/kft.py -C "$gitroot" archive "$topic" "$newhead" "$specdir"
    fi

    # create kernel-firmware-tools.tar.xz
    rm -f "$specdir"/kernel-firmware-tools*.tar.xz
    scripts/kft.py -C "$gitroot" archive-tools "$specdir/$kfttar"

    (cd "$specdir"; osc addremove)
    if [ -z "$nocommit" ]; then
	(cd "$specdir"; osc commit -m 'update')
    fi
}

if [ -z "$1" ]; then
    set -- $(awk '{print $1}' topicdefs)
fi

for topic in "$@"; do
    update_topic $topic
done
