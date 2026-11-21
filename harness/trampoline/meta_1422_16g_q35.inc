; meta_1422.inc — preload metadata (modulep @ 0x4094000) for KIMUNAKI 14.22
; Layout decoded from 14.22 kernel (L-123/L-124): flat TLV stream,
; block = tag(4) len(4) payload, 8-byte aligned, terminated by {tag0,len0}.
;   tag 1 = module header (payload = module name, e.g. "kernel")
;   tag 2 = name block (payload = searched filename, e.g. "elf64 kernel")
;   tag 3 = address qword — kernel image text base PA; 14.22: KERN_PHYS
;            0x200000 (L-164: the 13.60-era 0x210000 was wrong for our load)
;   tag 0x9001 = SMAP (BIOS memory map). Payload = N records of 20 bytes,
;            {u64 base, u64 length, u32 type}  (type 1 = usable RAM),
;            and len IS the payload byte-length (N*20).
;            STATIC PROOF (2026-11-19, q.py decomp of both ends):
;            consumer FUN_80c199b0 does
;              puVar4 = FUN_80e6f9c0(param_1, 0x9001);      // payload ptr
;              end    = puVar4 + *(uint*)(puVar4 - 4);     // <- len field
;              do { type = *(u32*)(puVar4+2); base = *puVar4;
;                   len = puVar4[1]; ... } while (puVar4 += 0x14, ...);
;            getter FUN_80e6f9c0 walks {u32 tag,u32 len,payload} and returns
;            param_1+8 (the payload), advancing (len+0xf)&~7 per block, so
;            puVar4-4 is the TLV LEN FIELD itself and stride 0x14 = 20 B.
;            The same 0x9001 payload is consumed by FUN_809aa040
;            ("ram_attach": one resource per type-1 record).
;            Block bytes are COPIED VERBATIM from 13.60's verified handoff
;            wp3_boot/meta.inc (the kit that reaches
;            "Device configuration finished." on this QEMU): three type-1
;            entries, 0x1000..0x9B000, 0x9C000..0xF0000, 0x100000..0x80000000
;            — i.e. a 2 GiB physmem top, so the guest must be -m 2G.
;            NOTE: the active getter patch row (patches_1422.inc,
;            "getter-selfhandle" @0xffffffff80e6f9c0) currently replaces the
;            getter with a stub that answers 0x9001 from a zero record region
;            at MODULEP+0x820 and prints 'G' on 0x408. While that row is
;            active the stream below is NOT read — b97's P97-GETTER-STUB
;            probe counts the 'G' so the shadowing is visible in the log.
;   tag 0/len 0 = end of stream
; Field ids 0x8003/0x8004/0x8006/0x800c (L-124) are OMITTED in v1: getter
; returns NULL for missing tags and the caller NULL-checks; the 0x8006
; KASLR self-remap path (KVA 0xffffff80_00000000) stays dormant so the
; kernel keeps executing from the trampoline's identity-KVA window.
; Add field blocks only if the next failure demands them.
;
; SIZE ARITHMETIC (asserted by coord/CLAIMS.md C-026):
;   tag1 8 + round8(7)  = 8 + 8  = 16   (offsets 0x00..0x10)
;   tag2 8 + round8(13) = 8 + 16 = 24   (0x10..0x28)
;   tag3 8 + round8(8)  = 8 + 8  = 16   (0x28..0x38)
;   tag 0x9001: 8 + round8(60) = 8 + 64 = 72   (0x38..0x80)
;              (60-byte payload occupies 68 raw bytes, padded to 72;
;               8 + round_up(60,8) = 72 = the getter's advance)
;   terminator 8                       (0x80..0x88)
;   META1422_LEN = 16+24+16+72+8 = 136 ; last byte 0x87, 136 % 8 = 0
; ===== Q35 (session123, L-361): SMAP rebuilt for QEMU -M q35 -m 16G. =====
; q35 RAM (QMP info mtree -f, FlatView 'memory'): low [0x0,0xa0000);
;   below-4G [0x100000,0x80000000) (2 GiB top, PCI hole starts 2 GiB);
;   above-4G [0x100000000,0x480000000) (4-18 GiB). Differs from i440fx below/above split.
; ===== (derived from BOOT 104 16 GiB i440fx SMAP) =====
; QEMU 8.2.2 REAL backing (verified via QMP `info mtree -f`, FlatView AS "memory"):
;   [0x0,        0xa0000)      low 640K
;   [0x100000,   0xc0000000)   below-4G main (1 MiB .. 3 GiB); PCI hole follows
;   [0x100000000,0x440000000)  above-4G (4 GiB .. 17 GiB)
; The 0x9001 block below claims ONLY QEMU-backed GPAs (no unbacked synthetic RAM).
; Low ranges kept verbatim from the 13.60 reference (coordinator directive).
; This supersedes the 2 GiB SMAP; the mode-4 carvers' 0x100000000 (4 GiB) and
; 0x400000000 (16 GiB) reservations now fall WITHIN the map. Register: LEDGER 11.
; META1422_LEN is computed from labels at the END of this file (L-391/L-392
; added a tag 0x8006 MODINFOMD_ENVP block + the env blob; was 152).
meta1422_blob:
    dd 1, 7
    db "kernel", 0            ; 7 B payload
    db 0                      ; pad -> 16
    dd 2, 13
    db "elf64 kernel", 0      ; 13 B payload
    db 0, 0, 0                ; pad -> 24
    dd 3, 8
    dq 0x200000               ; kernel image text base PA = KERN_PHYS (L-165);
                              ; explicit 8-byte payload (the old file relied on
                              ; a following dd 0 for the high dword AND on
                              ; 4 bytes past the label for the terminator —
                              ; both are emitted explicitly now)
    ; ---- tag 0x9001 SMAP: verbatim from 13.60 wp3_boot/meta.inc ----
    ; dd 0x9001, len 60 (3 x 20-byte {base,len,type} records, type 1 usable),
    ; then 4 zero bytes of padding so the NEXT block starts at 8+round8(60)=72.
    dd 0x9001, 80             ; 4 records x 20 B = 80-byte payload (8+80=88, 8-aligned)
    dq 0x0000000000001000, 0x000000000009A000
    dd 1                      ; [0x1000,0x9B000)       type 1 (kept, 13.60 ref)
    dq 0x000000000009C000, 0x0000000000054000
    dd 1                      ; [0x9C000,0xF0000)      type 1 (kept, 13.60 ref)
    dq 0x0000000000100000, 0x000000007FD00000
    dd 1                      ; [0x100000,0x7FE00000) below-4G USABLE @-M q35 -m 16G; top 2 MiB [0x7FE00000,0x80000000) CARVED OUT as ACPI-reserved (L-363b: SeaBIOS ZoneHigh holds the RSDT@0x7ffe22eb+tables; still QEMU-backed+mappable, just not free RAM, so ACPI survives)
    dq 0x0000000100000000, 0x0000000380000000
    dd 1                      ; [0x100000000,0x480000000) above-4G, QEMU-backed @-M q35 -m 16G
    ; no block pad: 8+80 = 88 already 8-aligned (getter advance = round_up(8+80,8))
    ; ---- tag 0x8006 MODINFOMD_ENVP (L-391/L-392; S-55) ----
    ; STEP-0 semantics, VERIFIED from THIS binary (not assumed from FreeBSD):
    ;   consumer FUN_80c19880: plVar4 = getter(kmdp,0x8006);
    ;     if (plVar4 && *plVar4) envp = kaslr_base + (*plVar4 - DAT_83df55f8);
    ;     init_static_kenv(envp, 0)  [FUN_80686c00]
    ;   kaslr_base + (p - DAT_83df55f8) is exactly FUN_80c1c060, the SAME
    ;   relocation FUN_80e6fb20 applies to tag-3 ADDR (phys 0x200000) -> so the
    ;   0x8006 payload is an 8-byte PHYSICAL pointer, NOT an inline blob. The
    ;   whole module-info region is walked via DAT_840311b8 (the KVA self-remap
    ;   window), so a pointer into the copied metadata resolves in an already
    ;   mapped window. getter (FUN_80e6f9c0) returns payload=param_1+2 and does
    ;   NOT relocate 0x8006 (only 3/0x8003/0x8004), so the payload stays physical.
    ;   init_static_kenv reads name=val\0name=val\0\0 directly.
    ; The trampoline copies meta1422_blob -> PA MODULEP, so the blob's physical
    ; address = MODULEP + (meta1422_env - meta1422_blob).
    ; 0x8006 block payload = [8-byte phys ptr][env string], env FOLDED INTO the
    ; recognized ENVP block (L-399.5 / s136 boot-1+boot-2 proof). s136 PROVED the
    ; kernel's preload reservation covers only the RECOGNIZED blocks: the 0x8006
    ; block's 8-byte pointer payload survived at PA 0x4094098 in BOTH boots, but
    ; everything past the last recognized block end (modulep+0xA8) was reclaimed/
    ; ZEROED before device-attach -- INCLUDING a separate carrier tag 0x8F00's
    ; payload (boot-2) -- so the msi=0 hints never applied (hpet panicked
    ; pci_alloc_msi:19). Putting the env INSIDE the 0x8006 payload keeps it in the
    ; preserved region. Consumer FUN_80c19880 reads only payload[0..8) as the
    ; pointer; the trailing env bytes are ignored by it and untouched by the
    ; relocator FUN_80e6fb20 (0x8006 not in {3,0x8003,0x8004}). The pointer targets
    ; the env (payload+8 = MODULEP+0xA0 => kern_envp 0xffffffff840940a0).
    ; hpet devclass "hpet_pci" (serial "hpet_pci0:"), NOT "hpet"; hint.hpet.0.msi
    ; kept as inert insurance. icc "icc" unit0, resname "msi"=DAT_815dc7a6.
    ; (kern.eventtimer.timer=LAPIC dropped: L-397/L-398 proved LAPIC already active.)
    dd 0x8006, meta1422_env_end - meta1422_ptr    ; len = 8 (ptr) + env bytes
meta1422_ptr:
    dq MODULEP + (meta1422_env - meta1422_blob)   ; phys ptr -> env (MODULEP+0xA0)
meta1422_env:
    db "hint.icc.0.msi=0", 0
    db "hint.hpet_pci.0.msi=0", 0
    db "hint.hpet.0.msi=0", 0
    db 0                      ; double-NUL: init_static_kenv stops here
meta1422_env_end:
    ; pad the 0x8006 payload to an 8-byte multiple RELATIVE TO THE BLOB so the
    ; getter's 8-aligned walk lands the terminator correctly. meta1422_ptr is at
    ; blob+0x98 (8-aligned); padding the payload length to a multiple of 8 suffices.
    times ((-(meta1422_env_end - meta1422_ptr)) & 7) db 0
    dd 0, 0                   ; {tag 0, len 0} terminator  (tag + len)
meta1422_end:
META1422_LEN equ meta1422_end - meta1422_blob
