#!/usr/bin/env python3
"""Translate a repo's debian/control relationships into RPM spec tags.

    deb2rpm-deps.py --upstream DIR --map MAP.tsv <debian/control>

Fedora spec style guide §3 (dependencies) applied mechanically, with §2's version
rule (epoch and Debian revision dropped, "~" kept) applied to every version in a
relation and §10's Override Exception form.

DIR holds the Baseline's Upstream packaging as DIR/<repo>/debian/control. Every
binary package there, and every name one of them Provides, is a Regolith name and
is kept as it is. Every other name must be in MAP.tsv ("<debian name>\t<fedora
name>"; an empty Fedora name means Fedora has no such package and the relation is
dropped). An unknown name is an error: never guess a Fedora name.

Output: source-level BuildRequires (with %ifarch / %ifnarch / %bcond check
conditionals), then the tags of the binary package named like the Source, then one
"%package -n <binary>" block (Summary, tags, %description) per other binary. It
parses with rpmspec after a header giving Name (= Source), Version, Release,
Summary and License, followed by a %description for the main package.

Exit status: 0 ok, 1 unknown names, 2 bad usage or unreadable input.
"""
import argparse, re, sys
from collections import defaultdict
from pathlib import Path

FEDORA_ARCHES = ["x86_64", "aarch64", "ppc64le", "s390x", "i686"]
DEB_TO_FEDORA_ARCH = {"amd64": "x86_64", "arm64": "aarch64", "ppc64el": "ppc64le", "s390x": "s390x", "i386": "i686"}
OPS = {">=": ">=", "<=": "<=", "=": "=", ">>": ">", "<<": "<", ">": ">=", "<": "<="}  # bare < and > are Debian's obsolete <= and >=
REL = re.compile(r"^(?P<name>[^\s:(\[<]+)(?::\S+)?\s*(?:\((?P<op><<|<=|>=|>>|=|<|>)\s*(?P<ver>[^)\s]+)\s*\))?"
                 r"\s*(?:\[(?P<arch>[^\]]*)\])?\s*(?P<prof>(?:<[^>]*>\s*)*)$")


def paragraphs(path):
    """deb822 paragraphs as {lowercased field: value}, continuation lines joined."""
    text = "".join(l for l in Path(path).read_text().splitlines(True) if not l.startswith("#"))
    for block in re.split(r"\n\s*\n", text):
        fields, key = {}, None
        for line in block.splitlines():
            if line[:1] in (" ", "\t") and key:
                fields[key] += " " + line.strip()
            elif ":" in line:
                key, _, value = line.partition(":")
                key = key.strip().lower()
                fields[key] = value.strip()
        if fields:
            yield fields


def fedora_version(v):
    """§2: drop the epoch and the Debian revision, keep '~'."""
    v = v.split(":", 1)[1] if ":" in v else v
    return v.rsplit("-", 1)[0] if "-" in v else v


def arch_active(spec, arch):
    """Is a Debian [arch list] true on this Fedora arch?"""
    terms = spec.split()
    neg = all(t.startswith("!") for t in terms)
    def hit(t):
        t = t.lstrip("!")
        if t in ("any", "linux-any", "any-any"):
            return True
        if t.startswith("any-"):
            return DEB_TO_FEDORA_ARCH.get(t[4:]) == arch
        if t.startswith("linux-"):
            return DEB_TO_FEDORA_ARCH.get(t[6:]) == arch
        return DEB_TO_FEDORA_ARCH.get(t) == arch
    return not any(hit(t) for t in terms) if neg else any(hit(t) for t in terms)


def profile_active(spec, with_check):
    """<...> groups are OR'ed, terms inside AND'ed. Only nocheck is honoured (as bcond check)."""
    groups = re.findall(r"<([^>]*)>", spec)
    if not groups:
        return True
    def term(t):
        neg, t = t.startswith("!"), t.lstrip("!")
        on = (not with_check) if t == "nocheck" else False
        return not on if neg else on
    return any(all(term(t) for t in g.split()) for g in groups)


class Translator:
    def __init__(self, upstream, mapping):
        self.regolith, self.binaries = set(), set()
        for control in Path(upstream).glob("*/debian/control"):
            for p in paragraphs(control):
                if "package" in p:
                    self.binaries.add(p["package"])
                    self.regolith.add(p["package"])
                    for item in split_list(p.get("provides", "")):
                        self.regolith.add(REL.match(item).group("name"))
        self.providers = defaultdict(set)
        for control in Path(upstream).glob("*/debian/control"):
            for p in paragraphs(control):
                for item in split_list(p.get("provides", "")):
                    self.providers[REL.match(item).group("name")].add(p.get("package"))
        self.map = mapping
        self.unknown = set()

    def name(self, n):
        """Fedora name, or None when Fedora has no such package. Regolith binaries keep
        their names; any other name the map lists (an Override Exception's name
        included) is written with its Fedora name everywhere."""
        if n in self.binaries:
            return n
        if n in self.map:
            return self.map[n] or None
        if n in self.regolith:
            return n
        self.unknown.add(n)
        return None

    def atom(self, m):
        n = self.name(m.group("name"))
        if n is None:
            return None
        if m.group("op"):
            return f"{n} {OPS[m.group('op')]} {fedora_version(m.group('ver'))}"
        return n

    def clause(self, item, arch=None, with_check=True):
        """One comma-separated Debian relation -> RPM dependency string (or None)."""
        alts = []
        for alt in item.split("|"):
            alt = alt.strip()
            m = REL.match(alt)
            if not m:
                raise SystemExit(f"cannot parse relation {alt!r}")
            if arch and m.group("arch") is not None and not arch_active(m.group("arch"), arch):
                continue
            if not profile_active(m.group("prof") or "", with_check):
                continue
            a = self.atom(m)
            if a and a not in alts:
                alts.append(a)
        if not alts:
            return None
        return alts[0] if len(alts) == 1 else "(" + " or ".join(alts) + ")"


def split_list(value):
    return [i.strip() for i in value.split(",") if i.strip() and not i.strip().startswith("${")]


def build_requires(tr, source):
    items = []
    for f in ("build-depends", "build-depends-arch", "build-depends-indep"):
        items += split_list(source.get(f, ""))
    variants = {}
    for arch in FEDORA_ARCHES:
        for with_check in (True, False):
            variants[arch, with_check] = [c for c in (tr.clause(i, arch, with_check) for i in items) if c]
    order = []
    for v in variants.values():
        order += [c for c in v if c not in order]
    def block(c, cond, on):
        wrap = [cond] if cond else []
        if set(on) != set(FEDORA_ARCHES):
            off = [a for a in FEDORA_ARCHES if a not in on]
            wrap.append(f"%ifarch {' '.join(a for a in FEDORA_ARCHES if a in on)}" if len(on) <= len(off)
                        else f"%ifnarch {' '.join(off)}")
        return wrap + [f"BuildRequires:  {c}"] + ["%endif"] * len(wrap)

    out = []
    for c in order:
        with_on = {a for a in FEDORA_ARCHES if c in variants[a, True]}
        without_on = {a for a in FEDORA_ARCHES if c in variants[a, False]}
        if with_on == without_on:
            out += block(c, None, with_on)
        else:
            if with_on:
                out += block(c, "%if %{with check}", with_on)
            if without_on:
                out += block(c, "%if %{without check}", without_on)
    for c in (tr.clause(i) for i in split_list(source.get("build-conflicts", ""))):
        if c:
            out.append(f"BuildConflicts: {c}")
    return out


def binary_tags(tr, p):
    tags = []
    if p.get("architecture", "").strip() == "all":
        tags.append("BuildArch:      noarch")
    for field, tag in (("pre-depends", "Requires(pre)"), ("depends", "Requires"), ("recommends", "Recommends"),
                       ("suggests", "Suggests"), ("enhances", "Enhances")):
        for c in (tr.clause(i) for i in split_list(p.get(field, ""))):
            if c:
                tags.append(f"{tag + ':':16}{c}")
    me = p["package"]
    provides = {REL.match(i).group("name"): i for i in split_list(p.get("provides", ""))}
    conflicts = {REL.match(i).group("name"): i for i in split_list(p.get("conflicts", "")) + split_list(p.get("breaks", ""))}
    replaces = {REL.match(i).group("name") for i in split_list(p.get("replaces", ""))}
    evr = "%{version}-%{release}"
    for n, item in provides.items():
        m = REL.match(item)
        if n in replaces and n in conflicts and len(tr.providers[n]) == 1 and n in tr.map and tr.map[n]:
            tags.append(f"Provides:       {tr.map[n]} = {evr}")        # Override Exception (§10)
        elif m.group("op"):
            if tr.name(n):
                tags.append(f"Provides:       {tr.name(n)} = {fedora_version(m.group('ver'))}")
        elif n in replaces and n in conflicts and len(tr.providers[n]) == 1:
            tags.append(f"Provides:       {n} = {evr}")                # rename: the old name lives on
        elif tr.name(n):
            tags.append(f"Provides:       {tr.name(n)}")
    for n, item in conflicts.items():
        renamed = n in replaces and n in provides and len(tr.providers[n]) == 1 and not tr.map.get(n) and n not in tr.map
        removed = n in replaces and n not in provides and n not in tr.regolith and n in tr.map and not tr.map[n]
        if renamed or removed:
            tags.append(f"Obsoletes:      {n} < {evr}")                # old Regolith name: replaced on upgrade
            continue
        c = tr.clause(item)
        if c:
            tags.append(f"Conflicts:      {c}")                       # groups, alternatives, Override Exceptions
    return tags


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--upstream", required=True, type=Path)
    ap.add_argument("--map", required=True, type=Path)
    ap.add_argument("control", type=Path)
    try:
        args = ap.parse_args()
    except SystemExit as e:
        sys.exit(2 if e.code else 0)
    try:
        mapping = {}
        for line in args.map.read_text().splitlines():
            if line.strip() and not line.startswith("#"):
                deb, _, fed = line.partition("\t")
                mapping[deb.strip()] = fed.strip()
        paras = list(paragraphs(args.control))
    except OSError as e:
        print(f"deb2rpm-deps: {e}", file=sys.stderr)
        sys.exit(2)
    if not paras or "source" not in paras[0]:
        print("deb2rpm-deps: no Source paragraph", file=sys.stderr)
        sys.exit(2)
    tr = Translator(args.upstream, mapping)
    source, binaries = paras[0], [p for p in paras[1:] if "package" in p]
    out = build_requires(tr, source)
    main_bin = [p for p in binaries if p["package"] == source["source"]]
    for p in main_bin:
        out += binary_tags(tr, p)
    for p in binaries:
        if p["package"] == source["source"]:
            continue
        out += ["", f"%package -n {p['package']}", f"Summary:        {p['package']}"]
        out += binary_tags(tr, p)
        out += [f"%description -n {p['package']}", p["package"]]
    if tr.unknown:
        print("deb2rpm-deps: not Regolith and not in the map: " + " ".join(sorted(tr.unknown)), file=sys.stderr)
        sys.exit(1)
    print("%bcond_without check" if any("%{with check}" in l for l in out) else "", *out, sep="\n")


if __name__ == "__main__":
    main()
