#!/usr/bin/env python3
"""q.py -- millisecond queries over the PS5 14.22 Ghidra index.  Stdlib only.

Usage:
  q.py func <addr>            function containing <addr>: metadata + size + signature
  q.py decomp <addr>          full decompiled C of the function containing <addr>
  q.py xrefs <addr>           every reference to <addr>  (--from = refs out of <addr>)
  q.py writers <addr>         only data-write refs to <addr> (who stores here?)
  q.py callers <addr>         only call refs to <addr>
  q.py string <substr>        strings containing <substr> (case-insensitive), with owner
  q.py funcs <lo> <hi>        all function boundaries overlapping [lo,hi)
  q.py stats                  index manifest
  q.py --json ...             machine-readable output

Addresses accept 0xffffffff804c3150, ffffffff804c3150, 804c3150 (low bits), or decimal.
"""
import bisect
import json
import os
import re
import struct
import sys

IDX = os.environ.get("QIDX") or os.path.dirname(os.path.abspath(__file__))
W = 18  # fixed width of "0x" + 16 hex digits


def hexa(v):
    return "0x%016x" % v


def parse_addr(s):
    s = s.strip().lower().replace("_", "")
    try:
        if s.startswith("0x"):
            return int(s, 16)
        if re.fullmatch(r"[0-9a-f]{6,16}", s):      # bare hex
            return int(s, 16)
        return int(s, 0)
    except ValueError:
        sys.exit("q.py: cannot parse address %r" % s)


# ---------------------------------------------------------------- funcs.tsv
# addr \t end \t size \t name \t sig \t ndecomp
_funcs = None
_faddrs = None


def load_funcs():
    global _funcs, _faddrs
    if _funcs is not None:
        return
    path = os.path.join(IDX, "funcs.tsv")
    rows = []
    with open(path, "r", encoding="utf-8", errors="replace") as fh:
        for line in fh:
            p = line.rstrip("\n").split("\t")
            if len(p) < 6:
                continue
            rows.append((int(p[0], 16), int(p[1], 16), int(p[2]), p[3], p[4], p[5]))
    rows.sort(key=lambda r: r[0])
    _funcs = rows
    _faddrs = [r[0] for r in rows]


def find_func(addr):
    load_funcs()
    i = bisect.bisect_right(_faddrs, addr) - 1
    if i < 0:
        return None
    r = _funcs[i]
    if r[0] <= addr < max(r[1], r[0] + 1):
        return r
    # gap in function bodies (interleaved/scrambled kernel): nearest below
    if addr - r[0] < 0x4000:
        return r
    return None


def func_at_exact(addr):
    load_funcs()
    i = bisect.bisect_left(_faddrs, addr)
    if i < len(_funcs) and _funcs[i][0] == addr:
        return _funcs[i]
    return None


# ---------------------------------------------------------------- xrefs
_xidx = None      # memoryview of fixed-width (to,line) records
_xfh = None


def _load_xindex():
    global _xidx, _xfh
    if _xidx is not None:
        return
    p = os.path.join(IDX, "xrefs.idx")
    _xfh = open(p, "rb", buffering=0)
    data = memoryview(_xfh.read())
    _xidx = data


def xref_count():
    _load_xindex()
    return len(_xidx) // 16


def _rec(i):
    off = i * 16
    return struct.unpack_from("<QQ", _xidx, off)


def _xref_line(lineno):
    # lines are 1-based in the idx; read via a small cache around the target
    global _cache_lo, _cache_lines
    try:
        lo, lines = _cache_lo, _cache_lines
    except NameError:
        lo, lines = -1, []
    if not (lo <= lineno < lo + len(lines)):
        lf = os.path.join(IDX, "xrefs.tsv")
        with open(lf, "rb") as fh:
            fh.seek(0)
            # cheap: read whole file only if small, else seek by index
            lines_all = fh.read().split(b"\n")
        _cache_lines = lines_all
        _cache_lo = 0
        lo = 0
        lines = lines_all
    return lines[lineno - 1].decode("utf-8", "replace") if lineno - 1 < len(lines) else ""


def _xrefs_to(addr):
    _load_xindex()
    n = xref_count()
    lo = 0
    hi = n
    target = addr
    while lo < hi:
        mid = (lo + hi) // 2
        if _rec(mid)[0] < target:
            lo = mid + 1
        else:
            hi = mid
    out = []
    i = lo
    lf = os.path.join(IDX, "xrefs.tsv")
    pending = []
    while i < n and _rec(i)[0] == target:
        pending.append(_rec(i)[1])
        i += 1
    if not pending:
        return out
    # read only the lines we need, in one pass
    want = set(pending)
    with open(lf, "r", encoding="utf-8", errors="replace") as fh:
        for ln, line in enumerate(fh, 1):
            if ln in want:
                p = line.rstrip("\n").split("\t")
                if len(p) >= 4:
                    # file is (to, from, kind, ghidra-type) after the sort swap
                    out.append((int(p[1], 16), int(p[0], 16), p[2], p[3]))
    return out


def _xrefs_from(addr):
    lf = os.path.join(IDX, "xrefs.tsv")
    out = []
    with open(lf, "r", encoding="utf-8", errors="replace") as fh:
        for line in fh:
            p = line.rstrip("\n").split("\t")
            if len(p) >= 4 and int(p[1], 16) == addr:
                out.append((int(p[1], 16), int(p[0], 16), p[2], p[3]))
    return out


# ---------------------------------------------------------------- strings
def search_strings(sub, limit=200):
    sub_l = sub.lower()
    out = []
    path = os.path.join(IDX, "strings.jsonl")
    if not os.path.exists(path):
        path = os.path.join(IDX, "strings.json")
    with open(path, "r", encoding="utf-8", errors="replace") as fh:
        for line in fh:
            if sub_l not in line.lower():
                continue
            line = line.strip().rstrip(",")
            try:
                d = json.loads(line)
            except ValueError:
                continue
            out.append(d)
            if len(out) >= limit:
                break
    return out


# ---------------------------------------------------------------- decomp
def decomp_of(addr):
    f = find_func(addr)
    if f is None:
        return None, None
    for name in (hexa(f[0]), hexa(f[0])[2:], "%x" % f[0]):
        p = os.path.join(IDX, "decomp", name + ".c")
        if os.path.exists(p):
            with open(p, "r", encoding="utf-8", errors="replace") as fh:
                return f, fh.read()
    # fall back to capped C embedded in functions.json
    fj = os.path.join(IDX, "functions.json")
    if os.path.exists(fj):
        with open(fj, "r", encoding="utf-8", errors="replace") as fh:
            for line in fh:
                if '"addr": "' + hexa(f[0]) + '"' in line:
                    try:
                        return f, json.loads(line).get("decomp", "")
                    except ValueError:
                        pass
    return f, ""


def main(argv):
    as_json = False
    if "--json" in argv:
        as_json = True
        argv = [a for a in argv if a != "--json"]
    if len(argv) < 2:
        print(__doc__)
        return 0
    cmd = argv[1].lower()

    if cmd == "stats":
        p = os.path.join(IDX, "manifest.json")
        print(open(p).read() if os.path.exists(p) else "no manifest")
        return 0

    if cmd == "string":
        for d in search_strings(" ".join(argv[2:])):
            fn = d.get("func") or "-"
            print('%s  %-20s  %s' % (d["addr"], fn, d["s"].replace("\n", "\\n")[:300]))
        return 0

    if cmd == "funcs":
        lo, hi = parse_addr(argv[2]), parse_addr(argv[3])
        load_funcs()
        for r in _funcs:
            if r[1] > lo and r[0] < hi:
                print("%s - %s  size=%-5d %s" % (hexa(r[0]), hexa(r[1]), r[2], r[3]))
        return 0

    if len(argv) < 3:
        print(__doc__)
        return 1
    addr = parse_addr(argv[2])

    if cmd == "func":
        f = find_func(addr)
        if not f:
            print("no function contains %s" % hexa(addr))
            return 1
        d = {"addr": hexa(f[0]), "end": hexa(f[1]), "size": f[2], "name": f[3],
             "sig": f[4], "decomp_cached": f[5] == "1"}
        if as_json:
            print(json.dumps(d))
        else:
            print("%s  %s" % (d["addr"], d["name"]))
            print("  range  %s - %s   size %d" % (d["addr"], d["end"], d["size"]))
            print("  sig    %s" % (d["sig"] or "(none)"))
            print("  decomp %s" % ("cached" if d["decomp_cached"] else "not decompiled"))
        return 0

    if cmd == "decomp":
        f, c = decomp_of(addr)
        if not f:
            print("no function contains %s" % hexa(addr))
            return 1
        if not as_json:
            print("// %s  %s  size=%d" % (hexa(f[0]), f[3], f[2]))
        print(c if c else "// (no cached decompilation)")
        return 0

    if cmd in ("xrefs", "writers", "callers"):
        rows = _xrefs_from(addr) if "--from" in argv else _xrefs_to(addr)
        if cmd == "writers":
            rows = [r for r in rows if r[2].endswith("data-write")]
        if cmd == "callers":
            rows = [r for r in rows if r[2].endswith("call")]
        if as_json:
            print(json.dumps([{"from": hexa(r[0]), "to": hexa(r[1]), "type": r[2],
                               "gtype": r[3]} for r in rows]))
            return 0
        if not rows:
            print("(none)")
            return 0
        for r in rows:
            f = find_func(r[0])
            who = ("%s %s" % (hexa(f[0]), f[3])) if f else "-"
            print("%s -> %s  %-16s %-12s   in %s" % (hexa(r[0]), hexa(r[1]), r[2], r[3], who))
        return 0

    print(__doc__)
    return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
