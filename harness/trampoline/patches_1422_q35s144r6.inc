PATCH_COUNT equ 62
patch_table:
    dd 0x0025bf67          ; L-180 P6b: stub-epilogue ring-test [rsp+0xf0]->[rsp+0xe8] (RFLAGS, not RIP)@0xffffffff8045bf67
    dd 1
    db 240
    db 232
    dd 0x0025c147          ; L-180 P6a: shared-tail ring-test [rsp+0xf0]->[rsp+0xe8] (swapgs misfire on odd-RIP traps)@0xffffffff8045c147
    dd 1
    db 240
    db 232
    dd 0x0025c159          ; L-179 P2: KGI-stub tail hlt;jmp. -> add rsp,0xe8;iretq (unwind 0xe0 stub frame + skip ERR)@0xffffffff8045c159
    dd 7
    db 244,235,253,144,144,144,144
    db 72,131,196,232,207,144,144
    dd 0x002c3150          ; L-180 P5: map_tmr entry push rbp;mov rbp,rsp;REX -> e9 graft64 (kernel-PML4 graft)@0xffffffff804c3150
    dd 5
    db 85,72,137,229,65
    db 233
    dd (graft64 - 0x804c3155)    ; L-190: next-IP low32 = 0x80200000+off+5 = 0x804c3155 (VA 0xffffffff804c3155)
    dd 0x003f8307          ; L-179 P3: crash-dispatcher ud2 -> nop@0xffffffff805f8307 (no trap-on-trap after dump)
    dd 2
    db 15,11
    db 144,144
    dd 0x003f73e8          ; L-221 P23: NOP mov dr6,eax (AMD debug-store -> #DB-in-#DB -> #DF)@0xffffffff805f73e8
    dd 3
    db 15,35,240
    db 144,144,144
    dd 0x00477500          ; stub-devattach-dispatcher@0xffffffff80677500
    dd 13
    db 85,72,137,229,65,87,65,86,65,85,65,84,83
    db 49,192,195,144,144,144,144,144,144,144,144,144,144
    dd 0x007bfda0          ; linewriter->putstr@0xffffffff809bfda0
    dd 12
    db 129,254,0,0,2,0,15,135,154,0,0,0
    db 72,137,254,233,120,91,56,0,144,144,144,144
    dd 0x007f5272          ; panic-halt@0xffffffff809f5272
    dd 5
    db 187,0,1,0,0
    db 244,235,254,144,144
    dd 0x00800400          ; L-179 P1: park-check never-park@0xffffffff80a00400 (BSP parked itself pre-init, IF=0 -> death)
    dd 51
    db 85,72,137,229,65,87,65,86,83,80,72,137,251,232,126,245,50,0,133,192,116,29,232,21,28,225,255,133,192,116,20,131,61,138,132,40,3,0,117,11,72,131,196,8,91,65,94,65,95,93,195
    db 85,72,137,229,49,192,93,195,144,144,144,144,144,144,144,144,144,144,144,144,144,144,144,144,144,144,144,144,144,144,144,144,144,144,144,144,144,144,144,144,144,144,144,144,144,144,144,144,144,144,144
    dd 0x00b45290          ; putc->debugcon0x408@0xffffffff80d45290
    dd 14
    db 85,72,137,229,65,87,65,86,65,85,65,84,83,80
    db 65,15,182,247,186,8,4,0,0,238,195,144,144,144
    dd 0x00c6f910          ; searchB-lenjmp@0xffffffff80e6f910
    dd 7
    db 65,131,127,4,0,116,52
    db 233,52,0,0,0,144,144
    dd 0x00c6f96a          ; search-NULL@0xffffffff80e6f96a
    dd 7
    db 116,71,72,133,255,116,14
    db 49,192,195,144,144,144,144
; b98: NO row for 0x00c6f9c0.  The 33-byte "getter-selfhandle" row that used to
; sit here (expect 31c04885ff7445... , write 31c0 81fe01900000 7513
; 48b820480984ffffffff ba08040000 b047 ee c3 c3 90 90 90) REPLACED the TLV
; getter FUN_80e6f9c0 with a stub that answered ONLY tag 0x9001, from a 32-byte
; zero record region at VA 0xffffffff84094820 (= PA 0x4094820 = MODULEP+0x820),
; and printed 'G' on debugcon 0x408. Every 0x9001 request was therefore
; shadowed, which is why b95/b96's phys_avail was 9.5 EiB regardless of the
; meta TLV. RETIRED in b98 (single variable): PATCH_COUNT 76 -> 75.
; The two rows that FOLLOW are left untouched this round (both are still in
; the table, byte for byte):
;   helper-exit@0xffffffff80e6fa85        2 bytes: 74 47 (je +0x47) -> eb 47
;   walker-selfhandle@0xffffffff80e6fb20 12 bytes: 55 48 89 e5 53 50 48 8b 1d
;                                         8b 16 1c -> 48 b8 00 48 c0 ff ff ff
;                                         ff ff c3 90 (movabs rax,
;                                         0xffffffffffc04800; ret; nop)
; So three rows existed for this one function; exactly ONE is gone.
    dd 0x00c6fa85          ; helper-exit@0xffffffff80e6fa85
    dd 2
    db 116,71
    db 235,71
    dd 0x00c6fb20          ; walker-selfhandle@0xffffffff80e6fb20
    dd 12
    db 85,72,137,229,83,80,72,139,29,139,22,28
    db 72,184,0,72,192,255,255,255,255,255,195,144
    dd 0x0191be0c          ; L-241 P25 (RE-APPLIED, boot 93): platform/memory mode word DAT_81b1be0c (kernel .data)
    dd 4
    db 1,0,0,0             ; expect (image): 01 00 00 00 = mode 1
    db 4,0,0,0             ; write: 04 00 00 00 = mode 4 (derived: python3 struct.pack('<I',4))
    dd 0x00a1992a          ; L-241 P26: skip the mode-4 call that lands in an INT3 hole @0xffffffff80c1992a
    dd 5
    db 232,97,96,17,0      ; expect (image): e8 61 60 11 00 = call 0xffffffff80d2f990 (FUN_80d2f990 returns mode==4)
    db 49,192,144,144,144  ; write: 31 c0 90 90 90 = xor eax,eax; 3x nop (derived: nasm -f bin, `bits 64 / xor eax,eax / nop / nop / nop`)
    dd 0x00a2146d          ; L-243 P27: panic("Failed to allocate application memory") -> graceful out-param -1 @0xffffffff80c2146d
    dd 31
    db 232,222,251,221,255 ; expect (image): e8 de fb dd ff = call 0xffffffff80a01050 (panic prologue)
    db 72,141,61,244,255,255,255   ; 48 8d 3d f4 ff ff ff = lea rdi,[rip-0xc] (panic ctx)
    db 232,146,250,221,255         ; e8 92 fa dd ff = call 0xffffffff80a00f10
    db 72,141,53,249,37,146,0      ; 48 8d 35 f9 25 92 00 = lea rsi,"Failed to allocate application memory" (0xffffffff81543a7e)
    db 191,68,0,0,0                ; bf 44 00 00 00 = mov edi,0x44
    db 235,164                     ; eb a4 = jmp 0xffffffff80c21430 (panic tail)
    db 72,139,133,160,251,255,255  ; write: 48 8b 85 a0 fb ff ff = mov rax,[rbp-0x460] (saved out-param ptr, set at 0x80c20802)
    db 199,0,255,255,255,255       ; c7 00 ff ff ff ff = mov dword [rax],-1 (negative => caller js 0x80c1c3a6)
    db 233,99,255,255,255          ; e9 63 ff ff ff = jmp 0xffffffff80c213e2 (epilogue: add rsp,0x468; pops; ret)
    db 144,144,144,144,144,144,144 ; 13x nop pad to the 31-byte block (0x80c2146d-0x80c2148b)
    db 144,144,144,144,144,144
    dd 0x00a1c340          ; L-243 P28: skip the mode-4 hole call in the CALLER FUN_80c1c080 @0xffffffff80c1c340
    dd 5
    db 232,75,111,97,255   ; expect (image): e8 4b 6f 61 ff = call 0xffffffff80233290 (0xCC hole)
    db 235,3,144,144,144   ; write: eb 03 90 90 90 = jmp short +3 -> 0xffffffff80c1c345 (derived: nasm -f bin, `bits 64 / org 0xffffffff80c1c340 / jmp short 0xffffffff80c1c345`)
    dd 0x00a2082a          ; L-243 P29: skip the mode-4 hole call inside FUN_80c207e0 @0xffffffff80c2082a
    dd 5
    db 232,241,153,105,255 ; expect (image): e8 f1 99 69 ff = call 0xffffffff802ba220 (0xCC hole)
    db 233,105,7,0,0       ; write: e9 69 07 00 00 = jmp 0xffffffff80c20f98 (derived: nasm -f bin, `bits 64 / org 0xffffffff80c2082a / jmp 0xffffffff80c20f98`; rel32 0x769 from next-IP 0x80c2082f)
    dd 0x00a1c6af          ; L-246 P30: S4 preserved-physmap FAILURE branch skipped @0xffffffff80c1c6af (the `je` after FUN_80c1b030 returned 0)
    dd 6
    db 15,132,235,6,0,0    ; expect (image): 0f 84 eb 06 00 00 = je 0xffffffff80c1cda0 (S4 panic block; rel32 0x6eb from next-IP 0x80c1c6b5)
    db 144,144,144,144,144,144 ; write: 6x 90 (derived: nasm -f bin, `bits 64 / org 0xffffffff80c1c6af / times 6 nop` -> 909090909090; capstone at the org prints 6x nop ending exactly at 0x80c1c6b5)
    dd 0x006c1886          ; L-289 P31/S-32: ACPI-MADT int3-hole tail-jmp skipped @0xffffffff808c1886 (FUN_808c17a0 tail-jumps into 0x802c9d60 which is int3 FILL = CODE ABSENT, L-254; the call is void + side-effect-only so it is SKIPPED, not answered)
    dd 5
    db 233,213,132,160,255 ; expect (image): e9 d5 84 a0 ff = jmp 0xffffffff802c9d60 (0xCC hole; derived: kernel_raw[0x6c1886:0x6c188b])
    db 195,144,144,144,144  ; write: c3 90 90 90 90 = ret + 4x nop -> FUN_808c17a0 RETURNS instead of entering absent code (c3=ret, 90=nop; single-byte opcodes, no rel32)
    dd 0x000c9e00          ; P32/S-33 TIER-A ret-stub @0xffffffff802c9e00 (int3 target; code absent L-254)
    dd 3
    db 204,204,204         ; expect: cc cc cc (int3 fill; derived kernel_raw[0xc9e00:+3])
    db 49,192,195          ; write: 31 c0 c3 = xor eax,eax; ret (benign 0; all callers)
    dd 0x000c9e90          ; P32/S-33 TIER-A ret-stub @0xffffffff802c9e90 (int3 target; code absent L-254)
    dd 3
    db 204,204,204         ; expect: cc cc cc (int3 fill; derived kernel_raw[0xc9e90:+3])
    db 49,192,195          ; write: 31 c0 c3 = xor eax,eax; ret (benign 0; all callers)
    dd 0x000c9f50          ; P32/S-33 TIER-A ret-stub @0xffffffff802c9f50 (int3 target; code absent L-254)
    dd 3
    db 204,204,204         ; expect: cc cc cc (int3 fill; derived kernel_raw[0xc9f50:+3])
    db 49,192,195          ; write: 31 c0 c3 = xor eax,eax; ret (benign 0; all callers)
    dd 0x000c9fb0          ; P32/S-33 TIER-A ret-stub @0xffffffff802c9fb0 (int3 target; code absent L-254)
    dd 3
    db 204,204,204         ; expect: cc cc cc (int3 fill; derived kernel_raw[0xc9fb0:+3])
    db 49,192,195          ; write: 31 c0 c3 = xor eax,eax; ret (benign 0; all callers)
    dd 0x0003ed40          ; P33/S-34 code-absent VOID ret-0 stub @0xffffffff8023ed40 (int3; audited void)
    dd 3
    db 204,204,204         ; expect cc cc cc (int3; kernel_raw[0x3ed40:+3])
    db 49,192,195          ; write 31 c0 c3 = xor eax,eax; ret
    dd 0x00083390
    dd 3
    db 204,204,204
    db 49,192,195   ; P34/S-35 ret-0 stub @0xffffffff80283390
    dd 0x00134020
    dd 3
    db 204,204,204
    db 49,192,195   ; P34/S-35 ret-0 stub @0xffffffff80334020
    dd 0x00b2c51e          ; P35/S-37: SMP IPI-gate install. je->nop so the forced-UP SYSINIT runs the kernel's own cpu_mp_start(FUN_80a96970): installs IPI vectors 0xf6-0xfd (incl 0xfb->0x80472cb0) + zeroes the pending bitmap. L-305 @0xffffffff80d2c51e
    dd 2
    db 116,199
    db 144,144
    dd 0x00b2c53f          ; P35/S-37: after cpu_mp_announce, jmp FUN_808e6e20 (MP-only AP-mem finalize that UP never runs) -> ret. Preserves UP semantics. L-305 @0xffffffff80d2c53f
    dd 5
    db 233,220,168,187,255
    db 195,144,144,144,144
    dd 0x00a275f1          ; P36/S-38: gc/TEE secure-video gate DAT_83e2f020 movb imm 1->0 (refuse GPU path, no GPU) @0xffffffff80c275f1 L-315f
    dd 1
    db 1
    db 0
; ===== P37/S-39 gbase GPU-refuse guards (L-315g) v2: 3 e9 funnels -> stubs OVERWRITING gbase_initialize body (X-mapped, boot-dead; REVERT at GPU milestone); no-write/no-log =====
    dd 0x009f8a10          ; P37/S-39: e9 -> gbase refuse stub @0x80bf2cf0 (map_to_vmid0->804c0009) L-315g
    dd 6
    db 85,72,137,229,65,87
    db 233,219,162,255,255,144
    dd 0x009fddc0          ; P37/S-39: e9 -> gbase refuse stub @0x80bf2d30 (alloc_dynamic_mmhub_vmid->804c0003) L-315g
    dd 6
    db 85,72,137,229,65,86
    db 233,107,79,255,255,144
    dd 0x009f3df0          ; P37/S-39: e9 -> gbase refuse stub @0x80bf2d70 (alloc_vm_space_internal->804c0002) L-315g
    dd 6
    db 85,72,137,229,65,87
    db 233,123,239,255,255,144
    dd 0x009f2cf0          ; P37/S-39: stub1 overwrites gbase_initialize body @0x80bf2cf0 (X-mapped, boot-dead; REVERT at GPU milestone) L-315g
    dd 64
    db 85,72,137,229,65,87,65,86,65,85,65,84,83,80,73,137,254,72,141,61,80,119,31,3,72,141,53,78,191,143,0,186,32,0,0,0,232,151,89,40,0,72,141,29,128,119,31,3,72,141,53,216,175,149,0,185,1,0,0,0,49,210,72,137
    db 72,131,60,37,56,165,222,131,0,117,6,184,9,0,76,128,195,85,72,137,229,65,87,233,10,93,0,0,204,204,204,204,204,204,204,204,204,204,204,204,204,204,204,204,204,204,204,204,204,204,204,204,204,204,204,204,204,204,204,204,204,204,204,204
    dd 0x009f2d30          ; P37/S-39: stub2 overwrites gbase_initialize body @0x80bf2d30 (X-mapped, boot-dead; REVERT at GPU milestone) L-315g
    dd 64
    db 223,232,74,223,173,255,72,141,61,107,119,31,3,72,141,53,81,25,143,0,49,210,232,101,89,40,0,72,141,61,246,118,31,3,72,141,53,236,239,158,0,49,210,49,201,232,30,223,173,255,72,141,61,119,119,31,3,72,141,53,114,86,150,0
    db 72,131,60,37,56,165,222,131,0,117,6,184,3,0,76,128,195,85,72,137,229,65,86,233,122,176,0,0,204,204,204,204,204,204,204,204,204,204,204,204,204,204,204,204,204,204,204,204,204,204,204,204,204,204,204,204,204,204,204,204,204,204,204,204
    dd 0x009f2d70          ; P37/S-39: stub3 overwrites gbase_initialize body @0x80bf2d70 (X-mapped, boot-dead; REVERT at GPU milestone) L-315g
    dd 64
    db 49,210,49,201,232,7,223,173,255,72,141,61,128,119,31,3,72,141,53,181,79,154,0,49,210,49,201,232,240,222,173,255,72,141,61,137,119,31,3,72,141,53,1,16,147,0,49,210,49,201,232,217,222,173,255,72,137,223,76,137,53,135,119,31
    db 72,131,60,37,56,165,222,131,0,117,6,184,2,0,76,128,195,85,72,137,229,65,87,233,106,16,0,0,204,204,204,204,204,204,204,204,204,204,204,204,204,204,204,204,204,204,204,204,204,204,204,204,204,204,204,204,204,204,204,204,204,204,204,204
; ===== P38/S-40 DCE module refuse (L-318): e9 @FUN_808a14e0 modevent -> stub in boot-dead X-mapped gbase_initialize body =====
    dd 0x006a14e0          ; P38/S-40: e9 -> DCE-modevent refuse stub @0x80bf2e00 (ENXIO if MOD_LOAD & no GPU) L-318
    dd 5
    db 85,72,137,229,83
    db 233,27,25,53,0
    dd 0x009f2e00          ; P38/S-40: DCE-refuse stub overwrites gbase_initialize body @0x80bf2e00 (X-mapped, boot-dead; REVERT at GPU milestone) L-318
    dd 31
    db 0,232,234,213,173,255,73,193,231,24,72,141,61,163,7,149,0,76,137,246,49,192,76,137,250,232,34,34,135,255,72
    db 133,246,117,17,72,131,60,37,56,165,222,131,0,117,6,184,6,0,0,0,195,85,72,137,229,83,233,198,230,202,255
; ===== P39/S-41 MP1/SMU register-primitive refuse on NULL softc DAT_84033330==0 (L-321): 3 e9 grafts -> guard stubs in boot-dead X-mapped gbase_initialize body; REVERT at firmware/VFIO milestone =====
    dd 0x00cad9c0          ; P39/S-41: e9 -> MP1 read-prim guard stubA @0x80bf2e40 (softc NULL -> ret 0 = no response -> waitmsg timeout/hangup storm) L-321
    dd 6
    db 85,72,137,229,65,87
    db 233,123,84,212,255,144
    dd 0x00cadb10          ; P39/S-41: e9 -> MP1 write-prim guard stubB @0x80bf2e60 (softc NULL -> ret, no reg write) L-321
    dd 6
    db 85,72,137,229,65,87
    db 233,75,83,212,255,144
    dd 0x00cadc70          ; P39/S-41: e9 -> MP1 bapm-thunk guard stubC @0x80bf2e80 (softc NULL -> ret 6 -> _mp1_bapm_logging_init_intr MSI-alloc error) L-321
    dd 11
    db 85,72,137,229,72,139,5,181,86,24,3
    db 233,11,82,212,255,144,144,144,144,144,144
    dd 0x009f2e40          ; P39/S-41: stubA (read-prim guard) overwrites gbase_initialize body @0x80bf2e40 (X-mapped, boot-dead; REVERT at firmware milestone) L-321
    dd 25
    db 106,6,106,0,232,71,157,177,255,72,131,196,16,72,137,199,72,137,5,233,118,31,3,232,84
    db 72,131,60,37,48,51,3,132,0,117,3,49,192,195,85,72,137,229,65,87,233,109,171,43,0
    dd 0x009f2e60          ; P39/S-41: stubB (write-prim guard) overwrites gbase_initialize body @0x80bf2e60 (X-mapped, boot-dead; REVERT at firmware milestone) L-321
    dd 23
    db 7,149,0,190,0,0,2,0,185,0,0,252,255,65,184,0,0,224,255,72,137,5,206
    db 72,131,60,37,48,51,3,132,0,117,1,195,85,72,137,229,65,87,233,159,172,43,0
    dd 0x009f2e80          ; P39/S-41: stubC (bapm-thunk guard) overwrites gbase_initialize body @0x80bf2e80 (X-mapped, boot-dead; REVERT at firmware milestone) L-321
    dd 34
    db 0,0,0,0,199,5,238,117,31,3,0,0,2,0,199,5,232,117,31,3,0,0,0,0,199,5,178,118,31,3,0,0,224,255
    db 72,131,60,37,48,51,3,132,0,117,6,184,6,0,0,0,195,85,72,137,229,72,139,4,37,48,51,3,132,233,217,173,43,0
; ===== P40/S-42 gbase gc-register READ (FUN_80bf3570) + WRITE (FUN_80bf43d0) helpers refuse on no-GPU DAT_83dea538==0 (L-322): 2 e9 grafts -> guard stubs in boot-dead X-mapped gbase_initialize body; REVERT at GPU/VFIO milestone =====
    dd 0x009f3570          ; P40/S-42: e9 -> gc-reg READ guard stubD @0x80bf2eb0 (no GPU BAR5 DAT_83dea538==0 -> reg reads 0 = 13.60 zeroed dump, before gbase rw-lock 0x83dea4a0) L-322
    dd 5
    db 85,72,137,229,83
    db 233,59,249,255,255
    dd 0x009f43d0          ; P40/S-42: e9 -> gc-reg WRITE guard stubE @0x80bf2ee0 (no GPU BAR5 -> skip write+lock, void ret) L-322
    dd 6
    db 85,72,137,229,65,86
    db 233,11,235,255,255,144
    dd 0x009f2eb0          ; P40/S-42: stubD (gc-reg READ guard) overwrites gbase_initialize body @0x80bf2eb0 (X-mapped, boot-dead; REVERT at GPU/VFIO milestone) L-322
    dd 24
    db 232,139,33,135,255,72,141,5,236,56,14,1,72,141,61,102,73,152,0,190,40,0,0,0
    db 72,131,60,37,56,165,222,131,0,117,3,49,192,195,85,72,137,229,83,233,173,6,0,0
    dd 0x009f2ee0          ; P40/S-42: stubE (gc-reg WRITE guard) overwrites gbase_initialize body @0x80bf2ee0 (X-mapped, boot-dead; REVERT at GPU/VFIO milestone) L-322
    dd 23
    db 1,72,137,8,49,201,106,0,106,7,232,81,16,165,255,72,131,196,16,72,137,5,102
    db 72,131,60,37,56,165,222,131,0,117,1,195,85,72,137,229,65,86,233,223,20,0,0
; ===== P41/S-43 pcist module refuse at modevent FUN_806c9e20 (L-323): MOD_LOAD + no-SoC-PCI-bridge -> ENXIO(6); stub in boot-dead X-mapped gbase_initialize body; REVERT at SoC-device-model/VFIO milestone =====
    dd 0x004c9e20          ; P41/S-43: e9 -> pcist-modevent refuse stub @0x80bf2f00 (ENXIO 6 if MOD_LOAD & no SoC PCI bridge) L-323
    dd 5
    db 85,72,137,229,83
    db 233,219,144,82,0
    dd 0x009f2f00          ; P41/S-43: pcist-modevent refuse stub overwrites gbase_initialize body @0x80bf2f00 (X-mapped, boot-dead; REVERT at SoC-device-model/VFIO milestone) L-323
    dd 20
    db 141,61,155,149,159,0,49,192,232,51,33,135,255,72,141,13,92,118,31,3
    db 133,246,117,6,184,6,0,0,0,195,85,72,137,229,83,233,17,111,173,255
; ===== P42/S-44 av_control (AV/video/HDCP display) module refuse at modevent FUN_80682390 (L-327): MOD_LOAD + no GPU/VBIOS (uninit gbase vbios lock 0x8402b9f0 wedges thread0) -> ENXIO(6); stub in boot-dead X-mapped gbase_initialize body; REVERT at GPU/VFIO/VBIOS milestone =====
    dd 0x00482390          ; P42/S-44: e9 -> av_control-modevent refuse stub @0x80bf2f20 (ENXIO 6 if MOD_LOAD esi==0) L-327
    dd 5
    db 85,72,137,229,83
    db 233,139,11,87,0
    dd 0x009f2f20          ; P42/S-44: av_control-modevent refuse stub overwrites gbase_initialize body @0x80bf2f20 (X-mapped, boot-dead; REVERT at GPU/VFIO/VBIOS milestone) L-327
    dd 20
    db 199,68,8,64,0,0,0,0,72,199,4,8,32,0,0,0,72,199,68,8
    db 133,246,117,6,184,6,0,0,0,195,85,72,137,229,83,233,97,244,168,255
; ===== P43/S-45 sbl_sm_service (Secure Boot Loader) module refuse at modevent FUN_807ad780 (L-328): MOD_LOAD + no secure-processor (SBL msg-handler registry sx 0x83739fd8 uninit, sceSblDriverRegisterMsgHandler sx_xlocks it -> thread0 wedge) -> ENOTSUP(45) = 13.60's sbl err45; stub in boot-dead X-mapped gbase_initialize body; REVERT at secure-processor/BD bring-up =====
; NOTE (v2): the stub is a COMPLETE replacement of the modevent — it NEVER re-enters the real FUN_807ad780 (no jmp-back, no prologue replay), so the non-clean 5-byte boundary and the orphaned 0x56 are moot. v1 replayed the prologue for cmd!=0, which let the MOD_UNLOAD cleanup run sbl's sm_service_finalize on a never-loaded module and wedge thread0 on uninit mutex 0x83b5c310 (C-052); v2 returns 0 for all non-MOD_LOAD cmds (a refused module has nothing to unload/finalize = correct FreeBSD module semantics, not a fake) so sbl's real body never runs.
    dd 0x005ad780          ; P43/S-45: e9 -> sbl_sm_service-modevent refuse stub @0x80bf2f40 (ENOTSUP 45 if MOD_LOAD esi==0) L-328
    dd 5
    db 85,72,137,229,65
    db 233,187,87,68,0
    dd 0x009f2f40          ; P43/S-45 v2: sbl_sm_service-modevent COMPLETE-REFUSE stub @0x80bf2f40 (MOD_LOAD esi==0 -> 45; all other cmds -> 0 no-op; NO replay, sbl real body never runs) overwrites gbase_initialize body (X-mapped, boot-dead; REVERT at secure-processor/BD milestone) L-328
    dd 13
    db 0,0,199,68,8,24,0,0,0,0,72,199,68
    db 133,246,116,3,49,192,195,184,45,0,0,0,195
; ===== P44/S-46 cam/sceCameraDriver module refuse at modevent FUN_80ccea00 (L-333, analyst-settled L-332): with no GPU our P37 gbase refuse drives the camera's SceCameraDriverMain kthread (FUN_80ccf200, spawned by the MOD_LOAD branch) into gbase_map_to_vmid0 FUN_80bf8a10 (P37-refused -> 0x804c0009); the error-cleanup tears down 4 isoc bufs via FUN_80e34ad0 with NO NULL-check; buf1=NULL -> pmap_enter(kernel_pmap, va=0) -> pmap_enter_pde panic (C-053). Refuse MOD_LOAD so the kthread never spawns -> no GPU-map -> no panic. ENOTSUP(45) = module default (honest "no camera/GPU"), NOT faked err12. Stub in boot-dead X-mapped gbase_initialize body; REVERT at GPU/VFIO milestone =====
; NOTE: COMPLETE replacement of the modevent (P43-v2 pattern) — the stub NEVER re-enters the real FUN_80ccea00, so no jmp-back/no prologue replay; all non-MOD_LOAD cmds return 0 (a never-loaded module has nothing to unload; re-entering the real MOD_UNLOAD would run eventhandler_deregister on uninit state).
    dd 0x00acea00          ; P44/S-46: e9 -> cam-modevent refuse stub @0x80bf2f50 (ENOTSUP 45 if MOD_LOAD esi==0) L-333
    dd 5
    db 85,72,137,229,65
    db 233,75,69,242,255
    dd 0x009f2f50          ; P44/S-46: cam-modevent COMPLETE-REFUSE stub @0x80bf2f50 (MOD_LOAD esi==0 -> 45; all other cmds -> 0 no-op; NO replay, cam real body never runs) overwrites gbase_initialize body (X-mapped, boot-dead; REVERT at GPU/VFIO milestone) L-333
    dd 13
    db 0,0,0,72,199,68,8,48,0,0,0,0,72
    db 133,246,116,3,49,192,195,184,45,0,0,0,195
; ===== P45/S-47 SIE IOMMU NULL-softc GUARD at the PASID-bind device-config SYSINIT FUN_80741090 (L-336, analyst L-335 + builder STEP-0 pin): the SIE-IOMMU global softc *(0xffffffff83783a70)=NULL (absent IOMMU/northbridge HW, S-20). This SYSINIT calls sie_iommu_bind_pasid FUN_80701980, which UNCONDITIONALLY _mtx_lock_sleeps softc+0xa8 (the mtx_lock word; lock_object base = softc+0x90) -> with softc NULL it turnstile-waits on the uninit mutex at VA 0x90 (lo_name=0, no owner) FOREVER = the pre-DEVCONF wedge (L-335, C-054). bind_pasid's error path is UNUSABLE as a guard return: its sole caller (this SYSINIT) PANICS on a nonzero return (`test eax,eax; jne -> panic FUN_80ec8050; ud2`) and faking success would need a fabricated pasid at *param_2. So guard the SYSINIT itself (bind_pasid's only caller): softc NULL -> ret (the whole PASID-bind SYSINIT does nothing = honest IOMMU-absent, mi_startup ignores SYSINIT return), else replay. Same P39/S-41 NULL-softc-guard pattern; stub in boot-dead X-mapped gbase_initialize body; REVERT at SoC/IOMMU-model milestone =====
; NOTE: fakes NOTHING, pre-inits NO softc (a fabricated softc would feed real IOMMU MMIO and refault, per the P39 MP1 note). Clean 5-byte boundary: e9 overwrites 55 48 89 e5 53 (push rbp;mov rbp,rsp;push rbx), the else-branch replays those + jmp 0x80741095 (the displaced 'push rax'). 13.60 reaches DEVCONF with its SIE-IOMMU softc non-NULL (HW present) and no iommu/pasid oracle line, so skipping this SYSINIT when the HW is absent is 13.60-faithful.
    dd 0x00541090          ; P45/S-47: e9 -> SIE-IOMMU PASID-bind SYSINIT NULL-softc guard stub @0x80bf2f60 (softc [0x83783a70]==0 -> ret, skip bind; else replay) L-336
    dd 5
    db 85,72,137,229,83
    db 233,203,30,75,0
    dd 0x009f2f60          ; P45/S-47: SIE-IOMMU PASID-bind SYSINIT NULL-softc guard stub @0x80bf2f60 (cmp qword[0x83783a70],0 / jne replay / ret ; replay: push rbp;mov rbp,rsp;push rbx; jmp 0x80741095) overwrites gbase_initialize body (X-mapped, boot-dead; REVERT at SoC/IOMMU-model milestone) L-336
    dd 22
    db 56,0,0,0,0,198,68,8,100,0,76,137,108,8,104,199,68,8,112,0,0,0
    db 72,131,60,37,112,58,120,131,0,117,1,195,85,72,137,229,83,233,31,225,180,255
; ===== P46/S-48 UMC (AMD Unified Memory Controller) module CONDITIONAL REFUSE at its modevent 0x80b906f0 (L-371 STEP-1): the UMC modevent MOD_LOAD handler calls init FUN_80b90710, whose first act is DAT_83de46c0 = FUN_805082f0(0,0,0) (find PCI dev at seg0/bus0/slot0/fn0 in Sony PCI registry DAT_830a8df0); NULL -> HARD-PANIC "UMC: BSF(0:0:0) is not found" @0x80b90a4b. On q35 the registry head DAT_830a8df0==0 (EMPTY at UMC-modload, live-confirmed park RnouJD) because the AMD northbridge/UMC is absent (q35 Intel MCH) and PCI enum has not populated it -> panic. CONDITIONAL guard (behavior-preserving, baseline-safe like P41-P45): on MOD_LOAD(esi==0), if DAT_830a8df0==0 (registry empty = no 0:0:0 = UMC absent) -> ENXIO(6); ELSE run real init FUN_80b90710 (bare q35/-M pc with populated registry UNCHANGED). Non-MOD_LOAD replicates the original modevent (MOD_UNLOAD->0, other->0x2d). module_register_init handles the nonzero MOD_LOAD gracefully (same loader as P38/P41-P44, prints MOD_LOAD error, NO panic). Stub in boot-dead X-mapped gbase_initialize body @0x80bf2f80 (free: P45 ends 0x80bf2f76, body ends 0x80bf3569); REVERT at AMD-UMC/northbridge-model milestone =====
    dd 0x009906f0          ; P46/S-48: e9 -> UMC-modevent conditional refuse stub @0x80bf2f80 (ENXIO 6 if MOD_LOAD & registry empty; else run real init FUN_80b90710) L-371
    dd 5
    db 131,254,1,116,22
    db 233,139,40,6,0
    dd 0x009f2f80          ; P46/S-48: UMC-refuse stub @0x80bf2f80 (test esi,esi/jne notload; cmpq[0xffffffff830a8df0],0/je refuse->mov eax,6; else push rbp;mov rbp,rsp;call 0x80b90710;xor eax,eax;pop rbp;ret; notload: cmp esi,1/jne->mov eax,0x2d; else xor eax,eax;ret) overwrites gbase_initialize body (X-mapped, boot-dead; REVERT at AMD-UMC-model milestone) L-371
    dd 48
    db 72,199,132,8,152,0,0,0,1,0,0,0,72,199,132,8,128,0,0,0,0,0,0,0,72,199,132,8,160,0,0,0,1,0,0,0,72,199,132,8,136,0,0,0,0,0,0,0
    db 133,246,117,24,72,131,60,37,240,141,10,131,0,116,27,85,72,137,229,232,120,215,249,255,49,192,93,195,131,254,1,117,3,49,192,195,184,45,0,0,0,195,184,6,0,0,0,195
; P25/P26 rationale (L-241, boot 93): b92 proved guest RAM is not the
; variable (wall byte-identical to b89 at 8 GiB), and static work shows the
; memory-reserve path in FUN_80c207e0 is reached only when the mode gate
; returns 4; failing the gate falls off the function into
; panic("Failed to allocate application memory"). So mode must be 4 — b91's
; failure was not the mode write but the mode-4 branch in FUN_80c19880
; (the "elf kernel" handler called from btext+0x20): at 0xffffffff80c19969
; it calls 0xffffffff80232ca0, inside the 662,328-byte 0xCC run
; 0x80210090-0x802b1bc8 (Sony's own image; 13.60 has the same kind of holes).
; P26 replaces the 5-byte `call 0xffffffff80d2f990` at 0xffffffff80c1992a
; with `xor eax,eax; nop;nop;nop`: eax=0 -> `test eax,eax` at 0x80c1992f ->
; `je 0xffffffff80c1996e` taken -> the FUN_80232ca0 call at 0x80c19969 is
; skipped. Same length, no reflow; the gate at 0x80d2f940/0x80d2f990 is not
; otherwise touched. P25 is a data patch, P26 a text patch.
; P25 was RETIRED in b92 (L-240) and is RE-APPLIED here with P26 as the fix
; for the exact wall b91 hit; S-26/S-27 are registered in the SYNTH line.
; P24 rationale (boot 88's wall, L-236 + coord/RUNS.md b88): the send is
; psp_mbox_map_tmr's `call 0xffffffff804c32e0` with (payload,0x75,10M,10M).
; Boot 88 printed "Mbox Is Busy(0x0, 0x75) . Send(Cmd 0x75)" -> "Command
; error" -> err=5 -> panic in commit_registered_static_tmr_region. That is a
; DEVICE wall: the mailbox base page is ordinary zero RAM and there is no PSP
; in this QEMU (an S-24-class synthetic, same class as P4a/P4b/P9b).
; Downstream (static, analyzed): al=1 -> `test al,al`/`je 0x804c32a2` not
; taken -> `mov edx,[r15+4]` reads the reply status inside the 0x40-byte
; buffer zeroed by the memset at 0x804c3236 -> 0 -> `je 0x804c32c9` ->
; iVar3=0 -> psp_mbox_map_tmr returns 0 for every TMR entry.
; P25 RETIRED (L-240, boot 91) then RE-APPLIED (L-241, boot 93): the
; mode-write synthetic @foff 0x191be0c (0xffffffff81b1be0c, static
; 01 00 00 00 -> 04 00 00 00). Boot 91 was read as a refutation of the write
; ("mode 4 has no implementation on the early path: FUN_80c19880 branches at
; 0x80c19969 into 0xffffffff80232ca0, inside an INT3 fill, and the guest
; triple-faults before the CR3 switch"). Boot 92 showed RAM size is not the
; variable, and L-241 re-read b91 as: mode must be 4, and the branch that
; must not execute is the one FUN_80232ca0 call — which P26 now skips.
; PATCH_COUNT is 75 (the P1-P30 set MINUS the retired getter-selfhandle row);
; boot 98 is a NEW image.
; L-243 P27 (boot 94) — the panic block at 0xffffffff80c2146d is REPLACED, not
; reflowed: the block is `call 0xffffffff80a01050; lea rdi,[rip-0xc];
; call 0xffffffff80a00f10; lea rsi,"Failed to allocate application memory"
; (0xffffffff81543a7e); mov edi,0x44; jmp 0xffffffff80c21430`, exactly 31
; bytes (0x80c2146d .. 0x80c2148b inclusive; 0x80c2148c begins the stack-
; canary panic). It is reached from ONE place: 0x80c21091 `je 0x80c2146d`
; after `call 0xffffffff80c1b030` returned 0 at 0x80c2108e. FUN_80c1b030's
; signature is (long param_1, int *param_2, ulong param_3, long param_4) and
; its FIRST act is `uVar7 = *param_2; if ((long)uVar7 < 0) return 0;` — so a
; NEGATIVE int at param_2 is already this code's own "no memory" value, which
; is why the write is `-1` and 4 bytes wide, not an invented pointer.
; param_2 is the handler's RSI, saved at 0x80c20802 to [rbp-0x460]; the CALLER
; FUN_80c1c080 passes `lea rsi,[rbp-0x21c]` (0x80c1c34c) and then does
; `mov eax,[rbp-0x21c]; test eax,eax; js 0x80c1c3a6` (0x80c1c366-372), where
; 0x80c1c3a6 is real continuing code (`add rdx,[0x83df5510]`, store to
; 0x83df41d8, `mov r12d,[rbp-0x220]`, ...), i.e. the "no application memory
; configured" state. P27 therefore turns an unreachable panic into that state.
; The 18 write bytes are DERIVED, never typed:
;   nasm -f bin, `bits 64 / org 0xffffffff80c2146d /
;    mov rax,[rbp-0x460] / mov dword [rax],-1 / jmp 0xffffffff80c213e2`
;   -> 48 8b 85 a0 fb ff ff | c7 00 ff ff ff ff | e9 63 ff ff ff
;   (rel32 0xffffff63 = -0x9d from next-IP 0x80c2147f -> 0x80c213e2)
;   + 13 x 90. Epilogue CONFIRMED by disassembly: 0x80c213e2 48 81 c4 68 04
;   00 00 (add rsp,0x468); 5b (pop rbx); 41 5c 41 5d 41 5e 41 5f (pop
;   r12/r13/r14/r15); 5d (pop rbp); c3 (ret). Jumping there skips the stack-
;   canary compare at 0x80c213d5 (cmp rax,[rbp-0x30]; jne 0x80c2148c), which
;   is correct: the canary value was only loaded, never corrupted.
; RISK KEPT VISIBLE (TASK B of L-243): at mode 4 the hole calls run BEFORE
; this block, so P27 alone cannot be reached — see the boot94.sh header for
; the full order (0x80c1c340 -> 0x80233290 in the CALLER, then 0x80c2082a ->
; 0x802ba220 and 0x80c20855 -> 0x802ba1f0 inside the handler). All three
; targets are 0xCC in the image. P27 is the graceful-degradation half only.
; L-243 P28/P29 (boot 94, added after the TASK B order was proved) — the two
; extra skips that make P27 reachable at mode 4. Both are 5-byte in-place
; rewrites, same length, no reflow, bytes DERIVED with nasm -f bin and
; capstone-decoded at the org address:
;   P28 @0xffffffff80c1c340 (foff 0xa1c340, CALLER FUN_80c1c080)
;       expect e8 4b 6f 61 ff = call 0xffffffff80233290
;       write  eb 03 90 90 90 = jmp short +3; 0x80c1c340+2+3 = 0x80c1c345,
;              which is the real `lea rdi,[rbp-0x120]` that follows. A short
;              jump, not `xor eax,eax`: the call's return value is never read
;              at this site (0x80c1c345 is `lea rdi,...`), so no return value
;              is invented; what IS invented is dropping the callee's side
;              effects (S-29).
;   P29 @0xffffffff80c2082a (foff 0xa2082a, inside FUN_80c207e0)
;       expect e8 f1 99 69 ff = call 0xffffffff802ba220
;       write  e9 69 07 00 00 = jmp 0xffffffff80c20f98; rel32 0x769 from
;              next-IP 0x80c2082f (0x80c2082a+5+0x769 = 0x80c20f98). That is
;              the shared bail/merge label both gates use on failure
;              (0x80c20824 and 0x80c20836), so ONE jump skips hole #1, GATE B,
;              hole #2 and both NULL checks of [rbp-0x450]/[rbp-0x458], and
;              lands on the real "no memory parameters" block 13.60's mode-1
;              boot takes. That block (0x80c20f98..0x80c2108e) writes NEITHER
;              out-param — it stores only [rbp-0x138] and [rbp-0x480], reads
;              param_2 at 0x80c21068, calls the allocator FUN_80c1b030 at
;              0x80c21089, and on rax==0 jumps to P27 (0x80c21091). The
;              allocator's failure path writes nothing through param_2, so
;              P27's -1 is the value the caller reads (0x80c1c366-372).
; Neither [rbp-0x450] nor [rbp-0x458] is fabricated, which is why P29 is
; preferred over skipping 0x80c20855 (that call must FILL those two slots or
; the following cmp/je bails anyway; filling them would invent the memory map).
; L-246 P30 (boot 95) — S-30, the S4 preserved-physmap FAILURE BRANCH skipped.
; Boot 94's last line was `panic: removal of kernel text [0x210000, 0xef0000)
; from s4_preserved_physmap failed`, reached in the CALLER FUN_80c1c080:
;   0x80c1c6a7  call 0xffffffff80c1b030          ; interval-table removal
;   0x80c1c6ac  test rax,rax                     (48 85 c0)
;   0x80c1c6af  je   0xffffffff80c1cda0          (0f 84 eb 06 00 00)
;   0x80c1c6b5  cmp  qword ptr [rbp-0x238],0     ; the SUCCESS continuation
; FUN_80c1b030 returned 0 because the index it was given is negative:
; DAT_ffffffff83df5300 (its param_2, `&DAT_ffffffff83df5300`) holds the
; caller's local_224, which P27 set to -1 via FUN_80c207e0's out-param, and
; FUN_80c1b030's first act is `if (*param_2 < 0) return 0`. The removal is a
; hibernate/S4 bookkeeping step (its own INFO printer FUN_80c1b310 is the
; `[KERNEL] INFO: S4 preserved memory` line boot 94 printed), not a boot
; prerequisite. P30 replaces the 6-byte conditional jump with 6 NOPs of the
; same length: control falls through to 0x80c1c6b5, no reflow, nothing
; written. TASK A VERDICT (checked before patching): the fall-through window
; 0x80c1c6b5..0x80c1c6f7 reads only [rbp-0x238] (a print flag) and
; [rbp-0x120] (a physmem bound already set earlier), copies that value to
; DAT_ffffffff83e08ba0/ba8/da8, and conditionally prints; it does NOT
; dereference the interval table. The table's next reader after this point
; is FUN_80bcee70 (0x80bceef3) and it is guarded by `if (-1 < DAT_ffffffff
; 83df5300)` — exactly like FUN_80c1b310 — so a -1 index is skipped, not
; walked. S-30 records that the preserved map is left possibly-wrong.
; BYTES DERIVED: nasm -f bin, `bits 64 / org 0xffffffff80c1c6af /
; times 6 nop` -> 90 90 90 90 90 90; capstone at the org address decodes six
; `nop` totalling 6 bytes, ending exactly at 0x80c1c6b5, whose first
; instruction is `cmp qword ptr [rbp - 0x238], 0`.

; L-192 P15 (DORMANT — only if P14 ever misses the CR3 switch: uncomment and
; set PATCH_COUNT 75->76, rebuild). e9 at the pmap-activate cr3 site
; 0xffffffff80a97337 (expect 8b 44 d0 7c 48 09 c8; `mov cr3,rax` at +7 left
; intact) -> cr3fix recomputes rax, re-grafts the 7 low-window slots into the
; kernel's PML4 (PA 0x60e5000) under our still-active table, does the real
; `mov cr3`, resumes at 0xffffffff80a97341. Label = next-IP low32
; (L-190 rule: 0x80200000 + off + 5).
;   dd 0x00897337
;   dd 7
;   db 139,68,208,124,72,9,200
;   db 233
;   dd (cr3fix - 0x80a9733e)
;   db 144,144
