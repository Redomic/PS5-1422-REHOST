# Acknowledgements

## Firmware — KIMUNAKI

**KIMUNAKI** ([@iamWitchKing](https://x.com/iamWitchKing)) supplied the two firmware images this
entire project runs on: the 14.22 kernel image and the kernel-side hypervisor-service module.
There is no harness, no boot, and no finding without them.

**Scope of this credit.** The capture and release of those images. Not credited to KIMUNAKI: the
QEMU harness and trampoline, the patch table and fidelity programme, the synthetic register, the
static analysis, or any finding in this repository — those are this project's own work and its own
errors.

**Provenance.** The images are Sony Interactive Entertainment's copyrighted code. This repository
does not distribute them, and crediting KIMUNAKI is a statement about who supplied the capture,
not about who owns the code.

## Special thanks

- **R0nov4** — the 13.60-on-QEMU kit; this project's harness is its descendant, and more than one
  wrong turn was caught by comparing against it.

- **ccclosed** ([ps5-1422-research](https://github.com/ccclosed/ps5-1422-research)) — the evidence
  reports, the verified image fetcher, and the 14.22 port kit; the most important external
  reference this work reads.

- **danthespal** — the public 13.60 live kernel RAM dump, which answers "what does this code
  actually see" when a static answer is not enough.

- **The QEMU project** — the emulator, its device-model framework, and the source that let us
  verify every device-behaviour claim instead of assuming it.

- **The FreeBSD project** — the upstream source that made it possible to separate inherited defects
  from platform-specific ones, and a disclosure process that rewards a plain, honest report.

- **The reviewers who said "no"** — the independent passes that refuted confident hypotheses during
  this campaign. They are the reason this record is worth reading.

## How to cite

> Built on the PS5 14.22 kernel and hypervisor-service images supplied by **KIMUNAKI**
> (@iamWitchKing). QEMU re-hosting, analysis and findings: the PS5-1422-REHOST project.

## Attribution note

Names are used with permission. Acknowledged parties have not reviewed or endorsed this work
unless explicitly stated.
