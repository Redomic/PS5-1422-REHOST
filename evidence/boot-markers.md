# Boot markers

The two lines that define the result, quoted verbatim from the boot log. The console driver
prints every line twice; the duplication in the logs is real and is left as-is.

## The logs

The complete, unedited logs of both runs are in [`logs/`](logs/):

| File | Run | What it shows |
|---|---|---|
| `logs/session148-serial.log` | 423-patch marker run | the kernel's own serial output, banner → `Device configuration finished.` (line 533) |
| `logs/session148-gdbstep.log` | same run | the gates and injects: `BTEXT-HIT`, the `CR3` domain, `P14-GRAFT`, every `SYNTH-HARNESS:` and `*-INJECT:` line |
| `logs/session157r6-serial.log` | 62-patch pristine run | same marker (line 530) reached with the reduced patch set |
| `logs/session157r6-gdbstep.log` | same run | the gates for the pristine run |

The `gdbstep` logs are the ones to read if you want to confirm the result is not a trampoline
fall-through: `BTEXT-HIT: kernel entry 0xffffffff8045a6c0 REACHED (run valid)`, the kernel-domain
`CR3`, and each synthetic announcing itself. Everything quoted below is drawn from these files.

## The kernel came up (`BTEXT-HIT`)

The run opens with the trampoline handing control to the kernel's own entry, and the gate
confirms that entry executed — without this line, nothing after it is kernel behaviour:

```
PS5-TRAMP-1422: booting KIMUNAKI 14.22 kernel
PS5-TRAMP-1422: entering long mode -> btext 0xffffffff8045a6c0
```

## The banner — the kernel believes it is a PS5

```
SIE CONFIDENTIAL
Copyright (C) 2026 Sony Interactive Entertainment Inc.
Copyright (c) 1992-2016 The FreeBSD Project.
Copyright (c) 1979, 1980, 1983, 1986, 1988, 1989, 1991, 1992, 1993, 1994
	The Regents of the University of California. All rights reserved.
r230580/releases/14.22 Oct 27 2026 02:17:44 amd64
...
mDBG: Kernel Build ID = dc496d74ef9d4813
Memory mode: 1: PPR16  (GDDR6 : 16 GiB, DDR5 : 0 GiB)
 Application memory(Total)   : 0x000000032d600000 bytes (13014MiB)
```

This is the kernel printing its own release identity. The build string, stamp, and build ID match
the genuine 14.22 image (see [`../docs/provenance.md`](../docs/provenance.md)).

## Device configuration finished — the Phase goal

Line 533 of the log, after the device-probe loop completes:

```
Device configuration finished.
```

Reaching this means the kernel enumerated and attached its device tree to completion. As on a
real console boot, the path there is tolerant of individual device failures (the log carries the
expected MP1/SMU/GPU fail-soft storm above the marker — e.g. `[MP1ERROR] : mp1_get_clk_from_cache:
FAILED`) — devices may fail, they may not *hang*. The marker is the kernel's own `printf`, not
anything the harness emitted.

The run continues past this point into mountroot and a userland exec attempt; those are beyond
the device-config goal and are not claimed here.
