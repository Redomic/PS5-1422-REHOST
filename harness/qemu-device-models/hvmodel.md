# hvmodel — the QEMU model the baseline boot runs on

The baseline boot (`harness/boot/session157r6.sh`, the 62-patch trampoline) does **not** run on
stock QEMU 8.2.2. It runs on a second binary — `qemu-system-x86_64-hvmodel` — built from QEMU 8.2.2
with the three edits in [`hvmodel.patch`](hvmodel.patch). These edits are the reason the patch
count is as low as it is: the PSP mailbox and the boot-reached hypervisor calls were moved out of
the trampoline and **modelled in QEMU**, so the kernel's own code drives them. This is the "model
what is" move in source form.

Keep the stock `qemu-system-x86_64` as well — the HPET model (`aeolia_hpet.c`) is needed by both.

## The three edits

| File | Edit | What it models |
|---|---|---|
| `target/i386/tcg/translate.c` | drop the `SVME` gate on the `0xd9` VMMCALL case | lets a bare `VMMCALL` from the (non-SVM) guest reach the helper instead of faulting `#UD` |
| `target/i386/tcg/sysemu/svm_helper.c` | `helper_vmmcall`: if not an SVM guest, set `eax=0` and return | the hypervisor answering the boot-reached hypercalls with `eax=0` |
| `hw/i386/pc_q35.c` | high-priority MMIO at physical `0xfdc10570` → read `0x80000000`, accept writes | the PSP mailbox status register (bit 31 = ready, done, not busy) |

Each is registered in the [synthetic register](../../docs/synthetic-register.md); nothing here is a
silent change.

## Build and run

```sh
cd <qemu-8.2.2>
patch -p1 < hvmodel.patch
cp <this repo>/harness/qemu-device-models/aeolia_hpet.c hw/misc/     # HPET model (device-config)
#   register it: append to hw/misc/meson.build:  system_ss.add(files('aeolia_hpet.c'))
./configure --target-list=x86_64-softmmu --enable-debug
ninja -C build qemu-system-x86_64
cp build/qemu-system-x86_64 build/qemu-system-x86_64-hvmodel          # keep stock QEMU too

export QEMU=<qemu-8.2.2>/build/qemu-system-x86_64-hvmodel
cd <this repo>/harness/boot && bash session157r6.sh
```

## Verify by boot, not by hash

QEMU C builds are **not** bit-reproducible, so a rebuilt `hvmodel` binary will not hash-match the
one that produced the published logs (`sha256 c4c0160c…`). That is expected — verify the rebuild
the way every run is judged: `BTEXT-HIT` fired, the banner reads `ACTIVE: 62 patches`, and
`Device configuration finished.` appears in the serial log (see
[`../../evidence/logs/`](../../evidence/logs/)). The deterministic artifact in the chain is the
trampoline ELF, which *does* reproduce.

The edits are transcribed from the project's recorded build spec and were regenerated against
pristine QEMU 8.2.2; `hvmodel.patch` applies cleanly with `patch -p1`.
