# Methodology

How a genuine PS5 14.22 kernel was brought up under QEMU with no Sony hypervisor, and the
complete toolchain used to do it. This is the document to read if you want to reproduce the
approach on a different kernel, a different version, or a different console.

The project has one organising idea: **we are not writing an emulator, we are re-hosting a
kernel.** The CPU is already the right one — the PS5 is x86-64 on AMD, and so is the host. The
distance between a console and a PC is not the instruction set; it is the **boot chain**. A
retail console boots through the PSP, the secure bootloader, and the `lv1` hypervisor, and each
layer hands the next a contract: page tables, a physical memory map, a loader environment, a
console ring, a device topology, hypercall services. We have the kernel. We have none of the
chain. The work is to reconstruct that contract from the only witness that survives — the
kernel's own expectations.

---

## 1. The core method

### 1.1 Every failed check is a line of an unread specification

When the kernel reads a field and faults because the value is wrong, that fault is not an
obstacle — it is information. It tells us precisely which clause of the boot contract we failed
to honour. A crash is the most informative event available, because it is the kernel stating,
in the only notation it has, what the boot chain was supposed to give it.

This inverts the usual debugging instinct. The checks are not adversarial. They are the
specification, delivered one fault at a time.

### 1.2 Make it exist — supply, never skip

When the kernel fails a check, **supply what it expects** so the kernel's own, unmodified code
succeeds. Do not `nop` the check out.

The reasoning is epistemic, not stylistic:

- If you remove the check, you learn nothing. The kernel proceeds and dies later, downstream of
  an input you never supplied, and the later death is unattributable.
- If you supply the data, the kernel's own code succeeds — and success is evidence that you
  understood the clause.

Four corollaries, each of which cost the project real time before it was adopted as doctrine:

1. **Prefer data recovered from a working reference.** PS5 13.60 boots on this same QEMU setup.
   When 14.22 wants a memory map, the map 13.60 hands over is not a guess — it is the same
   contract, one version older.
2. **When a value is corrupt, fix its source, not its consumer.** A cursor computed from a
   nonsense number is *correct arithmetic on a bad input*. Patching the cursor hides the real
   defect; fixing what feeds it is the actual repair.
3. **Every synthetic that satisfies a check must be observable and registered.** A silent fake
   is indistinguishable from a fact. (See §2 and [`docs/synthetic-register.md`](docs/synthetic-register.md).)
4. **Skipping is reserved for code that does not exist in the binary.** 17.8% of the kernel's
   executable segment is `int3` fill — Sony ships it that way, confirmed against an independent
   console dump with the same holes at the same offsets. A call into a hole cannot be answered,
   only skipped, and the skip must record the reason as "code absent," never "check
   inconvenient."

### 1.3 The three moves that reduce a patch to the kernel's own code

Bring-up accumulates synthetics; a re-host that is mostly synthetic has proved little. The
program is to drive the synthetic count down by replacing each fake with the real thing, and to
measure that as a curve. There are exactly three moves, cheapest first:

- **Remove what never runs.** Most of the early patch supply was *defensive blanket-stubbing* of
  code the boot never reaches. An instrumented boot measures which stubs actually execute; the
  unreached ones are deleted outright. This is the largest and cheapest lever, and it is finite —
  once exhausted, nothing is left to remove.
- **Model what is.** For a fake the boot *does* reach, build the real platform behind it: a QEMU
  device that answers the MMIO, a hypercall handler that implements the ABI, a loader
  environment that carries the tunable. The kernel's own driver then runs against a real model
  instead of a forced return value.
- **Guards aren't inert.** A guard that fires is not dead weight — it fires because the thing it
  handles is genuinely absent. Removing it crashes the boot. These retire only by modelling the
  absent device, not by deletion. Treating a live guard as removable is the mistake this move
  names.

The measured result (every step confirmed by a boot that still prints the device-config marker):

| Step | Patches | Change | How |
|---|---:|---|---|
| baseline | 423 | — | static census of the active patch table |
| | 413 | −10 | removed zero-reference `int3` stubs (no caller, jump, or data ref) |
| | 106 | −307 | removed unreached `int3` stubs — reachability boot: only 7 of 324 execute |
| | 71 | −35 | removed unreached hypercall stubs — only 6 of 41 execute |
| | 65 | −6 | modelled the 6 reached hypercalls in QEMU (first modelling retirement) |
| | **62** | −3 | modelled the PSP mailbox as a QEMU MMIO device |

**423 → 62 kernel patches, −85%, boot-proven.** The reachability lever collapsed the fear that
~330 `int3` holes were an irreducible floor — only 7 are genuinely executed. What remains at 62
is reached-instruction patches: loader and trampoline plumbing that *is* the platform, two
absent-crypto refuses that no QEMU can satisfy (the secure processor and its keys), the 7 reached
holes that need a more complete dump, and the device-refuse guards still awaiting their models.
The honest floor is not zero — it is "the kernel's own code everywhere the hardware can be
honestly modelled." The curve itself is the publishable claim.

---

## 2. Verification — telling "the kernel accepted it" from "we fooled it"

The seductive metric is "the boot got further." It is the wrong one. A boot that advances *for
the wrong reason* is debt: it moves the wall, spends a launch, and leaves a synthetic in the
machine that will be believed later. The project paid for that three separate times, each
recorded by number. So the artifacts that are trusted are narrow and mechanical.

**The mandatory gates — every boot proves these or its output is void:**

- **`BTEXT-HIT`.** A one-shot breakpoint at the kernel's own entry (`0xffffffff8045a6c0`) must
  fire. Without it, every subsequent serial line could be produced by the trampoline falling
  into arbitrary memory. Three early boots were voided exactly this way: a trampoline
  fall-through teleported into unrelated code and produced *convincing* fake kernel output.
- **`CR3-DOMAIN`.** The page-table root live at the fault must be the kernel's own. If it is the
  trampoline's table, the guest is not in the kernel's domain and the downstream output is not a
  kernel observation.
- **Control reads.** An out-of-RAM read returns zeros with a success code. Every memory snapshot
  therefore carries a known-nonzero control read, or "zero" means "wrong address," not "empty."
- **Hashes before and after** every transformation, and originals are never overwritten.

**Writer ≠ auditor.** The agent or person who builds a fix does not certify it. Verification is
done from the artifacts — the logs and the image — by someone trying to *refute* the advance,
not confirm it. Assume any success could be a fake until the artifacts rule it out.

**Self-describing logs.** Because the gates and the synthetic lines are printed on every boot,
each log stands on its own: it states which fakes were active, which patch count produced it,
and whether the kernel's entry actually executed. A log that cannot answer those questions is
discarded, not interpreted.

---

## 3. The toolchain

Every tool below was verified by running it, not by reading its README. The governing rule is
**never spend a boot on a question a read can answer, and never spend a read on a question a
decompile can answer.** Most walls were broken statically, before the boot that confirmed them.

### 3.1 Cost ladder — pick the cheapest tool that can answer

| Question | Tool | Cost |
|---|---|---|
| "What does this function do?" | Ghidra index (`q.py`) | 20–60 ms |
| "What references this address?" | Ghidra index / CSV index | 20–60 ms |
| "What does this stub do to registers?" | unicorn emulation | seconds |
| "Does this trampoline change reach its body?" | seam checker + emulator | seconds |
| "What is in guest memory right now?" | parked VM + `qread.sh` | one boot, then unlimited reads |
| "Does the boot get further?" | full QEMU boot | one of two per round |

### 3.2 Static analysis

- **Ghidra index + `q.py`** (`harness/analysis-index/q.py`) — the first stop for any static
  question. A pre-built JSON index of the decompiled kernel (21,467 functions), queried in
  milliseconds: `func` (name, range, signature), `xrefs`, `decomp` (cached C), `string`. The
  index is generated by `build_index.py` driving Ghidra headless via the exporters in
  `ghidra_scripts/`. Ghidra **11.4.2** was chosen deliberately over 12.x: 11.4.2 needs only
  JDK 21.
- **CSV index + `qcsv.py`** (`harness/analysis-index/qcsv.py`) — call graph and string xrefs in
  ~40 ms, no decompile: `callers`, `callees`, `addr`, `str`, `xref`. Built over a public
  disassembly of the *same* kernel ELF (hash-verified identical — see
  `harness/analysis-index/index-csv-PROVENANCE.md`), so addresses need no rebasing. Its one
  trap, documented there: the upstream module-attribution column is nearest-neighbour garbage
  and must never be quoted.
- **radare2 5.5.0** — for the exact instruction stream when Ghidra is ambiguous, or an xref the
  index did not record. The ELF has no section headers, so it must be mapped linearly
  (`r2 -n -m 0xffffffff80200000`) and functions defined on demand (`af @ VA; pdf @ VA`). Never
  `aaa` on this image — it runs for 13 minutes and 7 GB without finishing.
- **objdump / pyelftools** — byte-level spot checks and ELF ground truth (segments, `p_paddr`,
  symbol addresses).

**The index's blind spot, stated plainly:** it reflects the ELF as loaded. It cannot see
load-time patching (our own patches, Sony's patch lists) or runtime BSS. Any question about
runtime state goes to the parked VM, never the index.

### 3.3 Emulating one stub — unicorn

**unicorn 2.1.4** (`harness/trampoline/emu_graft_seam.py` is a worked example) answers "what does
this stub *do*" without a 15-minute boot: map a page, write the stub bytes at their link address,
set registers, run to a chosen PC, read back. It validates nothing about paging or the kernel's
own state — only what the stub does to the registers and memory it is given. That is enough for
the trampoline's own routines.

### 3.4 Proving a trampoline change without a boot

Two purpose-built checkers, run against the *candidate* image before a launch is spent:

- **`check_graft_seam.py`** — structural check of the trampoline: seams, terminators, that
  out-of-line routines are reached only by call and never by fall-through. Exits 0 only on a full
  pass.
- **`emu_graft_seam.py`** — emulates the trampoline to prove control actually reaches the body.

The discipline that makes them worth anything: **run them against the broken image too.** A
checker that only ever passes is decoration. On the real fix the seam checker scored 6/6; on the
pre-fix image it scored 1/5 and named the exact branch landing in the wrong place, and the
emulator reproduced the guest's exact fault address from the old bytes.

### 3.5 Runtime state — the parked VM

A single boot that **parks** instead of exiting, then answers unlimited memory queries — this is
how a runtime question is asked without re-booting per question.

```sh
cd harness/boot
bash session148_q35.sh                       # boots, then parks (does not kill the VM)
bash qread.sh <env> "x  /8bx 0xffffffff807ad780"   # virtual read (kernel TEXT)
bash qread.sh <env> "xp /32gx 0x3e08ba0"           # physical read (identity-mapped data)
bash qread.sh <env> "info registers"
bash park-stop.sh <env>                       # quit, clean up IPC and the boot lock
```

The hard-won caveats, all documented inline:

- **Kernel TEXT needs *virtual* reads (`x`), not `xp`.** Only the low kernel-data region happens
  to map at `PA = VA − 0x80000000`; kernel code is page-table-relocated elsewhere, so a physical
  read of a code VA returns garbage.
- **An out-of-RAM `xp` returns zeros with a success code** — hence the mandatory control read.
- **A parked read is at park time, not fault time.** A page that changed in between looks
  identical to one that never changed; pair it with a switch-stop read when the question is
  "*when* did this change."
- **A thread blocked on a mutex reads `td_wchan=0`** — do not conclude "not blocked." Mutex and
  rwlock blocks set `td_blocked`/`td_lockname`; only sleepqueue/`cv`/`sx` blocks use `td_wchan`.
- One gdb session per VM. The QMP pipe can be reopened after a client disconnects; the gdbstub
  cannot.

### 3.6 The boot harness itself

`harness/boot/session148_q35.sh` is the run that reaches the device-config marker. It is a single
self-contained script that assembles the trampoline, asserts the image is not stale (it greps the
built ELF for signature strings and refuses to boot a mismatched one), launches QEMU with the
kernel and the modelled devices, applies the debugger-side injects, and enforces the gates. The
scripts are verbose by design: a harness that narrates what it did is a harness whose logs can be
audited later. `session157r6.sh` is the same harness at the reduced 62-patch point of the curve.

### 3.7 Modelling the platform in QEMU

The "model what is" move is implemented as QEMU devices and ABI handlers that present the
platform the kernel expects. `harness/qemu-device-models/aeolia_hpet.c` is the worked, shippable
example: it presents the Sony southbridge identity the `hpet_pci` driver probes for, with QEMU's
genuine HPET aliased into the device's aperture so the kernel's real driver drives a real timer —
replacing what would otherwise be a faked "timer present" return. `INTEGRATION.md` beside it has
the drop-in and build steps against QEMU 8.2.2. The other models (the hypercall `vmmcall` path,
the PSP mailbox MMIO device) are described per-synthetic in the register and were built the same
way, against the same QEMU 8.2.2 source.

---

## 4. Operating discipline

The rules that keep the method honest, condensed:

- **Boots are rationed:** at most two QEMU boots per round, each with a timeout and a hard exit
  gate, and the previous serial log read before the next launch. Reasoning is cheap; boots are
  not.
- **Hypothesis before experiment:** a localization is written down — with the exact command —
  *before* the boot that tests it. Several leads per wall are wrong; catching your own with a
  measurement, and withdrawing it in writing, is the work, not a failure.
- **Count the walls before building an accelerator.** A static census that sizes the remaining
  work decides whether a heavier tool is worth building. Twice it showed the expensive option was
  unnecessary.
- **Artifacts are evidence.** Hash before and after any transformation; never overwrite an
  original; write derivatives to scratch or a new file.
- **A hollow advance is worth less than an honest stop.** The product is knowledge with hashes,
  not a trophy boot. Never trade the first for the second.
