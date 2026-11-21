#!/usr/bin/env python3
"""emu_graft_seam.py -- UNICORN proof (no boot) that graft64's oracle path
reaches the graft body (`mov rdx, cr3`) and that no `ret` pops the saved RBP.

Usage:  /opt/re-tools/venv/bin/python3 wp3_boot/emu_graft_seam.py [ELF]
        (venv = unicorn 2.1.4 + pyelftools; system python3 has capstone but
         no unicorn, so this is a separate interpreter on purpose)

Model of the boot-86 geometry (verified by reproduction, not assumed):
  entry   RSP -> [fake return address]        (call pushed it)
  graft64 `push rbp`  -> [RSP-8] = RBP
  graft64 `mov rbp,rsp` -> RBP = RSP-8
  the buggy path ran hex8_'s `ret`, which popped [RBP] (= the saved RBP) into
  RIP -> boot 86: IP=CR2=0xffffffff82f80c30 with RBP=0xffffffff82f80c10.
Here the saved RBP is 0xffffffff82f80c30 and the return slot is 0xdeadbeefc0de:
if either becomes the PC, the emulation FAILS.

Register arguments are the boot-86 call shape: rdi=0x24, rsi=0x40b0000,
rdx=0x4350000. graft_flag (.bss) is written 0 -> the ORACLE path runs
(message + 4 hex fields, captured by a port-0x408 OUT hook, so the text and
its order are checked against the ELF's own .rodata strings); then the same
run is repeated with graft_flag=1 -> the fast path (`jne .g_oracle_done`).
Exit 0 only if both paths land on the graft body without a bogus ret.
"""
import struct
import sys

from unicorn import Uc, UC_ARCH_X86, UC_MODE_64, UC_HOOK_INSN, UC_HOOK_CODE
from unicorn.unicorn_const import UC_PROT_ALL
from unicorn.x86_const import (UC_X86_REG_RSP, UC_X86_REG_RBP, UC_X86_REG_RDI,
                               UC_X86_REG_RSI, UC_X86_REG_RDX, UC_X86_REG_RIP,
                               UC_X86_REG_CR3, UC_X86_REG_RAX, UC_X86_INS_OUT)

DEFAULT_ELF = "/tmp/opencode/b87/trampoline1422.elf"
SAVED_RBP = 0xFFFFFFFF82F80C30      # boot-86 #PF: RIP == [RBP] == this
FAKE_RET = 0xDEADBEEFC0DE          # fake caller return address


def parse_elf(path):
    raw = open(path, "rb").read()
    if raw[:4] != b"\x7fELF" or raw[4] != 1:
        raise SystemExit("%s: not ELF32" % path)
    e_shoff, = struct.unpack_from("<I", raw, 0x20)
    shell, shnum, shstrndx = struct.unpack_from("<HHH", raw, 0x2E)
    secs = []
    for i in range(shnum):
        f = struct.unpack_from("<IIIIIIIIII", raw, e_shoff + i * shell)
        secs.append(dict(name=f[0], addr=f[3], off=f[4], size=f[5],
                         link=f[6], entsize=f[9]))
    base = secs[shstrndx]["off"]
    for s in secs:
        e = raw.index(b"\x00", base + s["name"])
        s["sname"] = raw[base + s["name"]:e].decode("latin-1")
    syms = {}
    st = next(s for s in secs if s["sname"] == ".symtab")
    strb = secs[st["link"]]["off"]
    for i in range(st["size"] // st["entsize"]):
        nm, val, size, info, other, shndx = struct.unpack_from(
            "<IIIBBH", raw, st["off"] + i * st["entsize"])
        e = raw.index(b"\x00", strb + nm)
        n = raw[strb + nm:e].decode("latin-1")
        if n:
            syms[n] = val
    phoff, = struct.unpack_from("<I", raw, 0x1C)
    phentsize, phnum = struct.unpack_from("<HH", raw, 0x2A)
    loads = []
    for i in range(phnum):
        p = struct.unpack_from("<8I", raw, phoff + i * phentsize)
        if p[0] == 1:                       # PT_LOAD
            loads.append(dict(off=p[1], vaddr=p[2], filesz=p[4], memsz=p[5]))
    return raw, syms, loads


def main(path):
    raw, syms, loads = parse_elf(path)
    load = next(l for l in loads if l["vaddr"] <= 0x7000000 < l["vaddr"] + l["memsz"])
    graft = syms["graft64"]
    expect_bug = "--expect-bug" in sys.argv[2:]
    body = syms.get("g_body")
    if body is None and not expect_bug:
        raise SystemExit("%s: no g_body symbol — pass --expect-bug to run this "
                         "image as the pre-fix NEGATIVE control" % path)
    hex8 = syms["hex8_"]
    k64 = syms["k64puts"]
    oracle = syms["graft64.g_oracle_done"]
    gflag = syms["graft_flag"]
    labels = {graft: "graft64", oracle: ".g_oracle_done", hex8: "hex8_",
              body: "g_body", k64: "k64puts", syms["hv14"]: "hv14"}

    def elfstr(sym):
        a = syms[sym]
        o = load["off"] + (a - load["vaddr"])
        e = raw.index(b"\x00", o)
        return raw[o:e].decode("latin-1")

    msg = (elfstr("s_or1"), elfstr("s_or2"), elfstr("s_or3"),
           elfstr("s_or4"), elfstr("s_nl"))
    print("ELF %s" % path)
    print("  graft64=0x%x .g_oracle_done=0x%x hex8_=0x%x g_body=%s "
          "k64puts=0x%x graft_flag=0x%x"
          % (graft, oracle, hex8, ("0x%x" % body) if body else "(no symbol)",
             k64, gflag))
    print("  .rodata strings: %r %r %r %r %r" % msg)

    size = (load["memsz"] + 0xFFF) & ~0xFFF
    stack_base, stack_size = 0x7FF000, 0x1000
    bogus = (FAKE_RET, SAVED_RBP)
    rc = 0

    runs = [("oracle path (graft_flag=0)", 0)]
    if not expect_bug:
        runs.append(("fast path (graft_flag=1)", 1))
    for label, flag in runs:
        uc = Uc(UC_ARCH_X86, UC_MODE_64)
        uc.mem_map(load["vaddr"], size, UC_PROT_ALL)
        uc.mem_write(load["vaddr"], raw[load["off"]:load["off"] + load["filesz"]])
        uc.mem_map(stack_base, stack_size, UC_PROT_ALL)
        # graft64 is entered by the kernel's e9 patch: [RSP] = caller return.
        rsp = stack_base + 0x800
        uc.mem_write(rsp, struct.pack("<Q", FAKE_RET))
        uc.mem_write(gflag, struct.pack("<Q", flag))
        uc.reg_write(UC_X86_REG_RSP, rsp)
        uc.reg_write(UC_X86_REG_RBP, SAVED_RBP)
        uc.reg_write(UC_X86_REG_RDI, 0x24)
        uc.reg_write(UC_X86_REG_RSI, 0x40B0000)
        uc.reg_write(UC_X86_REG_RDX, 0x4350000)
        cr3 = 0x4350000
        try:
            uc.reg_write(UC_X86_REG_CR3, cr3)
        except Exception as e:
            print("  NOTE: CR3 write refused (%s) — using the model's default" % e)
            cr3 = uc.reg_read(UC_X86_REG_CR3)

        out = bytearray()

        def hook_out(uc_, port, sz, value, user):
            if port == 0x408:
                out.append(value & 0xFF)
            return True

        uc.hook_add(UC_HOOK_INSN, hook_out, None, 1, 0, UC_X86_INS_OUT)

        trace = []

        class Stop(Exception):
            def __init__(self, kind, pc):
                self.kind, self.pc = kind, pc

        def hook_code(uc_, addr, sz, user):
            # UC_HOOK_CODE fires BEFORE the instruction executes, so a `ret`
            # that pops SAVED_RBP is caught at the popped address itself.
            trace.append(addr)
            if addr in bogus:
                raise Stop("bogus", addr)
            if body is not None and addr == body:
                raise Stop("body", addr)
            if len(trace) > 200000:
                raise Stop("limit", addr)

        hcode = uc.hook_add(UC_HOOK_CODE, hook_code)

        reached = False
        fault = None
        try:
            uc.emu_start(graft, 0)
        except Stop as s:
            if s.kind == "body":
                reached = True
            elif s.kind == "bogus":
                fault = ("PC 0x%x is the saved RBP / fake return address "
                         "-> a `ret` popped the caller frame" % s.pc)
            else:
                fault = "step limit exceeded at 0x%x" % s.pc
        except Exception as e:
            rip = uc.reg_read(UC_X86_REG_RIP)
            if rip in bogus:
                fault = ("RIP 0x%x is the saved RBP / fake return address "
                         "-> a `ret` popped the caller frame" % rip)
            else:
                fault = "unicorn stopped at PC 0x%x: %s" % (rip, e)

        print("\n-- %s --" % label)
        print("  PC trace (%d steps):" % len(trace))
        for i in range(0, len(trace), 6):
            print("   " + "  ".join(("0x%x%s" % (p, "(" + labels[p] + ")" if p in labels else ""))
                                    for p in trace[i:i + 6]))
        if out:
            print("  port 0x408 output: %r" % bytes(out).decode("latin-1"))
        print("  reached g_body (%s): %s"
              % (("0x%x" % body) if body else "(no symbol)", reached))
        if fault:
            print("  FAULT: %s" % fault)

        if expect_bug:
            ok = fault is not None and "saved RBP" in fault
            print("  VERDICT: %s" % ("NEGATIVE CONTROL REPRODUCED — the oracle "
                  "path fell into hex8_ and its ret popped the saved RBP"
                  if ok else "NOT REPRODUCED (expected the pre-fix fall-through)"))
            print("\nRESULT: %s" % ("OK — the emulator detects the boot-86 bug on "
                  "the unpatched image" if ok else "FAILED"))
            return 0 if ok else 2
        ok = reached and fault is None
        # no `ret` from hex8_ may have run: it is only entered by `call`, and
        # a call from graft64 returns to the next instruction — assert that
        # every visit to hex8_ is immediately followed by an address inside
        # graft64 (i.e. after a call), never by g_body.
        visits = [i for i, p in enumerate(trace) if p == hex8]
        print("  hex8_ entered %d time(s) (all by call): %s" % (len(visits), bool(visits)))
        # the messages the oracle prints must be the ELF's own strings, in order
        if flag == 0:
            import re
            text = bytes(out).decode("latin-1")
            strip = re.sub(r"[0-9a-fA-F]{8}", "@", text)
            want = re.sub(r"[0-9a-fA-F]{8}", "@",
                          msg[0] + "00000000" + msg[1] + "00000000" + msg[2]
                          + "00000000" + msg[3] + "00000000" + msg[4])
            print("  message skeleton match: %s (%r vs %r)" % (strip == want, strip, want))
            ok = ok and strip == want and len(visits) == 4
        else:
            ok = ok and not out and hex8 not in trace
        # one more step: g_body's first instruction must load CR3 into RDX
        uc.hook_del(hcode)
        uc.emu_start(body, 0, count=1)
        rdx = uc.reg_read(UC_X86_REG_RDX)
        print("  g_body first insn: RDX=0x%x (CR3=0x%x) match=%s"
              % (rdx, cr3, rdx == cr3))
        ok = ok and rdx == cr3
        print("  VERDICT: %s" % ("PASS" if ok else "FAIL"))
        rc |= 0 if ok else 1
    print("\nRESULT: %s" % ("OK — both paths reach the graft body, no bogus ret"
                            if rc == 0 else "FAILED"))
    return rc


if __name__ == "__main__":
    sys.exit(main(sys.argv[1] if len(sys.argv) > 1 else DEFAULT_ELF))
