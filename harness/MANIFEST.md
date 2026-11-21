# Harness manifest

What each file is, what you must supply, and the exact build and run. This is the working
harness as used, not a cleaned-up reimplementation — the scripts are verbose because a harness
that narrates what it did produces logs that can be audited later.

## You must supply (not in this repository)

| Item | How the harness finds it |
|---|---|
| A 14.22 kernel raw image | `export PS5_KERNEL_RAW=/path/to/kernel_raw_1422.bin` |
| QEMU 8.2.2 with the device models built in | `export QEMU=<qemu-8.2.2>/build/qemu-system-x86_64` |

See [`../docs/provenance.md`](../docs/provenance.md) for the image identity and
[`../docs/reproducing.md`](../docs/reproducing.md) for the full procedure.

## `trampoline/` — the boot-chain reconstruction

The trampoline is the firmware the PS5 would have run before the kernel: it builds the page
tables, hands over the memory map and loader environment, and applies the patch table that
supplies each check's expected value. It is assembled with `nasm` + `ld` by the boot script;
you do not build it by hand.

| File | Role |
|---|---|
| `tramp1422_16g_q35s144r6.asm` | the trampoline source for the baseline boot (62 patches) |
| `patches_1422_q35s144r6.inc` | the 62-patch table — one entry per substitution the boot stands on |
| `tramp1422_16g_q35s144.asm` | an earlier, fuller build kept for reference (see the methodology's reduction curve) |
| `patches_1422_q35s144.inc` | that earlier build's patch table |
| `meta_1422_16g_q35.inc` | the handoff blob: E820 memory map, module metadata, the `kenv` loader environment |
| `params.inc`, `tramp1422.ld`, `probe.ld` | assembly parameters and linker scripts |
| `check_graft_seam.py` | structural checker — seams, terminators, no fall-through into out-of-line routines |
| `emu_graft_seam.py` | unicorn emulation — proves control actually reaches the trampoline body |

Prove a trampoline change before spending a boot on it — and run the checkers against the broken
image too, or they are decoration:

```sh
python3 trampoline/check_graft_seam.py <candidate>.elf      # want: RESULT: 6/6 checks pass
python3 trampoline/emu_graft_seam.py   <candidate>.elf
```

## `qemu-device-models/` — the modelled platform

| File | Role |
|---|---|
| `aeolia_hpet.c` | the worked example: presents the Sony southbridge identity `hpet_pci` probes for, with QEMU's real HPET aliased into the aperture so the kernel's own driver drives a real timer |
| `INTEGRATION.md` | drop-in + build against QEMU 8.2.2 |

This is "model what is" in source form. The other models (the `vmmcall` hypercall handler, the
PSP mailbox MMIO device) are specified per-synthetic in
[`../docs/synthetic-register.md`](../docs/synthetic-register.md) and built into the same QEMU by
the same method; the HPET model is included in full as the reference for the technique.

## `boot/` — the run harness

| File | Role |
|---|---|
| `session157r6.sh` | the baseline boot that reaches `Device configuration finished.` — assembles the trampoline, asserts the image is not stale, launches QEMU, applies the debugger-side injects, enforces the gates |
| `session148_q35.sh` | an earlier, fuller build kept for reference |
| `qread.sh` | query a parked VM's memory/registers (one boot, unlimited reads) |
| `park-stop.sh` | shut a parked VM down cleanly and release the boot lock |

```sh
export PS5_KERNEL_RAW=/path/to/kernel_raw_1422.bin
export QEMU=<qemu-8.2.2>/build/qemu-system-x86_64
cd boot && bash session157r6.sh
```

Judge the run by the log, not the exit code: `BTEXT-HIT`, the `CR3-DOMAIN` line, a nonzero
control read, and then the banner and the marker. A run without `BTEXT-HIT` is void.

## `analysis-index/` — static analysis tooling

The index itself (tens of MB of generated JSON/TSV/decompile cache) is **not** shipped; it is
regenerated from your kernel. These are the generators and query helpers.

| File | Role |
|---|---|
| `build_index.py` | drives Ghidra 11.4.2 headless to produce the JSON index |
| `ghidra_scripts/*.java` | the exporters `build_index.py` runs (blocks, decompile, metadata) |
| `manifest.json` | the index's expected inputs and outputs |
| `q.py` | query the index: `func` / `xrefs` / `decomp` / `string`, 20–60 ms |
| `qcsv.py` | lighter call-graph/string index: `callers` / `callees` / `addr` / `str` / `xref` |
| `index-csv-PROVENANCE.md` | what the CSV index is built from, and the one column of it never to trust |

```sh
python3 q.py func   0xffffffff804c3150
python3 q.py decomp 0xffffffff804c3150
python3 qcsv.py callers 0xffffffff80bf2cf0
```
