# PS5 14.22 index (CSV) — provenance and trust boundary

Imported 2026-11-20. These are **generated indexes of the same kernel ELF this project
boots**, published by the scene. They are a convenience, not a new artifact.

## Source

| | |
|---|---|
| repos | `TakimuraRen/ps5-firmware-disasm` and `pulpito-bc/disasm` — **the same package**, identical README sha256 `56101758…`, identical file sizes, uploaded 40 minutes apart (2026-11-19 05:23 / 06:04); neither is a GitHub fork of the other |
| kernel.elf in repo | 47,651,880 B, sha256 **`c2ee77967dfebe3b63d00670b3385ea7b3af264ebf2ff645fdb9ed4ec390b17d`** — **byte-identical to `KIMUNAKI_PS5_kernel_1422.elf`** (verified by download + hash) |
| hypervisor.elf in repo | 475,136 B — same size as ours |
| claimed | "PS5 jailbreak for firmware 14.00 – 14.20… assemble the codes with the bundled toolchain" — **UNVERIFIED and implausible**: the two ELFs are Sony's own kernel and hypervisor, not a payload. The disassembly indexes are usable; the exploit claim is not evidence of anything |
| licence | none |

**Consequence for our provenance:** the 14.22 kernel image is public on at least two mirrors
since 2026-11-19. That does not make it more authentic (both are one capture), but "first to
**boot** 14.22" is now the only defensible claim — not "first to possess it".

## Files taken (with hashes)

```
80c9b7badd6e89201e8344525577e52c0be39df9d7cc5169067731f49140c3b0  kernel_calls.csv          11,459,639 B   301,569 edges
771aca8ef803fb45a724ec55ed51a80aed6ba9e0b282413b1c923085a94c01e5  kernel_strings.csv        10,741,844 B   263,571 strings
e79d85078495d8d85569a4978ad2f8ce36143f4b87c579316bfbe832e707ac1f  kernel_xrefs.csv           3,704,673 B    54,662 string xrefs
087e7676865a44a48754e60cf6ae6714c0f4959b3b25911293e3b8c0edd73e6c  kernel_relocations.csv     3,012,788 B    70,064 relocs
1f9a43837c80c0b0df47ed660dab25b7ee4952aea945164bd9b0fa77ff8a972f  kernel_segments.json             731 B
5821201b8980a1ef92d28238e4a428bef1ab2302a28bc94dd6e2f2319ce347bf  hypervisor_calls.csv          39,385 B
50c2535e358c9e8af5d68b34b95aee67f0199cd8cc9f5c060709409935c4d2a0  hypervisor_strings.csv        62,939 B
f6beac53193cb0daf6453e29db98d0b64bdaaff8f31cac3922db2598b9dc9451  hypervisor_xrefs.csv          65,696 B
2cc24557d4a557ea748888fdb1b10f49c86de8c685be6fa545e7c08e14a4b4df  hypervisor_segments.json         278 B
b96eea9e186431c96dc2397fdf0355d8e861ee41c1fa8da96252b07058e35bb3  summary.json                     313 B
```

**Not taken on purpose:** `kernel_modules.csv` / `hypervisor_modules.csv` (nearest-neighbour
attribution, demonstrably wrong — see below), `*_seeds.json` (derivable), and the ~50,000
per-function `.asm` files (derivable from our own Ghidra index and larger than the value).

## Trust boundary

| data | verdict | evidence |
|---|---|---|
| `kernel_calls.csv` | **trustworthy** | the four callers it lists for the TLV getter `0x80e6f9c0` are exactly the four our `q.py xrefs` returns |
| `kernel_xrefs.csv` | **trustworthy** | xref to the `"gbase lock"` string = `0x80bf2d08`, inside `FUN_80bf2cf0`, matching the decompile |
| `kernel_strings.csv` | **trustworthy** | string/address/length tuples; spot-checked against the raw image |
| `kernel_relocations.csv` | **trustworthy** | mechanical (RELATIVE relocs) |
| **module attribution** | **DO NOT USE** | `0x8045a6c0` (kernel entry, `machine_init`) → `sys/kern/tty_info.c`; `0x80e6f9c0` (TLV getter) → `bfs/bfs_vfsops.c`; `0x80e61900` (msgbuf) → `tty_info.c`; `0x80c199b0` (SMAP reader) → `cd9660_lookup.c`. The column's confidence value is literally `nearest` or `string` |

## Use

```bash
python3 analysis/1422/index-csv/qcsv.py callers 0xffffffff80bf2cf0   # who calls it
python3 analysis/1422/index-csv/qcsv.py callees 0xffffffff8068343b   # what it calls
python3 analysis/1422/index-csv/qcsv.py addr    0xffffffff80bf2cf0   # both
python3 analysis/1422/index-csv/qcsv.py str     gbase
python3 analysis/1422/index-csv/qcsv.py xref    0xffffffff814eec5d
```

Rules:
- **Addresses are the same as ours** (same ELF hash) — no rebasing.
- **Never quote the module name** from the source repo in the ledger; if a module is needed,
  derive it from the string/`__FILE__`-style evidence in `kernel_strings.csv` and say so.
- The Ghidra index (`q.py`) remains the primary tool — it has decompiled bodies. This CSV set
  answers *who calls whom* and *where a string lives* faster, and nothing else.

## What it has already settled

- `"gbase lock"` lives at `0xffffffff814eec5d`; its only xref is `0xffffffff80bf2d08`, inside
  `FUN_80bf2cf0` — i.e. the `sx_init` the analyst claimed **exists**.
- `FUN_80bf2cf0` has **exactly one caller**: `0xffffffff8068343b`, inside `FUN_80683020`, which
  dispatches through a kobject method table (`0xffffffff82aca490`) — an **attach-time** method.
  That is why the lock can be uninitialised while the allocator still runs: the init is
  attach-gated, the use is not.
