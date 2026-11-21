#!/usr/bin/env python3
"""build_index.py -- assemble the PS5 14.22 Ghidra export into the queryable index.

Input  (Ghidra staging dir, default /tmp/opencode/idx):
  functions_meta.jsonl, decomp.jsonl, decomp/<addr>.c, xrefs.tsv, strings.jsonl
Output (this directory):
  functions.json  xrefs.json  strings.json  funcs.tsv  xrefs.tsv  xrefs.idx
  manifest.json

Usage: build_index.py [staging_dir] [out_dir]
"""
import json
import os
import struct
import sys
import re
import time

STAGE = sys.argv[1] if len(sys.argv) > 1 else "/tmp/opencode/idx"
OUT = sys.argv[2] if len(sys.argv) > 2 else os.path.dirname(os.path.abspath(__file__))
DECOMP_CAP = 3000          # chars of C embedded in functions.json
W = 18
ADDR_RE = re.compile(r"^[0-9a-fA-F]{6,16}$")


def hexa(v):
    return "0x%016x" % v


def read_jsonl(path):
    if not os.path.exists(path):
        return []
    out = []
    with open(path, "r", encoding="utf-8", errors="replace") as fh:
        for line in fh:
            line = line.strip()
            if not line:
                continue
            try:
                out.append(json.loads(line))
            except ValueError:
                continue
    return out


def main():
    t0 = time.time()
    os.makedirs(OUT, exist_ok=True)
    funcs = read_jsonl(os.path.join(STAGE, "functions_meta.jsonl"))
    dec = {d["a"]: d for d in read_jsonl(os.path.join(STAGE, "decomp.jsonl"))}
    strings = read_jsonl(os.path.join(STAGE, "strings.jsonl"))
    funcs.sort(key=lambda d: int(d["addr"], 16))
    print("loaded funcs=%d decomp=%d strings=%d" % (len(funcs), len(dec), len(strings)))

    # ---- decomp/<addr>.c : copy the per-function C into the index (durable) ----
    dsrc = os.path.join(STAGE, "decomp")
    ddst = os.path.join(OUT, "decomp")
    os.makedirs(ddst, exist_ok=True)
    ncopied = 0
    if os.path.isdir(dsrc):
        for fn in os.listdir(dsrc):
            if not fn.endswith(".c"):
                continue
            dst = os.path.join(ddst, fn)
            src_p = os.path.join(dsrc, fn)
            if (not os.path.exists(dst)) or os.path.getsize(dst) != os.path.getsize(src_p):
                with open(src_p, "rb") as a, open(dst, "wb") as b:
                    b.write(a.read())
                ncopied += 1

    # ---- funcs.tsv (fast lookup: addr end size name sig has_decomp) ----
    with open(os.path.join(OUT, "funcs.tsv"), "w", encoding="utf-8") as fh:
        for d in funcs:
            a = int(d["addr"], 16)
            sz = d.get("size", 0)
            dd = dec.get(d["addr"]) or {}
            have = "1" if dd.get("clen", 0) else "0"
            # prefer the decompiler-derived prototype: it recovers parameters
            # that the stored (pre-decompile) signature may lack
            sig = dd.get("sig") or d.get("sig") or ""
            sig = sig.replace("\t", " ").replace("\n", " ")
            fh.write("%s\t%s\t%d\t%s\t%s\t%s\n" % (hexa(a), hexa(a + max(sz, 1)), sz,
                                                   d.get("name", "?"), sig, have))

    # ---- functions.json (valid JSON array, one element per line) ----
    with open(os.path.join(OUT, "functions.json"), "w", encoding="utf-8") as fh:
        fh.write("[\n")
        first = True
        for d in funcs:
            a = int(d["addr"], 16)
            sz = d.get("size", 0)
            c = ""
            if sz > 32:
                ddir = os.path.join(STAGE, "decomp")
                p = os.path.join(ddir, d["addr"] + ".c")
                if os.path.exists(p):
                    with open(p, "r", encoding="utf-8", errors="replace") as cf:
                        c = cf.read()
                    if len(c) > DECOMP_CAP:
                        c = c[:DECOMP_CAP] + "\n/* ... truncated at %d chars ... */" % DECOMP_CAP
            rec = {"addr": hexa(a), "name": d.get("name", "?"), "size": sz,
                   "sig": ((dec.get(d["addr"]) or {}).get("sig") or d.get("sig") or ""),
                   "nparams": d.get("nparams", 0),
                   "thunk": bool(d.get("thunk")), "decomp": c}
            if not first:
                fh.write(",\n")
            fh.write(json.dumps(rec, ensure_ascii=False))
            first = False
        fh.write("\n]\n")

    # ---- xrefs: swap to (to, from, kind, ghidra-type) and sort ----
    # Refs whose target is a symbolic storage location (e.g. "Stack[-0x1008]")
    # are not addresses; they are counted and excluded from address lookup.
    src = os.path.join(STAGE, "xrefs.tsv")
    lines = []
    skipped_sym = 0

    def is_addr(s):
        # Ghidra prints addresses as bare hex ("ffffffff804c3150"); storage
        # symbols look like "Stack[-0x1008]" or "unique:0x1000".
        return bool(ADDR_RE.match(s))

    if os.path.exists(src):
        with open(src, "r", encoding="utf-8", errors="replace") as fh:
            for line in fh:
                p = line.rstrip("\n").split("\t")
                if len(p) < 4:
                    continue
                if not (is_addr(p[0]) and is_addr(p[1])):
                    skipped_sym += 1
                    continue
                lines.append("%s\t%s\t%s\t%s" % (p[1], p[0], p[2], p[3]))
    lines.sort()
    print("sorted %d refs in %.1fs" % (len(lines), time.time() - t0))

    with open(os.path.join(OUT, "xrefs.tsv"), "w", encoding="utf-8") as fh:
        fh.write("\n".join(lines))
        fh.write("\n")

    # ---- xrefs.idx: fixed 16-byte (to, line_no) records, sorted by to ----
    with open(os.path.join(OUT, "xrefs.idx"), "wb") as fh:
        buf = bytearray()
        for i, line in enumerate(lines, 1):
            to = int(line.split("\t", 1)[0], 16)
            buf += struct.pack("<QQ", to, i)
            if len(buf) > (1 << 22):
                fh.write(buf)
                buf = bytearray()
        fh.write(buf)

    with open(os.path.join(OUT, "xrefs.json"), "w", encoding="utf-8") as fh:
        fh.write("[\n")
        first = True
        for line in lines:
            p = line.split("\t")
            rec = {"from": p[1], "to": p[0], "type": p[2], "gtype": p[3]}
            if not first:
                fh.write(",\n")
            fh.write(json.dumps(rec))
            first = False
        fh.write("\n]\n")

    # ---- strings.json (array, one per line) + strings.jsonl (fast grep) ----
    with open(os.path.join(OUT, "strings.json"), "w", encoding="utf-8") as fh:
        fh.write("[\n")
        for i, d in enumerate(strings):
            if i:
                fh.write(",\n")
            fh.write(json.dumps(d, ensure_ascii=False))
        fh.write("\n]\n")
    with open(os.path.join(OUT, "strings.jsonl"), "w", encoding="utf-8") as fh:
        for d in strings:
            fh.write(json.dumps(d, ensure_ascii=False) + "\n")

    kinds = {}
    for line in lines:
        kinds[line.split("\t")[2]] = kinds.get(line.split("\t")[2], 0) + 1

    manifest = {
        "source": "KIMUNAKI_PS5_kernel_1422.elf",
        "generated_utc": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "functions": len(funcs),
        "functions_decompiled": sum(1 for d in dec.values() if d.get("clen", 0)),
        "decomp_failures": sum(1 for d in dec.values() if d.get("err")),
        "xrefs": len(lines),
        "xrefs_symbolic_skipped": skipped_sym,
        "xref_kinds": kinds,
        "strings": len(strings),
        "decomp_cap_in_functions_json": DECOMP_CAP,
        "build_seconds": round(time.time() - t0, 1),
    }
    with open(os.path.join(OUT, "manifest.json"), "w") as fh:
        json.dump(manifest, fh, indent=2)
    print(json.dumps(manifest, indent=2))


if __name__ == "__main__":
    main()
