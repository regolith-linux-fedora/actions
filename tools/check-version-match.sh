#!/bin/bash
# Check that an RPM spec's Version matches debian/changelog (Fedora spec style
# guide, "Version, Release and tags"), that the changelog history keeps its
# order under the Debian-to-RPM mapping, and optionally that a tag matches the
# spec's Version and Release.
#
#   check-version-match.sh <spec> <debian/changelog> [<tag>]
#
# The spec's Version must equal the upstream part of the top changelog entry:
# the epoch ("1:") and the Debian revision (the last "-...") removed, "~" kept.
# Every pair of consecutive entries must be ordered too: the newer entry
# strictly newer by dpkg's comparison, and, when the upstream parts differ,
# strictly higher by rpmvercmp. With <tag>, it must be exactly
# fedora/v<Version>-<Release>, Release without the dist tag.
# Needs rpmspec (rpm-build) and python3 with the rpm module.
#
# Exit status: 0 match, 1 mismatch, 2 bad usage or unreadable input.
set -uo pipefail

usage() { echo "usage: $0 <spec> <debian/changelog> [<tag>]" >&2; exit 2; }
die() { echo "check-version-match: $*" >&2; exit 2; }

[ $# -eq 2 ] || [ $# -eq 3 ] || usage
spec=$1 changelog=$2 tag=${3-}
[ -r "$spec" ] || die "cannot read spec $spec"
[ -r "$changelog" ] || die "cannot read changelog $changelog"
command -v rpmspec >/dev/null || die "rpmspec not found (install rpm-build)"
command -v python3 >/dev/null || die "python3 not found"

# rpmspec expands macros, so Version: %{ver} works. The first line is the
# source package even when the spec has subpackages.
evr=$(rpmspec -q --srpm --undefine=dist --qf '%{VERSION} %{RELEASE}\n' "$spec" 2>/dev/null | head -n1)
read -r spec_version spec_release <<<"$evr"
[ -n "${spec_version:-}" ] && [ -n "${spec_release:-}" ] || die "cannot parse Version/Release from $spec"

# Top entry: "<source> (<version>) <distributions>; urgency=..."
deb_version=$(sed -n -E '/^[^[:space:]]/{s/^[^[:space:]]+ \(([^)]+)\).*/\1/p;q}' "$changelog")
[ -n "$deb_version" ] || die "cannot parse the top entry of $changelog"
upstream=$deb_version
case $upstream in *:*) upstream=${upstream#*:} ;; esac
case $upstream in *-*) upstream=${upstream%-*} ;; esac

status=0
if [ "$spec_version" != "$upstream" ]; then
    echo "MISMATCH: $spec Version is '$spec_version', $changelog says '$deb_version' (upstream part '$upstream')" >&2
    status=1
fi
if [ $# -eq 3 ]; then
    want="fedora/v$spec_version-$spec_release"
    if [ "$tag" != "$want" ]; then
        echo "MISMATCH: tag is '$tag', expected '$want'" >&2
        status=1
    fi
fi
# History order: every consecutive pair, newest above oldest. The upper entry
# must be strictly newer by dpkg's version ordering, and, when the upstream
# parts differ, strictly higher by rpmvercmp. The image has no dpkg tooling,
# so the Debian side is ported below (Debian Policy 5.6.12); the RPM side uses
# the system rpm module.
python3 - "$changelog" <<'HISTORY_EOF' >&2
import re
import sys

try:
    import rpm
except ImportError:
    print('check-version-match: rpm module not found (install python3-rpm)')
    raise SystemExit(2)


def _order(c):
    if c == '~':
        return -1
    if c == '':
        return 0
    o = ord(c)
    if 48 <= o <= 57:
        return 0
    if 65 <= o <= 90 or 97 <= o <= 122:
        return o
    return o + 256


def _verrevcmp(a, b):
    i = j = 0
    la, lb = len(a), len(b)
    while i < la or j < lb:
        while (i < la and not ('0' <= a[i] <= '9')) or \
                (j < lb and not ('0' <= b[j] <= '9')):
            ac = _order(a[i] if i < la else '')
            bc = _order(b[j] if j < lb else '')
            if ac != bc:
                return -1 if ac < bc else 1
            i += 1
            j += 1
        while i < la and a[i] == '0':
            i += 1
        while j < lb and b[j] == '0':
            j += 1
        i0, j0 = i, j
        while i < la and '0' <= a[i] <= '9':
            i += 1
        while j < lb and '0' <= b[j] <= '9':
            j += 1
        if (i - i0) != (j - j0):
            return -1 if (i - i0) < (j - j0) else 1
        for k in range(i - i0):
            if a[i0 + k] != b[j0 + k]:
                return -1 if a[i0 + k] < b[j0 + k] else 1
    return 0


def _split(version):
    epoch = 0
    rest = version
    if ':' in rest:
        part, rest = rest.split(':', 1)
        if not part.isdigit():
            raise ValueError('bad epoch in %r' % (version,))
        epoch = int(part)
    if '-' in rest:
        upstream, revision = rest.rsplit('-', 1)
    else:
        upstream, revision = rest, ''
    return epoch, upstream, revision


def _dpkg_cmp(a, b):
    ea, ua, ra = _split(a)
    eb, ub, rb = _split(b)
    if ea != eb:
        return -1 if ea < eb else 1
    result = _verrevcmp(ua, ub)
    return result if result else _verrevcmp(ra, rb)


try:
    with open(sys.argv[1], encoding='ascii') as handle:
        changelog_lines = handle.read().splitlines()
except (OSError, UnicodeError) as exc:
    print('check-version-match: cannot read changelog: %s' % (exc,))
    raise SystemExit(2)

entries = []
for _line in changelog_lines:
    _match = re.match(r'^[^\s]+\s+\(([^)]+)\)', _line)
    if _match:
        entries.append(_match.group(1))

try:
    for _newer, _older in zip(entries, entries[1:]):
        if _dpkg_cmp(_newer, _older) <= 0:
            print("MISMATCH: '%s' is not newer than '%s' (Debian order)" % (_newer, _older))
            raise SystemExit(1)
        _new_up = _split(_newer)[1]
        _old_up = _split(_older)[1]
        if _new_up != _old_up:
            try:
                _higher = rpm.labelCompare(('0', _new_up, '1'), ('0', _old_up, '1'))
            except Exception as exc:
                print('check-version-match: rpm comparison failed: %s' % (exc,))
                raise SystemExit(2)
            if _higher != 1:
                print("MISMATCH: upstream '%s' does not sort above '%s' (RPM order)" % (_new_up, _old_up))
                raise SystemExit(1)
except ValueError as exc:
    print('check-version-match: cannot parse changelog version: %s' % (exc,))
    raise SystemExit(2)
HISTORY_EOF
hist_rc=$?
if [ $hist_rc -eq 2 ]; then
    exit 2
elif [ $hist_rc -ne 0 ]; then
    status=1
fi
[ $status -eq 0 ] && echo "OK: Version $spec_version, Release $spec_release${tag:+, tag $tag}"
exit $status
