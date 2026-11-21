# Reproducing

This repository ships the harness, not the firmware. To reproduce the boot you supply your own
legally obtained PS5 14.22 kernel image; everything else is here. The numbers below are the
environment the result was produced on — nearby configurations should work, but this is the one
that is proven.

## Quickstart

On an AMD host with nested virtualization, once you have your own kernel image and have built QEMU
with the device models (§3):

```sh
# one-time: point the harness at your QEMU's firmware (it runs QEMU with -L ./bios)
ln -s <qemu-8.2.2>/pc-bios harness/boot/bios

export PS5_KERNEL_RAW=/path/to/your/kernel_raw_1422.bin
export QEMU=<qemu-8.2.2>/build/qemu-system-x86_64-hvmodel
cd harness/boot && bash session157r6.sh
```

The script's other two needs are already wired in the repository: `harness/boot/wp3_boot` is a
symlink to the trampoline sources, and `coord/` holds the runtime lock. Then read the log, not the
exit code: a run is only valid if the `BTEXT-HIT` checkpoint fired (§6). The sections below cover
each step in full; new terms are in the [glossary](glossary.md).

## 1. Host

The exact machine the result was produced on — the reference host. Nearby configurations should
work; this is the one that is proven.

| | |
|---|---|
| CPU | AMD Ryzen 9 9950X — 16 cores / 32 threads, AMD-V (SVM) with nested virtualization |
| Memory | 64 GiB DDR5-5600 (≈60 GiB available to the OS; the guest is given 16 GiB) |
| GPU | AMD Radeon integrated (RDNA, PCI `1002:13c0`) + NVIDIA GeForce RTX 5090 (driver 595.99.02) — neither is used for the boot (no passthrough) |
| OS | Ubuntu 24.04.3 LTS, Linux kernel 7.0.0-42-generic |
| Virtualization | `/dev/kvm` present, `kvm_amd nested=1` |
| QEMU | **8.2.2**, built from source with the device models compiled in (§3). The distro's system QEMU is also 8.2.2, but lacks the models |
| Toolchain | NASM 2.16.01, GNU ld 2.42 (binutils), Python 3.13; Ghidra 11.4.2 + JDK 21 for the static index |

The CPU matters more than the rest: the kernel is AMD x86-64 code, and the host is the same family,
so it runs directly. The relevant processor features are present and used — `svm`/`npt` for nested
KVM, `vmmcall` for the hypervisor-call path, and `smap`/`smep`, which the kernel enforces.

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

The baseline boot needs a QEMU 8.2.2 that presents the platform the kernel probes for. Two pieces,
both in `harness/qemu-device-models/`:

- **`aeolia_hpet.c`** — the HPET southbridge, needed to reach device configuration.
- **`hvmodel.patch`** — three source edits that model the PSP mailbox and the boot-reached
  hypervisor calls, so the kernel's own code drives them (this is what the 62-patch baseline runs
  on). Full notes: [`../harness/qemu-device-models/hvmodel.md`](../harness/qemu-device-models/hvmodel.md).

```sh
# extract qemu-8.2.2 source, then:
cd <qemu-8.2.2>
patch -p1 < <repo>/harness/qemu-device-models/hvmodel.patch
cp <repo>/harness/qemu-device-models/aeolia_hpet.c  hw/misc/
# register the HPET model: append to hw/misc/meson.build
#   system_ss.add(files('aeolia_hpet.c'))
./configure --target-list=x86_64-softmmu --enable-debug
ninja -C build qemu-system-x86_64
cp build/qemu-system-x86_64 build/qemu-system-x86_64-hvmodel   # keep stock QEMU too
```

Point the harness at the model build:

```sh
export QEMU=<qemu-8.2.2>/build/qemu-system-x86_64-hvmodel
```

`INTEGRATION.md` has the HPET integration notes. Note that a rebuilt QEMU binary will **not**
hash-match the one that produced the published logs — QEMU C builds are not bit-reproducible — so
verify the build by booting (§6), not by checksum.

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
bash session157r6.sh
```

The script assembles the trampoline from `harness/trampoline/`, refuses to boot a stale image
(it greps the built ELF for signature strings), launches QEMU with your kernel and the modelled
devices, applies the debugger-side injects, and parks. This is the baseline 62-patch boot;
`session148_q35.sh` is an earlier, fuller build kept for reference.

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
