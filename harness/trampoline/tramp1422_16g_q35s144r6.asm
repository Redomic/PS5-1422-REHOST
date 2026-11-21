; ============================================================================
; PS5 14.22 (KIMUNAKI) kernel boot trampoline v1 — L-109 layout
; QEMU multiboot ELF32, linked at 0x7000000.
; The flat kernel image (kernel_raw_1422.bin, 0x3e72040 B, rebuilt per L-109:
; foff = VA32 - 0x80200000, image @ PA 0x200000) is passed as a multiboot
; module via -initrd and copied to phys 0x200000.
;
; Layout (L-109; supersedes L-108 base 0x20000 / trampoline 0x100000):
;   kernel image      PA 0x200000 .. 0x4072040   (KVA = 0xffffffff80000000 + PA
;                                                  == link-time VA exactly)
;   trampoline stack  0x408F000 (16 KB, transient)
;   btext stack       0x4093000 (4 KB, entry rsp)
;   MODULEP page      0x4094000  (L-124: TLV module table via meta_1422.inc)
;   PT pages          0x40A0000..0x40A8000 (PML4 + 3x PDPT + 3x PD + PDPT_UNIV)
;   fxsave scratch    0x4095000 (512 B, L-168 FPU handoff)
;   param block       0x9B000..0x9C000 (13.60 values reused, L-108)
;   fake pcpu         0x99000 (GS base 0xffffffff80099000)
;   trampoline        0x7000000..0x7005400
;   PHYSFREE          0x7100000 (b86: ABOVE the trampoline; was 0x40A8000,
;                     which put our own code pages inside the kernel free pool)
;
; Page-table windows (L-177: UNIVERSAL fill — supersedes the 3-slot scheme):
;   EVERY PML4 slot -> a valid PDPT; EVERY PDPT slot -> a valid identity PD
;   (PD_ID: slot0 = PT_LOW 4KB split incl. the 0xf0000 ROM-scratch alias,
;    slots 1-511 = 2MB PS PA-identity). No VA can #PF on a missing table
;   entry anymore — only on a device PA beyond guest RAM (Tier-2).
;   Motivation: boot-50 CR2 = 0xffff80000009b6dc = the kernel's 64-bit DMAP
;   window 0xffff800000000000+PA (the real PS5 DMAP base, PA | 0xffff800000000000,
;   1 TB). Under BOTH the raw 64-bit TCG walk and the 48-bit sign-extended walk
;   it lands in PML4[0x1FC] -> PDPT[0] -> PD[0] — which was never mapped
;   (corrects L-173's "PDPT_KVA[0x1E0]" decode). Special entries kept:
;     PML4[0] = PDPT_ID, PML4[0x1FF] = PDPT_KVA ([0x1FE]=PD_KVA kernel KVA,
;     [0x1C0]=PD_DMAP), PML4[0x11C] = PDPT_11C (13.60-style DMAP insurance).
;
; Console: trampoline prints to isa-debugcon @ 0x408. The 14.22 kernel
; console is a proprietary single-register/status-bit model (NOT a 16550 —
; no in-al,dx/test-al,0x20 pattern in text); its patch site is still open,
; so kernel console output is EXPECTED SILENT in v1.
;
; PATCH TABLE (wp3_boot/patches_1422.inc, PATCH_COUNT 75): the active P-numbers
; are P1-P14, P21-P30; P15 is dormant (cr3fix, entry commented out); the
; "getter-selfhandle" row (@0xffffffff80e6f9c0) is RETIRED in b98 (see below),
; so 75 rows carry the P1-P30 set minus that one.
; L-238 added P24 = FAKE-SUCCESS SYNTHETIC (S-24) at 0xffffffff804c327a: the
; psp_mbox_map_tmr mailbox send `call 0xffffffff804c32e0` (cmd 0x75, TMR map)
; becomes `mov eax,1`, because the mailbox base page is zero RAM and this QEMU
; has no PSP device (boot 88's wall). P25 (the mode-write DATA patch at flat
; offset 0x191be0c) was boot 91's experiment, retired in b92 (L-240) and is
; RE-APPLIED in b93 (L-241) together with P26: mode 4 is required by the
; memory-reserve gate in FUN_80c207e0, and the one mode-4 branch that lands in
; an INT3 hole (FUN_80c19880 -> 0xffffffff80232ca0 @0x80c19969, inside the
; 0x80210090-0x802b1bc8 0xCC fill) is skipped by rewriting the preceding
; `call 0xffffffff80d2f990` at 0x80c1992a to `xor eax,eax` so the following
; `je 0xffffffff80c1996e` is taken. PATCH_COUNT 70 -> 72.
; L-243 adds P27 = GRACEFUL-FAILURE SYNTHETIC (S-28) at 0xffffffff80c2146d:
; the 31-byte block `call 0x80a01050; lea rdi,[rip-0xc]; call 0x80a00f10;
; lea rsi,"Failed to allocate application memory"; mov edi,0x44; jmp
; 0x80c21430` becomes `mov rax,[rbp-0x460]; mov dword [rax],-1;
; jmp 0x80c213e2` + 13 nops, so a failed application-memory allocation
; returns a negative out-param and the caller (FUN_80c1c080, `js
; 0x80c1c3a6`) continues down its real "no application memory" path instead
; of panicking. THE ALLOCATION OUTCOME IS INVENTED (-1 is written, no
; allocation is attempted on that branch). PATCH_COUNT 72 -> 73.
; L-243 adds P28/P29 = S-29, the two mode-4 hole skips that make P27
; reachable: P28 at 0xffffffff80c1c340 (caller FUN_80c1c080) expect
; e8 4b 6f 61 ff -> eb 03 90 90 90 (`jmp short +3` to 0x80c1c345); P29 at
; 0xffffffff80c2082a (inside FUN_80c207e0) expect e8 f1 99 69 ff ->
; e9 69 07 00 00 (`jmp 0x80c20f98`, the shared bail both gates use).
; The hole targets 0xffffffff80233290 / 0xffffffff802ba220 are 0xCC in the
; image, so the calls are removed, not answered. PATCH_COUNT 73 -> 75.
; L-246 adds P30 = S-30 at 0xffffffff80c1c6af (foff 0xa1c6af, caller
; FUN_80c1c080): the 6-byte `je 0xffffffff80c1cda0` (0f 84 eb 06 00 00)
; after `call FUN_80c1b030` (0x80c1c6a7) + `test rax,rax` becomes 6 NOPs, so
; control FALLS THROUGH to 0x80c1c6b5 (cmp [rbp-0x238],0) = the S4 success
; continuation instead of the boot-94 panic "removal of kernel text
; [0x210000,0xef0000) from s4_preserved_physmap failed". The call failed
; because the interval-table index DAT_ffffffff83df5300 is -1 (P27's
; out-param reaching FUN_80c1b030's `if (*param_2 < 0) return 0`), so the
; check's FAILURE is ignored: the preserved map may be WRONG and only
; S4/hibernate consumes it. TASK A checked the fall-through first: it reads
; [rbp-0x238] and [rbp-0x120], copies the value into DAT_ffffffff83e08ba0/
; ba8/da8 and prints; the interval table is not dereferenced there, and the
; next reader (FUN_80bcee70) guards `if (-1 < DAT_ffffffff83df5300)`.
; PATCH_COUNT 75 -> 76.
; b98 RETIRES the "getter-selfhandle" row at 0xffffffff80e6f9c0 (the 33-byte
; write 31c0 81fe01900000 7513 48b820480984ffffffff ba08040000 b047 ee c3 c3
; 90 90 90: cmp esi,0x9001 / jne + / movabs rax,0xffffffff84094820 /
; mov edx,0x408 / mov al,'G' / out dx,al / ret). That stub answered EVERY
; 0x9001 request from a 32-byte zero record at MODULEP+0x820 and printed 'G'
; (the "AG" in K64A/K64B), so the meta TLV's 0x9001 SMAP block was shadowed by
; construction — b95/b96's phys_avail of 9.5 EiB was a SHADOWED map, not a
; wrong one. The row is deleted (PATCH_COUNT 76 -> 75); the other two rows for
; the same function, helper-exit@0x80e6fa85 and walker-selfhandle@0x80e6fb20,
; are untouched. FUN_80e6f9c0 now runs Sony's code again.
; ============================================================================

KERN_PHYS   equ 0x200000
KERN_SIZE   equ 0x3e72040
MODULEP     equ 0x4094000
; b86 (boot-85 finding): this used to be 0x40A8000, 48 MiB BELOW the
; trampoline link address 0x7000000, so the kernel's free pool could reclaim
; and zero our own code page (b85: page 0x7000000 read all-zero, and _start
; at 0x7000686 shares that 4 KiB page with graft64 at 0x7000d22). Raise it
; just above the trampoline's end (0x7005400, 1 MiB margin) so our pages are
; never declared free. Only use below is `PHYSFREE >> 12` (a page index),
; no arithmetic depends on the old value.
PHYSFREE    equ 0x7100000

PML4        equ 0x40A0000
PDPT_ID     equ 0x40A1000
PDPT_KVA    equ 0x40A2000
PDPT_11C    equ 0x40A3000
PD_ID       equ 0x40A4000
PD_KVA      equ 0x40A5000
PD_DMAP     equ 0x40A6000
PDPT_UNIV   equ 0x40A7000           ; L-177: repurposed PD_11C page = universal PDPT (512 slots -> PD_ID)
PT_END      equ 0x40A8000
PT_LOW      equ 0x4097000           ; 4KB PTE table splitting 2MB PS page 0 (L-170)
ROM_SCRATCH equ 0x4100000           ; 1MB zeroed RAM standing in for PA 0xf0000-0x100000 (L-170)

TRAMP_STACK equ 0x408F000           ; 16 KB transient
BTEXT_STACK equ 0x4093000           ; 4 KB, btext entry rsp

DMAP_PML4I  equ 0x11C
DMAP_PDPTI  equ 0x1DC
KVA_PML4I   equ 0x1FF
KVA_PDPTI   equ 0x1FE
DMAP1422_PDPTI equ 0x1C0            ; 0xffffff8000000000 window (L-109)

BTEXT       equ 0xFFFFFFFF8045A6C0  ; 14.22 ELF entry (link VA == runtime KVA)
DBGCON      equ 0x408               ; 0x402 used by 13.60 kit; keep separate

MB_MAGIC    equ 0x2BADB002

%include "patches_1422_q35s144r6.inc"
%include "params.inc"
%include "meta_1422_16g_q35.inc"

section .multiboot
align 4
    dd 0x1BADB002
    dd 0x00000003                  ; want mem info; ELF kernel
    dd -(0x1BADB002 + 0x00000003)

section .bss
align 16
tramp_stack_bottom:
    resb 16384
tramp_stack_top:
mbi_ptr:   resd 1
mod_start: resd 1
mod_len:   resd 1
pcount:    resd 1
plen:      resd 1
ebda_base: resd 1
rsdp_count: resd 1
graft_flag: resq 1    ; L-181 P8: 0 = oracle not yet printed

section .rodata
s_boot:  db "PS5-TRAMP-1422: booting KIMUNAKI 14.22 kernel", 10, 0
s_nomod: db "PS5-TRAMP-1422: ERROR no module!", 10, 0
s_len:   db "PS5-TRAMP-1422: ERROR bad module size! want ", 0
s_len2:  db " got ", 0
s_pat:   db "PS5-TRAMP-1422: patch mismatch at ", 0
s_nl:    db 10, 0
s_or1:   db "TMRCALL tmrid=", 0
s_or2:   db " arg2=", 0
s_or3:   db " arg3=", 0
s_or4:   db " ret=", 0
s_hv14:  db "HV14 tmrid=", 0
p13_offs: dd 0x000, 0x008, 0x010, 0x5e0, 0x7f0, 0x7f8, 0xff8   ; L-186: our PML4 slot offsets (identity, +1, +2, legacy-11C, DMAP-univ, KVA-1FE, KVA-1FF); L-203: 0x7ff->0xff8 (entry 511 = 511*8 = 0xff8; 0x7ff was an UNALIGNED cross-page read that never grafted the KVA-window slot)
s_done:  db "PS5-TRAMP-1422: entering long mode -> btext 0xffffffff8045a6c0", 10, 0
s_synth: db "SYNTH: kernel-side fakes ACTIVE: 62 patches (s157r6 L-441: all 3 PSP-mailbox patches P24/P4a/P4b RETIRED via QEMU PSP-mbox model; from 423; devconf-confirmed) (s144: ALL 10 S-16 false-positive power-write->hlt rows removed, L-422 audit; khfix minus 9 live S-16) (P1-P46 minus the RETIRED getter-selfhandle row: FUN_80e6f9c0 is Sony's real TLV getter again in b98, so a 0x9001 request reads the meta TLV SMAP block at PA 0x9B000 instead of the old stub's zero record at PA 0x4094820/Printed 'G') + HV14/HV0A (eax=0, no outputs) + P13/P14 graft of our PML4 slots + param-TLV @PA 0x9B000 + physfree=0x7100000 (S-18 handoff: btext stack dword 0x71000; the trampoline's own pages 0x7000000-0x7005400 stay OUTSIDE the kernel free pool; b86 was 0x40A8000, which let the kernel zero page 0x7000000) + low-panic stub @VA 0x20 (P22: copies at PA 0x20/0x4100020/0x4097020 - every kernel-domain VA-0x20 resolution; trap-safe L-214/L-217) + P23/S-23 DR6-store NOP @0xffffffff805f73e8 (mov dr6,rax -> 3x nop; load+and kept) + P24/S-24 PSP-MAILBOX-SEND FAKE @0xffffffff804c327a (psp_mbox_map_tmr's call 0xffffffff804c32e0 -> mov eax,1: SUCCESS IS INVENTED, cmd 0x75 TMR map only, no PSP device in QEMU, reply status [r15+4] stays the memset-zeroed buffer word so map_tmr returns 0) + P25/S-26 platform mode = 4 (kernel .data 0x81b1be0c static 1 -> 4; selects the memory-param path; six per-mode jump tables in FUN_80d2eb90; HARDWARE FACT INVENTED) + P26/S-27 INT3-hole call skip @0xffffffff80c1992a (call 0xffffffff80d2f990 -> xor eax,eax; the mode-4 branch's call 0xffffffff80232ca0 @0x80c19969 lies in the 0x80210090-0x802b1bc8 0xCC fill; THE GATE RESULT IS INVENTED AS 0 - FUN_80d2f990 IS NOT EXECUTED) + P27/S-28 application memory unavailable -> out-param -1, no panic @0xffffffff80c2146d (panic('Failed to allocate application memory') block -> mov rax,[rbp-0x460]; mov dword [rax],-1; jmp 0x80c213e2 + 13 nops; the caller FUN_80c1c080's `js 0x80c1c3a6` then runs its real no-application-memory continuation; ALLOCATION OUTCOME IS INVENTED - -1 is written and no allocation is attempted on that branch) + P28/P29/S-29 mode-4 hole calls skipped in the memory path (0x80233290 before the handler @0x80c1c340, 0x802ba220 inside it @0x80c2082a); those functions are ABSENT from the image (int3), so the calls are removed rather than answered (jmp short +3 at the caller; jmp 0x80c20f98 = the shared bail inside the handler) + P30/S-30 S4 preserved-physmap kernel-text removal check skipped @0xffffffff80c1c6af (the 6-byte je after FUN_80c1b030 returned 0 -> 6x nop, so control falls through to 0x80c1c6b5; the check's FAILURE is ignored - the preserved map may be WRONG, only S4/hibernate consumes it; the table's later reader FUN_80bcee70 guards on index >= 0, as does the INFO printer FUN_80c1b310, so a -1 index is skipped, not walked) + P34/S-35 full-block code-absent ret-0 mass-batch (286 more int3 targets across [0x80210090-0x80450d8b]; 314/315 non-fatal stubbed per gate23-fullblock audit, FATAL 0x80422570 off-path left int3) + P33/S-34 process_fork-cluster code-absent VOID ret-0 stubs (26x 31c0c3 at audited-void int3 targets 0x8023e000-0x8023fa30; CONSUMED targets 0x8023e4c0,e9b0,f5f0,f6a0 FLAGGED NOT-stubbed) + P32/S-33 TIER-A code-absent ret-stubs (xor eax,eax;ret at 12 int3 targets 0x802c9880,0x99e0,0x9af0,0x9b60,0x9c20,0x9c80,0x9ce0,0x9d60,0x9e00,0x9e90,0x9f50,0x9fb0) + P31/S-32 ACPI-MADT int3-hole tail-jmp skip @0xffffffff808c1886 (FUN_808c17a0 -> 0x802c9d60 is int3 fill = code absent, L-254; void side-effect-only call skipped, not answered) + S-36 ENV legacy-8259 quiesce (trampoline masks master+slave 8259 IMR=0xff before btext handoff = the quiesced-legacy-PIC state the PS5 boot chain delivers; QEMU's i8254 PIT is live and the kernel never programs the 8259, so without this mi_startup's enable-intr SYSINIT sti takes a phantom IRQ0 -> apic_get_interrupt=-1 -> vector 0xffffffff -> #GP past IDT; L-303) + P35/S-37 SMP IPI-gate install (forced-UP routes the SMP-init SYSINIT through the kernel's OWN cpu_mp_start FUN_80a96970 via je->nop @0x80d2c51e, installing IPI vectors 0xf6-0xfd incl 0xfb->handler 0x8045eec0 + zeroing the pending bitmap; jmp->ret @0x80d2c53f skips the MP-only AP-mem finalize FUN_808e6e20 that UP never runs; the PS5 is multi-core and the PSP/SEP subsystem sends a vector-0xfb self-IPI regardless of CPU count, so without this the self-IPI hit the rsvd stub -> Fatal trap 30; L-305) + P36/S-38 TEE/secure-video enable-gate REFUSE (NARROW lever: we are NOT claiming to be a PS5 and NOT fixing the SoC rev - the true source FUN_80b7b0c0->DAT_83dce530 is LEFT non-PS5 on purpose, broad blast radius): fallback tee-modevent gate store DAT_83e2f020 imm 1->0 @0x80c275f1 refuses ONE subsystem (secure-video/gc) for gate 3, machine honestly non-PS5 everywhere else; the tee mutex init before the store STILL RUNS (no uninit-global risk), only the gbase/secure-video attach is refused so FUN_80c264b0 skips gbase_allocate_dynamic_mmhub_vmid and never sx_xlocks the uninit 'gbase lock' 0x83dea458; COLLATERAL debt BY CHOICE: TEE/secure-video, HDCP, Blu-ray/BD, sceSbl/NpDrm and any TEE-session user are now absent - REVISIT at GPU/BD bring-up (L-315f) + P37/S-39 gc/gbase GPU-subsystem REFUSE at the lock-acquiring funnels (e9 @0x80bf8a10/0x80bfddc0/0x80bf3df0 -> stubs OVERWRITING the boot-dead gbase_initialize body @0x80bf2cf0, which is X-mapped on the same 2MB large page as the executing funnels and is never called without a GPU; MUST BE REVERTED at the GPU/VFIO+amdgps5 milestone - restore gbase_initialize + add real init): if DAT_83dea538==0 (no GPU BAR5 aperture, attach never ran) each returns its OWN native SCE error (0x804c0009/0x804c0003/0x804c0002) in eax BEFORE the sx_xlock/any MMIO; NO writes / NO logging this iteration (the stub page is read-only R-X; a writable once-flag was dropped to guarantee no write-fault - the boot advancing past the DCE hang is itself proof the guard fired); pre-inits NOTHING, fakes NOTHING; records the SHAPE of the GPU demand (which gc entries device-config reached), not a spec; 3 of 41 ext-reachable gbase funnels guarded (bounded iteration; v1 placement in the CC-hole @0x802b0000 hit a fault, relocated, L-315g) + P38/S-40 DCE display MODULE REFUSE at its modevent entry (e9 @FUN_808a14e0 -> stub @0x80bf2e00, also in the boot-dead X-mapped gbase_initialize body; REVERT at GPU milestone): if cmd(esi)==0 (MOD_LOAD) AND DAT_83dea538==0 (no GPU) -> return ENXIO(6), else original; module_register_init handles the nonzero MOD_LOAD return gracefully (runs MOD_UNLOAD cleanup, prints 'MOD_LOAD error', NO panic - mirrors 13.60 reaching DEVCONF with MOD_LOAD errors). ONE guard kills BOTH DCE gbase touches (the sx path FUN_80cf1b70 AND the power-gating rw-lock path FUN_80d04ee0 that hit the spin-lock wall). MODULE-LEVEL refusal = the convergent strategy (per-funnel P37 proven non-convergent: gbase lock FAMILY x consumers); keeps P36+P37 as defense-in-depth; pre-inits NOTHING (L-318) + P39/S-41 MP1/SMU CPU-power register-primitive REFUSE on NULL softc (e9 @0x80ead9c0/0x80eadb10/0x80eadc70 -> guard stubs @0x80bf2e40/0x80bf2e60/0x80bf2e80 in the boot-dead X-mapped gbase_initialize body; REVERT at firmware/VFIO milestone): the MP1 softc DAT_84033330 is NULL (its writer FUN_80eade00 never ran = absent MP1/SMU firmware, attribution VERIFIED independent of P36-38, L-321), so each primitive guards on [0x84033330]==0 BEFORE the NULL lock-acquire/deref and returns a no-response value (read-prim FUN_80ead9c0 -> 0 so mp1fw_waitmsg spins out then hangs up; write-prim FUN_80eadb10 -> void ret, no reg write; bapm-thunk FUN_80eadc70 -> 6 so _mp1_bapm_logging_init_intr reports MSI-alloc error) = reproduces 13.60's own MP1 fail-soft storm (mp1fw busy/already hangup/zeroed reg dump/_bapm_logging failed); answers the absent-device call (hv14/hv0a pattern), pre-inits NOTHING, fakes NO softc (a fabricated softc would feed kobj->real SMU MMIO and still fault); else (softc present) replays the displaced prologue and jmps back (L-321) + P40/S-42 gbase gc-register READ (FUN_80bf3570 -> eax 0) + WRITE (FUN_80bf43d0 -> skip write, void ret) helpers REFUSE on no-GPU DAT_83dea538==0 (e9 @0x80bf3570/0x80bf43d0 -> guard stubs @0x80bf2eb0/0x80bf2ee0 in the boot-dead X-mapped gbase_initialize body; REVERT at GPU/VFIO milestone): both helpers acquire the uninit gbase rw-lock 0x83dea4a0 then deref DAT_83dea538 (GPU BAR5 aperture ptr, NULL = no GPU); the guard tests [0x83dea538]==0 at ENTRY BEFORE the lock and supplies the absent-device value - reg reads return 0 (= 13.60's own zeroed MP1 reg dump) / reg writes are skipped - so the uninit rw-lock 0x83dea4a0 is never acquired; make-it-exist (answers the absent GPU register file), NOTHING nop'd, fakes NO aperture. REACHED here via the MP1 timeout/reg-dump handler FUN_80870d60 (unlocked by P39); FUN_80870d60 line 138 calls the WRITE sibling FUN_80bf43d0 with the read guard's own 0 so BOTH are guarded (audited). BLAST RADIUS (L-205 transparency): the read guard changes the return of ~1179 gc-register call sites across ~230 fns kernel-wide to 0 when GPU absent = the uniform no-GPU state; LATENT gbase siblings (FUN_80bf3a20/3640/35d0/...) NOT on the FUN_80870d60 path are left for next-boot walls (L-322) + P41/S-43 pcist MODULE REFUSE at its modevent FUN_806c9e20 (e9 @0x806c9e20 -> stub @0x80bf2f00, boot-dead X-mapped gbase_initialize body; REVERT at SoC-device-model/VFIO milestone): if cmd(esi)==0 (MOD_LOAD) -> return ENXIO(6) in eax (honest 'no SoC PCI bridge device' - pcist_load FUN_806c9e70 HARD-PANICS 'Not found soc pci bridge' because PS5 SoC PCI devices AMD 0x1022:0x13df/0x13e4 + Sony 0x104d:0x90eb 'titania f0' are categorically absent in QEMU -M pc), else replay the displaced prologue (push rbp;mov rbp,rsp;push rbx) + jmp 0x806c9e25; module_register_init FUN_8078e0d0 handles the nonzero MOD_LOAD return gracefully (prints 'MOD_LOAD (pcist) error 6', NO panic) = 13.60's NET state (13.60 reaches DEVCONF with pcist failing too, its incidental ENOMEM 12; we use the HONEST no-device code 6 not a faked memory failure); NOTHING nop'd, fakes NO device (L-323) + P42/S-44 av_control (AV/video/HDCP display) MODULE REFUSE at its modevent FUN_80682390 (e9 @0x80682390 -> stub @0x80bf2f20, boot-dead X-mapped gbase_initialize body; REVERT at GPU/VFIO/VBIOS milestone): if cmd(esi)==0 (MOD_LOAD) -> return ENXIO(6) in eax (honest 'av_control/GPU-display absent' - with no GPU/VBIOS the VBIOS-ROM parser FUN_80e3a730 never runs, so the 'gbase vbios lock' sx 0x8402b9f0 is left uninit (lo_name 0, state 0x4 EXCL_WAITERS/no-owner) and av_control's FUN_80682580/FUN_805367b0 chain sx_xlocks it via FUN_80e3aaf0 -> thread0 sleeps forever, L-327), else replay the displaced prologue (push rbp;mov rbp,rsp;push rbx) + jmp 0x80682395; module_register_init FUN_8078e0d0 handles the nonzero MOD_LOAD return gracefully (same loader as P38 DCE-6 / P41 pcist-6, NO panic) = 13.60's NET state (13.60 reaches DEVCONF with the whole GPU/display/HDCP stack failing - dce/hdmi/hdcp/vcn/sdma - and without av_control); NOTHING nop'd, fakes NO device, pre-inits NOTHING (L-327) + P43/S-45 sbl_sm_service (Secure Boot Loader) MODULE REFUSE at its modevent FUN_807ad780 (e9 @0x807ad780 -> stub @0x80bf2f40, boot-dead X-mapped gbase_initialize body; REVERT at secure-processor/BD bring-up): v2 COMPLETE modevent replacement (never re-enters the real FUN_807ad780 - no replay, no jmp-back): if cmd(esi)==0 (MOD_LOAD) -> ENOTSUP(45) in eax (= 13.60's own sbl err45, honest 'no secure-processor' - with no SBL/secure-processor HW the SBL driver core never sx_init's its msg-handler registry sx 0x83739fd8, so the real _sceSblSmServiceIoInitialize -> sceSblDriverRegisterMsgHandler sx_xlocks the uninit lock -> wedge, L-328); ALL OTHER cmds (MOD_UNLOAD/quiesce/shutdown) -> 0 no-op (a refused module has NOTHING to unload/finalize - 0 = 'nothing to unload' is correct FreeBSD module semantics, NOT a fake). v1 replayed the 6-byte prologue for cmd!=0, which let module-unload-on-failure run sbl's real sm_service_finalize FUN_80540160 on the never-loaded module -> wedge on uninit MUTEX 0x83b5c310 (C-052); v2 never runs sbl's real body so that mutex is never touched. module_register_init FUN_8078e0d0 handles the nonzero MOD_LOAD return gracefully (same loader as P38 DCE-6 / P41 pcist-6 / P42 av_control-6, NO panic) = 13.60's NET state (DEVCONF with sbl_sm_service error 45); P36 already flags sceSbl/NpDrm absent collateral; NOTHING nop'd, fakes NO device, pre-inits NOTHING (L-328) + P44/S-46 cam/sceCameraDriver MODULE REFUSE at modevent FUN_80ccea00 (e9 @0x80ccea00 -> stub @0x80bf2f50, boot-dead X-mapped gbase_initialize body; REVERT at GPU/VFIO milestone): COMPLETE modevent replacement (P43-v2 pattern, NEVER re-enters the real body - no replay/no jmp-back): if cmd(esi)==0 (MOD_LOAD) -> ENOTSUP(45) in eax (module's own default = honest 'no camera/GPU', NOT a faked err12 memory-failure); ALL OTHER cmds -> 0 no-op (a refused module has nothing to unload; re-entering the real MOD_UNLOAD would run eventhandler_deregister on uninit state). WHY (analyst-settled L-332): with no GPU our P37/S-39 gbase refuse makes the camera's SceCameraDriverMain kthread (FUN_80ccf200, spawned ONLY by the MOD_LOAD branch via kthread_add) call gbase_map_to_vmid0 FUN_80bf8a10 -> 0x804c0009, and the error-cleanup tears down 4 isoc bufs via FUN_80e34ad0 with NO NULL-check -> buf1=NULL -> pmap_enter(kernel_pmap, va=0) -> pmap_enter_pde panic (C-053); refusing MOD_LOAD stops the kthread_add so the GPU-map never runs. module_register_init FUN_8078e0d0 handles the nonzero MOD_LOAD return gracefully (same loader as P38/P41/P42/P43, NO panic) = 13.60's NET state (DEVCONF with cam failing MOD_LOAD error 12 early @oracle 1255); honest GPU-absent collateral, recurring GPU-buffer-cleanup class, NOTHING nop'd, fakes NO device, pre-inits NOTHING (L-333) + P45/S-47 SIE-IOMMU NULL-softc GUARD at the PASID-bind device-config SYSINIT FUN_80741090 (e9 @0x80741090 -> stub @0x80bf2f60, boot-dead X-mapped gbase_initialize body; REVERT at SoC/IOMMU-model milestone): the SIE-IOMMU global softc *(0xffffffff83783a70)=NULL (absent IOMMU/northbridge HW, S-20), and this SYSINIT's sie_iommu_bind_pasid FUN_80701980 UNCONDITIONALLY _mtx_lock_sleeps softc+0xa8 (mtx_lock word; lock_object base softc+0x90) -> NULL-base uninit-mutex turnstile-wait forever = the pre-DEVCONF wedge (L-335, C-054); SAME NULL/uninit-base-lock disease as MP1(P39)/gbase/sbl, now a mutex. Guard tests [0x83783a70]==0 at ENTRY (cmp qword[0x83783a70],0, sign-extended disp32 = P39 pattern): if NULL (no IOMMU) -> ret, the whole PASID-bind SYSINIT does nothing (mi_startup ignores SYSINIT returns) so the NULL lock is never acquired; else (softc present) replay the displaced prologue (push rbp;mov rbp,rsp;push rbx) + jmp 0x80741095. GUARDED THE SYSINIT not bind_pasid because bind_pasid's sole caller (this SYSINIT) PANICS on a nonzero return (test eax,eax;jne->panic FUN_80ec8050;ud2) and a 0-return would need a fabricated pasid at *param_2 -> guarding the SYSINIT avoids both the panic and the fake. fakes NOTHING, pre-inits NO softc (a fabricated softc would feed real IOMMU MMIO and refault). 13.60 reaches DEVCONF with its SIE-IOMMU softc non-NULL (HW present, no iommu/pasid oracle line), so skipping this SYSINIT when the HW is absent is 13.60-faithful (L-336) + P46/S-48 UMC (AMD Unified Memory Controller) module CONDITIONAL REFUSE at modevent 0x80b906f0 (e9 @0x80b906f0 -> stub @0x80bf2f80, boot-dead X-mapped gbase_initialize body; REVERT at AMD-UMC/northbridge-model milestone): the UMC init FUN_80b90710 calls FUN_805082f0(0,0,0) (find PCI dev seg0/bus0/slot0/fn0 in Sony registry DAT_830a8df0); NULL -> HARD-PANIC 'UMC: BSF(0:0:0) is not found'. On q35 DAT_830a8df0==0 (registry EMPTY at UMC-modload, live-confirmed park RnouJD; AMD northbridge/UMC absent on Intel MCH). Guard: MOD_LOAD(esi==0) & DAT_830a8df0==0 -> ENXIO(6); else run the real init (bare q35/-M pc populated-registry UNCHANGED = baseline-safe); non-MOD_LOAD replicates original modevent (MOD_UNLOAD->0, other->0x2d). module_register_init handles the nonzero MOD_LOAD gracefully (same loader as P38/P41-P44, NO panic); answers the absent-device call (P41/P45 pattern), fakes NO device, pre-inits NOTHING (L-371) + S-55/kenv (L-391/L-392/L-394): meta tag 0x8006 MODINFOMD_ENVP carries a static kenv (physical ptr PA 0x40940A0 into the copied module metadata, relocated by FUN_80c19880 into the KVA self-remap window): hint.icc.0.msi=0 + hint.hpet_pci.0.msi=0 (+hint.hpet.0.msi=0 insurance) make icc take legacy rid-0 and the Belize HPET skip pci_alloc_msi (clears the s135 'icc unknown device 17' classifier panic; icc then benignly 'Can't allocate IRQ' ret 12, HPET continues to et-registration). NOT a hardware fake: boot env vars the real PS5 loader supplies. s136 proved the env must sit INSIDE the walked TLV region (as carrier tag 0x8F00's payload before the terminator) or the kernel reclaims/zeroes it past [modulep,terminator+8) before device-attach + S-56/HPET-enable (L-396): the trampoline sets QEMU HPET CONFIG PA 0xFED00010 bit0=ENABLE in 32-bit flat mode (we are the firmware; HPET resets disabled) so the Belize hpet_pci liveness double-read of MAIN_COUNTER sees it incrementing -> the quality-950 HPET eventtimer registers -> no 'failed to find a polling timer' panic ; register: LEDGER.md 11 (S-01..S-30, S-32, S-33, S-34, S-35, S-36, S-37, S-38, S-39, S-40, S-41, S-42, S-43, S-44, S-45, S-46, S-47, S-48, S-55, S-56; S-31 is the gdb-side MPERF/APERF inject; the S-24 entry is OWED)", 10, 0
    s_selfbad: db "PS5-TRAMP-1422: FATAL self-handle KVA out of kernel-KVA window!", 10, 0
; L-120: 64-bit out test markers
s_k64a:  db "K64A: ", 0
s_k64b:  db "K64B: ", 0
; L-121: 64-bit OUT-encoding test markers (one char each)
s_t1:    db "A", 0
s_t2:    db "B", 0
s_t3:    db 0                      ; L-184 P12: T3 disabled — E7 ib truncates
                                    ; 'out 0x408,eax' to port 0x08 (8259 PIC
                                    ; master): the test could never work and its
                                    ; 'C' write corrupted QEMU's PIC state.
                                    ; L-238: the loop body is now the DX form
                                    ; (`mov dx,0x408; out dx,al`, size-neutral),
                                    ; so re-enabling is safe; it stays 0 because
                                    ; T1 ("A") and the now-working k64puts labels
                                    ; already prove the 8-bit DX path on every
                                    ; boot — a third marker adds no information.
s_ptdbg: db "PT-VERIFY:", 0
s_pt1:   db " PML4[1FF]=", 0
s_pt2:   db " PDPT_KVA[1FE]=", 0
s_pt3:   db " PDPT_KVA[1C0]=", 0
s_pt4:   db " PD_KVA[1]=", 0
s_pt5:   db "/", 0
s_pt6:   db " PD_KVA[2]=", 0
s_pt7:   db " PD_DMAP[1]=", 0
s_pt8:   db " PML4[1FC]=", 0
s_pt9:   db " PDPT_UNIV[0]=", 0
s_pt10:  db " PDPT_KVA[0]=", 0

section .text
global _start

; --- tiny helpers (32-bit) ---
putc:
    ; al = char
    mov dx, DBGCON
    out dx, al
    ret
puts:
    ; esi = NUL-terminated
    push esi
    push eax
.l: lodsb
    test al, al
    jz .d
    call putc
    jmp .l
.d: pop eax
    pop esi
    ret
puthex32:
    ; eax = value
    push eax
    push ebx
    push ecx
    mov ebx, eax
    mov ecx, 8
.l: rol ebx, 4
    mov al, bl
    and al, 0x0F
    cmp al, 10
    jb .dig
    add al, 'A'-10
    jmp .o
.dig: add al, '0'
.o: call putc
    loop .l
    pop ecx
    pop ebx
    pop eax
    ret

_start:
    cli
    cld
    mov esp, tramp_stack_top
    mov [mbi_ptr], ebx

    lgdt [gdtdesc]
    mov ax, 0x10
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov fs, ax
    mov gs, ax
    mov eax, 0x08
    push eax
    push dword .flush
    retf
.flush:

    mov esi, s_boot
    call puts

    ; ---------------- locate the kernel module ----------------
    test dword [ebx], 8            ; mbi flags bit3: mods valid
    jz no_mod
    mov ecx, [ebx + 20]            ; mods_count
    test ecx, ecx
    jz no_mod
    mov edx, [ebx + 24]            ; mods_addr
    mov esi, [edx]                 ; mod_start
    mov edi, [edx + 4]             ; mod_end
    sub edi, esi                   ; length
    mov [mod_start], esi
    mov [mod_len], edi
    cmp edi, KERN_SIZE
    jne bad_len

    ; ---------------- copy kernel image to KERN_PHYS ----------------
    ; overlap-safe direction select
    mov eax, esi
    add eax, edi                   ; src_end
    cmp eax, KERN_PHYS             ; src_end <= dst_start -> forward
    jbe .fwd
    mov eax, KERN_PHYS
    add eax, edi                   ; dst_end
    cmp eax, esi                   ; dst_end <= src_start -> forward
    jbe .fwd
    ; backward copy
    mov ecx, edi
    shr ecx, 2
    mov eax, [mod_start]
    add eax, edi
    mov esi, eax
    sub esi, 4
    lea edi, [KERN_PHYS + KERN_SIZE - 4]
    std
    rep movsd
    cld
    jmp .copied
.fwd:
    mov esi, [mod_start]
    mov edi, KERN_PHYS
    mov ecx, [mod_len]
    shr ecx, 2
    rep movsd
.copied:

    ; ---------------- apply boot patches ----------------
    mov dword [pcount], PATCH_COUNT
    mov esi, patch_table
.ploop:
    lodsd                          ; image (flat) offset
    mov edx, eax
    add edx, KERN_PHYS             ; target phys
    lodsd                          ; len
    mov [plen], eax
    mov ecx, eax
    mov edi, edx                   ; verify target
    push esi
    push ecx
.vloop:
    lodsb
    cmp al, [edi]
    jne .pmismatch
    inc edi
    loop .vloop
    pop ecx
    pop esi
    add esi, [plen]                ; skip expect[] -> esi at new[]
    mov edi, edx
    mov ecx, [plen]
.wloop:
    lodsb
    mov [edi], al
    inc edi
    loop .wloop
    dec dword [pcount]
    jnz .ploop
    jmp .patches_done
.pmismatch:
    mov esi, s_pat
    call puts
    mov eax, edx
    call puthex32
    mov esi, s_nl
    call puts
    cli
    hlt
.patches_done:

    ; ---------------- write phys params (incl. contract words) ----------------
    mov edi, 0x9B000
    mov ecx, 0x1000 / 4
    xor eax, eax
    rep stosd
    mov esi, param_table
    mov ecx, PARAM_COUNT
.par_loop:
    push ecx
    lodsd                          ; phys
    mov edi, eax
    lodsd                          ; len
    mov ecx, eax
.pbloop:
    lodsb
    mov [edi], al
    inc edi
    loop .pbloop
    pop ecx
    loop .par_loop
    mov dword [0x472], 0           ; cold-boot warm flag

    ; ---------------- hide ACPI RSDP from the kernel ----------------
    xor eax, eax
    mov ax, [0x40E]
    shl eax, 10
    mov [ebda_base], eax
    mov dword [rsdp_count], 0
    mov eax, [ebda_base]
    mov ecx, 0x400
    call rsdp_scan
    mov eax, 0xE0000
    mov ecx, 0x20000
    call rsdp_scan

    ; ---------------- S-56: enable the QEMU HPET main counter (L-396) ----------------
    ; The HPET (QEMU q35 @ PA 0xFED00000, aliased into belize-hpet BAR4+0x182000)
    ; resets with HPET_CFG_ENABLE=0 (HPET spec: firmware enables it). The Belize
    ; hpet_pci attach FUN_80e72700 does a liveness double-read of MAIN_COUNTER
    ; (regs+0xF0) across DELAY(1); a frozen (disabled) counter -> "HPET never
    ; increments, disabling" -> the quality-950 HPET eventtimer never registers
    ; -> "failed to find a polling timer" panics (L-396/L-397, owner+coordinator).
    ; We ARE the firmware: set CONFIG (PA 0xFED00010) bit0=ENABLE (bit1 LEGACY=0
    ; => IOAPIC mode, L-389) here in 32-bit FLAT mode (paging off => direct
    ; physical MMIO, no mapping dependency), so the counter is already running
    ; when the driver reads it. Observable: SYNTH line + CONFIG/counter readable
    ; at park. S-56, LEDGER.md 11.
    mov dword [0xFED00010], 1

    ; ---------------- MODULEP page: TLV module table (L-123/L-124) ----------------
    ; 14.22 kernel walks this stream (lookup 0x80e6f8f0: tag1 name-hdr, tag2
    ; filename, tag3 addr; end {0,0}) to find its own module "elf64 kernel".
    ; v1: zero the page, then copy the meta blob at offset 0.
    mov edi, MODULEP
    mov ecx, 0x1000 / 4
    xor eax, eax
    rep stosd
    mov esi, meta1422_blob
    mov edi, MODULEP
    mov ecx, META1422_LEN
.m1422:
    lodsb
    mov [edi], al
    inc edi
    loop .m1422

    ; ---------------- SELF-handle value block (L-147, boot 9; L-164 fix) ----
    ; The kernel's module init panics when its own handle (field 0x9001) is
    ; NULL (L-145: "missing the kernel module handle of kernel itself.").
    ; L-164: the consumers' arithmetic (F1 epilogue: value - KVA_base +
    ; 0xffffff8000000000) requires VALUE01's u64 to be the KVA of the zero
    ; record region (PA 0x4094800 -> KVA 0xFFFFFFFF84094800), NOT a DMAP VA
    ; (the old DMAP-window model, L-155, was wrong; our DMAP window is
    ; identity via PD_KVA so the result maps to PA 0x4094800 either way).
    ; The W3v3 getter returns KVA 0xFFFFFFFF84094820 (= this u64's own
    ; address) for field 0x9001; the size dword sits at VALUE01-4 per the
    ; {field_id,size,value} entry contract the consumers expect.
    mov edi, MODULEP + 0x800
    mov ecx, 32 / 4
    xor eax, eax
    rep stosd                       ; zero record region (32 B)
    mov dword [MODULEP + 0x81C], 0x20          ; size field (VALUE01 - 4)
    ; L-172 (boot 47): KVA(recs) = KVA_BASE 0xFFFFFFFF80000000 + PA 0x4094800
    ; = 0xFFFFFFFF84094800 (PDPT_KVA[0x1FE] kernel-KVA window, PD_KVA[0x20] ->
    ; PA 0x4094800). The old low word 0xC0948000 = KVA_BASE + PA 0x40948000
    ; (author used a PA 16x too large) -> walked PDPT_KVA[0x1FF] (unmapped) -> #PF.
    ; Derive low32 from the PA symbol so a stale magic constant can't regress.
    mov eax, MODULEP + 0x800                   ; PA of the 32-B record region
    or  eax, 0x80000000                        ; + KVA_BASE low (PA<0x80000000 -> no carry)
    mov dword [MODULEP + 0x820], eax           ; KVA(recs) low  (= 0x84094800)
    mov dword [MODULEP + 0x824], 0xFFFFFFFF    ; KVA(recs) high (canonical)
    ; regression guard: the KVA must sit in the kernel-KVA window PDPT_KVA[0x1FE]
    ; (low32 in [0x80000000,0xC0000000) under high32 0xFFFFFFFF). Landing in the
    ; unmapped 0x1FF window (low32 >= 0xC0000000) is the early-mDBG #PF class.
    mov eax, [MODULEP + 0x820]
    mov ebx, [MODULEP + 0x824]
    cmp ebx, 0xFFFFFFFF
    jne .selfbad
    cmp eax, 0x80000000
    jb  .selfbad
    cmp eax, 0xC0000000
    jae .selfbad
    jmp .selfok
.selfbad:
    mov esi, s_selfbad
    call puts
    cli
    jmp $
.selfok:

    ; ---------------- build initial page tables (L-177: universal fill) -------
    mov edi, PML4
    mov ecx, (PT_END - PML4) / 4
    xor eax, eax
    rep stosd
    ; L-177 (boot 51): boot-50's wall was PML4[0x1FC] = 0 — the kernel's
    ; 64-bit DMAP window 0xffff800000000000+PA (the real PS5 DMAP base)
    ; projects there under BOTH walk semantics (see header). Map EVERY PML4
    ; slot to a valid PDPT and EVERY PDPT slot to a valid identity PD page,
    ; so no VA can #PF on a missing table entry (only on device PAs beyond
    ; guest RAM = Tier-2).
    mov eax, PDPT_UNIV | 3
    mov ecx, 512
    mov edi, PML4
.pml4u: mov [edi], eax
    add edi, 8
    loop .pml4u
    mov dword [PML4 + 0],            PDPT_ID | 3
    mov dword [PML4 + KVA_PML4I*8],  PDPT_KVA | 3
    mov dword [PML4 + DMAP_PML4I*8], PDPT_11C | 3
    ; all four PDPTs: 512 entries -> PD_ID (the universal identity PD table)
    mov eax, PD_ID | 3
    mov ecx, 512
    mov edi, PDPT_ID
.pdu1:  mov [edi], eax
    add edi, 8
    loop .pdu1
    mov ecx, 512
    mov edi, PDPT_KVA
.pdu2:  mov [edi], eax
    add edi, 8
    loop .pdu2
    mov ecx, 512
    mov edi, PDPT_11C
.pdu3:  mov [edi], eax
    add edi, 8
    loop .pdu3
    mov ecx, 512
    mov edi, PDPT_UNIV
.pdu4:  mov [edi], eax
    add edi, 8
    loop .pdu4
    ; window specials (content-identical PD tables; kept for the PT-VERIFY
    ; lines and the L-172 self-handle walk through PDPT_KVA[0x1FE])
    mov dword [PDPT_KVA + KVA_PDPTI*8],       PD_KVA | 3
    mov dword [PDPT_KVA + DMAP1422_PDPTI*8],  PD_DMAP | 3
    ; PD fill: 512 entries of 2MB pages. low = i*2MB|0x83 (P|RW|US),
    ; high = 0x200000 (PS, bit52) — PS MUST be set or entries are 4KB PTEs
    ; and kernel text fetch #PFs (13.60 source had this bug; its final kit
    ; fixed it via WP11 mmap_fix in a later trampoline build).
    mov edi, PD_ID
    mov eax, 0x83
    mov ecx, 512
.pdid:  mov [edi], eax
    mov dword [edi+4], 0x200000
    add eax, 0x200000
    add edi, 8
    loop .pdid
    mov edi, PD_KVA
    mov eax, 0x83
    mov ecx, 512
.pdkva: mov [edi], eax
    mov dword [edi+4], 0x200000
    add eax, 0x200000
    add edi, 8
    loop .pdkva
    mov edi, PD_DMAP
    mov eax, 0x83
    mov ecx, 512
.pddm:  mov [edi], eax
    mov dword [edi+4], 0x200000
    add eax, 0x200000
    add edi, 8
    loop .pddm

    ; ---------------- L-170 (boot 34): PA 0xf0000-0x100000 ROM -> zeroed RAM -----
    ; Boot 34 FAULTSITE dump: kernel derefs rsi=0xf000ff53f000ff53 = two adjacent
    ; QEMU cpu-reset IDT gates (seg 0xf000, off 0xff53) read as a qword from PA
    ; 0xf0000 via the identity mapping -> non-canonical -> #GP -> silent slot-9
    ; handler -> infinite bounce. On real PS5 hw, 0xf0000 is plain DRAM left by
    ; the boot ROM with loader handoff records; in QEMU the pc-bios ROM owns
    ; 0xc0000-0x100000. Split 2MB PS page 0 of PD_ID/PD_KVA into 4KB PTEs:
    ; identity for 0x0-0xef000, zeroed 1MB scratch for 0xf0000-0x100000.
    mov edi, PT_LOW
    mov ecx, 1024
    xor eax, eax
    rep stosd                        ; zero PT page (RAM is fresh, belt & braces)
    mov edi, ROM_SCRATCH
    mov ecx, 0x100000 / 4
    rep stosd                        ; zero the 1MB handoff scratch
    mov edi, PT_LOW
    mov ecx, 1                    ; page 0x00 (PA 0-0xfff): QEMU ROM alias / reset-IDT
    mov eax, ROM_SCRATCH          ; (L-171: same class of bug as 0xf0000 — the kernel
    or eax, 0x83                  ; reads its per-CPU root via gs:[0] with gs base 0)
.pdrom0: mov [edi], eax
    add edi, 8
    loop .pdrom0
    mov ecx, 0xEF                 ; pages 0x01..0xEE: identity 4KB
    mov eax, 0x1083
.pdlow: mov [edi], eax
    add eax, 0x1000
    add edi, 8
    loop .pdlow
    mov ecx, 256                     ; pages 0xF0..0x10F -> ROM_SCRATCH (zero)
    mov eax, ROM_SCRATCH
    or eax, 0x83
.pdrom: mov [edi], eax
    add eax, 0x1000
    add edi, 8
    loop .pdrom
    mov dword [PD_ID + 0],  PT_LOW | 3
    mov dword [PD_ID + 4],  0        ; MUST clear PS bit left by the 2MB fill!
    mov dword [PD_KVA + 0], PT_LOW | 3
    mov dword [PD_KVA + 4], 0
    ; same for the DMAP window (the PD_11C page is now PDPT_UNIV — do NOT touch it)
    mov dword [PD_DMAP + 0], PT_LOW | 3
    mov dword [PD_DMAP + 4], 0

    ; L-214 -> L-217 (P22, boot 78): TRAP-SAFE low-panic stub for the kernel's
    ; fatal drop to VA 0x20. This code runs in 32-bit FLAT mode BEFORE the CR3
    ; load (line ~573) — paging is off, so the bare copy lands at PA 0x20,
    ; which NO kernel domain maps (both domains map VA 0x0-0x1000 elsewhere).
    ; Boot 77 proved the consequence: the fatal drop executed PT_LOW PTE
    ; garbage (PA 0x4097020) as code -> trample -> nested #DF.
    ; P22: write the identical stub to EVERY PA a kernel domain resolves
    ; VA 0x20 to:
    ;   PA 0x4100020 — trampoline/P13-prefill domain: PD_ID[0]=PT_LOW (4K),
    ;                  PT_LOW[0]=ROM_SCRATCH (0x4100000)
    ;   PA 0x4097020 — kernel-refill domain: PD_ID[0]=2MiB PS @ 0x4097000
    ;                  (the kernel's stage-2 pmap refills the inherited PD_ID
    ;                  page in place, restoring the 2MiB-PS slot0 form)
    ; All three targets are < 4GB: plain 32-bit physical stores. The stub:
    ; pushfq; or eax,3 (IOPL=3 — a CPL3/IOPL0 drop can no longer #GP itself
    ; into the DF chain); popfq; mov ax,0x408; out 'L'; out '0'; cli; hlt;
    ; jmp hlt — deterministic park printing 'L0' once on the 0x408 debugcon.
    ; NOTE: the 0x4097020 copy clobbers PT_LOW PTE slots 2-4 (VA 0x2000-
    ; 0x6FFF of the 4K window) — unused by kernel/trampoline (record S-22).
    mov edi, 0x20                   ; legacy bare-PA copy (unreachable by kernel)
    mov dword [edi+0],  0x0003059c    ; pushfq; or eax,3 (05 03 00 00
    mov dword [edi+4],  0x669d0000    ; 00); popfq; (66)
    mov dword [edi+8],  0xb00408b8    ; mov ax,0x408 (66 b8 08 04); mov al,
    mov dword [edi+12], 0x30b0ee4c    ; 'L'; out dx,al; mov al,'0'
    mov dword [edi+16], 0xebf4faee    ; (b0 30); out dx,al; cli; hlt; (eb
    mov byte  [edi+20], 0xfd          ; fd -> hlt)
    mov dword [edi+21], 0             ; padding after the loop (never run)
    ; P22: same stub at the trampoline-domain VA 0x20 home
    mov edi, 0x4100020
    mov dword [edi+0],  0x0003059c
    mov dword [edi+4],  0x669d0000
    mov dword [edi+8],  0xb00408b8
    mov dword [edi+12], 0x30b0ee4c
    mov dword [edi+16], 0xebf4faee
    mov byte  [edi+20], 0xfd
    mov dword [edi+21], 0
    ; P22: same stub at the kernel-refill-domain VA 0x20 home
    mov edi, 0x4097020
    mov dword [edi+0],  0x0003059c
    mov dword [edi+4],  0x669d0000
    mov dword [edi+8],  0xb00408b8
    mov dword [edi+12], 0x30b0ee4c
    mov dword [edi+16], 0xebf4faee
    mov byte  [edi+20], 0xfd
    mov dword [edi+21], 0

    mov esi, s_done
    call puts
    mov esi, s_synth
    call puts

    ; ---------------- PT verification (debug) ----------------
    mov esi, s_ptdbg
    call puts
    mov esi, s_pt1
    call puts
    mov eax, [PML4 + KVA_PML4I*8]
    call puthex32
    mov esi, s_pt2
    call puts
    mov eax, [PDPT_KVA + KVA_PDPTI*8]
    call puthex32
    mov esi, s_pt3
    call puts
    mov eax, [PDPT_KVA + DMAP1422_PDPTI*8]
    call puthex32
    mov esi, s_pt4
    call puts
    mov eax, [PD_KVA + 1*8]            ; entry for PA 0x200000 (kernel start)
    call puthex32
    mov esi, s_pt5
    call puts
    mov eax, [PD_KVA + 1*8 + 4]        ; high dword: 00200000 = PS set
    call puthex32
    mov esi, s_pt6
    call puts
    mov eax, [PD_KVA + 2*8]          ; entry for PA 0x400000 (kernel body)
    call puthex32
    mov esi, s_pt7
    call puts
    mov eax, [PD_DMAP + 1*8]
    call puthex32
    mov esi, s_pt8
    call puts
    mov eax, [PML4 + 0x1FC*8]
    call puthex32
    mov esi, s_pt9
    call puts
    mov eax, [PDPT_UNIV + 0]
    call puthex32
    mov esi, s_pt10
    call puts
    mov eax, [PDPT_KVA + 0]
    call puthex32
    mov esi, s_nl
    call puts

    ; ---------------- enter long mode ----------------
    mov eax, cr4
    or eax, 0x20                   ; PAE
    or eax, 0x200                  ; OSFXSR (L-168: needed so fxsave releases TS)
    mov cr4, eax
    mov eax, PML4
    mov cr3, eax
    mov ecx, 0xC0000080            ; EFER
    rdmsr
    or eax, 0x100                  ; LME
    wrmsr
    ; L-168 (boot 32): the real PS5 boot ROM hands the kernel an AVAILABLE FPU
    ; (state in RAM, CR0.TS=0, MP/EM cleared). QEMU TCG keeps forcing CR0.TS=1
    ; ("FPU busy") until the guest has FXSAVED; the kernel's btext path then
    ; RMW's CR0 (NE|WP|PG) and inherits MP|EM|TS=0x80010031 -> first x87/SSE
    ; in machine_init -> #NM -> generic trap-logger handler (IDT slot 9) ->
    ; infinite bounce (boots 27-31). fxsave hands the FPU state to "memory",
    ; clearing TS; then pin CR0 to the kernel's own start: value.
    fxsave [0x4095000]             ; 512 B scratch, free region (L-109 layout)
    mov eax, cr0
    and eax, 0xfffffff1            ; clear MP|EM|TS (TS already 0 post-fxsave)
    or  eax, 0x80010021            ; PE|NE|WP|PG = kernel start: CR0 (L-167)
    mov cr0, eax
    jmp 0x18:long_mode

; ---- rsdp_scan: eax=base, ecx=len — corrupts 'RSD PTR ' signatures ----
rsdp_scan:
    push eax
    push ecx
    push esi
    mov esi, eax
    test ecx, ecx
    jz .done
.l:
    cmp dword [esi], 0x20445352           ; 'RSD '
    jne .next
    cmp dword [esi + 4], 0x20525450       ; 'PTR '
    jne .next
    mov byte [esi], 0
    inc dword [rsdp_count]
.next:
    inc esi
    dec ecx
    jnz .l
.done:
    pop esi
    pop ecx
    pop eax
    ret

no_mod:
    mov esi, s_nomod
    call puts
    cli
    hlt
bad_len:
    mov esi, s_len
    call puts
    mov eax, [mod_len]
    call puthex32
    mov esi, s_nl
    call puts
    cli
    hlt

; ---------------- 64-bit part ----------------
[bits 64]
long_mode:
    mov ax, 0x10
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov fs, ax
    mov gs, ax

    ; L-183: zero-init .bss one-shot flags (RAM is not zeroed; graft_flag
    ; held garbage so the P8 oracle was skipped in boots 58/59).
    mov     dword [graft_flag], 0

    ; L-120: 64-bit out test — marker BEFORE gs-base wrmsrs
    mov esi, s_k64a
    call k64puts

    ; ---------------- loader contract: EARLY GS BASE (fake pcpu) ----------------
    ; The Sony loader sets GS base before kernel entry; machine_init re-sets it to
    ; the real per-CPU shortly after. Everything before that (cpu-init hook,
    ; stats counters) reads gs:[0]/[0x10]/[0x20].
    ; Fake pcpu @ phys 0x99000 (KVA 0xffffffff80099000), 8KB scratch, zeroed:
    mov rdi, 0x99000
    mov ecx, 0x2000 / 8
    xor eax, eax
    rep stosq
    mov rax, 0xffffffff80099a00         ; fake thread (curthread)
    mov [qword 0x99000], rax
    mov rax, 0xffffffff8009aa00         ; fake proc (curproc)
    mov [qword 0x99010], rax
    mov rax, 0xffffffff80099000         ; curpcpu = self
    mov [qword 0x99020], rax
    mov ecx, 0xC0000101                 ; MSR_GS_BASE
    mov eax, 0x80099000
    mov edx, 0xffffffff
    wrmsr
    mov ecx, 0xC0000102                 ; MSR_KERNEL_GS_BASE
    xor eax, eax
    xor edx, edx
    wrmsr

    ; L-120: marker AFTER gs-base wrmsrs (tests if wrmsr breaks 64-bit out)
    mov esi, s_k64b
    call k64puts

    ; L-121: 64-bit OUT encoding test (each = one marker char to port 0x408)
    ; T1 "A" = EE  out dx,al    (the exact opcode that worked in 32-bit mode)
    ; T2 "B" = E8  out dx,eax   (32-bit via DX; expect 4x 'B' if it works)
    ; T3 "C" = E9  out $0x408,eax (16-bit immediate port, no DX involved)
    cld
    mov esi, s_t1
    mov dx, 0x408
.t1: lodsb
    test al, al
    jz .t1e
    movzx eax, al
    out dx, al
    jmp .t1
.t1e:
    mov esi, s_t2
    mov dx, 0x408
.t2: lodsb
    test al, al
    jz .t2e
    movzx eax, al
    out dx, eax
    jmp .t2
.t2e:
    mov esi, s_t3
.t3: lodsb
    test al, al
    jz .t3e
    ; L-238: was `movzx eax,al` + `out 0x408,eax` (E7 08 = OUT imm8 to port
    ; 0x08, the 8259 PIC master, because the immediate port form truncates to
    ; 8 bits; the 4-byte OUT is also dropped by debugcon's 1-byte port, see
    ; k64puts above). Now the DX form, byte-for-byte size-neutral (5 bytes:
    ; mov dx,0x408 = 4, out dx,al = 1), so nothing after this block moves.
    mov     dx, 0x408
    out     dx, al
    jmp .t3
.t3e:
    ; L-184 P11: the out-of-line block below (graft64/hv14/hv0a) must NOT be
    ; reachable by fall-through: graft64's tail jmps into the kernel (map_tmr),
    ; which in boots 58-60 teleported the trampoline's linear flow into kernel
    ; code BEFORE the btext jump, contaminating every verdict since boot 58.
    ; --- L-303 S-36: mask the legacy 8259 PICs = supply the quiesced-legacy-PIC
    ; state the PS5 boot chain hands the kernel. QEMU's i8254 PIT is live and
    ; IRQ0 is unmasked at the SeaBIOS default (master pic0 imr=0xb8). mi_startup's
    ; enable-intr SYSINIT (sti @FUN_8070e130, called from FUN_8073f170) then takes
    ; a phantom IRQ whose apic_get_interrupt() returns -1 (LAPIC LINT0 ExtINT
    ; masked, IOAPIC unprogrammed) -> vector 0xffffffff -> #GP past the IDT limit
    ; (b114/b115, L-302). The kernel never programs the 8259 (imr stays 0xb8 to
    ; the fault), so this inherited all-masked state persists to the sti. CPL0,
    ; IF=0 here; ports <=0xff so the E6 imm8 OUT form is exact (no L-238 trunc).
    ; Observable: post-boot `info pic` shows master+slave imr=0xff. S-36 reg LEDGER 11.
    mov     al, 0xff
    out     0x21, al                 ; master 8259 OCW1 (IMR) = mask IRQ0-7
    out     0xa1, al                 ; slave  8259 OCW1 (IMR) = mask IRQ8-15
    jmp     btext_go

; L-180 P5: kernel-PML4 graft. The kernel switches CR3 to its own table which
; has holes (low-identity / DMAP slots zero) -> unfixable #PF storm. Merging
; the trampoline's universal PDPT pages into the kernel's ZERO PML4 slots
; gives it full coverage without touching its own entries. Run via the e9
; patch at map_tmr entry (first kernel-CR3 function we know runs); re-runs
; are harmless (only zero slots are filled). The e9 replaces bytes
; 0x804c3150-54 (push rbp;mov rbp,rsp;REX prefix of push r15); this routine
; re-does the skipped prologue and resumes at 0xffffffff804c3156 ('push r14').
graft64:
    push    rbp
    mov     rbp, rsp
; L-237 (b88) ARGUMENT PRESERVATION. map_tmr reads its three arguments from
; RDI/RSI/RDX after our e9 returns (= resumed 0x804c3156), but the oracle below
; destroys RSI (k64puts/hex8_ take their string in ESI) and the graft body
; executes `mov rdx, cr3`. Boot 87: (short)param_2 == 0 failed -> "unaligned
; addr 0x70010AF" (0x70010af is the operand of the oracle's last mov esi,...).
; Saved AFTER mov rbp,rsp and restored immediately before the tail `push r15`,
; so the reconstructed frame stays byte-exact. Frame at this point
; (R = RSP on entry, [R] = caller's return address):
;   [R]      = caller return address     [R-8]    = saved rbp   (RBP = R-8)
;   [R-0x10] = saved rdi                 [R-0x18] = saved rsi
;   [R-0x20] = saved rdx
; k64puts/hex8_ keep their own stack balanced (push/pop pairs), so these three
; slots never move and are read back with plain pops in reverse order.
    push    rdi
    push    rsi
    push    rdx
; L-181 P8: first-call oracle — report map_tmr args (tmrid/arg2/arg3) + the
; caller's return address (identifies the tmrid source) on console 0x408.
    mov     rax, [graft_flag]
    test    rax, rax
    jne     .g_oracle_done
    mov     dword [graft_flag], 1
    mov     r8,  [rbp+8]               ; caller return address (rbp-relative:
                                       ; [rsp+8] is now the saved rsi)
    mov     r9,  rdx                   ; arg3 (k64puts-safe copies)
    mov     r10, rsi                   ; arg2
    mov     r11, rdi                   ; arg1 = tmrid
    mov     esi, s_or1
    call    k64puts
    mov     rax, r11
    call    hex8_
    mov     esi, s_or2
    call    k64puts
    mov     rax, r10
    call    hex8_
    mov     esi, s_or3
    call    k64puts
    mov     rax, r9
    call    hex8_
    mov     esi, s_or4
    call    k64puts
    mov     rax, r8
    call    hex8_
    mov     esi, s_nl
    call    k64puts
.g_oracle_done:
    ; SEAM-FIX (boot 86 #PF): BOTH paths above (fast path via `jne` and the
    ; oracle path via fall-through) arrive here, and hex8_ is a SUBROUTINE
    ; that lives below this label. Without this jmp control fell straight
    ; into hex8_'s body, ran its `ret`, and popped the caller's saved RBP
    ; as RIP — boot 86: #PF e=0011 IP=CR2=0xffffffff82f80c30 = [rsp] at
    ; graft64 entry, RBP=0xffffffff82f80c10 (= RSP after push rbp).
    ; Same class as the hv14/hv0a warning above: out-of-line code must be
    ; reachable only by call/jmp (L-184 linear-flow rule).
    jmp     g_body
hex8_:                      ; rax = 32-bit value -> 8 hex chars (MSB first) on 0x408
; L-237 (b88): the old body was `shr rax,4 / mov eax,eax / and eax,0xf /
; shr eax,0x1c`, i.e. it ANDed the nibble to <=0xf and then shifted it RIGHT by
; 0x1c, so every digit was 0 and the oracle printed TMRCALL …tmrid=00000000.
; New body: keep a WORKING copy of the value on the stack, `rol` it left by 4
; each iteration (MSB nibble lands in EAX[3:0]) and print that nibble, using
; the same digit conversion as the 32-bit puthex32 above (`add al,'A'-10`).
; The OLD conversion was also off by one for A-F (`add al,6` after adding
; '0' = '0'+16 for digit 10 -> '@' instead of 'A'), so 0xFFFFFFFF would have
; printed EEEEEEEE even with the nibble fix. Eight rotations of a 32-bit value
; are the identity, so the caller's EAX is intact when we return; RCX and RDX
; (used by the realigned `mov dx,0x408; out dx,al` flush) are saved too, which
; is a superset of the old contract (it saved RCX only). R8/R9/R10/R11 are LIVE
; across these calls in graft64/hv14 and are not touched. Stack: push rax
; (orig), push rax (work), push rdx, push rcx -> 4 slots, popped in reverse;
; balanced, so graft64's saved-arg slots below the return address are untouched.
    push    rcx
    push    rdx
    push    rax                ; [rsp+8] = original value (restored on exit)
    push    rax                ; [rsp]   = working copy (rotated in place)
    mov     ecx, 8
.hexlp:
    mov     eax, [rsp]
    rol     eax, 4             ; MSB-first: top nibble -> bits 3:0
    mov     [rsp], eax
    and     eax, 0xf
    cmp     al, 10
    jb      .hexdig
    add     al, 'A'-10
    jmp     .hexo
.hexdig:
    add     al, '0'
.hexo:
    mov     dx, 0x408
    out     dx, al
    dec     ecx
    jnz     .hexlp
    pop     rax                ; drop the working copy
    pop     rax                ; restore the caller's value
    pop     rdx
    pop     rcx
    ret
g_body:
    mov     rdx, cr3                  ; current PML4 PA (CR3 access: rax/rcx/rdx/rbx only)
    ; L-187: nasm's elf32-REX mode encodes 64-bit immediates (B8+rd) as a 4-byte
    ; se32 PLUS 4 stray bytes (a hidden `add [rax+disp],al` garbage instruction).
    ; Use the low-identity window instead of the DMAP window: PD_ID maps PA==VA
    ; (2MB identity, 0..1TB) in BOTH domains (kernel domain gets it from P13's
    ; handoff prefill). Same physical pages, 32-bit-safe encodings.
    mov     r11, rdx                  ; kernel PML4 page via low-identity window
    mov     r10, 0x40a0000           ; trampoline PML4 page via low-identity window
    mov     r8,  [r10 + 0x000]         ; idx 0:    identity PDPT
    test    r8, r8
    je      .g0
    mov     r9,  [r11 + 0x000]
    test    r9, r9
    jne     .g0
    mov     [r11 + 0x000], r8
.g0:
    mov     r8,  [r10 + 0x008]         ; idx 1
    test    r8, r8
    je      .g1
    mov     r9,  [r11 + 0x008]
    test    r9, r9
    jne     .g1
    mov     [r11 + 0x008], r8
.g1:
    mov     r8,  [r10 + 0x010]         ; idx 2
    test    r8, r8
    je      .g2
    mov     r9,  [r11 + 0x010]
    test    r9, r9
    jne     .g2
    mov     [r11 + 0x010], r8
.g2:
    mov     r8,  [r10 + 0x5e0]         ; idx 0x11c: legacy DMAP PDPT
    test    r8, r8
    je      .g3
    mov     r9,  [r11 + 0x5e0]
    test    r9, r9
    jne     .g3
    mov     [r11 + 0x5e0], r8
.g3:
    mov     r8,  [r10 + 0x7f0]         ; idx 0x1fc: universal DMAP PDPT
    test    r8, r8
    je      .g4
    mov     r9,  [r11 + 0x7f0]
    test    r9, r9
    jne     .g4
    mov     [r11 + 0x7f0], r8
.g4:
    mov     r8,  [r10 + 0x7f8]         ; idx 0x1fe: KVA PDPT (1)
    test    r8, r8
    je      .g5
    mov     r9,  [r11 + 0x7f8]
    test    r9, r9
    jne     .g5
    mov     [r11 + 0x7f8], r8
.g5:
    mov     r8,  [r10 + 0x7ff]         ; idx 0x1ff: KVA PDPT (0)
    test    r8, r8
    je      .g6
    mov     r9,  [r11 + 0x7ff]
    test    r9, r9
    jne     .g6
    mov     [r11 + 0x7ff], r8
.g6:
    ; L-183 P10: FRAME FIX. The P5 e9 replaced bytes 0x804c3150-54 incl. 0x804c3154
    ; = the REX prefix of 'push r15' (41 57); resuming at 0x804c3155 executed bare
    ; '57' = push rdi, so the epilogue's final 'pop rbp' grabbed the return address
    ; and 'ret' jumped into caller stack data = the boots 58/59 silent death.
    ; L-237 (b88): pop the saved arguments first, in reverse push order, which
    ; returns RSP to R-8 (= RBP) exactly; then push the caller's r15 ourselves
    ; and resume at 0x804c3156 ('push r14'). The reconstructed frame is the one
    ; map_tmr's own prologue would have built: at the resumed instruction
    ; RSP = R-0x10 with [RSP]=r15, [RSP+8]=saved rbp, [RSP+0x10]=caller return
    ; address, and 0x804c3156's 'push r14' lands at R-0x18 as in the original.
    pop     rdx
    pop     rsi
    pop     rdi
    push    r15
    mov     rax, 0xffffffff804c3156   ; resume map_tmr at 'push r14'
    jmp     rax

; L-183 P9: HV TMR vmmcall emulators (e9 targets; preserve callee-saved regs;
; end with jmp to the byte after the replaced block — no ret, there is no
; return address on the stack).
; fn 0x14 = TMR register/notify (in: ebx=tmrid, rcx=arg2, rdx=arg3; out: eax=0 ok)
hv14:
    push    rbx
    push    r13
    push    r14
    push    r15
    mov     rcx, r14                  ; redo 'mov rcx,r14' inside the replaced block
    mov     r8d, ebx                  ; tmrid
    mov     r9,  r14                  ; arg2
    mov     r10, rdx                  ; arg3
    mov     esi, s_hv14
    call    k64puts
    mov     rax, r8
    call    hex8_
    mov     esi, s_or2
    call    k64puts
    mov     rax, r9
    call    hex8_
    mov     esi, s_or3
    call    k64puts
    mov     rax, r10
    call    hex8_
    mov     esi, s_nl
    call    k64puts
    xor     eax, eax                  ; success
    pop     r15
    pop     r14
    pop     r13
    pop     rbx
    ; L-187: direct E9 rel32 computed in nasm's 32-bit space lands at the low-VA
    ; alias 0x0000000080e4307c (empty RAM under the low window), NOT the kernel
    ; KVA. Indirect via se32: 0x80e4307c has bit31 set -> sign-extends to the
    ; exact 64-bit KVA. r11 is caller-clobbered per the vmmcall ABI.
    mov     r11, 0xffffffff80e4307c  ; = 0xFFFFFFFF80E4307C after sign-extension
    jmp     r11
; fn 0xa = TMR status poll (out: eax=0 ready)
hv0a:
    xor     eax, eax
    ; L-187: se32-exact kernel KVA via indirect jump (see hv14 tail)
    mov     r11, 0xffffffff80e43098  ; = 0xFFFFFFFF80E43098 after sign-extension
    jmp     r11


    btext_go:
    ; L-186 P13: pre-fill the kernel's ZERO PML4 slots at handoff. On real hw the
    ; kernel inherits the PSP boot table (low-identity window mapped); our fresh
    ; start hands it a zero BSS table (PA 0x60e5000, proven by boot-57/61 cr3).
    ; Boot 61: first touch of VA 0x108 (low identity) = fatal #PF storm BEFORE the
    ; TMR phase (gs healthy, so the L-181 GS story is over; this is the page-hole
    ; story P5 was built for, but P5 hooks map_tmr = too late). Merge our 7
    ; universal slots (the same set the runtime graft uses) into the zero slots
    ; now; the kernel's own table build overwrites the slots it manages.
    mov     r10, 0x40a0000            ; L-187: our PML4 page via low-identity window (32-bit-safe)
    mov     r11, 0x60e5000            ; kernel PML4 page (PA 0x60e5000) via low-identity window
    mov     esi, p13_offs        ; L-186: absolute 32-bit load (no RIP base: elf32 asm emits REX-in-32)
    mov     ecx, 7
p13l:
    mov     eax, [rsi]
    inc     esi
    mov     r8,  [r10 + rax]
    test    r8, r8
    je      p13n
    mov     r9,  [r11 + rax]
    test    r9, r9
    jne     p13n
    mov     [r11 + rax], r8
p13n:
    dec     ecx
    jnz     p13l

    ; btext entry stack: [rsp+4] = modulep>>12, [rsp+8] = physfree>>12 (dwords)
    mov dword [BTEXT_STACK + 0], 0
    mov dword [BTEXT_STACK + 4], MODULEP >> 12
    mov dword [BTEXT_STACK + 8], PHYSFREE >> 12
    mov rsp, BTEXT_STACK
    mov rax, BTEXT
    jmp rax

; L-192 P15 (dormant — activate the table entry only if P14 misses the switch):
; e9-interposer for the pmap-activate CR3 switch at 0xffffffff80a97337
; (expect[] 8b 44 d0 7c 48 09 c8; the original `mov cr3,rax` at 0xffffffff80a9733e
; is left intact and IS the switch this routine performs on r15's value).
; On entry (from the e9): rax = percpu pmap struct, rcx = flags [rax+0x28],
; rdx = gs:[0x34] cpu word. Recomputes rax = [pmap + cpu*8 + 0x7c] | flags,
; re-grafts the 7 universal low-window slots into the kernel's zero PML4 slots
; (via the trampoline's low identity window — still active, the switch happens
; on the next instruction), then switches and resumes at 0xffffffff80a97341.
; Preserves ALL caller-saved regs; reachable only via the e9 patch (btext_go
; ends in an indirect jmp — L-184 linear-flow rule holds).
cr3fix:
    push    rax
    push    rcx
    push    rdx
    push    r8
    push    r9
    push    r10
    push    r11
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    mov     r12, rax                 ; pmap struct
    mov     r13, rcx                 ; flags
    mov     r14, rdx                 ; cpu word
    mov     eax, [r12 + r14*8 + 0x7c]
    or      rax, r13
    mov     r15, rax                 ; new CR3 value
    mov     r10, 0x40a0000           ; our PML4 page via low-identity window (L-187 32-bit-safe)
    mov     r11, 0x60e5000           ; kernel PML4 page (PA) via low-identity window
    mov     esi, p13_offs
    mov     ecx, 7
cfl:
    mov     eax, [rsi]
    inc     esi
    mov     r8,  [r10 + rax]
    test    r8, r8
    je      cfn
    mov     r9,  [r11 + rax]
    test    r9, r9
    jne     cfn
    mov     [r11 + rax], r8
cfn:
    dec     ecx
    jnz     cfl
    mov     rax, r15                 ; rax = new cr3 (original code had it here)
    mov     cr3, rax                 ; THE switch (grafter ran under our table)
    mov     rcx, r13
    mov     rdx, r14
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     r11
    pop     r10
    pop     r9
    pop     r8
    pop     rdx
    pop     rcx
    pop     rax
    ; L-187: se32-exact kernel KVA via indirect jump (0x80a97341 bit31 set)
    mov     r11, 0x80a97341
    jmp     r11

; L-120: 64-bit putc for debugcon 0x408. L-238 (b88): this used `out dx,eax`
; (EF) and printed NOTHING on TCG — QEMU 8.2.2's isa-debugcon registers
; ops.valid.max_access_size = 1 (hw/char/debugcon.c:84-85) and
; memory_region_dispatch_write (system/memory.c) turns an over-size dispatch
; into unassigned_mem_write + MEMTX_DECODE_ERROR: a 4-byte OUT is DROPPED
; silently. Proof inside our own boot log: T1 (out dx,al) prints its 'A',
; T2 (out dx,eax) never prints its 'B', and K64A/K64B/TMRCALL/HV14 labels
; were absent in every TCG boot (they DO print under KVM, where the in-kernel
; PIO emulation splits the access — serial1422kvm.log:4 `K64A: K64B: AB`).
; The 8-bit form EE is the only one that reaches the chardev; same length,
; so no symbol moves.
k64puts:
    cld
    push rsi
.k64l:
    lodsb
    test al, al
    jz .k64e
    movzx eax, al
    mov dx, 0x408
    out dx, al
    jmp .k64l
.k64e:
    pop rsi
    ret

section .rodata
s_pad: resb 0

; ---------------- GDT ----------------
align 8
gdt:
    dq 0                           ; 0x00 null
    dq 0x00CF9A000000FFFF          ; 0x08 code32
    dq 0x00CF92000000FFFF          ; 0x10 data
    dq 0x00AF9A000000FFFF          ; 0x18 code64 (L=1)
gdtdesc:
    dw gdtdesc - gdt - 1
    dd gdt