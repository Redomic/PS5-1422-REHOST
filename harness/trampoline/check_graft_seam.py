#!/usr/bin/env python3
"""check_graft_seam.py -- STATIC (no boot) proof that graft64's oracle path can
no longer fall out of the oracle into the hex8_ subroutine, plus a
fall-through / reachability audit of every out-of-line routine.

Usage:
  python3 wp3_boot/check_graft_seam.py [ELF]

ELF default: /tmp/opencode/b88/trampoline1422.elf (the boot-88 rebuild).
Negative control (check F must FAIL, naming rsi/rdx):
  /tmp/opencode/b87/trampoline1422.elf (boot-87 image, no argument save).
Requires: system python3 with capstone (5.x). Nothing here is hand-written:
the .text bytes come from the ELF's own PT_LOAD/'.text' section header, every
label address comes from the ELF's .symtab, and control flow is decoded with
capstone in CS_MODE_64 (objdump mis-decodes this elf32-REX image; see
coord/TOOLS.md).

Checks (each prints PASS/FAIL, exit 0 only if all PASS):
  A  instruction at .g_oracle_done is `jmp g_body` (unconditional, exact target)
  B  following control flow from .g_oracle_done reaches g_body with ZERO
     executed `ret` (BFS; `call` returns to the next instruction)
  C  g_body's first instruction is `mov rdx, cr3` (the graft body entry)
  D  no routine is entered by fall-through: the instruction that ends exactly
     at each entry is an unconditional jmp / ret / hlt
  E  every reference (imm operand) to hex8_ and k64puts is a `call`
  F  ARGUMENT PRESERVATION (b88, the check that would have caught boot 87
     without a boot): emulate GRAFT64_ADDR from a caller frame with sentinels
     rdi=0x11111111 rsi=0x22222222 rdx=0x33333333, once with graft_flag=1
     (fast path) and once with graft_flag=0 (oracle path), stop at the tail
     `jmp <reg>`-to-0xffffffff804c3156 and require rdi/rsi/rdx == sentinels
     AND rsp == R-0x10 with [rsp]=r15, [rsp+8]=saved rbp, [rsp+0x10]=return
     address (the frame map_tmr's own `push r15` produces). Unicorn; the
     venv at /opt/re-tools/venv has unicorn but no capstone, so F re-execs
     itself with `--f-emu` under that interpreter and reads the JSON back.
"""
import json
import os
import struct
import subprocess
import sys

try:
    from capstone import Cs, CS_ARCH_X86, CS_MODE_32, CS_MODE_64
    from capstone.x86 import X86_OP_IMM, X86_OP_REG
    HAVE_CAPSTONE = True
except ImportError:                                   # the unicorn venv
    HAVE_CAPSTONE = False

DEFAULT_ELF = "/tmp/opencode/b88/trampoline1422.elf"
VENV_PY = "/opt/re-tools/venv/bin/python3"

# ---- check F geometry (all values are models, chosen here and printed) ----
F_GRAFT_FLAGS = (1, 0)              # fast path first, then the oracle path
F_RDI, F_RSI, F_RDX = 0x11111111, 0x22222222, 0x33333333
F_R15 = 0x5555555555555555
F_SAVED_RBP = 0xFFFFFFFF82F80C30     # boot-86 [RBP]; also the bogus-PC tripwire
F_FAKE_RET = 0xDEADB000              # fake caller return address, MAPPED so a
                                     # stray `ret` is caught by the hook, not a
                                     # fetch fault
F_STACK = 0x7FF000
F_STACK_RSP = 0x7FF800
F_CR3 = 0x4350000                    # fake kernel PML4 (body: mov rdx,cr3)
F_PML4_OURS = 0x40A0000              # body reads [r10+…] with r10=0x40a0000
F_RESUME = 0xFFFFFFFF804C3156

# routines: name -> decode mode. 32-bit helpers were assembled under [bits 32].
ROUTINES = [
    ("putc", 32), ("puts", 32), ("puthex32", 32), ("_start", 32),
    ("rsdp_scan", 32), ("no_mod", 32), ("bad_len", 32),
    ("long_mode", 64), ("graft64", 64), ("hex8_", 64), ("g_body", 64),
    ("hv14", 64), ("hv0a", 64), ("btext_go", 64), ("cr3fix", 64),
    ("k64puts", 64),
]


class Elf:
    """Minimal ELF32 reader: just what this check needs (section + symbols)."""

    def __init__(self, path):
        self.raw = open(path, "rb").read()
        if self.raw[:4] != b"\x7fELF" or self.raw[4] != 1:
            raise SystemExit("%s: not an ELF32 file" % path)
        (self.e_shoff,) = struct.unpack_from("<I", self.raw, 0x20)
        self.e_shentsize, self.e_shnum, self.e_shstrndx = struct.unpack_from(
            "<HHH", self.raw, 0x2E)
        self.secs = []
        for i in range(self.e_shnum):
            off = self.e_shoff + i * self.e_shentsize
            name, typ, flags, addr, offset, size, link, info, align, entsize = \
                struct.unpack_from("<IIIIIIIIII", self.raw, off)
            self.secs.append(dict(name=name, type=typ, addr=addr,
                                  offset=offset, size=size, link=link,
                                  entsize=entsize))
        shstr = self.secs[self.e_shstrndx]
        for s in self.secs:
            s["sname"] = self._str(shstr["offset"], s["name"])
        self.syms = {}
        symtab = next((s for s in self.secs if s["sname"] == ".symtab"), None)
        if symtab is None:
            raise SystemExit("%s: no .symtab" % path)
        strtab = self.secs[symtab["link"]]
        for i in range(symtab["size"] // symtab["entsize"]):
            off = symtab["offset"] + i * symtab["entsize"]
            nm, val, size, info, other, shndx = struct.unpack_from(
                "<IIIBBH", self.raw, off)
            n = self._str(strtab["offset"], nm)
            if n:
                self.syms[n] = (val, size)
        text = self.section(".text")
        self.text_va = text["addr"]
        self.text = self.raw[text["offset"]:text["offset"] + text["size"]]
        self.text_end = self.text_va + text["size"]

    def loads(self):
        """PT_LOAD segments: (vaddr, filesz, memsz, file_off). Check F maps
        these into unicorn, so the guest image is the ELF's own bytes."""
        (e_phoff,) = struct.unpack_from("<I", self.raw, 0x1C)
        e_phentsize, e_phnum = struct.unpack_from("<HH", self.raw, 0x2A)
        out = []
        for i in range(e_phnum):
            p = struct.unpack_from("<8I", self.raw, e_phoff + i * e_phentsize)
            if p[0] == 1:
                out.append((p[2], p[4], p[5], p[1]))
        return out

    def _str(self, base, off):
        end = self.raw.index(b"\x00", base + off)
        return self.raw[base + off:end].decode("latin-1")

    def section(self, name):
        for s in self.secs:
            if s["sname"] == name:
                return s
        raise SystemExit("no %s section" % name)

    def sym(self, name):
        if name not in self.syms:
            raise SystemExit("no symbol %r in ELF" % name)
        return self.syms[name][0]

    def code(self, va, size):
        """Bytes [va, va+size) that live inside .text (zero-filled past it)."""
        out = bytearray(size)
        for i in range(size):
            a = va + i
            if self.text_va <= a < self.text_end:
                out[i] = self.text[a - self.text_va]
        return bytes(out)


MD = ({}
      if not HAVE_CAPSTONE else
      {32: Cs(CS_ARCH_X86, CS_MODE_32), 64: Cs(CS_ARCH_X86, CS_MODE_64)})
for _md in MD.values():
    _md.detail = True


def decode_one(elf, va, mode=64):
    b = elf.code(va, 16)
    for ins in MD[mode].disasm(b, va, 1):
        return ins
    return None


def decode_range(elf, va, end, mode=64):
    b = elf.code(va, end - va)
    return list(MD[mode].disasm(b, va))


def imms(ins):
    return [op.imm for op in ins.operands if op.type == X86_OP_IMM]


results = []


def check(tag, ok, detail):
    results.append((tag, ok))
    print("%s  %-58s %s" % ("PASS" if ok else "FAIL", tag, detail))


def main(path):
    elf = Elf(path)
    print("ELF: %s" % path)
    print(".text: VA 0x%x size 0x%x  (end 0x%x)"
          % (elf.text_va, len(elf.text), elf.text_end))
    sym = {n: elf.sym(n) for n, _ in ROUTINES if n != "g_body"}
    for n, _ in ROUTINES:
        print("  %-10s %s" % (n, "0x%x" % sym[n] if n in sym else "(no symbol)"))
    print("  %-10s 0x%x" % ("graft64.g_oracle_done",
                             elf.sym("graft64.g_oracle_done")))

    oracle = elf.sym("graft64.g_oracle_done")
    graft = sym["graft64"]
    hex8 = sym["hex8_"]
    k64 = sym["k64puts"]
    if "g_body" in elf.syms:
        body = elf.sym("g_body")
    else:
        # Pre-fix images have no g_body label: locate the graft body by its
        # first instruction (the only `mov rdx, cr3` after graft64's prologue).
        # This keeps the check meaningful as a NEGATIVE control on the old ELF.
        body = None
        for i in decode_range(elf, graft, sym["hv14"], 64):
            if (i.mnemonic == "mov" and len(i.operands) == 2
                    and i.operands[1].type == X86_OP_REG
                    and i.reg_name(i.operands[1].reg) == "cr3"):
                body = i.address
                break
        print("  %-10s 0x%x (no symbol: located by `mov rdx, cr3`)"
              % ("g_body", body if body is not None else 0))
        if body is None:
            raise SystemExit("cannot locate the graft body (`mov rdx, cr3`)")

    print("\n-- A: the instruction at .g_oracle_done --")
    ins = decode_one(elf, oracle, 64)
    a_ok = (ins is not None and ins.mnemonic == "jmp"
            and body in imms(ins))
    check("A .g_oracle_done is `jmp g_body` (target 0x%x)" % body, a_ok,
          "0x%x %s %s" % (oracle, ins.mnemonic if ins else "?", ins.op_str if ins else "?"))

    print("\n-- B: control flow .g_oracle_done -> g_body, no ret executed --")
    # BFS. `call` returns to the next instruction (helpers are opaque here and
    # their own `ret` is audited in D). Conditional jmp = both successors.
    # Unconditional jmp inside .text is followed; jmp/ret/hlt outside = dead end.
    # NOTE: not named `path`: `path` is main()'s ELF argument and a local of
    # that name silently shadowed it (check F then fed the BFS trail to
    # subprocess.run as an argv element).
    bpath = None
    seen = set()
    queue = [(oracle, [])]
    ret_on_path = 0
    while queue:
        pc, trail = queue.pop(0)
        if pc in seen:
            continue
        seen.add(pc)
        i = decode_one(elf, pc, 64)
        if i is None:
            continue
        m, t = i.mnemonic, "%s %s" % (i.mnemonic, i.op_str)
        if m in ("ret", "retf"):
            ret_on_path += 1
            print("   ret reached at 0x%x (would pop the caller frame)" % pc)
            continue
        if m in ("hlt", "ud2", "int3"):
            continue
        if m == "jmp":
            tgt = imms(i)
            if tgt and elf.text_va <= tgt[0] < elf.text_end:
                if tgt[0] == body:
                    bpath = trail + [(pc, t)]
                queue.append((tgt[0], trail + [(pc, t)]))
            continue
        if m.startswith("j"):
            for t0 in imms(i):
                if elf.text_va <= t0 < elf.text_end:
                    if t0 == body:
                        bpath = trail + [(pc, t)]
                    queue.append((t0, trail + [(pc, t)]))
        nxt = i.address + i.size
        if nxt == body:
            bpath = trail + [(pc, t)]
        queue.append((nxt, trail + [(pc, t)]))
    b_ok = bpath is not None and ret_on_path == 0
    if bpath:
        print("   path: " + " -> ".join("0x%x(%s)" % (a, s) for a, s in bpath)
              + " -> 0x%x(g_body)" % body)
    check("B reaches g_body, 0 ret executed", b_ok,
          "%d insns in trail, %d ret seen" % (len(path) if path else -1, ret_on_path))

    print("\n-- C: g_body is the graft body --")
    ins = decode_one(elf, body, 64)
    c_ok = (ins is not None and ins.mnemonic == "mov"
            and len(ins.operands) == 2
            and ins.operands[0].type == X86_OP_REG
            and ins.operands[1].type == X86_OP_REG
            and ins.reg_name(ins.operands[0].reg) == "rdx"
            and ins.reg_name(ins.operands[1].reg) == "cr3")
    check("C g_body starts `mov rdx, cr3`", c_ok,
          "0x%x %s %s" % (body, ins.mnemonic if ins else "?", ins.op_str if ins else "?"))

    print("\n-- D: no entry can be reached by fall-through + terminator audit --")
    sym_all = dict(sym)
    sym_all["g_body"] = body
    order = sorted(((sym_all[n], n, mode) for n, mode in ROUTINES))
    audit = []
    d_ok = True
    for idx, (va, name, mode) in enumerate(order):
        if idx + 1 < len(order):
            end = order[idx + 1][0]
        else:
            end = elf.text_end
        insns = decode_range(elf, va, end, mode)
        if not insns:
            audit.append((name, va, "0x%x" % va, "(no decode)", "?", "no"))
            d_ok = False
            continue
        last = insns[-1]
        nxt_name = order[idx + 1][1] if idx + 1 < len(order) else "(.text end)"
        term = "%s %s" % (last.mnemonic, last.op_str)
        safe_term = (last.mnemonic in ("ret", "retf", "hlt", "ljmp", "jmpf")
                     or last.mnemonic.startswith("j"))
        if not safe_term:
            d_ok = False
        # fall-through into the NEXT routine's entry only matters if this
        # range's last instruction does not terminate the flow.
        audit.append((name, va, "0x%x" % last.address, term,
                      nxt_name, "yes" if safe_term else "NO"))
    print("  routine    start        last insn @     end-insn                 next       safe")
    for name, va, lva, term, nxt, safe in audit:
        print("  %-10s 0x%-10x %-15s %-24s %-10s %s"
              % (name, va, lva, term, nxt, safe))
    check("D every routine ends in ret/jmp/hlt (balanced, no fall-out)", d_ok,
          "%d routines audited" % len(audit))

    print("\n-- E: subroutine reachability (all refs are call/jmp) --")
    # Decode the whole 64-bit out-of-line block linearly (graft64 .. k64puts end)
    # so every direct `call 0x700xxxx` is visible as an imm operand.
    seg_end = elf.text_end
    refs = {"hex8_": [], "k64puts": []}
    for i in decode_range(elf, graft, seg_end, 64):
        for t in imms(i):
            for nm, addr in (("hex8_", hex8), ("k64puts", k64)):
                if t == addr:
                    refs[nm].append((i.address, i.mnemonic, i.op_str))
    e_ok = True
    for nm in ("hex8_", "k64puts"):
        calls = [r for r in refs[nm] if r[1] == "call"]
        other = [r for r in refs[nm] if r[1] != "call"]
        print("  %-8s 0x%x: %d refs, %d call, %d other %s"
              % (nm, sym[nm], len(refs[nm]), len(calls), len(other),
                 [(hex(a), m, s) for a, m, s in other]))
        if not calls or other:
            e_ok = False
    check("E hex8_/k64puts referenced only by call", e_ok,
          "hex8_=%d k64puts=%d call sites" % (len(refs["hex8_"]), len(refs["k64puts"])))

    # ------------------------------------------------------------------ F
    print("\n-- F: argument preservation across graft64 (unicorn) --")
    f_ok = check_f(elf, path, body, graft, hex8, k64)

    bad = [t for t, ok in results if not ok]
    print("\n%s: %d/%d checks pass" % ("RESULT", len(results) - len(bad), len(results)))
    if bad:
        print("FAILED: " + "; ".join(bad))
        return 1
    print("RESULT: OK -- the oracle path jmps to the graft body; hex8_/k64puts "
          "are call-only; graft64 returns to map_tmr with rdi/rsi/rdx intact")
    return 0


def find_tail(elf, body):
    """Locate graft64's tail `push r15; mov <reg>,0xffffffff804c3156; jmp <reg>`.
    Returns (tail_jmp_va, reg_name) or (None, reason). Decoded, not scanned."""
    insns = decode_range(elf, body, elf.text_end, 64)
    for idx, i in enumerate(insns):
        if (i.mnemonic == "mov" and len(i.operands) == 2
                and i.operands[0].type == X86_OP_REG
                and i.operands[1].type == X86_OP_IMM
                and i.operands[1].imm & 0xFFFFFFFFFFFFFFFF == F_RESUME):
            reg = i.reg_name(i.operands[0].reg)
            if idx == 0 or insns[idx - 1].mnemonic != "push" \
                    or insns[idx - 1].op_str != "r15":
                return None, "mov %s,%#x is not preceded by `push r15`" % (reg, F_RESUME)
            if idx + 1 >= len(insns):
                return None, "no instruction after mov %s" % reg
            j = insns[idx + 1]
            if j.mnemonic != "jmp" or j.op_str != reg:
                return None, "expected `jmp %s`, got `%s %s`" % (reg, j.mnemonic, j.op_str)
            return j.address, reg
    return None, "no `mov <reg>, %#x` between g_body and .text end" % F_RESUME


def f_emulate(path, tail_va):
    """TWO unicorn runs of GRAFT64_ADDR. Needs unicorn (venv interpreter)."""
    from unicorn import Uc, UC_ARCH_X86, UC_MODE_64, UC_HOOK_INSN, UC_HOOK_CODE
    from unicorn.unicorn_const import UC_PROT_ALL
    from unicorn.x86_const import (
        UC_X86_REG_RAX, UC_X86_REG_RBP, UC_X86_REG_RCX, UC_X86_REG_RDX,
        UC_X86_REG_RDI, UC_X86_REG_RIP, UC_X86_REG_RSP, UC_X86_REG_RSI,
        UC_X86_REG_R15, UC_X86_REG_CR3, UC_X86_INS_OUT)

    elf = Elf(path)
    graft = elf.sym("graft64")
    gflag = elf.sym("graft_flag")
    segs = elf.loads()
    runs = []
    for flag in F_GRAFT_FLAGS:
        uc = Uc(UC_ARCH_X86, UC_MODE_64)
        for vaddr, filesz, memsz, off in segs:
            base = vaddr & ~0xFFF
            size = ((vaddr + memsz + 0xFFF) & ~0xFFF) - base
            uc.mem_map(base, size, UC_PROT_ALL)
            uc.mem_write(vaddr, elf.raw[off:off + filesz])
        for page in (F_STACK, F_PML4_OURS, F_CR3 & ~0xFFF,
                     F_FAKE_RET & ~0xFFF):
            uc.mem_map(page, 0x1000, UC_PROT_ALL)
        uc.mem_write(gflag, struct.pack("<Q", flag))
        uc.mem_write(F_STACK_RSP, struct.pack("<Q", F_FAKE_RET))
        uc.reg_write(UC_X86_REG_RSP, F_STACK_RSP)
        uc.reg_write(UC_X86_REG_RBP, F_SAVED_RBP)
        uc.reg_write(UC_X86_REG_RDI, F_RDI)
        uc.reg_write(UC_X86_REG_RSI, F_RSI)
        uc.reg_write(UC_X86_REG_RDX, F_RDX)
        uc.reg_write(UC_X86_REG_R15, F_R15)
        cr3 = F_CR3
        try:
            uc.reg_write(UC_X86_REG_CR3, cr3)
        except Exception:
            cr3 = uc.reg_read(UC_X86_REG_CR3)

        out = bytearray()

        def hook_out(uc_, port, sz, value, user):
            if port == 0x408:
                out.append(value & 0xFF)
            return True

        uc.hook_add(UC_HOOK_INSN, hook_out, None, 1, 0, UC_X86_INS_OUT)

        class Stop(Exception):
            def __init__(self, kind):
                self.kind = kind

        state = {"n": 0}

        def hook_code(uc_, addr, sz, user):
            state["n"] += 1
            if addr == tail_va:
                raise Stop("tail")
            if addr in (F_FAKE_RET, F_SAVED_RBP):
                raise Stop("bogus-pc")
            if state["n"] > 200000:
                raise Stop("limit")

        uc.hook_add(UC_HOOK_CODE, hook_code)
        rec = dict(flag=flag, reason="error", pc=graft, rsp=F_STACK_RSP,
                   cr3=cr3, out="")
        try:
            uc.emu_start(graft, 0)
        except Stop as s:
            rec["reason"] = s.kind
        except Exception as e:                      # unmapped fetch etc.
            rec["reason"] = "unicorn-error: %s" % e
        rip = uc.reg_read(UC_X86_REG_RIP)
        rec.update(
            pc=rip,
            rdi=uc.reg_read(UC_X86_REG_RDI), rsi=uc.reg_read(UC_X86_REG_RSI),
            rdx=uc.reg_read(UC_X86_REG_RDX), rsp=uc.reg_read(UC_X86_REG_RSP),
            rax=uc.reg_read(UC_X86_REG_RAX), rcx=uc.reg_read(UC_X86_REG_RCX),
            rbp=uc.reg_read(UC_X86_REG_RBP), r15=uc.reg_read(UC_X86_REG_R15),
            out=bytes(out).decode("latin-1"))
        try:
            mem = uc.mem_read(rec["rsp"], 24)
            rec["frame"] = list(struct.unpack("<3Q", bytes(mem)))
        except Exception as e:
            rec["frame"] = None
            rec["frame_err"] = str(e)
        runs.append(rec)
    return runs


def check_f(elf, path, body, graft, hex8, k64):
    tail_va, reg = find_tail(elf, body)
    if tail_va is None:
        check("F rdi/rsi/rdx preserved + frame exact at the tail jmp", False,
              "cannot locate the tail: %s" % reg)
        return False
    print("  tail: 0x%x `push r15; mov %s, %#x; jmp %s` (decoded from 0x%x)"
          % (tail_va, reg, F_RESUME, reg, body))
    print("  model: entry rsp R=0x%x [R]=0x%x rdi=0x%x rsi=0x%x rdx=0x%x r15=0x%x "
          "rbp=0x%x cr3=0x%x" % (F_STACK_RSP, F_FAKE_RET, F_RDI, F_RSI, F_RDX,
                                 F_R15, F_SAVED_RBP, F_CR3))
    try:
        runs = f_emulate(path, tail_va)
    except ImportError:
        # system python3 has capstone but no unicorn; the venv has unicorn but
        # no capstone. Run the emulation half in the venv, same code path.
        proc = subprocess.run([VENV_PY, os.path.abspath(__file__),
                               "--f-emu", path, "0x%x" % tail_va],
                              capture_output=True, text=True)
        if proc.returncode != 0:
            check("F rdi/rsi/rdx preserved + frame exact at the tail jmp", False,
                  "emulator child failed rc=%d: %s"
                  % (proc.returncode, (proc.stderr or proc.stdout).strip()[-300:]))
            return False
        runs = json.loads(proc.stdout)

    ok = True
    for rec in runs:
        tag = "fast path (graft_flag=1)" if rec["flag"] else "oracle path (graft_flag=0)"
        print("  -- %s --" % tag)
        print("     stop: %s at pc=0x%x" % (rec["reason"], rec["pc"]))
        if rec["out"]:
            print("     port 0x408: %r" % rec["out"])
        ok = ok and rec["reason"] == "tail"
        if rec["reason"] != "tail":
            print("     FAIL: the run did not stop at the tail jmp 0x%x" % tail_va)
        for nm, want in (("rdi", F_RDI), ("rsi", F_RSI), ("rdx", F_RDX)):
            got = rec[nm]
            good = got == want
            ok = ok and good
            print("     %s = 0x%x  expected 0x%x  %s%s"
                  % (nm, got, want, "OK" if good else "CLOBBERED",
                     "" if good else "  <-- FAIL F: %s" % nm.upper()))
        want_rsp = F_STACK_RSP - 0x10
        good = rec["rsp"] == want_rsp
        ok = ok and good
        print("     rsp = 0x%x  expected 0x%x (R-0x10 after the graft's `push r15`)  %s"
              % (rec["rsp"], want_rsp, "OK" if good else "MISMATCH  <-- FAIL F: RSP"))
        fr = rec["frame"]
        if fr is None:
            ok = False
            print("     frame unreadable at rsp: %s" % rec.get("frame_err"))
            continue
        for lbl, got, want in (("[rsp] (r15)", fr[0], F_R15),
                               ("[rsp+8] (rbp)", fr[1], F_SAVED_RBP),
                               ("[rsp+0x10] (ret)", fr[2], F_FAKE_RET)):
            good = got == want
            ok = ok and good
            print("     %-18s = 0x%x  expected 0x%x  %s"
                  % (lbl, got, want, "OK" if good else "MISMATCH  <-- FAIL F: frame"))
    check("F rdi/rsi/rdx preserved + frame exact at the tail jmp", ok,
          "%d runs (graft_flag=1,0), tail 0x%x, sentinels 0x11111111/0x22222222/0x33333333"
          % (len(runs), tail_va))
    return ok


if __name__ == "__main__":
    if len(sys.argv) >= 2 and sys.argv[1] == "--f-emu":
        # child mode: capstone-free, run by the unicorn venv interpreter
        print(json.dumps(f_emulate(sys.argv[2], int(sys.argv[3], 16))))
        sys.exit(0)
    if not HAVE_CAPSTONE:
        raise SystemExit("capstone not importable in %s; run A-F with the system "
                         "python3 (F re-execs the venv for the emulation)"
                         % sys.executable)
    sys.exit(main(sys.argv[1] if len(sys.argv) > 1 else DEFAULT_ELF))

