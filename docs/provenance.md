# Provenance, scope, and disclosure

## Artifact identities

This repository redistributes none of these. The identities are published so a reproduction can
be checked against the exact artifacts used, without any firmware changing hands.

| Artifact | Size (bytes) | SHA-256 |
|---|---:|---|
| KIMUNAKI PS5 14.22 kernel (ELF) | 47,651,880 | `c2ee77967dfebe3b63d00670b3385ea7b3af264ebf2ff645fdb9ed4ec390b17d` |
| KIMUNAKI 14.22 hypervisor (ELF) | 475,136 | `78f7223d364a46a786ee96ddbc1b3025d32767f765664b208e89c1c342411bb7` |

The hypervisor hash is published for identification only. The hypervisor is **not** used in the
boot — the whole point is that the kernel runs with Sony's `lv1` absent — but the image was
inspected to recover the hypercall ABI the harness has to answer.

### Why the kernel is believed genuine

- The build string is self-consistent and specific: `r230580/releases/14.22`, `amd64`, stamp
  `Oct 27 2026 02:17:44`, kernel build ID `dc496d74ef9d4813`. The HV literal dates to
  `2026-10-26`, both days before the public release, as a real release build should be.
- The same kernel ELF is published in an independent third-party disassembly, and its SHA-256
  matches the image used here (this is what makes the CSV index addresses directly usable — see
  `harness/analysis-index/index-csv-PROVENANCE.md`).
- The ELF segment table and entry point were independently corroborated, and the executable
  segment's `int3` fill is present at the same offsets and sizes in an unrelated on-console dump
  — Sony ships those holes; they are not a capture defect.

Scene/community claims attached to the original upload (jailbreak bundles, payload toolchains)
are **unverified and unrelated** to this work. The two ELFs are Sony's own kernel and hypervisor;
nothing here depends on any such claim being true.

## What this repository contains

Documentation and a harness: the boot-chain reconstruction (NASM trampoline and patch tables),
one worked QEMU device model, the boot and parked-VM scripts, and the static-analysis index
tooling. Total footprint is well under a megabyte, and the `.gitignore` is written to keep any
firmware, dump, build output, or boot log out of history permanently.

## What it deliberately excludes

- No kernel, hypervisor, or raw dump, and no means to obtain one.
- No reconstructed, decrypted, or recovered firmware code; no keys; no content.
- No game execution and no path to it. The missing executable regions of the dump are uniform
  `int3` fill, not recoverable ciphertext, so the paths that would need them are structurally
  unavailable here regardless.
- No vulnerability details (see below).

## Scope and legality

This is security research and interoperability analysis on firmware obtained for that purpose,
conducted statically on the host and dynamically inside a disposable QEMU guest. It redistributes
no copyrighted code or keys and provides no capability to run unauthorized content. The harness's
value is as a research instrument — a way to exercise and characterize a real kernel's early boot
and device-attach behaviour — not as a product.

## Coordinated disclosure

Reaching device-config completion exercises the kernel's device-init, driver-attach, and parser
surface under instrumentation, which is the research purpose. Any vulnerability identified through
that work is handled by **private coordinated disclosure to the vendor** and is intentionally
absent from this repository. This release is about the rehost and the method; it names no flaw,
publishes no proof-of-concept, and should not be read as doing either.
