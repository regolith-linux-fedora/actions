#!/bin/bash
# Tests for check-version-match.sh: epoch, revision and tilde cases, tags,
# changelog history order and bad input. Run from anywhere; exits non-zero if
# any case fails.
set -u
here=$(cd "$(dirname "$0")" && pwd)
check=$here/check-version-match.sh
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
fail=0

spec() {  # spec <file> <Version> [<Release>]
    cat >"$work/$1" <<SPEC
Name: example
Version: $2
Release: ${3:-1}%{?dist}
Summary: Example
License: MIT
%description
Example.
SPEC
}
changelog() {  # changelog <file> <debian version> [<older version>]
    {
        printf 'example (%s) unstable; urgency=medium\n\n  * New release.\n\n -- A <a@example.org>  Thu, 15 Oct 2026 00:00:00 +0000\n' "$2"
        [ -n "${3-}" ] && printf '\nexample (%s) unstable; urgency=medium\n\n  * Older.\n\n -- A <a@example.org>  Wed, 14 Oct 2026 00:00:00 +0000\n' "$3"
    } >"$work/$1"
}
histchangelog() {  # histchangelog <file> <newest version>...
    local out=$1; shift
    : >"$work/$out"
    local version
    for version in "$@"; do
        printf 'example (%s) unstable; urgency=medium\n\n  * History.\n\n -- A <a@example.org>  Thu, 15 Oct 2026 00:00:00 +0000\n\n' "$version" >>"$work/$out"
    done
}
expect() {  # expect <status> <description> <args...>
    local want=$1 what=$2; shift 2
    "$check" "$@" >/dev/null 2>&1
    local got=$?
    if [ "$got" -eq "$want" ]; then echo "ok   $what"; else echo "FAIL $what (exit $got, want $want)"; fail=1; fi
}

spec plain.spec 4.10.0
changelog revision 4.10.0-1
changelog epoch 1:4.10.0-1
changelog epoch2 2:4.10.0-0ubuntu3
changelog native 4.10.0
changelog newer 4.10.1-1 4.10.0-1
changelog older-top 4.9.0-1 4.10.0-1
expect 0 "revision dropped: 4.10.0-1 = 4.10.0" "$work/plain.spec" "$work/revision"
expect 0 "epoch dropped: 1:4.10.0-1 = 4.10.0" "$work/plain.spec" "$work/epoch"
expect 0 "epoch and ubuntu revision dropped: 2:4.10.0-0ubuntu3 = 4.10.0" "$work/plain.spec" "$work/epoch2"
expect 0 "native version: 4.10.0 = 4.10.0" "$work/plain.spec" "$work/native"
expect 1 "top entry wins: 4.10.1-1 != 4.10.0" "$work/plain.spec" "$work/newer"
expect 1 "only the top entry counts" "$work/plain.spec" "$work/older-top"

spec epochspec.spec 1.4.10.0
expect 1 "epoch is not folded into the version" "$work/epochspec.spec" "$work/epoch"
spec revspec.spec 4.10.0.1
expect 1 "revision is not folded into the version" "$work/revspec.spec" "$work/revision"

spec tilde.spec '1.0~rc2'
spec dotted.spec 1.0.rc2
spec final.spec 1.0
changelog tilde 1.0~rc2-1
changelog tilde-epoch 3:1.0~rc2-0ubuntu1
expect 0 "tilde kept: 1.0~rc2-1 = 1.0~rc2" "$work/tilde.spec" "$work/tilde"
expect 0 "tilde with epoch: 3:1.0~rc2-0ubuntu1 = 1.0~rc2" "$work/tilde.spec" "$work/tilde-epoch"
expect 1 "tilde is not a dot" "$work/dotted.spec" "$work/tilde"
expect 1 "tilde part is not dropped" "$work/final.spec" "$work/tilde"

cat >"$work/macro.spec" <<'SPEC'
%global ver 4.10.0
Name: example
Version: %{ver}
Release: 2%{?dist}
Summary: Example
License: MIT
%description
Example.
SPEC
expect 0 "Version from a macro" "$work/macro.spec" "$work/revision"

expect 0 "tag matches" "$work/plain.spec" "$work/revision" fedora/v4.10.0-1
expect 0 "tag uses Release without dist" "$work/macro.spec" "$work/revision" fedora/v4.10.0-2
expect 1 "tag with wrong Release" "$work/plain.spec" "$work/revision" fedora/v4.10.0-2
expect 1 "tag without fedora/ prefix" "$work/plain.spec" "$work/revision" v4.10.0-1
expect 1 "tag with Debian version" "$work/plain.spec" "$work/revision" fedora/v4.10.0-1-1
expect 1 "tag fine but version mismatch" "$work/plain.spec" "$work/newer" fedora/v4.10.0-1
expect 1 "empty tag is a mismatch" "$work/plain.spec" "$work/revision" ""

spec order.spec 1.1
histchangelog order 1.1-1 1.0+dfsg-2 1.0+dfsg-1 1.0-1 1.0~rc2-1 1.0~rc1-1
expect 0 "history in order" "$work/order.spec" "$work/order"
spec epochbump.spec 1.5
histchangelog epochbump 1:1.5-1 2.0-1 1.9-1
expect 1 "epoch bump inverts rpm order" "$work/epochbump.spec" "$work/epochbump"
spec epochonly.spec 2.0
histchangelog epochonly 1:2.0-1 2.0-1
expect 0 "epoch-only change keeps upstream" "$work/epochonly.spec" "$work/epochonly"
spec dpkginv.spec 1.0b
histchangelog dpkginv 1.0b-1 1.0+a-1 0.9-1
expect 1 "plus sorts above letters in dpkg" "$work/dpkginv.spec" "$work/dpkginv"
spec pluswins.spec 1.0+b
histchangelog pluswins 1.0+b-1 1.0a-1
expect 0 "plus above letters on both sides" "$work/pluswins.spec" "$work/pluswins"
spec rpminv.spec 1.0+a
histchangelog rpminv 1.0+a-1 1.0b-1
expect 1 "rpm order inverted below dpkg order" "$work/rpminv.spec" "$work/rpminv"
spec belowtop.spec 3.0
histchangelog belowtop 3.0-1 2.0-1 2.1-1 1.0-1
expect 1 "violation below the top pair" "$work/belowtop.spec" "$work/belowtop"
spec tildechain.spec 2.0
histchangelog tildechain 2.0-1 2.0~beta-1 2.0~alpha-1 1.9-1
expect 0 "tilde chain in order" "$work/tildechain.spec" "$work/tildechain"
spec revonly.spec 1.0
histchangelog revonly 1.0-1ubuntu1 1.0-1 1.0-0ubuntu1
expect 0 "revision-only changes keep upstream" "$work/revonly.spec" "$work/revonly"
spec revdown.spec 1.0
histchangelog revdown 1.0-1 1.0-1ubuntu1
expect 1 "revision stepped down" "$work/revdown.spec" "$work/revdown"

expect 2 "no arguments"
expect 2 "missing changelog" "$work/plain.spec" "$work/nonexistent"
expect 2 "missing spec" "$work/nonexistent.spec" "$work/revision"
: >"$work/empty"
expect 2 "empty changelog" "$work/plain.spec" "$work/empty"

exit $fail
