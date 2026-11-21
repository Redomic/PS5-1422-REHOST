# Reproducing

This repository ships the harness, not the firmware. To reproduce the boot you supply your own
legally obtained PS5 14.22 kernel image; everything else is here. The numbers below are the
environment the result was produced on — nearby configurations should work, but this is the one
that is proven.

## 1. Host

| | |
|---|---|
| CPU | AMD x86-64 with nested virtualization (SVM) enabled |
| Memory | 60 GiB (the guest is given 16 GiB; headroom is for the toolchain) |
| Kernel | Linux with KVM; nested KVM on |
| QEMU | **8.2.2**, built from source with the device models compiled in (see §3) |
| Toolchain | `nasm`, `ld` (binutils), `python3`; Ghidra 11.4.2 + JDK 21 for the static index |

A note on acceleration: the CPU path is native x86-on-x86 through KVM, which is why the boot runs
at a usable speed. The device-config path itself does not depend on KVM being available, but the
proven runs use it.

## 2. The kernel you supply

The harness expects a raw kernel image at the path in the `PS5_KERNEL_RAW` environment variable:

```sh
export PS5_KERNEL_RAW=/path/to/your/kernel_raw_1422.bin
```

Check it against the identity in [`provenance.md`](provenance.md) before you start — a
reproduction against a different image is a different experiment. This project does not provide
the image, a download for it, or a way to extract one.

## 3. Build QEMU with the device models

The boot needs a QEMU 8.2.2 that presents the platform the kernel probes for. The worked,
shippable model is the HPET southbridge:

```sh
# extract qemu-8.2.2 source, then:
cp harness/qemu-device-models/aeolia_hpet.c  <qemu-8.2.2>/hw/misc/
# register it: append to <qemu-8.2.2>/hw/misc/meson.build
#   system_ss.add(files('aeolia_hpet.c'))
cd <qemu-8.2.2>
./configure --target-list=x86_64-softmmu --enable-debug
ninja -C build qemu-system-x86_64
```

`harness/qemu-device-models/INTEGRATION.md` has the full integration notes. The remaining models
(the `vmmcall` hypercall path and the PSP mailbox MMIO device) are described per-synthetic in
[`synthetic-register.md`](synthetic-register.md) and are built into the same QEMU the same way;
the HPET model is included in full as the reference implementation of the technique.

Point the harness at the build:

```sh
export QEMU=<qemu-8.2.2>/build/qemu-system-x86_64
```

## 4. Build the static index (optional but recommended)

The walls in this project were broken statically before any boot. To work the same way, build the
Ghidra index over your kernel:

```sh
cd harness/analysis-index
# drives Ghidra 11.4.2 headless via ghidra_scripts/ to produce the JSON index
python3 build_index.py        # see manifest.json for the expected inputs/outputs
python3 q.py func   0xffffffff804c3150
python3 q.py decomp 0xffffffff804c3150
```

`qcsv.py` is the lighter call-graph/string index; `index-csv-PROVENANCE.md` documents what it is
built from and the one column of it that must not be trusted.

## 5. Boot

```sh
cd harness/boot
bash session148_q35.sh
```

The script assembles the trampoline from `harness/trampoline/`, refuses to boot a stale image
(it greps the built ELF for signature strings), launches QEMU with your kernel and the modelled
devices, applies the debugger-side injects, and parks. `session157r6.sh` is the same boot at the
reduced 62-patch point of the curve.

## 6. What a real boot looks like

Read the log, not the exit code. A reproduction is only valid if the **gates** pass — these are
what separate a genuine kernel boot from a trampoline falling into arbitrary memory:

- `BTEXT-HIT` at the kernel entry `0xffffffff8045a6c0` — if this is missing, **nothing below it in
  the log is kernel behaviour**, however convincing it looks.
- the `CR3-DOMAIN` line showing the kernel's own page-table root at the fault;
- a known-nonzero control read in any memory snapshot (a zeroed read can mean "wrong address," not
  "empty");
- the `SYNTH:` and `SYNTH-HARNESS:` lines, which state exactly which synthetics were active for
  that run.

Then the result:

```
SIE CONFIDENTIAL
Copyright (C) 2026 Sony Interactive Entertainment Inc.
...
r230580/releases/14.22 Oct 27 2026 02:17:44 amd64
...
Device configuration finished.
```

The banner is the kernel asserting it believes it is on a PS5; the marker is the device-probe
loop completing. Both quoted with their log line numbers in
[`../evidence/boot-markers.md`](../evidence/boot-markers.md).

## 7. Asking the VM questions without re-booting

```sh
bash qread.sh <env> "x  /8bx 0xffffffff807ad780"   # virtual read of kernel TEXT
bash qread.sh <env> "xp /32gx 0x3e08ba0"           # physical read of identity-mapped data
bash park-stop.sh <env>                            # shut the parked VM down cleanly
```

The read caveats (virtual vs physical, park-time vs fault-time, mutex blocks not setting
`td_wchan`, the mandatory control read) are in [`../METHODOLOGY.md`](../METHODOLOGY.md) §3.5. They
are not optional; each one has produced a wrong conclusion at least once.
