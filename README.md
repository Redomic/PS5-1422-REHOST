# PS5-1422-REHOST

**The first publicly documented rehost of a current-generation console kernel on a PC.**

A genuine Sony PlayStation 5 system-software **14.22** kernel, booted under QEMU on commodity
AMD hardware with **no Sony hypervisor**, far enough to print its own
`Device configuration finished.` marker — with every synthetic it took to get there
**registered, observable, and revertible**.

The kernel is not emulated. It is the real signed-build kernel (`r230580/releases/14.22`,
Oct 27 2026), executing its own code on a native x86-64 CPU. What this project supplies is the
*boot chain* a console would normally provide and a PC does not: the page tables, the memory
map, the device topology, the loader environment, the hypercall services. Each was reconstructed
from the only specification that exists — the kernel's own expectations, read one fault at a
time.

---

## What is claimed

1. **A documented rehost, not a demo.** A current-gen console kernel reaches device-config
   completion on a PC, and *every* departure from genuine Sony behaviour that made it possible is
   written down with its address, its pretense, and the condition for its removal. The accounting
   is the contribution as much as the boot.
2. **A reusable method.** *Remove what never runs, model what is, guards aren't inert* — a
   three-move discipline for reducing a bring-up from mostly-synthetic toward the kernel's own
   code, measured as a curve. See [`METHODOLOGY.md`](METHODOLOGY.md).
3. **A security-research harness.** Reaching device-config exercises the kernel's device-init,
   driver-attach, and parser surface under instrumentation. Any vulnerabilities found are handled
   through private coordinated disclosure and are **not** part of this release.

## The headline numbers

| | |
|---|---|
| Kernel | `r230580/releases/14.22`, `amd64`, build stamp Oct 27 2026 |
| Host | AMD, nested KVM, 32 cores, 60 GiB RAM, QEMU 8.2.2 |
| Hypervisor | none — Sony `lv1` is absent; the kernel's hypercalls are answered by the harness/QEMU |
| Boot reached | SYSINIT → `SIE CONFIDENTIAL … r230580/releases/14.22` banner → `Device configuration finished.` |
| Synthetics to get there | 56, all registered and observable ([`docs/synthetic-register.md`](docs/synthetic-register.md)) |
| Patch-reduction curve | **423 → 62 kernel patches (−85%)**, every step boot-proven |

The two gate lines, quoted verbatim from the boot log, are in
[`evidence/boot-markers.md`](evidence/boot-markers.md).

---

## What is *not* here

This repository is everything needed to understand and reproduce the method — **minus the
firmware itself**. By design it contains no Sony binaries:

- no kernel or hypervisor image, and no raw dump;
- no reconstructed firmware code, no keys, no decrypted content.

You supply your own legally obtained 14.22 kernel image; the harness builds around it. Identities
and SHA-256 hashes of the artifacts used are listed in [`docs/provenance.md`](docs/provenance.md)
so a reproduction can be checked against them without redistributing anything.

## Repository map

```
PS5-1422-REHOST/
├── README.md                     you are here
├── METHODOLOGY.md                ★ the method and the complete toolchain
├── docs/
│   ├── synthetic-register.md     every synthetic: address, pretense, return, revert condition
│   ├── reproducing.md            host requirements, build, and run — bring your own kernel
│   └── provenance.md             artifact identities + hashes, scope, legality, disclosure
├── harness/
│   ├── MANIFEST.md               what each file is, and the exact build + run commands
│   ├── trampoline/               the boot-chain reconstruction (NASM) + patch tables + seam checkers
│   ├── qemu-device-models/       the modelled platform (worked example: the HPET southbridge)
│   ├── boot/                     the boot + parked-VM harness scripts
│   └── analysis-index/           the static-analysis index tooling (Ghidra + CSV query helpers)
└── evidence/
    └── boot-markers.md           the banner and device-config marker, quoted from the log
```

## Where to start

- To understand *how* it was done and reproduce the approach: [`METHODOLOGY.md`](METHODOLOGY.md).
- To see exactly *what* was faked and why it is honest: [`docs/synthetic-register.md`](docs/synthetic-register.md).
- To run it against your own kernel: [`docs/reproducing.md`](docs/reproducing.md).

## Scope and ethics

This is security research and interoperability work on firmware obtained for that purpose. The
repository distributes no copyrighted Sony code or keys and enables no piracy — there is no game
execution, no content, and no path to either here. Vulnerability findings are disclosed privately
to the vendor, not published. See [`docs/provenance.md`](docs/provenance.md) for the full
statement.
