#!/usr/bin/env python3
"""qcsv.py — query the imported PS5 14.22 index (call graph / strings / xrefs).

Provenance: TakimuraRen/ps5-firmware-disasm (mirror: pulpito-bc/disasm). Both
ship the SAME kernel ELF this project boots — sha256
c2ee77967dfebe3b63d00670b3385ea7b3af264ebf2ff645fdb9ed4ec390b17d — so the
addresses here are our addresses.

WHAT IS TRUSTWORTHY: kernel_calls.csv, kernel_strings.csv, kernel_xrefs.csv,
kernel_relocations.csv (mechanically derived; spot-verified against our own
Ghidra index — e.g. the four callers of the TLV getter 0x80e6f9c0 match).

WHAT IS NOT: the repo's module attribution (nearest-neighbour; it labels the
kernel entry 0x8045a6c0 as "tty_info.c"). This tool deliberately does not
expose it.

Usage:
  qcsv.py callers 0xffffffff80bf2cf0      who calls this address
  qcsv.py callees 0xffffffff8068343b      what this instruction calls
  qcsv.py addr    0xffffffff80bf2cf0      both, plus name strings nearby
  qcsv.py str     gbase                   strings containing the text
  qcsv.py xref    0xffffffff814eec5d      instructions referencing a string

Exit 0 always (a missing answer prints nothing).
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
CALLS = os.path.join(HERE, "kernel_calls.csv")
STRINGS = os.path.join(HERE, "kernel_strings.csv")
XREFS = os.path.join(HERE, "kernel_xrefs.csv")


def _addr(tok: str) -> int:
    return int(tok.strip(), 16)


def callers(target: int):
    """rows of kernel_calls.csv whose target == target."""
    with open(CALLS, "r", errors="replace") as f:
        next(f, None)
        for line in f:
            insn, _, tgt = line.partition(",")
            try:
                if _addr(tgt) == target:
                    yield _addr(insn)
            except ValueError:
                continue


def callees(insn: int):
    with open(CALLS, "r", errors="replace") as f:
        next(f, None)
        for line in f:
            a, _, tgt = line.partition(",")
            try:
                if _addr(a) == insn:
                    yield _addr(tgt)
            except ValueError:
                continue


def strings(sub: str, limit: int = 40):
    sub_l = sub.lower()
    n = 0
    with open(STRINGS, "r", errors="replace") as f:
        next(f, None)
        for line in f:
            parts = line.rstrip("\n").split(",", 3)
            if len(parts) < 4:
                continue
            if sub_l in parts[3].lower():
                print("  %s  %s" % (parts[0], parts[3][:120]))
                n += 1
                if n >= limit:
                    break


def xrefs_to(addr: int):
    with open(XREFS, "r", errors="replace") as f:
        next(f, None)
        for line in f:
            parts = line.rstrip("\n").split(",", 2)
            if len(parts) < 2:
                continue
            try:
                if _addr(parts[1]) == addr:
                    print("  %s  %s" % (parts[0], parts[2][:100] if len(parts) > 2 else ""))
            except ValueError:
                continue


def main(argv):
    if len(argv) < 3:
        print(__doc__)
        return 0
    cmd, arg = argv[1], argv[2]

    if cmd == "callers":
        for a in callers(_addr(arg)):
            print("  0x%016x" % a)
    elif cmd == "callees":
        for a in callees(_addr(arg)):
            print("  0x%016x" % a)
    elif cmd == "addr":
        t = _addr(arg)
        print("callers of %#x:" % t)
        for a in callers(t):
            print("  0x%016x" % a)
        print("callees at %#x:" % t)
        for a in callees(t):
            print("  0x%016x" % a)
    elif cmd == "str":
        strings(arg)
    elif cmd == "xref":
        xrefs_to(_addr(arg))
    else:
        print(__doc__)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
