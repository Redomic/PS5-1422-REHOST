# Aeolia-HPET QEMU device — integration (hardware-supply track, L-345/L-347)

Presents the Sony southbridge identity the PS5 14.22 `hpet_pci` driver requires, with
QEMU's genuine HPET aliased into the aperture so the real driver drives a real timer.
Target: QEMU **8.2.2** source (the `-M pc` i440fx build the harness uses, L-346).

## 1. Drop in + build (~15 min)
```sh
# <qemu-8.2.2>/ = the extracted source tree
cp aeolia_hpet.c  <qemu-8.2.2>/hw/misc/

# register it in the build: append to <qemu-8.2.2>/hw/misc/meson.build
#   system_ss.add(files('aeolia_hpet.c'))

cd <qemu-8.2.2>
./configure --target-list=x86_64-softmmu --enable-debug   # --enable-debug keeps asserts/symbols
ninja -C build qemu-system-x86_64
# binary: <qemu-8.2.2>/build/qemu-system-x86_64
```

## 2. Point the harness at the new binary + add the device
In `session117.sh`:
- set `QEMU=<qemu-8.2.2>/build/qemu-system-x86_64` (the launcher already honours `QEMU=`),
- add the device to the invocation (the `-M pc ... ` line, ~L275):
  ```
  -device aeolia-hpet
  ```
  (auto-attaches to the i440fx PCI bus; the kernel's pci0 enumeration — already seen in
  serial — will probe it, and `hpet_pci` claims it on the Sony subsystem IDs.)

## 3. Confirm it (one gated boot)
Breakpoint-trace boot (session118-style, log-and-continue; NO patch change):
- `hpet_pci` probe **FUN_80e74ac0** — should now return 0 (match) instead of ENXIO,
- `hpet_attach` **FUN_80e72700** — should FIRE and run,
- its `et_register` call — should register an "HPET" node,
- then **FUN_8051d530** finds the node → **`Device configuration finished.`** (gate 3).
Gates as always: BTEXT-HIT, CR3 0x9134000, SNAP1 (else VOID). Park-stop any live park first.

## 4. Honest expectation — 1–2 iterations (owner, L-347)
The Sony attach maps the southbridge window and may read registers **beyond** the HPET block.
Everything in the 2 MiB BAR reads 0 except the aliased HPET at `+0x109000`.
- If attach **completes** → timer registers, panic gone, gate 3. Done.
- If attach **faults / mis-reads** a non-HPET offset: the boot's fault VA minus the BAR base
  gives the exact offset; add that register (with a plausible real/zero value) to
  `aeolia_hpet.c` as a small MMIO sub-region, rebuild, re-boot. Repeat until attach completes.

## Two things to confirm on the first boot (spec assumptions)
- **revision (softc+0x168 == 5):** modelled as PCI **revision id = 5**. If attach sources
  `softc+0x168` from the southbridge MMIO instead of PCI config, it'll read 0 → add a revision
  register in the aperture returning 5.
- **extra ivar byte = 0x00 (Aeolia):** assumed to be a default-zero PCI config byte → satisfied.
  If it maps to a nonzero-required field, set it.

## Scope note (L-345)
This is the first device of the hardware-supply milestone (L-137). The census flagged more
SoC-identity consumers behind HPET; they're supplied the same way. The **P36–P45 refuses stay
valid until their hardware exists** — revert each as its device is modelled/passed through.
Device model written from the owner's reverse-engineered spec (L-347); not a fake — a real HPET
behind a Sony-shaped device.
