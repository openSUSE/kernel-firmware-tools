# KERNEL-FIRMWARE-TOOLS

## General

This package contains various tools and some meta data for creating
and maintaining the stuff for kernel-firmware-* packages on openSUSE
and SUSE distributions.

Each kernel-firmware-* package contains a part of the big
linux-firmware git tree in a compressed format, per each flavor
(''topic'') of the firmware files.

## Files

- `topicdefs`:
  Definitions of each flavor (topic) and description;
  the description is filled into spec file

- `topics.list`:
  Mapping between `WHENCE` entries and topics.
  Each line consists of two or more items.  The first column is
  the first word of the `Driver:` entry line in `WHENCE` to match.
  The second column is the topic/flavor, and the rest columns
  are the module names.  If no module name is provided, the same
  word as the first column is used as the module name.

- `licenses.list`:
  List of license files for each `WHENCE` entry.

- `spdx.list`:
  List of SPDX-form licenses for each `WHENCE` entry.

- `kernel-firmware.spec.in`:
  The spec file template, processed via `make-topic-spec.sh`.

- `.projconf`:
  An optional configuration file for `update-firmware-git.sh`.

Each topic may have metadata in the subdirectory of the topic name
(e.g. `amdgpu`). The following files can be found in each topic
subdirectory.

- `aliases`:
  List of module aliases for each module.
  This is updated by `kft.py`.

- `$TOPIC/topicprovs`:
  Additional Provides and Obsoletes of each topic, processed
  by `make-topic-spec.sh`.

- `$TOPIC/extrawhence*`:
  Additional `WHENCE` entries for the own firmware files.
  You can pass multiple files with this file prefix.
  Listed the additional files to be installed here.
  Those files are also put in $TOPIC directory, where
  `make-topic-spec.sh` will copy automatically.

- `$TOPIC/setup`:
  Additional setup to be executed in the spec file, processed by
  `make-topic-spec.sh`.

The `scripts` subdirectory contains the following scripts.

- `scripts/update-firmware-git.sh`:
  The main script to update the whole stuff.

- `scripts/kft.py`:
  A python helper script, serving for various purposes.

- `make-topic-spec.sh`:
- `extra-whence-setup.sh`:
  Helper scripts for generating a spec file.

- `strip-topic-whence.sh`:
- `install-licenses.sh`:
  Scripts called at building the package.

## Maintenance Works

### Upon the update of linux-firmware.git

On the kernel-firmware-tools directory, set up the linux-firmware git
tree at first. You can either clone / link into the subdirectory
`linux-firmware`, pass via `-C` option, or set up `.projconf`, e.g.:
```
git_root=$HOME/somewhere/linux-git
```

When the Gitea org name is different from the default one
(`kernel-firmware`), specify via `-P` option or put in `.projconf`
file like:
```
obsgitproj=some-orgname
```

For updating the kernel firmware package, simply run the script
`scripts/update-firmware-git.sh`.  Without argument, it runs git-pull
of the given linux-firmware.git repository, and updates the stuff if
needed:
```
% scripts/update-firmware-git.sh -C /somewhere/linux-firmware.git
```

If you want to update only specific topic packages, pass the topic
names to the arguments, e.g.
```
% scripts/update-firmware-git.sh amdgpu platform
```

If you have already updated linux-firmware.git tree, you can pass `-r`
option to skip the git-pull and compare phase.

The `update-firmware-git.sh` script will check the changes of
linux-firmware git, and expands the stuff to the Gitea repo and
package onto `specs/*` subdirectories. For example, after running the
script, it'll have the Gitea repo directories under `specs/*`:
```
% ls specs
kernel-firmware-amdgpu/     kernel-firmware-mellanox/
kernel-firmware-ath10k/     kernel-firmware-mwifiex/
....
```

After preparing all materials, the script will commit the package to
OBS automatically. For keeping without commit to Gitea, pass `-n`
option.

Note that, when `specs/*` directories are present, the script will try
to use those contents instead of the Gitea repo. Update the `specs/*`
appropriately beforehand, or remove all `specs/*` contents beforehand,
so that the latest stuff gets downloaded at running the script.

### Inspection without updates

For inspecting the changes without updating the Gitea repos,
pass `-V` option to `update-firmware-git.sh`. It'll perform git-pull
(unless `-r` option is given), compare the aliases and the updated git
contents, then show what are changed and not.

### New drivers in linux-firmware.git

When the linux-firmware git contains some new drivers that aren't
listed in the topic definitions, `update-firmware-git.sh` will complain
and exit. You'll need to update the topic meta data appropriately and
retry. At least, `topics.list` must be updated to map the new driver
name and the associated topic name, as well as the corresponding
kernel module names.

### Upon the update of kernel binary rpms

When new kernel packages become available, you should update the
module aliases.
To do so, simply run `kft.py update-alias` command with the RPM files
(or expanded directories) to be processed:
```
% scripts/kft.py update-alias /rpms/kernel-default-*.rpm
```

When new aliases have been added, run run `update-firmware-git.sh` after
that. Then it'll update only the modified packages appropriately.

### Adding own firmware binaries

The new packaging relies purely on `WHENCE` file for counting the
installed files. You have to put the new files into each topic
subdirectory and add/update `extrawhence*` file(s) accordingly.

## GIT Repository

https://github.com/openSUSE/kernel-firmware-tools

## License

GPL-v2-or-later

The firmware data included in each topic subdirectory follows the own
licenses mentioned in each extrawhence* files.
