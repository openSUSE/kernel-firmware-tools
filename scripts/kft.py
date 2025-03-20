#!/usr/bin/python3
# SPDX-License-Identifier: GPL-2.0-or-later
#
# kernel-firmware-tools
#

import os, re, string, hashlib, subprocess, tempfile, fnmatch, sys, pygit2
from datetime import datetime, timezone
from optparse import OptionParser

# list of all topics
topic_list = []
# driver -> topic name mapping
topics = {}
# driver -> module list mapping
modules = {}
# module -> topic list mapping
modmap = {}
# driver -> license files mapping
licenses = {}
# cache of computed hashes
hashes = {}
# module -> aliases list mapping
aliases = {}
# per topic, alias table has been updated?
alias_dirty = {}

def canon_module(name):
    """convert to canonical module name with underscore"""
    return re.sub('-', '_', name)

def read_list(fname, process):
    with open(fname, 'r') as f:
        for t in f.read().split('\n'):
            t.rstrip()
            if t == '':
                continue
            if re.match('#', t):
                continue
            l = t.split()
            key = re.sub(r':$', '', l.pop(0))
            process(key, l)

def read_topics_list():
    """Read topics.list file and store into topics[], modules[] and modmap[]"""
    def process(key, l):
        topic = l.pop(0)
        topics[key] = topic
        if not topic in topic_list:
            topic_list.append(topic)
            topic_list.sort()
        if len(l) > 0:
            modules[key] = []
            for m in l:
                m = canon_module(m)
                modules[key].append(m)
                modmap[m] = topic
        else:
            m = canon_module(key)
            modules[key] = [ m ]
            modmap[m] = topic
    read_list('topics.list', process)

def read_licenses_list():
    """Read licenses.list file and store into liceness[]"""
    def process(key, l):
        licenses[key] = l
    read_list('licenses.list', process)

def walk_whence(tree, topic, process):
    """Walk over WHENCE file and process the files for the topic"""
    cur = None
    for t in tree['WHENCE'].data.decode('utf-8').split('\n'):
        t.rstrip()
        if t == '':
            continue
        if re.match('----', t):
            cur = None
            continue
        elif re.match('Driver:', t):
            driver = re.sub(r'^Driver: *', '', t)
            driver = driver.split()[0]
            driver = re.sub(r':.*$', '', driver)
            cur = topics.get(driver)
            if cur != topic:
                continue
            # update for matching licenses at first
            l = licenses.get(driver)
            if l != None:
                for t in l:
                    if t in tree:
                        process(t)
            continue
        elif cur != topic:
            continue

        # update with each file entry
        if re.match(r'File:', t):
            t = re.sub(r'^File: *', '', t)
        elif re.match(r'RawFile:', t):
            t = re.sub(r'^RawFile: *', '', t)
        else:
            continue
        t = re.sub('"', '', t)
        process(t)

def compute_hash(commit, topic):
    """Compute a hash for the given topic at the given GIT commit"""
    tree = commit.tree
    def process(t):
        hash.update(tree[t].id.raw)
    hash = hashlib.sha1()
    walk_whence(tree, topic, process)
    return hash

def lookup_hash(commit, topic):
    """Look up the hash for the given commit and topic with caching"""
    h = hashes.get(commit.oid)
    if h == None:
        h = compute_hash(commit, topic).digest()
        hashes[commit.oid] = h
    return h

def print_commits(repo, topic, start, end, file, prefix):
    """
    Print git logs for the specific topic between start and end GIT commits
    (ids or tags).
    """

    file = file or sys.stdout;
    start = repo.revparse_single(start)
    end = repo.revparse_single(end)

    # short-cut, just check start and end
    if lookup_hash(end, topic) == lookup_hash(start, topic):
        return

    for commit in repo.walk(end.oid,
                            pygit2.enums.SortMode.TOPOLOGICAL):

        # reached to the end?
        if commit.id == start.id:
            break

        # skip merge commits
        if len(commit.parents) != 1:
            continue

        # check whether any relevant change seen in this commit
        if lookup_hash(commit, topic) != lookup_hash(commit.parents[0], topic):
            t = commit.message.split('\n')[0]
            if prefix:
                print(prefix, t, file=file)
            else:
                print(t, file=file)

def print_changelog(repo, topic, start, end, file=None):
    """
    Print git logs for the specific topic between start and end GIT commits
    (ids or tags).
    Only the subjects are printed, and formatted for RPM changelog style.
    """
    print_commits(repo, topic, start, end, file, '  *')

def print_gitlog(repo, topic, start, end, file=None):
    """
    Print git logs for the specific topic between start and end GIT commits
    (ids or tags).
    Only the subjects are printed, and formatted for GIT commit log style.
    """
    print_commits(repo, topic, start, end, file, '*')

def check_hash_changed(repo, topic, commit1, commit2):
    """Check two git commits"""

    commit1 = repo.revparse_single(commit1)
    commit2 = repo.revparse_single(commit2)
    return lookup_hash(commit1, topic) != lookup_hash(commit2, topic)

def get_file_list(repo, topic, commit):
    """Get the list of files belonging to the given topic at the git commit"""

    paths = []
    def process(t):
        if not t in paths:
            paths.append(t)
    walk_whence(commit.tree, topic, process)
    paths.sort()
    return paths

def commit_time(commit):
    """Get the commit time of the given commit"""
    return datetime.fromtimestamp(float(commit.committer.time), tz=timezone.utc)

def commit_date(commit):
    """Get the commit date string of the given commit in YYYYMMDD form"""
    return commit_time(commit).strftime('%Y%m%d')

def package_name(topic):
    """Package name string for the given topic"""
    if topic == 'ucode-amd':
        return topic
    else:
        return 'kernel-firmware-' + topic

def make_topic_archive(repo, topic, commit, dir='.'):
    """Create a firmware tarball for the topic at the given commit"""
    
    crev = repo.revparse_single(commit)

    date = commit_date(crev)
    name = package_name(topic) + '-' + date

    tarfile = dir + '/' + name + '.tar.xz'
    if os.path.exists(tarfile):
        print(tarfile, 'already present, skipping')
        return

    paths = get_file_list(repo, topic, crev)
    for p in ('WHENCE', 'copy-firmware.sh', 'dedup-firmware.sh',
              'check_whence.py', 'Makefile', 'README.md'):
        paths.append(p)

    print('Creating archive', tarfile)
    f = open(tarfile, 'wb')
    p1 = subprocess.Popen(['git', '-C', options.git_root, 'archive', '--prefix=' + name + '/', commit, '--'] + paths,
                          stdout=subprocess.PIPE)
    p2 = subprocess.Popen(['xz'], stdin=p1.stdout, stdout=f)
    p2.communicate()

def make_kf_tools(path):
    """Create a kernel-firmware-tools tarball"""

    files_to_pack = [ 'README-kft.md', 'scripts', 'topicdefs', 'topics.list',
                      'licenses.list', 'spdx.list', 'rpmlintrc',
                      'kernel-firmware.spec.in' ]

    if os.path.isdir('common'):
        files_to_pack.append('common')

    if os.path.exists('.git'):
        f = open(path, 'wb')
        p1 = subprocess.Popen(['git', 'archive', 'HEAD', '--'] + files_to_pack,
                              stdout=subprocess.PIPE)
        p2 = subprocess.Popen(['xz'], stdin=p1.stdout, stdout=f)
    else:
        os.system('tar cvfJ ' + path + ' ' + ' '.join(files_to_pack))

def read_topic_aliases(topic):
    """Read aliases files for the given topic"""
    path = topic + '/aliases'
    if not os.path.isfile(path):
        return
    with open(path, 'r') as f:
        for t in f.read().split('\n'):
            t.rstrip()
            if t == '':
                continue
            l = t.split()
            module = re.sub(r':$', '', l.pop(0))
            if aliases.get(module) == None:
                aliases[module] = []
            aliases[module].append(l.pop(0))

def write_topic_aliases(topic):
    """Write aliases files for the given topic"""
    if not os.path.isdir(topic):
        os.mkdir(topic)
    with open(topic + '/aliases', 'w') as f:
        for m in sorted(aliases.keys()):
            if modmap.get(m) != topic:
                continue
            for p in sorted(aliases[m]):
                f.write(m + ': ' + p + '\n')

def kernel_binary_rpm(file):
    """Check whether the file is a proper kernel binary rpm file"""
    file = os.path.basename(file)
    if not fnmatch.fnmatch(file, 'kernel*.rpm'):
        return False
    blacklist = ( '*.noarch.rpm', '*.src.rpm', '*.nosrc.rpm',
                  '*-debuginfo*', '*-debugsource*',
                  '*-devel-*', '*-hmac-*',
                  'kernel-docs*', 'kernel-syms-*' )
    for p in blacklist:
        if fnmatch.fnmatch(file, p):
            return False
    return True

def modinfo(ko, attr):
    """get the modinfo output for the attr"""
    return subprocess.check_output(['/usr/sbin/modinfo', '-F', attr, ko]).decode('utf-8').split('\n')

def add_matching_aliases(ko, name):
    """Append to aliases list if the module is matching to the topics"""
    if modmap.get(name) != None:
        for f in modinfo(ko, 'alias'):
            if f == '':
                continue
            if re.match(r'^acpi', f):
                f = re.sub(r'([^:]*):([^:]*)$', r'\1%3A\2', f)
            if aliases.get(name) == None:
                aliases[name] = []
            if not f in aliases[name]:
                aliases[name].append(f)
                alias_dirty[modmap[name]] = True
                print('adding alias', name, f)

def scan_firmware_dir(dir):
    for root, dirs, files in os.walk(dir):
        for p in files:
            ko = os.path.join(root, p)
            name = re.sub(r'\.xz$', '', p)
            name = re.sub(r'\.zst$', '', p)
            if not fnmatch.fnmatch(name, '*.ko'):
                continue
            name = re.sub(r'\.ko$', '', name)
            name = canon_module(name)
            add_matching_aliases(ko, name)

def scan_firmware_rpm(rpm):
    if not kernel_binary_rpm(rpm):
        return
    with tempfile.TemporaryDirectory() as dir:
        subprocess.call('rpm2cpio ' + rpm + ' | cpio -i --make-directories -D ' + dir,
                        shell=True)
        scan_firmware_dir(dir)

def update_aliases(arg):
    """Scan the given RPM or directory and update aliases"""
    if os.path.isdir(arg):
        scan_firmware_dir(arg)
    else:
        scan_firmware_rpm(arg)

def check_whence(repo, commit):
    """Check WHENCE file and verify whether it contains unknown drivers"""
    commit = repo.revparse_single(commit)
    cur = None
    rc = 0
    for t in commit.tree['WHENCE'].data.decode('utf-8').split('\n'):
        t.rstrip()
        if t == '':
            continue
        if re.match('----', t):
            cur = None
            continue
        elif re.match('Driver:', t):
            driver = re.sub(r'^Driver: *', '', t)
            driver = driver.split()[0]
            driver = re.sub(r':.*$', '', driver)
            if topics.get(driver) == None:
                print('An unknown driver found in WHENCE:', driver)
                rc = 1
    exit(rc)

if __name__ == '__main__':

    usage = """usage: %prog [options] COMMAND [ARGS...]

* Check whether any changes are found between two GIT commits for the topic:
  % %prog changed $TOPIC $GIT_ID1 $GIT_ID2
  Exit 0 when changed, 1 when unchanged

* Check whether WHENCE contains unknown drivers:
  % %prog check-whence $GIT_ID
  Unknown drivers are printed, and exit 1 if found

* Print RPM changelog entry for the topic between two GIT commits:
  % %prog changelog $TOPIC $OLD_ID $NEW_ID

* Print GIT commit log entry for the topic between two GIT commits:
  % %prog gitlog $TOPIC $OLD_ID $NEW_ID

* Print a version number in YYYYMMDD format of the given GIT commit:
  % %prog commit-version $GIT_ID

* Make a tarball of selected firmware files for the topic:
  % %prog archive $TOPIC $GIT_ID [$DIRECTORY]
  When $DIRECTORY is given, it's stored on that directory.

* Make a tarball of kernel-firmware-tools:
  % %prog archive-tools [DIRECTORY]
  When $DIRECTORY is given, it's stored on that directory.

* Update the module aliases from RPM or directory:
  % %prog update-alias RPM | DIRECTORY...
"""

    parser = OptionParser(usage=usage)
    parser.add_option("-C", "--firmware-git", action="store",
                      dest="git_root", type="string",
                      default="linux-firmware",
                      help="linux-firmware GIT repository")
    (options, args) = parser.parse_args()

    def error():
        parser.print_usage()
        exit(1)

    if len(args) < 1:
        error()

    cmd = args.pop(0)
    repo = pygit2.Repository(options.git_root)

    read_topics_list()
    read_licenses_list()

    if cmd == "changed":
        if len(args) < 3:
            error()
        if check_hash_changed(repo, args[0], args[1], args[2]):
            exit(0)
        else:
            exit(1)

    elif cmd == "check-whence":
        commit = 'HEAD'
        if len(args) > 0:
            commit = args[0]
        check_whence(repo, commit)

    elif cmd == "changelog":
        if len(args) < 3:
            error()
        print_changelog(repo, args[0], args[1], args[2])

    elif cmd == "gitlog":
        if len(args) < 3:
            error()
        print_gitlog(repo, args[0], args[1], args[2])

    elif cmd == "commit-version":
        if len(args) < 1:
            error()
        print(commit_date(repo.revparse_single(args[0])))

    elif cmd == "archive":
        if len(args) < 2:
            error()
        dir = '.'
        if len(args) > 2:
            dir = args[2]
        make_topic_archive(repo, args[0], args[1], dir)

    elif cmd == "archive-tools":
        dir = 'kernel-firmware-tools.tar.xz'
        if len(args) > 0:
            dir = args[0]
        make_kf_tools(dir)

    elif cmd == "update-alias":
        if len(args) == 0:
            print('ERROR: Specify RPMs or directories to scan for aliases')
            error()
        for topic in topic_list:
            read_topic_aliases(topic)
        for arg in args:
            update_aliases(arg)
        if len(alias_dirty) > 0:
            for topic in sorted(alias_dirty.keys()):
                print('Updating aliases for', topic)
                write_topic_aliases(topic)

    else:
        print('Invalid command', cmd)
        error()
