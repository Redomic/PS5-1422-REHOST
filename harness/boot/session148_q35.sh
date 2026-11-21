# session128.sh — Q35 MILESTONE 3 (Titania config-override model). = session123 + -device titania-f0 on pcie.0. Baseline + session117 + session123 untouched. Placement/synth per analyst spec.
# session99.sh — PARKED-MODE clone of boot99.sh (identical body except the
# parking envelope: TMO default 6 h, t2 does not kill, PS5_PARKED keeps the
# FIFOs and the VM alive for qread.sh). Same image, same probes, same fixes:
# BOOT 99 = the b98 IMAGE (75 patches, P1-P30 minus the retired
# getter-selfhandle row) + THREE HARNESS PARSER FIXES + the L-252(7) measurement
# reads. NO patch was added, removed or reordered: patches_1422.inc is
# byte-identical to the b98 one, PATCH_COUNT is 75, and the trampoline sources
# (tramp1422_16g_q35s144.asm / patches_1422.inc / meta_1422_16g_q35.inc) are untouched, so every
# nm-derived address in this script is the b98 value (re-derived below anyway).
#
# DOCTRINE (AGENTS.md + L-252(6)): skipping is WITHDRAWN. P31 — the 5x nop over
# `call 0xffffffff806b9830` at 0xffffffff80c1bef6 (the msgbuf/console ring
# init) — is NOT in this tree: `grep -c 0xc1bef6 wp3_boot/patches_1422_q35s144.inc` = 0.
# L-252 proved the cursor that #GPs at 0xffffffff80e61906 is CORRECT ARITHMETIC
# ON A CORRUPT INPUT (rax = phys_avail[idx] = 0x83e04a7000000000, a 9.5 EiB
# region end; the DMAP base + that value wraps 2^64). So the ring is PROVIDED
# by fixing phys_avail, not by deleting the init call. b99 therefore does not
# touch the guest; it MEASURES where phys_avail gets its nonsense from.
#
# WHAT CHANGED vs boot98.sh — harness only, three defect classes the auditor
# found (L-251(6); each one made a probe unable to state the truth):
#   (1) BYTE-SEQUENCE PARSERS CAPTURED THE ADDRESS COLUMN. gdb's `x/8bx`
#       prints `0x7000dd6 <sym>:\t0x55\t0x48 ...`; the old
#       findall('0x([0-9a-fA-F]{2})', txt) matched the FIRST TWO HEX DIGITS OF
#       THE ADDRESS ('0x70'), so the byte list started with 0x70 and
#       looks_like_trampoline= could never be 'yes'. Fixed by splitting the
#       address column off each line before taking bytes, and by requiring a
#       word boundary after the two digits (`0x([0-9a-fA-F]{1,2})\b`) so a
#       wider token can never be truncated into a byte. Re-checked the same
#       defect everywhere: P86-TRAMP-AT-SWITCH and P86-TRAMP-BASE (gdb side)
#       are the only two gdb `x/` byte comparisons in the file; P84-CALLSITE /
#       P84-CALLEE / P86-TRAMP-AT-PARK / P86-TRAMP-BASE / P97-PHYSAVAIL /
#       P93-MODE (QMP side) all parse through parse_xp_list(), which already
#       cuts at the ':' so the HMP address column never reaches the byte list.
#       The b98 evidence is in gdbstep1422s98.log: line 42 reads
#       `0x7000dd6:\t0x55\t0x48\t0x89\t0xe5\t0x57\t0x56\t0x52\t0x48` (the real
#       graft64 prologue) while line 43 says looks_like_trampoline=no.
#   (2) PRINTF ARITY. Three probes passed 3 arguments to a 2-%-spec format
#       (P97-MAPSEEN, P97-GETTER-STUB, P98-SELFHANDLE — the "$SLOG" argument
#       was extra). bash re-applies the format for the surplus argument, so a
#       SECOND line printed with the snapshot number in count=, minting
#       `count=1` (L-251(6), GLOG 437-442 print in pairs). Fixed: exactly one
#       argument per %s, and the snapshot number is the only variable that
#       reaches "at SNAP%s".
#   (3) ANCHORED GREPS (kept). P94-APP-MEM-ERR / P97-GETTER-STUB count only
#       lines that do NOT begin with `SYNTH:` (`grep -a ... | grep -vc
#       '^SYNTH:'`) and print raw= next to the anchored value, so a SYNTH line
#       quoting the string can never satisfy a count (a SYNTH line begins with
#       `SYNTH:` at column 0 by construction). b98's raw=1/anchored=0 pair is
#       the artifact this anchor exists for. When adding a serial grep, ask:
#       can the trampoline's own SYNTH text match it? If yes, anchor it.
#
# HARNESS SELF-CHECK (do not reintroduce; every new probe must pass all three):
#   [A] BYTES: every byte-sequence comparison must strip the producer's address
#       column first (gdb `x/` -> '0xADDR <sym>:', HMP `xp` -> 'ADDR:') and
#       must print the parsed length; a MATCH/MISMATCH that cannot report
#       MATCH is a broken probe, not a negative result.
#   [B] PRINTF: number of %-specs == number of arguments. A surplus argument
#       makes bash print the format AGAIN with the leftovers (the `count=1`
#       artifact); a missing one prints a literal %s. Count both sides.
#   [C] GREP: every count that our own text could satisfy is anchored against
#       `^SYNTH:` and reported with raw= alongside. Every probe prints on
#       entry (ENTER line), so "never ran" is distinguishable from "read 0".
#
# THE IMAGE (unchanged from b98): tags 1/2/3 + tag 0x9001 with three type-1
# E820 entries whose top is 0x80000000 (13.60's verified handoff), a 2 GiB guest,
# physfree=0x7100000, P22-P30 active. b98 measured: P97-GETTER-STUB 0 (the
# retirement worked), P98-SELFHANDLE 0 (no regression), and the wall byte-
# identical to b95/b96 — cursor 0x83dffa50ffffffb8, exception #GP at
# 0xffffffff80e61906 (`cmp [rdi+8],0x63062`).
#
# WHAT b99 ADDS (read-only; no breakpoint, no stop, no guest write — this is
# the L-252(7) measurement set, and it cannot change what the kernel does):
#   P99-CURSOR           xp /1gx 0x3e08a80  = DAT_83e08a80, the console-ring
#                        cursor written at 0x80c1cd0d and consumed at
#                        0x80c1bee9. A PROVIDED ring leaves a canonical DMAP VA
#                        here; b98 left 0x83dffa50ffffffb8. Printed raw plus a
#                        canonical yes/no (bits 63:48 all equal bit 47).
#   P99-PHYSAVAIL-ARRAY  xp /32gx 0x3e08ba0 = the WHOLE phys_avail array
#                        (b98 read slots 0-7 only, all zero; L-252 found the
#                        9.5 EiB value in an index nobody read). The line
#                        prints slot index + PA + raw qword per slot, so the
#                        slot holding 0x83e04a7000000000 is named, not guessed.
#   P99-K12              xp /2gx  0x3b89294 = the KASLR DMAP shifts (K1 at
#                        +0, K2 at +4) that build B = 0xffff800000000000 |
#                        K1<<39 | K2<<30; B is COMPUTED and printed next to the
#                        raw values (L-252: B = 0xffffafe100000000 in b98).
#   P99-E2EF88           xp /1gx  0x3e2ef88 = DAT_83e2ef88 (phys_avail>>14
#                        channel; b98 measured 0x00020f8129c00000).
#   P99-MAPPAGES         xp /4gx  0x3e08ca0 = DAT_83e08ca0 (the second array
#                        base used by FUN_80c1c080 at 0x80c1cb2c).
#   P99-TLV              xp /8gx  0x9b000   = the first 64 bytes of our own
#                        parameter TLV block (control read: our handoff IS
#                        present in the guest; if this reads zeros the block
#                        was never copied and the map is irrelevant).
#   P99-DF5530           xp /1gx  0x3df5530 = DAT_83df5530 (the byte total R15
#                        adds and stores back at 0x80c1ccb2/0x80c1cceb).
# A control read: every block prints ENTER before the read, and the QMP layer
# logs SNAP<n>-QMP-FAIL if a read fails (out-of-RAM xp returns zeros with rc
# ok — never treat a zero as "read succeeded" without the ENTER/raw pair).
#
# LITERALS: nothing moved (no table row, no SYNTH change), and the values are
# re-derived in this round from the on-disk ELF with nm/readelf, not copied:
#   nm: graft64 0x7000dd6 (TRAMP_SIG / P86-TRAMP-AT-SWITCH), g_body 0x7000e83,
#       graft_flag 0x7005d8c (GF_PA), file_off = VA - 0x7000000 + 0x1000
#       (PT_LOAD VirtAddr=PhysAddr=0x7000000, Offset=0x1000).
#   The IMGBUILD asserts below still refuse a stale image (all 11 clauses,
#   unchanged from b98 because the image is unchanged).
#
# DECISION TREE:
#   (a) P99-PHYSAVAIL-ARRAY names a slot holding 0x83e04a7000000000 -> that
#       slot is the corrupt input; next question is its writer, not the cursor.
#   (b) every slot sane (< 0x80000000) and P99-CURSOR canonical -> the wall
#       moved by b98's retirement; read the serial tail for the new exception.
#   (c) P99-TLV reads zeros -> our parameter block is absent in the guest and
#       the map cannot be feeding anything: fix the handoff copy first.
#   (d) any garbage after PT-VERIFY -> BTEXT-HIT / CR3-DOMAIN first (VOID).
#
# Everything else is boot98.sh verbatim (minus the three parser defects): fast
# wall-watch, SNAP2 opt-in, PS5_FIXED_TIMING A/B control, -smp 1, a 2 GiB
# guest, physfree=0x7100000, the whole P22-P30 chain, and every probe.
# Usage: bash session99.sh [t1] [t2] [tmo] [snap2]  (default 180 540 21600, snap2 off)
# ============================================================================
cd "$(dirname "$0")"
T1=${1:-180}
T2=${2:-540}
TMO=${3:-21600}   # park mode: 6 h envelope; t2 does NOT kill
# b97 switches (documented in the header): PS5_FIXED_TIMING=1 restores the exact
# pre-b87 fixed-timing behaviour for the A/B control, and therefore forces the
# old two-snapshot shape. Fast mode is SNAP2-off unless asked for.
SNAP2_ON=${PS5_SNAP2:-0}
[ "${PS5_FIXED_TIMING:-0}" = 1 ] && SNAP2_ON=1
[ -n "${4:-}" ] && [ "${4:-0}" != 0 ] && SNAP2_ON=1
mkdir -p /tmp/opencode || exit 1
PS5_BOOT_IPC=$(mktemp -d /tmp/ps5park.XXXXXX) || exit 1
export PS5_BOOT_IPC
trap 'if [ -z "${PS5_PARKED:-}" ]; then if [ -n "${QPID:-}" ]; then kill "$QPID" 2>/dev/null; fi; rm -f "$PS5_BOOT_IPC"/{gdb.in,gdb.out,qmp.in,qmp.out,gdb_bridge.py}; rmdir "$PS5_BOOT_IPC" 2>/dev/null; fi' EXIT
mkfifo "$PS5_BOOT_IPC"/{gdb.in,gdb.out,qmp.in,qmp.out} || exit 1
cat > "$PS5_BOOT_IPC/gdb_bridge.py" <<'PY'
import os
import select

base = os.environ['PS5_BOOT_IPC']
to_qemu = os.open(base + '/gdb.in', os.O_RDWR)
from_qemu = os.open(base + '/gdb.out', os.O_RDWR)
while True:
    ready, _, _ = select.select([0, from_qemu], [], [])
    for fd in ready:
        data = os.read(fd, 65536)
        if not data:
            raise SystemExit(0)
        stream = to_qemu if fd == 0 else 1
        while data:
            data = data[os.write(stream, data):]
PY
KRAW=${PS5_KERNEL_RAW:?supply your own legally-obtained 14.22 kernel_raw bin via PS5_KERNEL_RAW}
SLOG=serial1422s148.log
GLOG=gdbstep1422s148.log
: > "$GLOG"

QEMU=${QEMU:-$(command -v qemu-system-x86_64 || true)}
[ -z "$QEMU" ] && [ -x /usr/lib/qemu/qemu-system-x86_64 ] && QEMU=/usr/lib/qemu/qemu-system-x86_64
[ -x "$QEMU" ] || { echo "qemu not found"; exit 1; }

if [ ! -f wp3_boot/trampoline1422_16g_q35s144.elf ] || \
   [ wp3_boot/tramp1422_16g_q35s144.asm -nt wp3_boot/trampoline1422_16g_q35s144.elf ] || \
   [ wp3_boot/patches_1422_q35s144.inc -nt wp3_boot/trampoline1422_16g_q35s144.elf ] || \
   [ wp3_boot/meta_1422_16g_q35.inc -nt wp3_boot/trampoline1422_16g_q35s144.elf ]; then
      nasm -f elf32 -I wp3_boot/ -o wp3_boot/trampoline1422_16g_q35s144.o wp3_boot/tramp1422_16g_q35s144.asm 2>/dev/null || exit 1
      ld -m elf_i386 -T wp3_boot/tramp1422.ld -o wp3_boot/trampoline1422_16g_q35s144.elf wp3_boot/trampoline1422_16g_q35s144.o || exit 1
      echo "[*] built trampoline1422_16g_q35s144.elf"
fi

# IMAGE ASSERTS (b83 -> b98): never boot a stale image. Each clause is a fact
# only the CURRENT build carries: 'P23/S-23 DR6-store NOP' (b83+ patch table
# present), 'physfree=0x7100000' (b86+ our pages stay out of the free pool),
# 'PSP-MAILBOX-SEND FAKE' (b89 P24/S-24), 'P25/S-26 platform mode = 4' (b94),
# 'P26/S-27 INT3-hole call skip' (b94), 'P27/S-28 application memory
# unavailable' (b94, the graceful-failure patch), 'P28/P29/S-29' (b94, the two
# hole skips), 'P30/S-30' (b97, the S4 failure-branch skip AND its SYNTH
# clause), 'S-01..S-30' (b97, the SYNTH register range), '75 patches (P1-P30
# minus the RETIRED getter-selfhandle row' (b98: the exact table size, 76 -> 75,
# ONE row removed), 'RETIRED getter-selfhandle row' (b98: the retirement is in
# the SYNTH line) and the row-header ABSENCE check (b98: the 8 bytes c0 f9 c6 00
# 21 00 00 00 = struct.pack of 0xc6f9c0/33 must NOT appear in the image, so a
# b97-era ELF cannot re-shadow 0x9001). The ELF hash changes on every rebuild
# and is reported by the IMGBUILD line, never asserted as a literal (b97+P30
# artifact: a291428778a25a53166f494a5ac363b716821434cbcd7f522e4c9135c130efb4).
if ! strings wp3_boot/trampoline1422_16g_q35s144.elf | grep -qF 'P23/S-23 DR6-store NOP'; then
  echo "=== IMGBUILD-ASSERT-FAIL: trampoline1422_16g_q35s144.elf lacks 'P23/S-23 DR6-store NOP' — stale image, refusing to boot ===" | tee -a "$GLOG"
  exit 1
fi
if ! strings wp3_boot/trampoline1422_16g_q35s144.elf | grep -qF 'physfree=0x7100000'; then
  echo "=== IMGBUILD-ASSERT-FAIL: trampoline1422_16g_q35s144.elf does not carry physfree=0x7100000 — stale b85 image, refusing to boot ===" | tee -a "$GLOG"
  exit 1
fi
if ! strings wp3_boot/trampoline1422_16g_q35s144.elf | grep -qF 'PSP-MAILBOX-SEND FAKE'; then
  echo "=== IMGBUILD-ASSERT-FAIL: trampoline1422_16g_q35s144.elf lacks 'PSP-MAILBOX-SEND FAKE' (P24/S-24, 75 patches) — stale pre-b89 image, refusing to boot ===" | tee -a "$GLOG"
  exit 1
fi
if ! strings wp3_boot/trampoline1422_16g_q35s144.elf | grep -qF 'P25/S-26 platform mode = 4'; then
  echo "=== IMGBUILD-ASSERT-FAIL: trampoline1422_16g_q35s144.elf lacks 'P25/S-26 platform mode = 4' (P25 re-applied, 75 patches) — stale pre-b94 image, refusing to boot ===" | tee -a "$GLOG"
  exit 1
fi
# BOOT 114 / S-34 MODE-4 ASSERT (owner-mandated): the P33/S-34 code-absent ret-stubs
# (and the P26/P28/P29/P31 hole-skips) are the SAME mode-4 gate as the gate-1 carvers,
# so they are valid ONLY while platform mode==4. Assert P25 sets DAT_ffffffff81b1be0c
# (foff 0x191be0c) := 4 at patch-apply. If mode!=4, the int3-hole paths are not taken
# and these stubs would be mis-scoped.
if ! python3 -c '
import sys
s=open("wp3_boot/patches_1422_q35s144.inc").read().splitlines()
for i,l in enumerate(s):
    if l.strip().startswith("dd 0x0191be0c"):
        w=s[i+3].strip()
        sys.exit(0 if w.startswith("db 4,0,0,0") else 1)
sys.exit(1)'; then
  echo "=== IMGBUILD-ASSERT-FAIL: P25 does not set DAT_ffffffff81b1be0c:=4 (mode-4 gate unasserted) — the S-34 code-absent stubs are valid only while mode=4, refusing to boot ===" | tee -a "$GLOG"
  exit 1
fi
if ! strings wp3_boot/trampoline1422_16g_q35s144.elf | grep -qF 'P26/S-27 INT3-hole call skip'; then
  echo "=== IMGBUILD-ASSERT-FAIL: trampoline1422_16g_q35s144.elf lacks 'P26/S-27 INT3-hole call skip' (P26, 75 patches) — stale pre-b94 image, refusing to boot ===" | tee -a "$GLOG"
  exit 1
fi
if ! strings wp3_boot/trampoline1422_16g_q35s144.elf | grep -qF 'P27/S-28 application memory unavailable'; then
  echo "=== IMGBUILD-ASSERT-FAIL: trampoline1422_16g_q35s144.elf lacks 'P27/S-28 application memory unavailable' (P27, 75 patches) — stale pre-b94 image, refusing to boot ===" | tee -a "$GLOG"
  exit 1
fi
if ! strings wp3_boot/trampoline1422_16g_q35s144.elf | grep -qF 'P28/P29/S-29'; then
  echo "=== IMGBUILD-ASSERT-FAIL: trampoline1422_16g_q35s144.elf lacks 'P28/P29/S-29' (P28/P29, 75 patches) — stale pre-P28 image, refusing to boot ===" | tee -a "$GLOG"
  exit 1
fi
if ! strings wp3_boot/trampoline1422_16g_q35s144.elf | grep -qF 'P30/S-30'; then
  echo "=== IMGBUILD-ASSERT-FAIL: trampoline1422_16g_q35s144.elf lacks 'P30/S-30' (P30, 75 patches) — stale pre-b97 image (or a table without the S-30 clause), refusing to boot ===" | tee -a "$GLOG"
  exit 1
fi
if ! strings wp3_boot/trampoline1422_16g_q35s144.elf | grep -qF 'S-01..S-30'; then
  echo "=== IMGBUILD-ASSERT-FAIL: trampoline1422_16g_q35s144.elf does not declare 'S-01..S-30' — an S-29-era SYNTH line, refusing to boot ===" | tee -a "$GLOG"
  exit 1
fi
if ! strings wp3_boot/trampoline1422_16g_q35s144.elf | grep -qF '423 patches (s144'; then
  echo "=== IMGBUILD-ASSERT-FAIL: trampoline1422_16g_q35s144.elf does not declare '423 patches (s144' — a wrong-count (72/73/75/77) (or otherwise wrong) table, refusing to boot ===" | tee -a "$GLOG"
  exit 1
fi
if ! python3 -c 'import sys,struct
recs=[(0x1000,0x9a000,1),(0x9c000,0x54000,1),(0x100000,0x7fd00000,1),(0x100000000,0x380000000,1)]
pay=b"".join(struct.pack("<QQI",b,l,t) for b,l,t in recs)
blk=struct.pack("<II",0x9001,len(pay))+pay
d=open("wp3_boot/trampoline1422_16g_q35s144.elf","rb").read()
sys.exit(0 if blk in d else 1)'; then
  echo "=== IMGBUILD-ASSERT-FAIL: trampoline1422_16g_q35s144.elf does not carry the 16 GiB 0x9001 SMAP block (4 type-1 records, 88 B: [0x1000,0x9B000)+[0x9C000,0xF0000)+[0x100000,0x7FE00000)+[0x100000000,0x480000000); derived via struct.pack and matched against QEMU -M q35 -m 16G mtree, L-361) — stale/mis-sized meta_1422_16g_q35.inc, refusing to boot ===" | tee -a "$GLOG"
  exit 1
fi
# b98: THE RETIRED ROW MUST BE ABSENT FROM THE IMAGE. The row's header word is
# `dd 0x00c6f9c0 / dd 33` (little-endian c0 f9 c6 00 21 00 00 00, DERIVED here
# with python struct.pack("<II",0xc6f9c0,33)); the b97 artifact carried it, a
# b98 image must not. A b97-era ELF would re-shadow 0x9001 and the run would
# measure the stub again.
if ! python3 -c 'import sys,struct; d=open("wp3_boot/trampoline1422_16g_q35s144.elf","rb").read(); sys.exit(0 if struct.pack("<II",0xc6f9c0,33) not in d else 1)'; then
  echo "=== IMGBUILD-ASSERT-FAIL: trampoline1422_16g_q35s144.elf still carries the getter-selfhandle row header (0x00c6f9c0/33) — the 0x9001 stub would shadow the map again, refusing to boot ===" | tee -a "$GLOG"
  exit 1
fi
if ! strings wp3_boot/trampoline1422_16g_q35s144.elf | grep -qF 'RETIRED getter-selfhandle row'; then
  echo "=== IMGBUILD-ASSERT-FAIL: trampoline1422_16g_q35s144.elf does not declare 'RETIRED getter-selfhandle row' in its SYNTH line — a b97-era image, refusing to boot ===" | tee -a "$GLOG"
  exit 1
fi

# Provenance: the exact image + patch table about to be handed to QEMU.
IMGBUILD_ELF_HASH=$(sha256sum wp3_boot/trampoline1422_16g_q35s144.elf | awk '{print $1}')
IMGBUILD_INC_HASH=$(sha256sum wp3_boot/patches_1422_q35s144.inc | awk '{print $1}')
echo "=== IMGBUILD: trampoline1422_16g_q35s144.elf sha256 $IMGBUILD_ELF_HASH ; patches_1422.inc sha256 $IMGBUILD_INC_HASH ===" >> "$GLOG"

setsid timeout -k 5s "${TMO}s" "$QEMU" -L ./bios \
  -M q35 -cpu EPYC -m 16G -smp 1 -nic none \
  -global hpet.timers=4 \
  -device pcie-root-port,id=pad,bus=pcie.0,addr=0x17.0,chassis=2,bus-reserve=0x3e \
  -device pcie-root-port,id=trc,bus=pcie.0,addr=0x18.0,chassis=1 \
  -device titania-f0,bus=trc,addr=0.0,multifunction=on \
  -device belize-glue,bus=trc,addr=0.1 \
  -device ari-stub,bus=trc,addr=1.5,device=0x90c8 \
  -device ari-stub,bus=trc,addr=1.6,device=0x90c9 \
  -device ari-stub,bus=trc,addr=1.7,device=0x90ca \
  -device ari-stub,bus=trc,addr=2.0,device=0x90cb,multifunction=on \
  -kernel wp3_boot/trampoline1422_16g_q35s144.elf -initrd "$KRAW" \
  -display none -serial null -monitor none -S \
  -chardev "pipe,id=qmp,path=$PS5_BOOT_IPC/qmp" -mon chardev=qmp,mode=control \
  -chardev file,id=dbg,path=$SLOG \
  -device isa-debugcon,iobase=0x408,chardev=dbg \
  -d int -D /tmp/opencode/qemu1422s148-int.log \
  -no-reboot -no-shutdown -chardev "pipe,id=gdb,path=$PS5_BOOT_IPC/gdb" -gdb chardev:gdb >/dev/null 2>qemu_err_s148.txt &
LAUNCH_PID=$!
# The QEMU cmdline carries the unique IPC path, so resolve the real qemu pid
# (the setsid/timeout wrapper shares the same argv). QPID must be QEMU itself:
# park-stop.sh uses it for the SIGTERM fallback, and `kill -0` must test the VM.
QPID=
for _i in $(seq 1 50); do
  for _p in $(pgrep -f "path=$PS5_BOOT_IPC/qmp" 2>/dev/null); do
    case "$(tr -d '\0' < /proc/$_p/comm 2>/dev/null)" in
      qemu-system-x86*) QPID=$_p; break ;;
    esac
  done
  [ -n "$QPID" ] && break
  sleep 0.1
done
if [ -z "$QPID" ]; then
  QPID=$LAUNCH_PID
  echo "WARN: qemu pid not resolved (setsid launcher pid $LAUNCH_PID) — park-stop falls back to it"
fi
STARTED=$(date -Is 2>/dev/null || date)
echo "QEMU pid $QPID (detached via setsid; TCG, frozen with -S, local control pipes); launcher pid $LAUNCH_PID"

qmp() { # $1 = command json
  python3 - "$1" <<'PY'
import json, os, select, sys, time

base = os.environ['PS5_BOOT_IPC']
reader = os.open(base + '/qmp.out', os.O_RDWR)
writer = os.open(base + '/qmp.in', os.O_RDWR)
request = json.loads(sys.argv[1])

def send(message):
    os.write(writer, json.dumps(message).encode() + bytes([10]))

send({'execute': 'qmp_capabilities', 'id': 'caps'})
request['id'] = 'command'
send(request)
deadline = time.monotonic() + 8
buffer = b''
while time.monotonic() < deadline:
    readable, _, _ = select.select([reader], [], [], max(0, deadline - time.monotonic()))
    if not readable:
        break
    buffer += os.read(reader, 65536)
    while bytes([10]) in buffer:
        line, _, buffer = buffer.partition(bytes([10]))
        reply = json.loads(line)
        if reply.get('id') == 'command':
            print(json.dumps(reply))
            sys.exit(0 if 'return' in reply else 3)
sys.exit('QMP command timed out: ' + request['execute'])
PY
}

snapqmp() { # $1 = snapshot number; QMP/HMP only — no gdb attach after the arming session
  # L-225: the FIFO gdbstub serves exactly ONE client per run. After the arming
  # session detaches at the CR3 switch, every later gdb attach in boot 81 was
  # garbage ("Bogus trace status reply", "Unknown thread 1", every x/ "Cannot
  # access memory"). SNAPs therefore use QMP only: human-monitor-command
  # "info registers" (the L-212 source that DOES expose DR0-DR7) and HMP xp
  # physical reads. No breakpoint, no resume, no gdb here.
  # Read rules proven in coord/notes/qmp-snapshot.md: (1) an out-of-RAM xp
  # returns zeros with rc ok, so the FIRST read is a control (kernel PML4[0]
  # @PA 0x60e5000 — nonzero 0x40a1023 in the kernel domain); a zero control
  # marks every later dump in this SNAP VOID. (2) HMP xp address columns have
  # no 0x prefix (format %016x:), so parsers must not require one.
  python3 - "$1" >> "$GLOG" 2>&1 <<'PY'
import json, os, re, select, sys, time

snap = sys.argv[1]
base = os.environ['PS5_BOOT_IPC']
reader = os.open(base + '/qmp.out', os.O_RDWR)
writer = os.open(base + '/qmp.in', os.O_RDWR)
buf = b''
seq = 0

def fail(what):
    print('SNAP%s-QMP-FAIL: %s' % (snap, what), flush=True)

def send(msg):
    os.write(writer, json.dumps(msg).encode() + bytes([10]))

def read_until(want, timeout=10):
    global buf
    deadline = time.monotonic() + timeout
    while True:
        while bytes([10]) in buf:
            line, _, buf = buf.partition(bytes([10]))
            line = line.strip()
            msg = None
            if line:
                try:
                    msg = json.loads(line)
                except Exception:
                    msg = None
            if msg is not None and msg.get('id') == want:
                return msg
        left = deadline - time.monotonic()
        if left <= 0:
            return None
        ready, _, _ = select.select([reader], [], [], left)
        if not ready:
            return None
        buf += os.read(reader, 65536)

def hmp(command, name):
    global seq
    seq += 1
    want = 'h%d' % seq
    send({'execute': 'human-monitor-command',
          'arguments': {'command-line': command}, 'id': want})
    reply = read_until(want)
    if reply is None:
        fail('%s: QMP timeout for HMP: %s' % (name, command))
        return None
    if 'error' in reply:
        fail('%s: QMP error for HMP %s: %s' % (name, command, json.dumps(reply['error'])))
        return None
    text = reply.get('return')
    if not isinstance(text, str) or not text.strip():
        fail('%s: empty HMP return for: %s' % (name, command))
        return None
    return text

def dump(name, command):
    text = hmp(command, name)
    if text is not None:
        print('SNAP%s-QMP %s' % (snap, name))
        print(text.rstrip())
    return text

def parse_xp(text):
    # HMP xp line format (qmp-snapshot.md): 000000000060e5000: 0x00000000040a1023
    # The ADDRESS column has NO 0x prefix — match %016x:, never 0x<addr>:.
    m = re.search(r'^\s*([0-9a-fA-F]+):\s*(?:0x)?([0-9a-fA-F]+)', text)
    if m:
        return int(m.group(2), 16)
    m = re.search(r':\s*(?:0x)?([0-9a-fA-F]+)\s*$', text)
    if m:
        return int(m.group(1), 16)
    return None

try:
    send({'execute': 'qmp_capabilities', 'id': 'caps'})
    if read_until('caps') is None:
        fail('qmp_capabilities handshake timed out — no QMP channel')
        sys.exit(1)

    # CONTROL FIRST (qmp-snapshot.md read rule 1): an out-of-RAM xp returns
    # zeros with rc ok, so an all-zero dump is ambiguous. 0x60e5000 is kernel
    # PML4 slot 0, nonzero (0x40a1023, our P13/P21 graft) in the kernel domain.
    ctrl_text = hmp('xp /1gx 0x60e5000', 'CONTROL PML4[0] @PA=0x60e5000')
    ctrl = parse_xp(ctrl_text) if ctrl_text is not None else None
    if ctrl is None:
        print('SNAP%s-CONTROL-FAIL: PML4[0] unreadable via HMP xp — snapshot read path is wrong, treat all data in this SNAP as VOID' % snap)
    elif ctrl == 0:
        print('SNAP%s-CONTROL-FAIL: PML4[0]=0 — snapshot read path is wrong, treat all data in this SNAP as VOID' % snap)
    else:
        print('SNAP%s-CONTROL PML4[0]=0x%x OK' % (snap, ctrl))

    regs = dump('info registers (HMP, verbatim)', 'info registers')

    cr3 = None
    if regs is not None:
        m = re.search(r'CR3=\s*(?:0x)?([0-9a-fA-F]+)', regs)
        if m:
            cr3 = int(m.group(1), 16)
    if cr3 is None:
        print('CR3-DOMAIN: UNKNOWN (no cr3 in QMP info registers — target not stopped?)')
    elif cr3 == 0x40a0000:
        print('CR3-DOMAIN: TRAMPOLINE(0x40a0000) — guest NOT in kernel domain, downstream output VOID')
    elif cr3 == 0x60e5000:
        print('CR3-DOMAIN: KERNEL(0x60e5000)')
    else:
        print('CR3-DOMAIN: OTHER (0x%x — verify vs 0x60e5000)' % cr3)

    dump('P23-B81UD-STACK PA=0x2f80c18', 'xp /32gx 0x2f80c18')
    dump('P23-B81DF-STACK PA=0x2f80930', 'xp /32gx 0x2f80930')

    def xp_qword(name, pa):
        text = hmp('xp /1gx 0x%x' % pa, name)
        if text is None:
            return None
        print('SNAP%s-QMP %s raw: %s' % (snap, name, ' '.join(text.split())))
        value = parse_xp(text)
        if value is None:
            fail('%s: unparseable xp return: %r' % (name, text))
            return None
        print('SNAP%s-QMP %s = 0x%016x (P=%d PS=%d)' % (snap, name, value, value & 1, (value >> 7) & 1))
        return value

    def root_for(tag):
        # One root rule for every walk: the live CR3 when the register read
        # succeeded, else the 0x60e5000 kernel table with a DISCLOSED
        # fallback line (never a silent default).
        if cr3 is None:
            print('SNAP%s-QMP %s cr3 missing; disclosed fallback root=0x60e5000' % (snap, tag))
            return 0x60e5000
        return cr3 & 0x000ffffffffff000

    def walk_va(va, tag, root, pd_only=False):
        # Four-level page walk, ONE HMP xp per level entry. This is the b82
        # P23-WILDVA machinery, extracted so every b85 walk uses the SAME code
        # path with a different VA (callers print the VA/indices header and
        # choose root via root_for()). pd_only stops after the PD (L2) entry.
        i4 = (va >> 39) & 0x1ff
        i3 = (va >> 30) & 0x1ff
        i2 = (va >> 21) & 0x1ff
        i1 = (va >> 12) & 0x1ff
        e4 = xp_qword('%s L4[0x%x] @PA=0x%x' % (tag, i4, root + i4 * 8), root + i4 * 8)
        if e4 is None:
            return None
        if not (e4 & 1):
            print('SNAP%s-QMP %s L4 entry not present — VA 0x%x unmapped at this level' % (snap, tag, va))
            return None
        if e4 & 0x80:
            print('SNAP%s-QMP %s L4 PS bit set (reserved in 4-level paging; ignored)' % (snap, tag))
        t3 = e4 & 0x000ffffffffff000
        e3 = xp_qword('%s L3[0x%x] @PA=0x%x' % (tag, i3, t3 + i3 * 8), t3 + i3 * 8)
        if e3 is None:
            return None
        if not (e3 & 1):
            print('SNAP%s-QMP %s L3 entry not present — walk ends here' % (snap, tag))
            return None
        if e3 & 0x80:
            print('SNAP%s-QMP %s L3 1GiB PS entry — used' % (snap, tag))
            return (e3 & 0x000fffffc0000000) | (va & 0x3fffffff)
        t2 = e3 & 0x000ffffffffff000
        e2 = xp_qword('%s L2[0x%x] @PA=0x%x' % (tag, i2, t2 + i2 * 8), t2 + i2 * 8)
        if e2 is None:
            return None
        if not (e2 & 1):
            print('SNAP%s-QMP %s L2 entry not present — walk ends here' % (snap, tag))
            return None
        if e2 & 0x80:
            print('SNAP%s-QMP %s L2 2MiB PS entry — used' % (snap, tag))
            return (e2 & 0x000fffffffe00000) | (va & 0x1fffff)
        if pd_only:
            print('SNAP%s-QMP %s L2 entry is a table (PT walk skipped by pd_only); PD PA field=0x%x'
                  % (snap, tag, e2 & 0x000ffffffffff000))
            return None
        t1 = e2 & 0x000ffffffffff000
        e1 = xp_qword('%s L1[0x%x] @PA=0x%x' % (tag, i1, t1 + i1 * 8), t1 + i1 * 8)
        if e1 is None:
            return None
        if e1 & 1:
            return (e1 & 0x000ffffffffff000) | (va & 0xfff)
        print('SNAP%s-QMP %s L1 entry not present — walk ends here' % (snap, tag))
        return None

    va = 0xffffffff080f1006
    i4 = (va >> 39) & 0x1ff
    i3 = (va >> 30) & 0x1ff
    i2 = (va >> 21) & 0x1ff
    i1 = (va >> 12) & 0x1ff
    print('SNAP%s-QMP P23-WILDVA VA=0x%x indices: pml4=0x%x pdpt=0x%x pd=0x%x pt=0x%x' % (snap, va, i4, i3, i2, i1))
    root = root_for('P23-WILDVA')
    pa = walk_va(va, 'P23-WILDVA', root)

    if pa is None:
        print('SNAP%s-QMP P23-WILDVA resolved PA=none (walk did not reach a present leaf)' % snap)
    else:
        print('SNAP%s-QMP P23-WILDVA resolved PA=0x%x' % (snap, pa))
        dump('P23-WILDVA resolved-PA bytes', 'xp /32bx 0x%x' % pa)

    dump('P23-WILDVA-IDENT PA=0x80f1006', 'xp /32bx 0x80f1006')
    dump('P23-VA20 PA=0x4097020', 'xp /32bx 0x4097020')

    # === BOOT 83: four PASSIVE reads (capture only — no breakpoint, no stop,
    # no config change). Every block logs on ENTER so a block that never runs
    # is distinguishable from one that read zeros, and every read is ONE HMP
    # xp: all derived lines below come from that same text, never a re-read.

    def parse_xp_list(text):
        # same line format as parse_xp: %016x: 0x... 0x...  (no 0x on the
        # address column). Returns every qword value in read order.
        vals = []
        for line in text.splitlines():
            if ':' in line:
                for tok in re.findall(r'0x([0-9a-fA-F]+)', line.split(':', 1)[1]):
                    vals.append(int(tok, 16))
        return vals

    def read_qwords(name, command, count):
        print('SNAP%s-QMP %s ENTER' % (snap, name))
        text = hmp(command, name)
        if text is None:
            return None
        print('SNAP%s-QMP %s raw:' % (snap, name))
        print(text.rstrip())
        vals = parse_xp_list(text)
        if len(vals) < count:
            fail('%s: parsed only %d of %d qwords from the xp return' % (name, len(vals), count))
            return None
        return vals[:count]

    # (1) The 32 x 0x28 static-TMR descriptor table that
    #     commit_registered_static_tmr_region() (0xffffffff80800720) walks
    #     (L-227: RBX=0 at the #UD => it was on ENTRY 0). BSS-zero in the
    #     image, so this content is built at runtime.
    TMR_N, TMR_PA = 32, 0x39110d8
    tmr = read_qwords('P83-TMRTABLE PA=0x39110d8', 'xp /160gx 0x%x' % TMR_PA, TMR_N * 5)
    if tmr is not None:
        tmr_nz = 0
        for i in range(TMR_N):
            q = tmr[i * 5:(i + 1) * 5]      # 0x28 bytes = 5 qwords
            if any(q):
                tmr_nz += 1
                ptr, e1, arg1, arg2, e4 = q
                # +0x08 id (pad in the high dword), +0x20 state (low dword of
                # the +0x20 qword), +0x24 status (its high dword).
                print('SNAP%s-QMP P83-TMR[%d] ptr=0x%016x id=%d arg1=0x%016x arg2=0x%016x state=%d status=0x%08x'
                      % (snap, i, ptr, e1 & 0xffffffff, arg1, arg2, e4 & 0xffffffff, e4 >> 32))
        print('SNAP%s-QMP P83-TMRTABLE SUMMARY: %d of %d entries not all-zero' % (snap, tmr_nz, TMR_N))

    # (2) The six qwords up to and including the #UD-time RSP 0x2f80c18
    #     (VA 0xffffffff82f80c18 -> PA 0x2f80c18: the kernel-window rule
    #     proven by b82's own read of this stack). Slot 0x2f80c10 is
    #     [RSP-8]: the value a `push <computed>; ret` would have consumed.
    SBLW_PA = 0x2f80bf0
    sb = read_qwords('P83-UD-STACK-BELOW PA=0x2f80bf0', 'xp /6gx 0x%x' % SBLW_PA, 6)
    if sb is not None:
        for k, v in enumerate(sb):
            pa = SBLW_PA + k * 8
            note = ''
            if pa == 0x2f80c10:
                note = '  <- [RSP-8], push-ret candidate slot'
            elif pa == 0x2f80c18:
                note = '  <- #UD-time RSP'
            print('SNAP%s-QMP P83-UD-STACK off=0x%x PA=0x%x = 0x%016x%s'
                  % (snap, pa & 0xfff, pa, v, note))

    # (3) TSS.IST1 = TR.base + 0x24 (TSS64 layout), the stack the b82 #DF
    #     frame lives on. TR.base comes from the `info registers` text
    #     captured ABOVE (no second register read). Kernel-window VA -> PA
    #     uses the b82-proven rule VA-0xffffffff80000000 (0xffffffff82f80c18
    #     -> 0x2f80c18). Unparsed TR line is reported, never guessed.
    print('SNAP%s-QMP P83-TSS-IST1 ENTER (TR.base from the info registers text above)' % snap)
    tr_base = None
    if regs is not None:
        mtr = re.search(r'^TR\s*=\s*([0-9a-fA-F]+)\s+([0-9a-fA-F]+)', regs, re.M)
        if mtr:
            tr_base = int(mtr.group(2), 16)
    if tr_base is None:
        print('P83-TSS-IST1-FAIL: TR line unparsed')
    else:
        if 0xffffffff80000000 <= tr_base < 0xffffffffc0000000:
            ist_pa = tr_base - 0xffffffff80000000 + 0x24
            rule = 'VA-0xffffffff80000000'
        else:
            ist_pa = (tr_base + 0x24) & 0xffffffffffffffff
            rule = 'raw, TR.base outside the kernel window'
        print('SNAP%s-QMP P83-TSS-IST1 TR.base=0x%x +0x24 -> PA=0x%x [%s]'
              % (snap, tr_base, ist_pa, rule))
        ist_text = hmp('xp /1gx 0x%x' % ist_pa, 'P83-TSS-IST1')
        if ist_text is not None:
            print('SNAP%s-QMP P83-TSS-IST1 raw: %s' % (snap, ' '.join(ist_text.split())))
            ist = parse_xp_list(ist_text)
            if ist:
                print('SNAP%s-QMP P83-TSS-IST1 IST1 @PA=0x%x = 0x%016x' % (snap, ist_pa, ist[0]))
            else:
                fail('P83-TSS-IST1: unparseable xp return: %r' % ist_text)

    # (4) The S-18 handoff param-TLV at PA 0x9b000, for comparison with (1).
    tlv = read_qwords('P83-PARAM-TLV PA=0x9b000', 'xp /32gx 0x9b000', 32)
    if tlv is not None:
        print('SNAP%s-QMP P83-PARAM-TLV SUMMARY: %d of 32 qwords nonzero'
              % (snap, sum(1 for v in tlv if v)))

    # === BOOT 84: four PASSIVE reads (capture only — no breakpoint, no stop,
    # no config change, no guest mutation). Every block logs on ENTER so a
    # block that never runs is distinguishable from one that read zeros, and
    # every derived line comes from ONE HMP xp, never a re-read.

    def read_bytes(name, command, count):
        print('SNAP%s-QMP %s ENTER (cmd: %s)' % (snap, name, command))
        text = hmp(command, name)
        if text is None:
            return None
        print('SNAP%s-QMP %s raw:' % (snap, name))
        print(text.rstrip())
        vals = parse_xp_list(text)
        if len(vals) < count:
            fail('%s: parsed only %d of %d bytes from the xp return' % (name, len(vals), count))
            return None
        return vals[:count]

    def hx(bs):
        return ' '.join('%02x' % b for b in bs)

    # (1) THE SINGLE MOST IMPORTANT LINE OF THE BOOT: the `call
    #     psp_mbox_map_tmr` at VA 0xffffffff80800771 (PA 0x800771) as it
    #     exists at runtime, byte-for-byte against the image. The read starts
    #     one byte early (0x800770) so the `e8` opcode is unambiguous.
    #     Image bytes verified straight from analysis/1422/kernel_raw_1422.bin
    #     at file_off = VA - 0xffffffff80200000 = 0x600771:
    #     e8 da 29 cc ff  (rel32 -0x33d626 from 0xffffffff80800776 ->
    #     target 0xffffffff804c3150, the psp_mbox_map_tmr entry).
    CS_PA = 0x800770
    CS_IMG = [0xe8, 0xda, 0x29, 0xcc, 0xff]
    cs = read_bytes('P84-CALLSITE PA=0x800770', 'xp /24bx 0x%x' % CS_PA, 24)
    if cs is None:
        print('P84-CALLSITE UNREADABLE: read path failed (see SNAP%s-QMP-FAIL above) — neither MATCH nor MISMATCH emitted' % snap)
    else:
        cs_rt = cs[1:6]   # 0x800771..0x800775
        print('SNAP%s-QMP P84-CALLSITE runtime@PA=0x800771: %s' % (snap, hx(cs_rt)))
        if cs_rt == CS_IMG:
            print('P84-CALLSITE MATCH: e8 da 29 cc ff (call 0xffffffff804c3150 intact at runtime)')
        else:
            print('P84-CALLSITE MISMATCH: runtime=%s image=e8 da 29 cc ff' % hx(cs_rt))

    # (2) The callee entry psp_mbox_map_tmr @VA 0xffffffff804c3150 (PA
    #     0x4c3150), compared against the image prologue. Image bytes from
    #     analysis/1422/kernel_raw_1422.bin at file_off = 0x2c3150:
    #     55 48 89 e5 (push rbp; mov rbp,rsp) 41 57 41 56 41 55 41 54 53
    #     (push r15/r14/r13/r12/rbx) 48 83 ec 58 (sub rsp,0x58) = 17 bytes.
    #     If this MATCHes while (1) MATCHes, the image's call site and callee
    #     both survived: the transfer itself is what went elsewhere.
    CA_PA = 0x4c3150
    CA_IMG = [0x55, 0x48, 0x89, 0xe5, 0x41, 0x57, 0x41, 0x56, 0x41, 0x55,
              0x41, 0x54, 0x53, 0x48, 0x83, 0xec, 0x58]
    ca = read_bytes('P84-CALLEE PA=0x4c3150', 'xp /32bx 0x%x' % CA_PA, len(CA_IMG))
    if ca is None:
        print('P84-CALLEE UNREADABLE: read path failed (see SNAP%s-QMP-FAIL above) — neither MATCH nor MISMATCH emitted' % snap)
    else:
        print('SNAP%s-QMP P84-CALLEE runtime@PA=0x4c3150: %s' % (snap, hx(ca)))
        if ca == CA_IMG:
            print('P84-CALLEE MATCH: %s' % hx(CA_IMG))
        else:
            print('P84-CALLEE MISMATCH: runtime=%s image=%s' % (hx(ca), hx(CA_IMG)))

    # (3) The #DF (vector 8) stack itself: TSS.IST1 = 0xffffffff83dfca80,
    #     measured in b83 (TR.base 0xffffffff83df7000 + 0x24); PA by the
    #     b82-proven kernel-window rule VA-0xffffffff80000000 -> 0x3dfca80.
    #     This stack has never been readable before: the b82/b83 #DF frame
    #     fired inside the report machine (RIP 0xffffffff805f7192), so the
    #     frame should be the vector-8 hardware interrupt frame. Annotation
    #     only: qwords that look like code / kernel-stack addresses are
    #     tagged, never interpreted.
    DF_PA, DF_N = 0x3dfca80, 24
    print('SNAP%s-QMP P84-DFFRAME ENTER: TSS.IST1=0xffffffff83dfca80 (#DF vector 8 stack) -> PA=0x%x, %d qwords'
          % (snap, DF_PA, DF_N))
    df = read_qwords('P84-DFFRAME PA=0x3dfca80', 'xp /24gx 0x3dfca80', DF_N)
    if df is not None:
        for k, v in enumerate(df):
            pa = DF_PA + k * 8
            tags = []
            if 0xffffffff80200000 <= v <= 0xffffffff80ef0000:
                tags.append('<CODE>')
            if 0xffffffff82f80000 <= v <= 0xffffffff83000000:
                tags.append('<KSTACK>')
            print('SNAP%s-QMP P84-DFFRAME off=0x%03x PA=0x%08x = 0x%016x %s'
                  % (snap, k * 8, pa, v, ' '.join(tags)))

    # (4) SECOND independent capture of the S-18 param-TLV at PA 0x9b000 in
    #     the same session, on top of the unchanged P83 block above. b83 read
    #     0 of 32 nonzero while the SYNTH: line declares the TLV active; a
    #     repeat at the same SNAP separates a transient from a
    #     never-written/cleared block.
    tlv2 = read_qwords('P84-PARAM-TLV2 (repeat of P83-PARAM-TLV — b83 read 0 of 32 nonzero)',
                       'xp /32gx 0x9b000', 32)
    if tlv2 is not None:
        print('SNAP%s-QMP P84-PARAM-TLV2 SUMMARY: %d of 32 qwords nonzero'
              % (snap, sum(1 for v in tlv2 if v)))

    # === BOOT 85: five PASSIVE reads (capture only — no breakpoint, no stop,
    # no config change, no guest mutation). Every block logs on ENTER so a
    # block that never runs is distinguishable from one that read zeros, and
    # every derived line comes from ONE HMP xp, never a re-read.
    #
    # THE QUESTION b85 ANSWERS (b84 SNAP1): the patch P5 at map_tmr entry
    # replaced the prologue with e9 <rel32>, and rel32 0x86b3dccb =
    # -0x794c2381 from next-IP 0xffffffff804c3155 lands on
    # 0xffffffff07000e20 = window 0xffffffff00000000 | PA 0x07000dd4, i.e.
    # the link address of graft64 (nm: 07000dd4 t graft64; the ELF LOAD
    # segment is PhysAddr 0x07000000). The arithmetic is therefore right.
    # Yet graft64's first-call oracle (TMRCALL) never printed and the #UD is
    # at a DIFFERENT window VA, with RSP untouched by graft64's `push rbp`.
    # So the jmp was taken and the page it landed on is not our graft64.
    # Prime suspect: PD_ID slot 0x38 is one of the 35 foreign entries the
    # kernel rewrites (b80 fingerprint: slots 32-66 hold user-VA-as-PA
    # garbage). These reads MEASURE it.

    def rd_one(name, command):
        # ONE HMP xp -> raw text -> (none | empty list | parsed qword list).
        print('SNAP%s-QMP %s ENTER (cmd: %s)' % (snap, name, command))
        text = hmp(command, name)
        if text is None:
            return None
        print('SNAP%s-QMP %s raw:' % (snap, name))
        print(text.rstrip())
        vals = parse_xp_list(text)
        if not vals:
            fail('%s: unparseable xp return: %r' % (name, text))
            return None
        return vals

    # graft64's expected first bytes, DERIVED FROM THE LINK IMAGE ITSELF
    # (not typed from a note): wp3_boot/trampoline1422_16g_q35s144.elf, LOAD segment
    # FileSiz 0x1d6e / VirtAddr=PhysAddr=0x07000000 / offset 0x1000, so
    # file_off = 0x7000dd6 - 0x7000000 + 0x1000 = 0x1dd6. Bytes there:
    #   55 48 89 e5 57 56 52 48 8b 04 25 8c 5d 00 07 48 85 c0 75 6a ...
    #   push rbp; mov rbp,rsp; push rdi; push rsi; push rdx;
    #   mov rax,[0x70005cac] (graft_flag); test rax,rax; jne .g_oracle_done
    # NOTE: the load is ABSOLUTE-addressed (`48 8b 04 25 <abs32>`), not
    # RIP-relative (`48 8b 05 <rel32>`): nasm's elf32 REX encoding emitted
    # the absolute form (cf. L-187's encoding note). The five-byte
    # discriminator is 55 48 89 e5 57 (it ends on our own `push rdi`); bytes
    # 5-11 are checked separately so the absolute-oracle form is visible,
    # not swallowed.
    # SYMBOL DRIFT, re-derived from the installed ELF's own nm each boot.
    #   THIS image (b98, getter row retired): graft_flag 0x7005d8c — nm prints
    #   `07005d8c`, and graft64's abs32 operand (48 8b 04 25 8c 5d 00 07)
    #   encodes exactly 0x7005d8c, so symbol and instruction agree.
    #   L-245 CORRECTION (b97): boot 94's probe read PA 0x70005afc — an
    #   extra hex digit = 0x070005afc = 1.75 GiB of ordinary zero RAM —
    #   instead of the symbol 0x7005afc (nm: 07005afc). P85-GRAFTFLAG's
    #   `is_zero=yes` in b94 is therefore a PROBE-ADDRESS typo, NOT evidence
    #   that the trampoline's abs32 references resolve to a different PA.
    #   (Same class as the wrong-expected-length trap: a literal that looks
    #   right in the same notation but is one digit off proves nothing.)
    # G64_12's last byte IS graft_flag's low byte (the oracle's absolute
    # `mov rax,[imm32]`), so it follows the symbol: 0xcc in b88, 0xfc in b94/b97,
    # 0x8c here.
    # G64_5 and TRAMP_SIG are the graft64 prologue, which did NOT change.
    G64_5 = [0x55, 0x48, 0x89, 0xe5, 0x57]
    G64_12 = [0x55, 0x48, 0x89, 0xe5, 0x57, 0x56, 0x52, 0x48, 0x8b, 0x04, 0x25, 0x8c]

    # (1) Walk VA 0xffffffff07000dd6 (the P5 jmp target) through the LIVE
    #     kernel table, then read the bytes it resolves to. Healthy result:
    #     PD idx=0x38, 2MiB PS entry, resolved PA 0x7000dd6, bytes 55 48 89 e5 57.
    #     Anything else names the substitution directly.
    TW_VA = 0xffffffff07000dd6
    print('SNAP%s-QMP P85-THUNKWALK VA=0xffffffff07000dd6 ENTER (P5 jmp target; expect PD idx=0x38, 2MiB PS, PA 0x7000dd6)' % snap)
    print('SNAP%s-QMP P85-THUNKWALK indices: pml4(L4)=0x%x pdpt(L3)=0x%x pd(L2)=0x%x pt(L1)=0x%x'
          % (snap, (TW_VA >> 39) & 0x1ff, (TW_VA >> 30) & 0x1ff,
             (TW_VA >> 21) & 0x1ff, (TW_VA >> 12) & 0x1ff))
    tw_pa = walk_va(TW_VA, 'P85-THUNKWALK', root_for('P85-THUNKWALK'))
    if tw_pa is None:
        print('P85-THUNKWALK RESOLVED PA=none bytes_match_graft64=no (walk did not reach a present leaf)')
    else:
        print('SNAP%s-QMP P85-THUNKWALK resolved PA=0x%x (expected 0x7000dd6)' % (snap, tw_pa))
        tw_bytes = read_bytes('P85-THUNKWALK BYTES PA=0x%x' % tw_pa, 'xp /32bx 0x%x' % tw_pa, 32)
        if tw_bytes is None:
            print('P85-THUNKWALK RESOLVED PA=0x%x bytes_match_graft64=no (bytes unreadable — see SNAP%s-QMP-FAIL)' % (tw_pa, snap))
        else:
            print('SNAP%s-QMP P85-THUNKWALK bytes@PA=0x%x: %s' % (snap, tw_pa, hx(tw_bytes)))
            match = tw_bytes[:5] == G64_5
            print('P85-THUNKWALK RESOLVED PA=0x%x bytes_match_graft64=%s'
                  % (tw_pa, 'yes' if match else 'no'))

    # (2) PD_ID slot 0x38 (56), the PD entry the THUNKWALK uses:
    #     PA 0x40a4000 + 0x38*8 = 0x40a41c0. A healthy identity entry is
    #     0x7000000 | flags with PS (bit 7) set; if the kernel rewrote this
    #     slot, the PA field says where the window VA actually goes.
    S38_PA = 0x40a41c0
    s38 = rd_one('P85-PDID-SLOT38 PA=0x40a41c0', 'xp /1gx 0x%x' % S38_PA)
    if s38 is not None:
        v = s38[0]
        pa_field = v & 0x000fffffffe00000
        present = v & 1
        ps = (v >> 7) & 1
        print('SNAP%s-QMP P85-PDID-SLOT38 entry=0x%016x present=%d PS=%d pa_field=0x%x'
              % (snap, v, present, ps, pa_field))
        ident = bool(present and ps and pa_field == 0x7000000)
        print('P85-PDID-SLOT38 identity=%s' % ('yes' if ident else 'no'))

    # (3) graft64 as physically loaded at PA 0x7000dd6 — the trampoline copy,
    #     independent of any page table. If this matches the link image while
    #     (1) resolves elsewhere, the substitution is in the MAPPING; if this
    #     also differs, the physical page itself is not our image.
    g64 = read_bytes('P85-GRAFT64-PHYS PA=0x7000dd6', 'xp /32bx 0x7000dd6', 32)
    if g64 is None:
        print('P85-GRAFT64-PHYS matches_link_image=no read=FAILED (see SNAP%s-QMP-FAIL)' % snap)
    else:
        print('SNAP%s-QMP P85-GRAFT64-PHYS bytes@PA=0x7000dd6: %s' % (snap, hx(g64)))
        m5 = g64[:5] == G64_5
        print('P85-GRAFT64-PHYS matches_link_image=%s (first 5: %s vs %s)'
              % ('yes' if m5 else 'no', hx(g64[:5]), hx(G64_5)))
        m12 = g64[:12] == G64_12
        print('SNAP%s-QMP P85-GRAFT64-PHYS abs_oracle=%s (first 12: %s vs %s)'
              % (snap, 'yes' if m12 else 'no', hx(g64[:12]), hx(G64_12)))

    # (4) graft_flag (nm: 070055fc b graft_flag in the b89 image; .bss,
    #     `resq 1`; b88 had 070054cc, b86/b87 070053ec).
    #     graft64's oracle is `mov rax,[graft_flag]; test rax,rax; jne
    #     .g_oracle_done`, so a NONZERO qword here suppresses the TMRCALL
    #     line by itself — that is a complete explanation of the missing
    #     oracle print and would mean graft64 DID run earlier in the boot.
    #     The trampoline zeroes the low dword at init (tramp1422_16g_q35s144.asm:682).
    #     Two qwords are read because the oracle tests the full 64-bit value.
    GF_PA = 0x7005d8c
    gf = read_qwords('P85-GRAFTFLAG PA=0x%x' % GF_PA, 'xp /2gx 0x%x' % GF_PA, 2)
    if gf is not None:
        print('SNAP%s-QMP P85-GRAFTFLAG qword0=0x%016x (low_dword=0x%08x) qword1=0x%016x'
              % (snap, gf[0], gf[0] & 0xffffffff, gf[1]))
        print('P85-GRAFTFLAG is_zero=%s' % ('yes' if gf[0] == 0 else 'no'))

    # (5) PD-level walk of the #UD VA 0xffffffff080f1006. Only the PD (L2)
    #     entry and the resolved PA — its bytes are already dumped by
    #     P23-WILDVA. Expected PD idx=0x40 (the DENSIFY-filled identity
    #     entry). This is the control: if (1) resolves wrongly while this
    #     one still resolves to 0x80f1006, the THUNKWALK fault is local to
    #     window slot 0x38, not a broken snapshot.
    PV_VA = 0xffffffff080f1006
    print('SNAP%s-QMP P85-0x80f1006-PTWALK VA=0xffffffff080f1006 ENTER (PD level only; expect PD idx=0x40)' % snap)
    print('SNAP%s-QMP P85-0x80f1006-PTWALK indices: pml4(L4)=0x%x pdpt(L3)=0x%x pd(L2)=0x%x pt(L1)=0x%x'
          % (snap, (PV_VA >> 39) & 0x1ff, (PV_VA >> 30) & 0x1ff,
             (PV_VA >> 21) & 0x1ff, (PV_VA >> 12) & 0x1ff))
    pv_pa = walk_va(PV_VA, 'P85-0x80f1006-PTWALK', root_for('P85-0x80f1006-PTWALK'), pd_only=True)
    if pv_pa is None:
        print('P85-0x80f1006-PTWALK RESOLVED PA=none (PD-level walk ended early; expected PD idx=0x40)')
    else:
        print('P85-0x80f1006-PTWALK RESOLVED PA=0x%x (expected PD idx=0x40)' % pv_pa)

    # === BOOT 87: two PASSIVE reads at the trampoline's link addresses
    # (capture only — no breakpoint, no stop, no config change, no guest
    # mutation). b85 proved the mapping is perfect (PD_ID[0x38] identity ->
    # PA 0x7000dd6) while the page was zeros. These two reads measure the
    # b86 one-variable fix (PHYSFREE 0x40A8000 -> 0x7100000) at park, the
    # same question the P14 switch-stop probes ask earlier in the run.
    # looks_like_trampoline=yes iff 8 bytes at PA 0x7000dd6 are
    # 55 48 89 e5 57 56 52 48 (graft64 prologue + our own `push rdi`).
    TRAMP_SIG = [0x55, 0x48, 0x89, 0xe5, 0x57, 0x56, 0x52, 0x48]

    d22 = read_bytes('P86-TRAMP-AT-PARK PA=0x7000dd6', 'xp /8bx 0x7000dd6', 8)
    if d22 is None:
        tv = False
        print('P86-TRAMP-AT-PARK PA=0x7000dd6 looks_like_trampoline=no (read failed — see SNAP%s-QMP-FAIL)' % snap)
    else:
        tv = d22 == TRAMP_SIG
        print('P86-TRAMP-AT-PARK PA=0x7000dd6 looks_like_trampoline=%s'
              % ('yes' if tv else 'no'))

    base = read_bytes('P86-TRAMP-BASE PA=0x7000000', 'xp /8bx 0x7000000', 8)
    if base is None:
        print('P86-TRAMP-BASE PA=0x7000000 looks_like_trampoline=no (read failed — see SNAP%s-QMP-FAIL)' % snap)
    else:
        mbt = base[:4] == [0x02, 0xb0, 0xad, 0x1b]
        print('P86-TRAMP-BASE PA=0x7000000 multiboot_header=%s (first 4: %s vs 02 b0 ad 1b)'
              % ('yes' if mbt else 'no', hx(base[:4])))
        print('P86-TRAMP-BASE PA=0x7000000 looks_like_trampoline=%s'
              % ('yes' if tv else 'no'))

    # === BOOT 89: ONE PASSIVE read of TMR entries 0 and 1 (no stop added).
    # b89 fakes psp_mbox_map_tmr's mailbox send to success, so the commit should
    # now walk the table and mark entries done. Layout (p83/b88: 0x28-byte
    # stride, base PA 0x39110d8): entry+0x00 ptr, +0x08 id, +0x10 arg1,
    # +0x18 arg2, +0x20 state (low dword) | status (high dword). This read
    # starts at base+0x08, so qword 3 is TMR[0]'s state|status and qword 7 is
    # TMR[1].arg2; TMR[1]'s state|status is the NEXT qword (0x3911128) and is
    # deliberately outside this read — widen it rather than re-reading.
    print('SNAP%s-QMP P89-TMRSTATE ENTER (cmd: xp /8gx 0x39110e0) — entry0 state|status is qword 3; entry1 state|status is @0x3911128' % snap)
    tmr8 = read_qwords('P89-TMRSTATE PA=0x39110e0', 'xp /8gx 0x39110e0', 8)
    if tmr8 is None:
        print('P89-TMRSTATE UNREADABLE: read path failed (see SNAP%s-QMP-FAIL above)' % snap)
    else:
        tmr89_names = ['TMR0.id(+0x08)', 'TMR0.arg1', 'TMR0.arg2',
                       'TMR0.state|status', 'TMR1.ptr', 'TMR1.id',
                       'TMR1.arg1', 'TMR1.arg2']
        for k, v in enumerate(tmr8):
            pa = 0x39110e0 + k * 8
            extra = ''
            if k == 3:
                extra = '  <- TMR0: state=%d status=0x%08x' % (v & 0xffffffff, v >> 32)
            print('SNAP%s-QMP P89-TMRSTATE[%d] PA=0x%x = 0x%016x  %s%s'
                  % (snap, k, pa, v, tmr89_names[k], extra))
        st = tmr8[3]
        print('P89-TMRSTATE VERDICT TMR0: state=%d status=0x%08x -> %s'
              % (st & 0xffffffff, st >> 32,
                 'COMMITTED (status=0)' if (st >> 32) == 0
                 else 'status nonzero (not committed / failed)'))

    # === BOOT 97: P97-PHYSAVAIL — the decisive measurement of this round.
    # TWO passive HMP reads, no breakpoint, no stop, no write. These are the
    # UPSTREAM values the DMAP setup reads: DAT_83e08ba0 (VA, identity PA
    # 0x3e08ba0) is where the post-S4 fall-through copies the physmem bound,
    # and DAT_83e2ef88 (PA 0x3e2ef88) is physmem>>0xe. The broken run showed
    # 0x83e07a5100000000 upstream (a length/number pair read as one 64-bit
    # value — the signature of the empty 0x9001 map). Printed RAW: no verdict
    # here, because "sane" depends on which of the two is being read and the
    # boot log is the evidence. Read together with P97-GETTER-STUB (shell
    # side): count>=1 means the TLV map was SHADOWED by the getter stub, so
    # unchanged absurd values are a shadow result, not a map failure.
    for _lab, _pa, _va in (('DAT_83e08ba0', 0x3e08ba0, 0xffffffff83e08ba0),
                           ('DAT_83e2ef88', 0x3e2ef88, 0xffffffff83e2ef88)):
        print('SNAP%s-QMP P97-PHYSAVAIL ENTER %s VA=0x%x PA=0x%x (xp /1gx)' % (snap, _lab, _va, _pa))
        _v = read_qwords('P97-PHYSAVAIL %s PA=0x%x' % (_lab, _pa), 'xp /1gx 0x%x' % _pa, 1)
        if _v is None:
            print('P97-PHYSAVAIL %s UNREADABLE (read path failed — see SNAP%s-QMP-FAIL above)' % (_lab, snap))
        else:
            print('SNAP%s-QMP P97-PHYSAVAIL %s PA=0x%x raw=0x%016x hi=0x%08x lo=0x%08x'
                  % (snap, _lab, _pa, _v[0], _v[0] >> 32, _v[0] & 0xffffffff))

    # ==========================================================================
    # === BOOT 99: THE L-252(7) MEASUREMENT SET — seven PASSIVE HMP reads. No
    # breakpoint, no stop, no config change, no guest write, and NO image
    # change: this run is the b98 75-patch image byte for byte (P31 is
    # withdrawn — `grep -c 0xc1bef6 wp3_boot/patches_1422_q35s144.inc` = 0).
    #
    # WHY THESE SEVEN: b98's #GP is `cmp [rdi+8],0x63062` at 0xffffffff80e61906
    # with RDI = the console-ring cursor, and L-252 proved statically that the
    # cursor is CORRECT arithmetic on a CORRUPT input —
    #   B = 0xffff800000000000 | K1<<39 | K2<<30          (K1=DAT_83d89294,
    #                                                      K2=DAT_83d89298)
    #   cursor = B + phys_avail[idx]
    # i.e. rax = [r13] = DAT_83e08ba0[idx] was 0x83e04a7000000000 (9.5 EiB), so
    # the 64-bit sum wrapped and the store at 0x80c1cd0d landed outside every
    # canonical window. b98 read slots 0-7 of phys_avail (all zero) and the
    # cursor only. These reads answer "which slot is it, and what fed it",
    # which is the difference between PROVIDING the ring (fix phys_avail) and
    # patching the consumer (forbidden by L-252(6)).
    #
    # NO VERDICT IS TAKEN FROM THESE VALUES. Every block prints ENTER before
    # its read, every raw line is printed, and an out-of-RAM `xp` returns zeros
    # with rc ok — so a zero is only meaningful next to its ENTER/raw pair and
    # against a control read (P99-TLV and P99-MODE are the controls).

    # (1) P99-CURSOR — DAT_83e08a80: the console-ring cursor. PA by the
    #     b82-proven kernel-window rule VA - 0xffffffff80000000 (same rule as
    #     P97-PHYSAVAIL's 0x3e08ba0). Writers: 0x806b9843 (FUN_806b9830) and
    #     0x80c1cd0d (FUN_80c1c080); consumer: 0x80c1bee9 -> 0x80c1bef6.
    #     `canonical=yes` is bits 63:47 all equal; `dmap=yes` is >= 0xffff800000000000.
    CUR_PA, CUR_VA = 0x3e08a80, 0xffffffff83e08a80
    print('SNAP%s-QMP P99-CURSOR ENTER DAT_83e08a80 VA=0x%x PA=0x%x (xp /1gx)' % (snap, CUR_VA, CUR_PA))
    _cv = read_qwords('P99-CURSOR PA=0x3e08a80', 'xp /1gx 0x%x' % CUR_PA, 1)
    if _cv is None:
        print('P99-CURSOR UNREADABLE (read path failed — see SNAP%s-QMP-FAIL above)' % snap)
    else:
        _v = _cv[0]
        _canon = 'yes' if (_v >> 47) in (0, 0x1ffff) else 'no'
        print('SNAP%s-QMP P99-CURSOR PA=0x%x raw=0x%016x canonical=%s dmap=%s'
              % (snap, CUR_PA, _v, _canon, 'yes' if _v >= 0xffff800000000000 else 'no'))

    # (2) P99-PHYSAVAIL-ARRAY — the WHOLE array, slots 0..31, one read.
    #     DAT_83e08ba0 is the base (0x80c1ca89 lea rcx;[rel 0xffffffff83e08ba0],
    #     0x80c1ca94/0x80c1cb14 `lea r13,[rcx+r8*8]`); the entry holding
    #     0x83e04a7000000000 is the corrupt input L-252 identified. Slot index,
    #     PA and the raw qword are printed per slot so the index is NAMED.
    PHY_PA, PHY_N = 0x3e08ba0, 32
    print('SNAP%s-QMP P99-PHYSAVAIL-ARRAY ENTER DAT_83e08ba0 PA=0x%x slots 0..%d (xp /%dgx)'
          % (snap, PHY_PA, PHY_N - 1, PHY_N))
    _ph = read_qwords('P99-PHYSAVAIL-ARRAY PA=0x3e08ba0', 'xp /%dgx 0x%x' % (PHY_N, PHY_PA), PHY_N)
    if _ph is None:
        print('P99-PHYSAVAIL-ARRAY UNREADABLE (read path failed — see SNAP%s-QMP-FAIL above)' % snap)
    else:
        _nz = [(k, v) for k, v in enumerate(_ph) if v]
        print('SNAP%s-QMP P99-PHYSAVAIL-ARRAY nonzero=%d of %d' % (snap, len(_nz), PHY_N))
        for k, v in _nz:
            _tag = '  <- the L-252 value (0x83e04a7000000000)' if v == 0x83e04a7000000000 else ''
            _big = '  <- NOT a plausible region end (> 0x80000000)' if v > 0x80000000 else ''
            print('SNAP%s-QMP P99-PHYSAVAIL-ARRAY[%d] PA=0x%x = 0x%016x (>>14 = 0x%016x)%s%s'
                  % (snap, k, PHY_PA + k * 8, v, v >> 14, _tag, _big))

    # (3) P99-K12 — the per-boot KASLR DMAP shifts (L-252(3): written by
    #     FUN_80aebf70 at 0x80aec135/0x80aec186, fallbacks 0x1fe/0 at
    #     0x80aec070/0x80aec07a). K1 and K2 are dwords at DAT_83d89294 /
    #     DAT_83d89298; one /1gx read returns both (low dword = K1). B is
    #     COMPUTED from the raw values and printed next to them.
    K12_PA = 0x3b89294
    print('SNAP%s-QMP P99-K12 ENTER DAT_83d89294/DAT_83d89298 PA=0x%x (xp /2wx)' % (snap, K12_PA))
    _t = hmp('xp /2wx 0x%x' % K12_PA, 'P99-K12 PA=0x3b89294')
    if _t is None:
        print('P99-K12 UNREADABLE (read path failed — see SNAP%s-QMP-FAIL above)' % snap)
    else:
        print('SNAP%s-QMP P99-K12 raw: %s' % (snap, ' '.join(_t.split())))
        # NOTE: this is the QMP heredoc, whose imports are `json, os, re,
        # select, sys, time` (line 327) — `_re` exists only in the gdb-side
        # template (import re as _re), so use `re` here.
        _dw = [w for w in re.findall(r'0x([0-9a-fA-F]+)', _t.split(':', 1)[-1])]
        if len(_dw) >= 2:
            _k1, _k2 = int(_dw[0], 16) & 0xffffffff, int(_dw[1], 16) & 0xffffffff
            _B = (0xffff800000000000 | (_k1 << 0x27) | (_k2 << 0x1e)) & 0xffffffffffffffff
            print('SNAP%s-QMP P99-K12 K1=0x%x K2=0x%x -> B=0x%016x (b98 measured B=0xffffafe100000000)'
                  % (snap, _k1, _k2, _B))
        else:
            print('P99-K12 PARSE-ERR: %d dwords parsed from the xp return (need 2)' % len(_dw))

    # (4) P99-E2EF88 — DAT_83e2ef88, the phys_avail>>14 channel (b98:
    #     0x00020f8129c00000, which must equal (the 9.5 EiB entry) >> 14).
    E2_PA = 0x3e2ef88
    print('SNAP%s-QMP P99-E2EF88 ENTER DAT_83e2ef88 PA=0x%x (xp /1gx)' % (snap, E2_PA))
    _e2 = read_qwords('P99-E2EF88 PA=0x3e2ef88', 'xp /1gx 0x%x' % E2_PA, 1)
    if _e2 is None:
        print('P99-E2EF88 UNREADABLE (read path failed — see SNAP%s-QMP-FAIL above)' % snap)
    else:
        print('SNAP%s-QMP P99-E2EF88 PA=0x%x raw=0x%016x (hi=0x%08x lo=0x%08x)'
              % (snap, E2_PA, _e2[0], _e2[0] >> 32, _e2[0] & 0xffffffff))

    # (5) P99-MAPPAGES — DAT_83e08ca0, the SECOND array base FUN_80c1c080 uses
    #     (0x80c1cb2c `lea r14,[rel 0xffffffff83e08ca0]`; the pmap page lists).
    MP_PA, MP_N = 0x3e08ca0, 4
    print('SNAP%s-QMP P99-MAPPAGES ENTER DAT_83e08ca0 PA=0x%x (%d qwords)' % (snap, MP_PA, MP_N))
    _mp = read_qwords('P99-MAPPAGES PA=0x3e08ca0', 'xp /%dgx 0x%x' % (MP_N, MP_PA), MP_N)
    if _mp is None:
        print('P99-MAPPAGES UNREADABLE (read path failed — see SNAP%s-QMP-FAIL above)' % snap)
    else:
        for k, v in enumerate(_mp):
            print('SNAP%s-QMP P99-MAPPAGES[%d] PA=0x%x = 0x%016x' % (snap, k, MP_PA + k * 8, v))

    # (6) P99-TLV — the first 64 bytes of OUR parameter TLV block at PA 0x9b000.
    #     CONTROL READ: our handoff must be in the guest whatever the kernel
    #     did. All-zero here means the block was never copied, so "the map was
    #     consumed" cannot be assumed for any other probe.
    TLV_PA, TLV_N = 0x9b000, 8
    print('SNAP%s-QMP P99-TLV ENTER our param TLV block PA=0x%x (%d qwords; control read)' % (snap, TLV_PA, TLV_N))
    _tlv = read_qwords('P99-TLV PA=0x9b000', 'xp /%dgx 0x%x' % (TLV_N, TLV_PA), TLV_N)
    if _tlv is None:
        print('P99-TLV UNREADABLE (read path failed — see SNAP%s-QMP-FAIL above)' % snap)
    else:
        print('SNAP%s-QMP P99-TLV nonzero=%d of %d' % (snap, sum(1 for v in _tlv if v), TLV_N))
        for k, v in enumerate(_tlv):
            print('SNAP%s-QMP P99-TLV[%d] PA=0x%x = 0x%016x' % (snap, k, TLV_PA + k * 8, v))

    # (7) P99-DF5530 — DAT_83df5530, the byte total R15 accumulates and stores
    #     back (0x80c1ccb2 add r15,[rel 0xffffffff83df5530]; 0x80c1cceb store).
    #     L-252(4) says it is a total, not an address; printed so that stays
    #     checkable rather than asserted.
    DF_PA = 0x3df5530
    print('SNAP%s-QMP P99-DF5530 ENTER DAT_83df5530 PA=0x%x (xp /1gx)' % (snap, DF_PA))
    _df = read_qwords('P99-DF5530 PA=0x3df5530', 'xp /1gx 0x%x' % DF_PA, 1)
    if _df is None:
        print('P99-DF5530 UNREADABLE (read path failed — see SNAP%s-QMP-FAIL above)' % snap)
    else:
        print('SNAP%s-QMP P99-DF5530 PA=0x%x raw=0x%016x' % (snap, DF_PA, _df[0]))

    # === BOOT 97: ONE PASSIVE read of the phase word P25 forces
    # (the same block as b94's — kept so P93-MODE stays directly comparable).
    # P25 is BACK (04 00 00 00 over the image's 01 00 00 00 at flat offset
    # 0x191be0c), so in this image the dword must read back 4. PA is foff +
    # KERN_PHYS 0x200000 = 0x1b1be0c. ONE HMP `xp /1wx`: no breakpoint, no
    # stop, no guest mutation. A verdict of 1 here means the patch did not take
    # (or the run is not this ELF); 2/3/5/6 means the kernel itself advanced
    # the phase word (NEW behaviour); anything else is outside FUN_80d2eb90's
    # valid 1..6 mode-table range.
    MODE_PA = 0x1b1be0c
    print('SNAP%s-QMP P93-MODE ENTER (cmd: xp /1wx 0x1b1be0c) — DAT_81b1be0c, the platform/memory phase word (P25 applied; expect 4)' % snap)
    mode_text = hmp('xp /1wx 0x%x' % MODE_PA, 'P93-MODE PA=0x1b1be0c')
    if mode_text is None:
        print('P93-MODE UNREADABLE: read path failed (see SNAP%s-QMP-FAIL above) — neither value nor verdict emitted' % snap)
    else:
        print('SNAP%s-QMP P93-MODE raw: %s' % (snap, ' '.join(mode_text.split())))
        mode_val = parse_xp(mode_text)
        if mode_val is None:
            fail('P93-MODE: unparseable xp return: %r' % (mode_text,))
        else:
            mode = mode_val & 0xffffffff
            if mode == 4:
                verdict = ('MODE-4 (expected: P25 is in this 73-patch image, and P26 skips the '
                           'FUN_80232ca0 call at 0x80c19969)')
            elif mode == 1:
                verdict = ('MODE-1 (the P25 write did not take, or the run is not this ELF — '
                           'check the IMGBUILD hashes; the 73-patch table carries 04 00 00 00)')
            elif mode in (2, 3, 5, 6):
                verdict = ('MODE-%d (the kernel itself advanced the phase word — NEW behaviour, '
                           'record it; valid range of FUN_80d2eb90 tables is 1..6)' % mode)
            else:
                verdict = ('MODE-%d (OUTSIDE the valid 1..6 range of FUN_80d2eb90\'s mode-1 tables — '
                           'the handler would bail)' % mode)
            print('SNAP%s-QMP P93-MODE PA=0x%x = 0x%08x -> %s' % (snap, MODE_PA, mode, verdict))

    # Reminder only: the harness cannot grep the guest serial mid-run (and
    # must not parse it as a verdict). TMRCALL presence is read from the log.
    print('P85-ORACLE-CHECK: see serial1422s148.log for TMRCALL (expect the LABEL now: k64puts 8-bit fix)')
except SystemExit:
    raise
except Exception:
    import traceback
    fail('unhandled python exception in QMP snapshot: %s' % ' | '.join(traceback.format_exc().splitlines()))
    sys.exit(1)
PY
  # P91-MP-FOUND (b91, KEPT UNCHANGED in b97; same label on purpose so b89/b90/
  # b91/b92/b94/b97 are directly comparable): a SERIAL grep at SNAP time, printed
  # unconditionally so a handler that never took the memory path is
  # distinguishable from one that did. `Memory param is found.` is printed by
  # FUN_ffffffff80c207e0 only after its first guards pass. b91 measured P25's
  # mode write with it; b92 had no P25; in b94 P25 is back, so count>=1 means
  # the handler reached the memory path with mode 4. Never a verdict on its
  # own: it states the fact, the SNAPs are the measurement.
  MP_N=$(grep -c 'Memory param is found' "$SLOG" 2>/dev/null)
  MP_N=${MP_N:-0}
  printf 'P91-MP-FOUND count=%s (serial grep of %s at SNAP%s; count>=1 => the memory-param handler took the memory path)\n' \
         "$MP_N" "$SLOG" "$1" | tee -a "$GLOG"
  # P93-MP-RESERVE (b94): the OTHER panic string inside FUN_80c207e0's gated
  # block, `failed to reserve memory` (image string @0x815588e1; exactly one
  # occurrence in the raw image). A serial grep, printed unconditionally and
  # next to P91-MP-FOUND, so the two failure modes are distinguishable:
  #   count>=1 -> the mode gate PASSED and the FIXED 0xec00000 reserve itself
  #               failed (arm b of the b94 decision tree);
  #   count=0  -> either the gate still bailed or the boot never reached the
  #               gated block — decided together with P93-MODE, never alone.
  RES_N=$(grep -c 'failed to reserve memory' "$SLOG" 2>/dev/null)
  RES_N=${RES_N:-0}
  printf 'P93-RESERVE-ERR count=%s (serial grep of %s at SNAP%s; count>=1 => gate passed, the fixed 0xec00000 reserve failed)\n' \
         "$RES_N" "$SLOG" "$1" | tee -a "$GLOG"
  # P94-APP-MEM-ERR (b94, label kept; ANCHOR FIXED in b97): the string P27
  # removes. `Failed to allocate application memory` is printed ONLY by the
  # panic block at 0xffffffff80c2146d, which P27 replaces with
  # `mov dword [rax],-1; jmp epilogue` (S-28). So this count is the P27
  # signal INVERSE to its intent:
  #   count=0 -> the panic block never printed; either P27 ran (good) or the
  #              boot never reached 0x80c21091 (mode-4 hole #BP, arm (a)) —
  #              decided together with P93-MODE / P91-MP-FOUND, never alone;
  #   count>=1 -> the unpatched block executed: the patch did not take, or
  #              the run is not this ELF (check the IMGBUILD hashes).
  # THE ANCHOR (L-244(2)): boot 94's count was 1 and it was an ARTIFACT — the
  # grep matched the trampoline's SYNTH line, which quotes the string inside
  # P27's description. b97 counts ONLY lines that do not begin with `SYNTH:`:
  #   grep -a <string> "$SLOG" | grep -vc '^SYNTH:'
  # i.e. the whole-file grep is piped into a second grep that DROPS every line
  # whose first six bytes are `SYNTH:`, then counts the survivors (-v + -c).
  # A line beginning with `SYNTH:` can therefore never be counted, whatever
  # string it quotes. The raw count is printed next to it so the anchor is
  # measurable: raw=1 / anchored=0 is the b94 artifact, raw=anchored means the
  # SYNTH line was not the source.
  # (The string itself is still looked up in the image first: exactly one
  # occurrence @0xffffffff81543a7e was verified when P27 was written; a
  # widened grep would silently keep matching if the image changed.)
  # b99 CONFIRMATION of the anchor (measured, not argued — the b98 log is the
  # evidence): `grep -ac` over serial1422s98.log = 1, and that one hit IS a
  # SYNTH: line (line 3, the trampoline's register text, which quotes the
  # string inside P27's description). The anchored form prints 0. So the pair
  # raw=1/anchored=0 on a log whose kernel printed nothing is exactly the
  # artifact the anchor removes, and a SYNTH: line cannot reach count= unless
  # it stops beginning with `SYNTH:` at column 0 — which the trampoline cannot
  # do, since the literal "SYNTH: " is the first byte of that string and it is
  # written straight after a newline (s_synth in tramp1422_16g_q35s144.asm).
  AM_RAW=$(grep -ac 'Failed to allocate application memory' "$SLOG" 2>/dev/null)
  AM_RAW=${AM_RAW:-0}
  AM_N=$(grep -a 'Failed to allocate application memory' "$SLOG" 2>/dev/null | grep -vc '^SYNTH:')
  AM_N=${AM_N:-0}
  printf 'P94-APP-MEM-ERR count=%s raw=%s (serial grep of %s at SNAP%s, anchored so a line beginning with SYNTH: is excluded; expect 0 — P27/S-28 replaced the only printer of this string; raw=1/anchored=0 is b94'"'"'s artifact)\n' \
         "$AM_N" "$AM_RAW" "$SLOG" "$1" | tee -a "$GLOG"
  # P95-ACPI (b97, NEW): gate-2 reach, three INDEPENDENT counts, each with its
  # own meaning. Printed unconditionally, so "probe never ran" is visible.
  # 13.60's reference log (serial.log) reaches these in this order, ~10 lines
  # after entry: `Table 'FACP' at ...` -> `MADT: Found CPU ...` ->
  # `APIC: Found table at ...` / `APIC: Using the MADT enumerator.` ->
  # `SIE CONFIDENTIAL`. All three strings exist in the 14.22 image too
  # (the format `Table '%.4s' at 0x%jx` @0xffffffff8134ce22, `MADT:` 15
  # occurrences, `APIC:` 13), so a count > 0 here is the kernel's OWN ACPI
  # code talking.
  # NOTE: b94 printed some kernel lines TWICE (the S4 INFO line and its panic
  # both appeared twice), so >=1 is the signal; the number itself is not a
  # quantity of anything.
  TAB_N=$(grep -acF "Table '" "$SLOG" 2>/dev/null)
  TAB_N=${TAB_N:-0}
  MADT_N=$(grep -acF 'MADT:' "$SLOG" 2>/dev/null)
  MADT_N=${MADT_N:-0}
  APIC_N=$(grep -acF 'APIC:' "$SLOG" 2>/dev/null)
  APIC_N=${APIC_N:-0}
  printf "P95-ACPI ACPI_TABLE count=%s (serial grep of \"Table '\" at SNAP%s; >=1 => the ACPI table walker printed \"Table <sig> at <pa>\" for at least one table)\n" \
         "$TAB_N" "$1" | tee -a "$GLOG"
  printf 'P95-ACPI MADT count=%s (serial grep of "MADT:" at SNAP%s; >=1 => the MADT (APIC) table parser ran and enumerated CPUs)\n' \
         "$MADT_N" "$1" | tee -a "$GLOG"
  printf 'P95-ACPI APIC count=%s (serial grep of "APIC:" at SNAP%s; >=1 => the APIC layer attached (table found / MADT enumerator selected))\n' \
         "$APIC_N" "$1" | tee -a "$GLOG"
  # P95-BANNER (b97, NEW): the two halves of the gate-2 banner, counted
  # SEPARATELY on purpose. `SIE CONFIDENTIAL` is the banner header
  # (@0xffffffff81b10750 in the image); `releases/14.22` is the release stamp
  # `r230580/releases/14.22 Oct 27 2026 02:17:44` (@0xffffffff81ac4388, 1
  # occurrence). Both at once = the kernel printed its own identity, which is
  # the Phase-2 gate. Note the trampoline's own "PS5-TRAMP-1422: booting
  # KIMUNAKI 14.22 kernel" line contains "14.22" but NOT "releases/14.22",
  # so the stamp count cannot be satisfied by the trampoline.
  BAN1_N=$(grep -acF 'SIE CONFIDENTIAL' "$SLOG" 2>/dev/null)
  BAN1_N=${BAN1_N:-0}
  BAN2_N=$(grep -acF 'releases/14.22' "$SLOG" 2>/dev/null)
  BAN2_N=${BAN2_N:-0}
  printf 'P95-BANNER SIE-CONFIDENTIAL count=%s (serial grep at SNAP%s; >=1 => the kernel banner header printed)\n' \
         "$BAN1_N" "$1" | tee -a "$GLOG"
  printf 'P95-BANNER RELEASE-14.22 count=%s (serial grep at SNAP%s; >=1 => the 14.22 release stamp printed — our image identity, not a trampoline string)\n' \
         "$BAN2_N" "$1" | tee -a "$GLOG"
  # P95-DEVCONF (b97, NEW): the Phase-2 finish line the mission names.
  DEV_N=$(grep -acF 'Device configuration finished' "$SLOG" 2>/dev/null)
  DEV_N=${DEV_N:-0}
  printf 'P95-DEVCONF count=%s (serial grep at SNAP%s; >=1 => "Device configuration finished." printed — the Phase-2 gate)\n' \
         "$DEV_N" "$1" | tee -a "$GLOG"
  # P92-RAMTOP (b92, label kept): UNKNOWN BY DESIGN, and the skip is honest.
  # The trampoline has no RAM-top view to read: tramp1422_16g_q35s144.asm never calls
  # e820 and never parses the multiboot info (no mem_lower/mem_upper read ->
  # nothing to probe), PHYSFREE is only `PHYSFREE >> 12` on the btext stack,
  # and KERN_SIZE is the module length (0x3e72040), not RAM. So there is no
  # address that carries "top of RAM" and none is invented here. Guest RAM is
  # whatever this script's own QEMU line configures (2 GiB for boot 97); if the
  # size is encoded in the S-18 handoff, the boot must fail in a way that says
  # so (one variable at a time).
  # P97-MAPSEEN (b97): the kernel prints "SMAP type=%02x base=%016lx len=%016lx"
  # once per SMAP entry ONLY when (DAT_837c81b0._1_1_ & 8) != 0, a debug flag
  # this harness does NOT force. count=0 is therefore EXPECTED and is not
  # evidence either way; it is printed so the flag's state is visible rather
  # than assumed. Do not "fix" this by writing the flag.
  MAPSEEN_N=$(grep -acF 'SMAP type=' "$SLOG" 2>/dev/null)
  MAPSEEN_N=${MAPSEEN_N:-0}
  # [B] PRINTF ARITY FIX (b99): this format has exactly TWO %-specs (count,
  # SNAP) and now gets exactly TWO arguments. Through b98 it got three
  # ("$MAPSEEN_N" "$SLOG" "$1"), so bash re-applied the format with the
  # leftover argument and printed a SECOND line with the snapshot number in
  # count= — the `count=1` mint of L-251(6) (b98 GLOG lines 437 + 438). The
  # SAME defect is fixed in P97-GETTER-STUB and P98-SELFHANDLE below; never
  # add an argument without adding a %s (header self-check [B]).
  printf 'P97-MAPSEEN SMAP-type-lines count=%s (serial grep at SNAP%s; EXPECTED 0 — the printer is gated on DAT_837c81b0&8, a debug flag we do not force; 0 says nothing about whether the map was read)\n' \
         "$MAPSEEN_N" "$1" | tee -a "$GLOG"
  # P97-GETTER-STUB (b97, retargeted in b98): THE SHADOW DETECTOR. Through b97
  # the active row at 0xffffffff80e6f9c0 replaced the TLV getter with a stub
  # that answered field 0x9001 from a zero record region and printed 'G' on
  # isa-debugcon 0x408 (the "AG" of b95's "K64A: K64B: AG"). b98 DELETES that
  # row, so the 'AG' marker must be GONE: count=0 is the b98 success condition
  # and >=1 means a b97-era image ran (or the stub came back). Anchored on
  # lines not beginning with SYNTH: so the trampoline's own text cannot count.
  STUBG_RAW=$(grep -aoF 'AG' "$SLOG" 2>/dev/null | wc -l)
  STUBG_RAW=${STUBG_RAW:-0}
  STUBG_N=$(grep -aF 'AG' "$SLOG" 2>/dev/null | grep -vc '^SYNTH:' )
  STUBG_N=${STUBG_N:-0}
  # [B] arity: THREE %-specs (count, raw, SNAP) / THREE args (b98 passed a
  # fourth, "$SLOG", and minted `count=<snap> raw=` on the re-applied format).
  printf 'P97-GETTER-STUB AG-occurrences count=%s raw=%s (serial grep at SNAP%s; b98 RETIRED the stub: EXPECT 0. >=1 => the getter-selfhandle row is still active (wrong image) or the stub ran; the count is anchored so a line beginning with SYNTH: cannot satisfy it)\n' \
         "$STUBG_N" "$STUBG_RAW" "$1" | tee -a "$GLOG"
  # P98-SELFHANDLE (b98, NEW): the REGRESSION the retired row was hiding. The
  # stub existed to fabricate a module self-handle (L-149/150, W1v2); with the
  # real getter back the kernel may refuse the module: `missing the module
  # handle of kernel itself.` A count>=1 is the CLEAN failure this round
  # expects to see IF the map is consumed but the handle is not; report it
  # verbatim, do not patch it in this round.
  SH_N=$(grep -acF 'module handle of kernel' "$SLOG" 2>/dev/null)
  SH_N=${SH_N:-0}
  # [B] arity: TWO %-specs (count, SNAP) / TWO args (b98 passed a third).
  printf 'P98-SELFHANDLE count=%s (serial grep of "module handle of kernel" at SNAP%s; EXPECT 0 — >=1 => the retired stub WAS the self-handle source (L-149/150): clean, informative failure, do not fix this round)\n' \
         "$SH_N" "$1" | tee -a "$GLOG"
  printf 'P92-RAMTOP UNKNOWN (no trampoline RAM-top probe exists — no e820 call, no multiboot-info parse; probe skipped by design, guest RAM is set by this script QEMU line = 2 GiB)\n' | tee -a "$GLOG"

}

# L-188 P14 session (supersedes btexthit, whose echo gave a false BTEXT-HIT when
# gdb failed to attach): ONE gdb client from t0+~2s until ~10 s before T1.
# Arms: btext breakpoint (BTEXT-HIT verdict, now only on a REAL stop) + all 23
# kernel `mov cr3` sites (wp3_boot/cr3_sites.txt). On each stop at a cr3 site:
# if the switch's source register != current CR3 (a REAL switch, not a
# self-reload), the kernel is about to switch to its own table (zero low-window
# slots — boot 62 proved its build wipes P13's handoff prefill). Re-graft our 7
# universal slots into that table's zero slots via the low window (still valid:
# at the breakpoint CR3 is still the trampoline's table). Then detach, freeing
# the stub for the SNAP1/SNAP2 dumps.
p14sess() { # $1 = session duration seconds (must be < T1)
  local DUR=${1:-100}
  local GDBF="/tmp/opencode/p14sess_$$.gdb"
  python3 - "$DUR" "$GDBF" <<'PY'
import sys
dur, out = sys.argv[1], sys.argv[2]
sites=[l.split() for l in open('wp3_boot/cr3_sites.txt') if l.strip()]
sitestr = ", ".join('int("%s",16):"%s"' % (va,reg) for va,reg in sites)
py='''
import gdb, os, time
SITES = {@SITES@}
BT = 0xffffffff8045a6c0
log = lambda m: print(m, flush=True)
inf = gdb.selected_inferior()
ok = False
# L-218 (boot 78): retry window = 40 x 0.75 s = 30 s = the shell's QMP grace
# window. Boot 78's 20-iteration (15 s) window expired while the attach was
# still flaking on the vMustReplyEmpty handshake -> the QMP fallback released
# the guest first -> late attach -> contaminated unmonored run.
for a in range(40):
    try:
        gdb.execute('target remote | python3 ' + os.path.join(os.environ['PS5_BOOT_IPC'], 'gdb_bridge.py')); ok = True; break
    except gdb.error as e:
        log('P14-attach attempt %d failed: %s' % (a+1, e))
        time.sleep(0.75)
if ok:
    gdb.execute('tbreak *0xffffffff8045a6c0')
    for va in SITES: gdb.execute('break *0x%x' % va)
    # L-211/L-212/L-213: first-kernel-console-output stop. The kernel has TWO
    # patched console bridges (P8, patches_1422.inc): putc @0xffffffff80d45290
    # and the linewriter ENTRY @0xffffffff809bfda0 (patch: sub esi,0x20000;
    # ja ..; mov rsi,rdi; call our putstr -> out 0x408). Boot 74 (unmonored,
    # VOID) put its early trap messages on serial with NO capture break armed,
    # so which bridge carries early output was unproven — arm BOTH; the FIRST
    # hit of either is the first console output. At that instant the CPU sits
    # inside the kernel's console/trap path with the kernel's own debug state
    # still live (DR0-7/DR6/DR7/TF via 'monitor info registers' — $drN parses
    # void in this gdbstub, L-212) and the context on the stack: capture all
    # of it, then delete ONLY the fired break. The switch stop deletes
    # everything EXCEPT the still-alive capture breaks (software int3 =
    # #BP/trap3, never a #DB source). L-213: NO backslash-n escapes in string
    # literals anywhere in this inner code — the outer triple-quoted template
    # converts them to REAL newlines and the generated gdb script dies with
    # 'unterminated string literal' (boot 74 harness death; monitor text is
    # multiline already, no joiner needed).
    PUTC = 0xffffffff80d45290
    LINW = 0xffffffff809bfda0
    pbp = {}
    for va in (PUTC, LINW):
        try:
            out = gdb.execute('break *0x%x' % va, to_string=True)
            # L-214: INT — the sterile keep-list tests membership against
            # gdb.breakpoints()'s INT numbers; boot 75 stored strings and
            # '25' in [25] is False, so both capture breaks were deleted at
            # the first switch stop and the first-char capture was lost.
            pbp[va] = int(out.strip().split()[1])
        except Exception as e:
            pbp[va] = None
            log('P14-CAP-ARM-ERR 0x%x: %r' % (va, e))
    # L-215(7): capture is now HARDWARE (gdb hbreak -> Z0 -> DR0-DR2): boot
    # 76 proved the sw int3 captures never fire on the early trap output
    # (the #DF handler prints via a THIRD leaf, 0x80465040, P8 never
    # patched it) and kept sw breaks are a live #BP source in kernel
    # code. DR bps are intercepted by the gdbstub: vCPU stops, the guest
    # #DB handler NEVER runs (no DR6 store, no AMD debug-store #DF, no
    # int3 bytes in text). Three trap-report entries:
    #   DR0 @0xffffffff805f7080 report BODY entry (frame in RDI at entry)
    #   DR1 @0xffffffff805f8230 #DF handler entry (frame in RDI at entry)
    #   DR2 @0xffffffff8045bf60 shared early-trap TAIL entry (frame in
    #       RSP; pre-trap GPRs still live in the registers; CPU-pushed
    #       RIP/RFLAGS at [rsp+0xe8]/[rsp+0xf0])
    HW = {0xffffffff805f7080: 'BODY', 0xffffffff805f8230: 'DFH', 0xffffffff8045bf60: 'TAIL'}
    hbp = {}
    import re as _re
    for va in HW:
        try:
            out = gdb.execute('hbreak *0x%x' % va, to_string=True)
            # L-217: gdb prints "Hardware assisted breakpoint N at ..." — the
            # number is NOT token 2 (boot 77: split()[1] = 'assisted' -> all
            # hbp None -> everything deleted at the switch stop, capture blind)
            m = _re.search('breakpoint ([0-9]+)', out)
            if not m:
                raise ValueError('no bp number in %r' % out)
            hbp[va] = int(m.group(1))
        except Exception as e:
            hbp[va] = None
            log('P14-HWARM-ERR 0x%x: %r' % (va, e))
    cap_done = False
    sw_done = False
    def reg(name):
        try: return int(gdb.parse_and_eval('$'+name)) & 0xffffffffffffffff
        except Exception: return None
    log('=== P14-ARMED: btext + %d cr3-site + sw console breaks putc(0x%x, bp#%s) linw(0x%x, bp#%s) [entry window only, deleted at switch stop] + HW capture DR0/DR1/DR2 @BODY(0x805f7080, bp#%s) DFH(0x805f8230, bp#%s) TAIL(0x8045bf60, bp#%s) set, releasing guest ===' % (len(SITES), PUTC, pbp.get(PUTC), LINW, pbp.get(LINW), hbp.get(0xffffffff805f7080), hbp.get(0xffffffff805f8230), hbp.get(0xffffffff8045bf60)))
    log('SYNTH-HARNESS: btext, %d CR3-site and 2 console software breakpoints plus 3 hardware capture breakpoints are armed before the first real CR3 switch only. At that stop: P14 graft, DENSIFY and conditional P21 slot-0 graft (same table mutations as boot 80); AUDIT and FINGERPRINT are read-only. All breakpoints are deleted before GDB detaches and the guest switches. QEMU interrupt tracing uses no guest breakpoints. QEMU has no NIC. GDB and QMP use local FIFO pipes. BOOT 104 (P104, 16 GiB gate-1 fix): Q35 (session123, L-361): the trampoline SMAP (0x9001) is REBUILT to 4 QEMU-backed ranges for -M q35 -m 16G ([0x1000,0x9B000),[0x9C000,0xF0000),[0x100000,0x7FE00000),[0x100000000,0x480000000)) matching QEMU 8.2.2 q35 mtree exactly (below-4G 2 GiB top, above-4G to 18 GiB; UPDATED SYNTHETIC, LEDGER 11 S-20); BOOT 114 (P114, S-31 + S-13 scoped): DENSIFY SKIPS PML4[511] PDPT[0]+PDPT[2] (the kernel low-KVA map 0xffffff8000000000-0x3fffffff + 0xffffff8080000000-0xbfffffff it tears down; BOOT146 added PDPT[0] for the s145 residual VA 0xffffff800b200000=PDPT[0]/PD[89], L-426/L-287), keeping PDPT[449]/graft64 mapped (b109 regressed: full-PML4[511] skip #PF-faulted graft64), so the kernel no longer finds a DENSIFY 2MiB superpage to demote in that slot (pmap_remove_kernel_pde panic fixed, C-035); keeps the S-31 inject at the printcpuinfo rdmsr sites (MPERF 0xb7a2de, APERF 0xb7a2e9) the gdb session INJECTS advancing MPERF=APERF=0x200000 into guest registers (eax/edx) so the div by MPERF is nonzero (TCG leaves 0xe7/0xe8 stuck 0 -> #DE). This WRITES guest registers (a synthetic, not read-only), logged at inject + confirmed at the div; registered LEDGER 11 S-31; SESSION145 (L-425, a53io inject) then keeps GDB ATTACHED past the switch (the s128/STEP-D stay-attached machinery, HW/hbreak) all the way to the a53io NULL-tag CFI wall: ONE hbreak at initialize_naps entry FUN_807c4770; at the hit it gdb-writes a valid no-bounce NAPS bus_dma_tag to gdb-owned scratch 0xffffffff84030000 (impl=0xffffffff81d19a10, nsegments=1) and sets DAT_838e79b0 to it (observable A53-INJECT/SYNTH-HARNESS lines), answering the cfi_check_fail(callee 0) panic @0x80e441b8 (make-it-exist). serial/triage are the regression guard. Register: LEDGER.md 11 (S-12, S-13, S-20, S-21, + the session145 a53io NAPS-tag harness synthetic).' % len(SITES))
    # L-193: this gdb build lacks BOTH non-stop wait primitives (gdb.wait and
    # gdb.stop_event: absent), so async 'continue &' + events.stop is blind
    # (boot 64: time.sleep blocks the loop; boot 65: 'shell sleep' and
    # 'info reg' pumps never read the target socket — the CPU sat stopped at
    # btext the whole run while gdb believed the target was running).
    # Foreground 'gdb.execute("continue")' is the one construct that works:
    # it blocks in the real event loop, delivers the stop, and returns with
    # the target stopped — do the per-stop work inline, then continue again.
    def u64(va): return int.from_bytes(inf.read_memory(va,8),'little')
    def process_stop():
        # L-219 (boot 79): cap_done/sw_done live at MODULE level (the `if ok:`
        # block is not a scope); this function ASSIGNS them (cap_done = True /
        # sw_done = True), so Python classifies them as local to this function
        # and the first READ (`not cap_done` in the HW branch) raises
        # UnboundLocalError. Boot 79: both capture stops (BP27 BODY
        # 0x805f7080, BP28 DFH 0x805f8230) died here before any dump.
        # Latent in boots 71-78 (their HW branch never executed).
        global cap_done, sw_done
        # L-198: NO cr3 read — this gdb build has neither a symbol table
        # (parse_and_eval('cr3') failed, boot 67) nor Inferior.read_register
        # (boot 68). A REAL switch = source register differs from the
        # trampoline's own table (0x40a0000 — CR3 at handoff, unchanged until
        # the first real switch); the graft then targets the OBSERVED src
        # table (not a hardcoded PA), so a wrong-table surprise self-corrects.
        pc = int(gdb.parse_and_eval('$pc'))
        if pc == BT:
            log('=== BTEXT-HIT: kernel entry 0xffffffff8045a6c0 REACHED (run valid) ===')
        elif pc in SITES:
            src = int(gdb.parse_and_eval('$'+SITES[pc]))
            if src and src != 0x40a0000 and src < 0x100000000:
                oo, ko = 0x40a0000, src
                n = 0
                for off in (0,8,0x10,0x5e0,0x7f0,0x7f8,0xff8):
                    our = u64(oo+off)
                    if our and u64(ko+off) == 0:
                        inf.write_memory(ko+off, our.to_bytes(8,'little')); n += 1
                log('=== P14-GRAFT: re-filled %d zero slot(s) of table 0x%x before CR3 switch (site 0x%x, src 0x%x) ===' % (n, ko, pc, src))
                # L-199: full-PML4 audit (observe-only, boot 70+): PML4 = 512 x 8B.
                # Any slot nonzero in our table but still zero in the src table
                # AFTER the 7-slot graft names an incomplete slot set if a
                # 0x108-species wall persists despite the graft.
                extra = [hex(i*8) for i in range(512)
                         if u64(oo+i*8) and u64(ko+i*8) == 0]
                if extra:
                    log('P14-AUDIT: %d slot(s) nonzero in tramp table but zero in src (beyond the 7 grafted): %s' % (len(extra), ' '.join(extra[:40])))
            else:
                log('P14-SELFRELOAD at site 0x%x (src 0x%x = trampoline table or invalid)' % (pc, src))
            # L-201 (boot 69 wall): the kernel INHERITS a dense table from the
            # PSP and modifies it in place; its stage-2 pmap init re-points a
            # PML4 slot at its OWN (sparse) PDPT page — boot 69's #PF at
            # 0xffffffff07000c74 (KVA-window offset 0x07000c74, PA 0x07000c74)
            # is that species: dense coverage lost when the PDPT was swapped.
            # PSP-ify at EVERY cr3 stop: zero PDPT slots get our dense identity
            # PD (PD_ID, 0x40a4000: 512 x 2MiB identity), zero PD slots get
            # identity 2MiB PTEs; the kernel's own nonzero entries untouched.
            t = src if (src and src != 0x40a0000 and src < 0x100000000) else 0x60e5000
            d1 = d2 = 0
            for off in (0,8,0x10,0x5e0,0x7f0,0x7f8,0xff8,0xff0):
                v = u64(t+off)
                if not v:
                    continue
                p = v & ~0xFFF
                if p in (0x40a1000,0x40a2000,0x40a3000,0x40a7000):
                    continue  # one of our own PDPT pages (already dense)
                # BOOT 114 / S-13 SCOPED (L-285/C-035): under PML4[511] (off 0xff8 =
                # kernel high-half KVA, VM_MIN_KERNEL_ADDRESS 0xffffff8000000000+), skip
                # the kernel-managed low-KVA PDPT slots — the kernel's own KVA map range
                # it tears down via pmap_remove, where a DENSIFY 2MiB identity superpage
                # crashes pmap_remove_kernel_pde "Missing pt page" (C-035).
                # BOOT 146 (S-13 EXTENDED, L-426 residual that L-287 predicted): add
                # PDPT slot 0 (VA 0xffffff8000000000-0xffffff803fffffff). session145
                # advanced past a53io/srtc to a SECOND pmap_remove_kernel_pde panic at
                # VA 0xffffff800b200000 = PML4[511]/PDPT[0]/PD[89] (ORIG_PDE
                # 0x002000000b200083, PDE* 0xffffafe1040a42c8 = PD_ID@0x40a4000 slot 89;
                # recovered from the s145 park stack frame below pmap_remove_pde's call
                # 0x80af010a). PDPT[0] is the SAME kernel-KVA class as PDPT[2]: the kernel
                # is doing pmap_remove on it (= it owns/manages it), it is NOT graft64
                # (PDPT[449], the ONLY proven load-bearing slot, b109), and no switch-time
                # harness AUDIT/FINGERPRINT read touches PDPT[0]'s VA range (reads are
                # PDPT[508]/[510]/graft64). Keep EVERY OTHER PDPT slot densified: b109
                # proved skipping all of PML4[511] #PF'd our own graft64 at VA
                # 0xffffffff07000de6 (= PML4[511]/PDPT[449]/PD_ID[56] -> PA 0x7000000),
                # so PDPT[449] etc. MUST stay mapped. Surgical: don't fake the KVA the
                # kernel builds/clears; keep the ones our code + early kernel read.
                # NOTE: PDPT[1] (0xffffff8040000000-0x7fffffff) is the contiguous middle
                # slot of the same low-KVA bootstrap window; if a later teardown panics
                # there, extend this set to {0,1,2} (the P14-DENSIFY-SCOPE log shows it).
                skip_pdpt = {0, 2} if off == 0xff8 else set()
                pdt = 0
                for i in range(512):
                    if i in skip_pdpt:
                        if u64(p+i*8) == 0:
                            log('P14-DENSIFY-SCOPE: PML4[511] PDPT[%d] left ZERO (kernel KVA map 0xffffff80_8xxxxxxx it tears down; S-13 scoped, C-035 fix)' % i)
                        continue
                    e = u64(p+i*8)
                    if e == 0:
                        inf.write_memory(p+i*8, (0x40a4003).to_bytes(8,'little')); d1 += 1
                    elif pdt < 8:
                        q = e & ~0xFFF
                        if q in (0x40a4000,0x40a5000,0x40a6000):
                            continue  # our dense PD pages
                        pdt += 1
                        for j in range(512):
                            if u64(q+j*8) == 0:
                                inf.write_memory(q+j*8, (j*0x200000|0x83).to_bytes(8,'little')); d2 += 1
            if d1 or d2:
                log('P14-DENSIFY: table 0x%x at site 0x%x: filled %d PDPT slot(s) + %d PD 2MiB slot(s) with identity (PSP-ify)' % (t, pc, d1, d2))
            # L-215(5): P21 — kernel PML4 slot 0 (VA 0x0-0x100000000) was
            # never grafted (AUDIT lists it among the zeros): the low
            # window (VA 0x20 stub / VA 0x108 BDA -> 2MiB @PA 0x4097000,
            # the SAME page the trampoline domain uses) exists only in
            # the trampoline domain, so the kernel fatal drop to VA 0x20
            # #PFs into the DF cascade (boots 71-76). Graft slot0 := our
            # PML4 slot0 (-> PDPT 0x40a1000 -> PD_ID[0]=0x4097023 2MiB
            # @0x4097000 + identity 2MiB above). Re-applied at EVERY real
            # switch stop (only when slot0 is zero — kernel-owned entries
            # never touched).
            tt = t
            s0 = u64(tt)
            if s0 == 0:
                o0 = u64(0x40a0000)
                if o0:
                    inf.write_memory(tt, o0.to_bytes(8,'little'))
                    log('P21: kernel PML4[0] (table 0x%x) was zero -> grafted := our PML4[0] 0x%x (low window grafted: VA 0x0-0x200000 -> 2MiB@PA 0x4097000: stub VA 0x20 -> PA 0x4097020, BDA VA 0x108 -> PA 0x4097108; VA 0x200000-0x100000000 identity via PD_ID slots 1+)' % (tt, o0))
            # L-208: fingerprint OUR pages + the kernel's new PD pages at release
            # (4-point change timeline across stops — the information a watchpoint
            # would give, without extra debug registers)
            def fp(page, tag):
                z = odd = 0; samples = []
                for j in range(512):
                    e = u64(page + j*8)
                    if e == 0: z += 1
                    elif (e & 0xFFF) != 0x83 and j != 0:
                        odd += 1
                        if len(samples) < 6: samples.append('slot%d=0x%x' % (j, e))
                log('P14-FINGERPRINT %s@0x%x: %d zero, %d foreign, %d identity/ours of 512 %s' % (tag, page, z, odd, 512-z-odd, ('; '.join(samples)) or ''))
            fp(0x40a4000, 'PD_ID (ours)')
            for off in (0xff8, 0xff0):
                v = u64(t + off)
                if v:
                    pdpt = v & ~0xFFF
                    if pdpt not in (0x40a1000,0x40a2000,0x40a3000,0x40a7000):
                        for i in range(512):
                            e = u64(pdpt + i*8)
                            p2 = (e & ~0xFFF) if e else 0
                            if e and p2 not in (0x40a4000,0x40a5000,0x40a6000) and p2 > 0x10000 and p2 < 0x80000000:
                                fp(p2, 'kernel-PD (via t+0x%x slot%d)' % (off, i))
            # === BOOT 87: two PASSIVE read-only probes at the trampoline's
            # link addresses (no breakpoint, no stop added; nothing written).
            # At this stop CR3 is still the trampoline table (0x40a0000), so
            # the low VAs identity-map to the same PAs (PML4[0] -> PDPT_ID ->
            # PD_ID slot 0x38 = 2MiB @0x7000000). Read only: gdb `x/8bx`.
            TRAMP_SIG = [0x55,0x48,0x89,0xe5,0x57,0x56,0x52,0x48]
            def p86_read8(va, name):
                log('P86-%s ENTER VA=0x%x' % (name, va))
                try:
                    txt = gdb.execute('x/8bx 0x%x' % va, to_string=True)
                except Exception as e:
                    log('P86-%s READ-ERR %r looks_like_trampoline=no' % (name, e))
                    return None
                log('P86-%s raw: %s' % (name, txt.rstrip()))
                # b99 FIX (defect class [A] in the header): gdb prints
                #   `0x7000dd6 <graft64>:	0x55	0x48 ...`
                # so the ADDRESS column starts with `0x70`, and the old
                # _re.findall('0x([0-9a-fA-F]{2})', txt) took it as byte 0 —
                # every list was shifted by one and could never equal
                # TRAMP_SIG (b98 GLOG line 42 proves it: correct bytes,
                # looks_like_trampoline=no). Strip the column at ':' per line
                # first, then take only 1-2 hex digits that end at a word
                # boundary, so neither the address nor a 3+ digit token can
                # leak a byte into the list.
                bs = []
                for _ln in txt.splitlines():
                    _body = _ln.split(':', 1)[1] if ':' in _ln else _ln
                    bs += [int(h, 16) for h in _re.findall(r'0x([0-9a-fA-F]{1,2})\b', _body)]
                if len(bs) < 8:
                    log('P86-%s PARSE-ERR (%d bytes of 8) looks_like_trampoline=no' % (name, len(bs)))
                    return None
                log('P86-%s parsed %d byte(s): %s' % (name, len(bs), ' '.join('%02x' % b for b in bs[:8])))
                return bs[:8]
            p86_d22 = p86_read8(0x7000dd6, 'TRAMP-AT-SWITCH')
            p86_tv = (p86_d22 == TRAMP_SIG)
            log('P86-TRAMP-AT-SWITCH PA=0x7000dd6 looks_like_trampoline=%s' % ('yes' if p86_tv else 'no'))
            p86_base = p86_read8(0x7000000, 'TRAMP-BASE')
            if p86_base is not None:
                log('P86-TRAMP-BASE PA=0x7000000 multiboot_header=%s (first 4: %s vs 02 b0 ad 1b)' % ('yes' if p86_base[:4] == [0x02,0xb0,0xad,0x1b] else 'no', ' '.join('%02x' % b for b in p86_base[:4])))
            log('P86-TRAMP-BASE PA=0x7000000 looks_like_trampoline=%s' % ('yes' if p86_tv else 'no'))
            if src and src != 0x40a0000 and src < 0x100000000:
                count = len(gdb.breakpoints() or ())
                gdb.execute('delete')
                remaining = len(gdb.breakpoints() or ())
                if remaining:
                    raise RuntimeError('P14-STERILE: %d breakpoints remain' % remaining)
                log('P14-STERILE: deleted %d breakpoints at site 0x%x; remaining=0' % (count, pc))
                # ===== BOOT 114: P114 S-31 inject + DENSIFY-scope regression boot =====
                # The DENSIFY loop above now SKIPS PML4[511] (off 0xff8, kernel high-half
                # KVA) so the kernel no longer finds a DENSIFY 2MiB superpage to demote
                # (C-035 fix). P114 only keeps the S-31 MPERF/APERF inject (needed to pass
                # the #DE), then DETACHES so the guest free-runs: the serial + triage are
                # the regression guard (banner still prints? pmap panic gone? how far?).
                # A watchpoint at the pmap panic (0xb0210d) is kept as a NEGATIVE check:
                # if the scope failed it still fires. Register: LEDGER 11 (S-31, S-13).
                MPERF_INJ = 0x200000; APERF_INJ = 0x200000
                I1 = 0xffffffff80b7a2de; I2 = 0xffffffff80b7a2e9; PP = 0xffffffff80b0210d
                import re as _re2
                def p110_cr3():
                    try:
                        mm = gdb.execute('monitor info registers', to_string=True)
                        g = _re2.search('CR3=(?:0x)?([0-9a-fA-F]+)', mm or '')
                        return g.group(1) if g else '?'
                    except Exception as e:
                        return 'err:%r' % e
                def inject(tag, val):
                    pre_a = reg('rax')
                    try:
                        gdb.execute('set $rax = 0x%x' % val); gdb.execute('set $rdx = 0')
                    except Exception as e:
                        log('P114-%s INJECT-ERR %r' % (tag, e)); return
                    ok = (reg('rax') == val)
                    log('P114-%s CR3=0x%s rdmsr pre eax=0x%x -> INJECT eax=0x%x WRITE_OK=%s' % (tag, p110_cr3(), (pre_a or 0) & 0xffffffff, val, ok))
                log('=== P114-ARM: I1 0xffffffff80b7a2de I2 0xffffffff80b7a2e9 (S-31 MPERF/APERF inject) + PP 0xffffffff80b0210d (pmap-panic NEGATIVE check) ; DENSIFY scoped off PML4[511] PDPT[0]+PDPT[2] (BOOT146 S-13 extended, L-426) ===')
                p110_bp = {}
                for va in (I1, I2, PP):
                    try:
                        o = gdb.execute('break *0x%x' % va, to_string=True)
                        m = _re2.search(r'[Bb]reakpoint ([0-9]+)', o or ''); p110_bp[va] = int(m.group(1)) if m else None
                    except Exception as e: p110_bp[va] = None; log('P114-ARM-ERR 0x%x: %r' % (va, e))
                _i1 = _i2 = False
                for _step in range(8):
                    if _i1 and _i2: break
                    try:
                        gdb.execute('continue')
                    except gdb.error as e:
                        log('P114-CONT-END: %s' % e); break
                    cpc = int(gdb.parse_and_eval('$pc'))
                    if cpc == I1 and not _i1:
                        _i1 = True; inject('I1-MPERF', MPERF_INJ)
                    elif cpc == I2 and not _i2:
                        _i2 = True; inject('I2-APERF', APERF_INJ)
                    elif cpc == PP:
                        log('P114-PANIC-STILL-FIRES: pmap_remove_kernel_pde panic reached BEFORE both injects — DENSIFY scope did NOT clear it (regression/fix-fail)'); break
                    else:
                        log('P114-STOP @0x%x (unexpected) — stopping' % cpc); break
                if not _i1: log('P114-NOFIRE I1 (printcpuinfo MPERF rdmsr) — did not reach CPU-ID')
                if not _i2: log('P114-NOFIRE I2 (printcpuinfo APERF rdmsr)')
                # delete the inject/panic bps (I1/I2/PP); the funchigh trace below
                # keeps gdb ATTACHED past this point (the stock P114 would detach here).
                _nums = [str(n) for n in p110_bp.values() if n]
                if _nums:
                    try: gdb.execute('delete %s' % ' '.join(_nums))
                    except Exception as e: log('P114-DEL-ERR: %r' % e)
                # ===== A53IO INJECT (session145, L-425 make-it-exist): stay
                # ATTACHED past the switch to the a53io NULL-tag CFI wall @0x80e441b8
                # (L-424) and ANSWER-THE-CALL (hv14/hv0a pattern): inject a valid
                # no-bounce NAPS bus_dma_tag so the kernel's OWN bus_dmamap_create
                # (FUN_80788410) returns 0 for all 440 initialize_naps iterations, so
                # the cfi_check_fail(callee 0) panic never fires and a53io_load returns
                # to mi_startup. Reuses the P114/STEP-D stay-attached HW-break machinery.
                # ONE hbreak at initialize_naps entry (FUN_807c4770; its ONLY callers
                # are a53io_load @0x807c20fa/0x807c2165, one branch runs, so it fires
                # once). gdb-side write: DAT_838e79b0 is TRUE BSS (zeroed by kernel
                # early-start), so a trampoline/static pre-set would NOT survive.
                # DAT_838e79b0 is copied from the NULL DAT_838e7998 just before the
                # call (@0x807c20f3/0x807c215e) and re-read EACH loop iteration
                # (@0x807c4810), so overwriting it at this entry bp propagates to all
                # 440 iterations. Addressing is virtual via the current (kernel) CR3.
                A53_BP   = 0xffffffff807c4770   # initialize_naps entry (FUN_807c4770)
                DAT79B0  = 0xffffffff838e79b0   # a53io NAPS meta-tag ptr (consumed by the CFI dispatcher)
                SCRATCH  = 0xffffffff84030000   # gdb-owned scratch: high kernel BSS, RW seg [0x81c95000,0x84072040), 0 xrefs, above softc 0x8402eb88, unused during the loop
                IMPL     = 0xffffffff81d19a10   # bus_dma impl vtable: impl+0x10=bus_dmamap_create, CFI fast-path (L-425)
                a53n = None
                try:
                    o = gdb.execute('hbreak *0x%x' % A53_BP, to_string=True)
                    m = _re2.search(r'[Bb]reakpoint ([0-9]+)', o or ''); a53n = int(m.group(1)) if m else None
                except Exception as e:
                    log('A53-ARM-ERR: %r' % e)
                log('=== A53-ARMED (HW/hbreak #%s) @initialize_naps 0x%x ; scratch-tag 0x%x (impl 0x%x, nsegments=1) -> DAT_838e79b0 0x%x ===' % (a53n, A53_BP, SCRATCH, IMPL, DAT79B0))
                # ===== BOOTVERBOSE ENABLE (session148, L-431, S-60, make-it-exist,
                # FAITHFUL). The literal devconf marker is printed by configure_final
                # FUN_805dcda0 only when bootverbose DAT_ffffffff837c8878 != 0
                # (index-confirmed; cold DAT_827a61d0 has exactly ONE writer, inside
                # FUN_805dcda0, so cold=0/userland PROVES configure_final executed).
                # bootverbose has EXACTLY ONE writer, mi_startup FUN_8073f170 at
                # 0x8073f179, which ran EARLY and left it 0 (our boothowto lacks
                # RB_VERBOSE 0x800). Runs s148-run2/run3 proved configure_final executes
                # BEFORE the A53 (initialize_naps) and SBL inject points in THIS build
                # (a53io/SBL run later), so a write at those points is too late. We arm
                # the configure_final ENTRY hbreak HERE — at the earliest attached point
                # (right after the CR3 switch, before initialize_naps) — and set
                # bootverbose at its entry in whichever inject loop reaches it first
                # (A53 loop primary; SBL loop + a post-SBL catch are fallbacks). The OWN
                # configure_final then runs its OWN bootverbose-gated printf and prints
                # its OWN marker; no string is faked or printed harness-side (FAITHFUL).
                CFG_BP = 0xffffffff805dcda0   # configure_final entry (FUN_805dcda0)
                bv_done = False
                cfgn = None
                try:
                    o = gdb.execute('hbreak *0x%x' % CFG_BP, to_string=True)
                    m = _re2.search(r'[Bb]reakpoint ([0-9]+)', o or ''); cfgn = int(m.group(1)) if m else None
                except Exception as e:
                    log('CFG-ARM-ERR: %r' % e)
                log('=== BOOTVERBOSE-ARMED (HW/hbreak #%s) @configure_final 0x%x ; will set bootverbose DAT_0x837c8878:=1 at its entry so the kernel prints its OWN devconf marker (S-60) ===' % (cfgn, CFG_BP))
                def _set_bootverbose(where):
                    # set bootverbose=1 at configure_final entry; returns True on success.
                    BV = 0xffffffff837c8878
                    try:
                        bv_before = int.from_bytes(bytes(inf.read_memory(BV, 8)), 'little')
                        inf.write_memory(BV, (1).to_bytes(8, 'little'))
                        bv_after = int.from_bytes(bytes(inf.read_memory(BV, 8)), 'little')
                        okbv = (bv_after & 0xffffffff) == 1
                        log('*** BOOTVERBOSE-INJECT: at configure_final 0x%x entry (%s), DAT_ffffffff837c8878 (bootverbose) before=0x%x -> wrote 1 -> after=0x%x  cr3=0x%s  %s ***' % (
                            CFG_BP, where, bv_before, bv_after, p110_cr3(), 'OK' if okbv else 'FAILED'))
                        log('SYNTH-HARNESS: set bootverbose (DAT_ffffffff837c8878) := 1 at the configure_final FUN_805dcda0 ENTRY bp (after mi_startup FUN_8073f170 at 0x8073f179 left it 0, immediately before configure_final OWN bootverbose-gated printf and its cold=0 write). This is the real -v / RB_VERBOSE 0x800 value mi_startup would have set from boothowto, supplied make-it-exist style; bootverbose has exactly one writer (q.py) so it is unchallenged. The KERNEL OWN configure_final then prints its OWN device-config marker on resume; no string is faked or printed harness-side (FAITHFUL). S-60.')
                        return okbv
                    except Exception as e:
                        log('BOOTVERBOSE-INJECT-ERR: %r (bootverbose NOT set; the literal devconf marker will stay suppressed this run)' % e)
                        return False
                a53_done = False
                for _astep in range(200):
                    try:
                        gdb.execute('continue')
                    except gdb.error as e:
                        log('A53-CONT-END (guest exited/halted/panicked before the inject bp): %s' % e); break
                    apc = int(gdb.parse_and_eval('$pc'))
                    if apc == CFG_BP and not bv_done:
                        # configure_final entry reached (runs BEFORE initialize_naps in
                        # this build): set bootverbose before its OWN marker test. S-60.
                        bv_done = _set_bootverbose('A53-loop')
                        try:
                            if cfgn: gdb.execute('delete %d' % cfgn); cfgn = None
                        except Exception as e:
                            log('CFG-DEL-ERR: %r' % e)
                        continue
                    if apc != A53_BP:
                        # only the a53io + configure_final hbreaks are armed here (all
                        # pre-switch bps were deleted at the switch); s144 free-ran this
                        # region cleanly. A stop elsewhere is a defensive/residual-int3
                        # case: push through toward initialize_naps rather than abort the
                        # inject (bounded by the 200-step budget).
                        if _astep < 6 or _astep % 25 == 0:
                            log('A53-STEP %d: stop @0x%x (not the inject bp) — continuing toward initialize_naps' % (_astep, apc))
                        continue
                    try:
                        before = int.from_bytes(bytes(inf.read_memory(DAT79B0, 8)), 'little')
                    except Exception as e:
                        before = None; log('A53-READ-BEFORE-ERR: %r' % e)
                    # 0x90-byte zero-filled no-bounce tag: [0x00]=impl, [0x48]=nsegments=1(u32);
                    # [0x78]=0, [0x7c] flags bit0=0, [0x80]=0 are left zero by the zero-fill.
                    tag = bytearray(0x90)
                    tag[0x00:0x08] = IMPL.to_bytes(8, 'little')
                    tag[0x48:0x4c] = (1).to_bytes(4, 'little')
                    ok_tag = ok_ptr = False
                    try:
                        inf.write_memory(SCRATCH, bytes(tag)); ok_tag = True
                    except Exception as e:
                        log('A53-WRITE-TAG-ERR: %r' % e)
                    try:
                        inf.write_memory(DAT79B0, SCRATCH.to_bytes(8, 'little')); ok_ptr = True
                    except Exception as e:
                        log('A53-WRITE-PTR-ERR: %r' % e)
                    try:
                        after = int.from_bytes(bytes(inf.read_memory(DAT79B0, 8)), 'little')
                    except Exception as e:
                        after = None; log('A53-READ-AFTER-ERR: %r' % e)
                    # confirm the scratch tag reads back with impl@+0 and nsegments@+0x48
                    try:
                        chk = bytes(inf.read_memory(SCRATCH, 0x90))
                        chk_impl = int.from_bytes(chk[0x00:0x08], 'little'); chk_nseg = int.from_bytes(chk[0x48:0x4c], 'little')
                    except Exception as e:
                        chk_impl = chk_nseg = None; log('A53-READ-TAG-ERR: %r' % e)
                    a53_done = ok_tag and ok_ptr and (after == SCRATCH) and (chk_impl == IMPL) and (chk_nseg == 1)
                    log('*** A53-INJECT: DAT_838e79b0 before=0x%s -> wrote scratch-tag 0x%x (write_tag=%s write_ptr=%s) -> after=0x%s ; scratch[+0]impl=0x%s scratch[+0x48]nseg=%s  cr3=0x%s  %s ***' % (
                        ('%x' % before) if before is not None else '?', SCRATCH, ok_tag, ok_ptr,
                        ('%x' % after) if after is not None else '?',
                        ('%x' % chk_impl) if chk_impl is not None else '?', chk_nseg,
                        p110_cr3(), 'OK' if a53_done else 'FAILED'))
                    log('SYNTH-HARNESS: injected a valid no-bounce NAPS bus_dma_tag at gdb-owned scratch 0x%x (impl=0x%x @+0x00, nsegments=1 @+0x48, flags bit0=0, +0x78/+0x80=0) and set DAT_838e79b0:=scratch at the initialize_naps entry bp, replacing the a53io NULL meta-tag. The kernel bus_dmamap_create (FUN_80788410) now takes the no-bounce success path (returns 0) for all 440 iterations so the cfi_check_fail(callee 0) panic @0x80e441b8 is answered (make-it-exist, hv14/hv0a). GDB-side because DAT_838e79b0/DAT_838e7998 are TRUE BSS (no trampoline/static pre-set survives kernel BSS-zeroing). CAVEAT: leaves the a53io controller fundamentally absent -> runtime a53io request handlers (post-devconf) fault on NULL meta-tag/maps (acceptable, Phase-2 = Device-configuration-finished only).' % (SCRATCH, IMPL))
                    break
                if not a53_done:
                    log('A53-NOFIRE-OR-FAIL: the initialize_naps inject bp did not fire or the write failed — the a53io CFI wall was NOT answered this run')
                try:
                    if a53n: gdb.execute('delete %d' % a53n)
                except Exception as e: log('A53-DEL-ERR: %r' % e)
                # ===== SBL MAILBOX MUTEX INJECT (session147, L-428/L-429, S-59,
                # make-it-exist): supply the lock/cv state the REFUSED sbl_sm_service
                # modevent (_sceSblSmServiceRequestInitialize FUN_809c0aa0, which
                # mtx_init's "req mtx") never built, so sblServiceRequest FUN_809c0610's
                # OWN mtx_lock (FUN_806cf8d0 @ &0x83c6e890) acquires an UNOWNED mutex
                # instead of turnstile-blocking thread0 forever on the uninit lock-word
                # (0x2 contested/owner-NULL, L-428). 13.60 fail-softs this exact call.
                # We do NOT nop the mtx_lock, do NOT call FUN_809c0aa0 (its tail
                # sx_xlocks the uninit registry sx 0x83739fd8 = C-051), and do NOT write
                # DAT 0x83739ff8 (leaving the driver-ready guard =0 is what makes
                # sceSblDriverSendMsg early-return -0x25 and fail-soft like 13.60).
                # ONE-SHOT hbreak at sblServiceRequest ENTRY (0x809c0610) — precedes the
                # param_4==0 mtx_lock (decomp confirms the lock is inside that branch) —
                # on the FIRST hit write set A BEFORE the lock executes. A live park's
                # already-queued thread0 can't be woken, so this must land on a FRESH
                # boot before thread0's first sblServiceRequest (the wedge site, reached
                # post-TSC). Virtual addressing via the current kernel CR3.
                SBL_BP = 0xffffffff809c0610   # sblServiceRequest entry (FUN_809c0610)
                # set A: (addr, qword). Sibling MTX "intr config" @0x83b5c3e8 = {name,0x01030000,0,0x4}.
                SBL_W = [
                    (0xffffffff83c6e878, 0xffffffff814ec785),  # req mtx : lock_object.lo_name  -> "req mtx"
                    (0xffffffff83c6e880, 0x0000000001030000),  # req mtx : lo_flags (MTX_DEF, sibling-matched)
                    (0xffffffff83c6e888, 0x0000000000000000),  # req mtx : lo_data/lo_witness
                    (0xffffffff83c6e890, 0x0000000000000004),  # req mtx : mtx_lock = MTX_UNOWNED (unblocks the wait)
                    (0xffffffff83c6e898, 0xffffffff814c3860),  # req cv  : cv_description -> "req cv"
                    (0xffffffff83c6e8a0, 0x0000000000000000),  # req cv  : cv_waiters
                ]
                for _n in range(15):                           # 15x "req msg cv" @0x83c6e628 + n*0x28
                    _slot = 0xffffffff83c6e628 + _n*0x28
                    SBL_W.append((_slot + 0x00, 0xffffffff81536320))  # cv_description -> "req msg cv"
                    SBL_W.append((_slot + 0x08, 0x0000000000000000))  # cv_waiters
                # (bitmap 0x83c6e870 / counter 0x83c6e868 already 0 -> NOT written; 0x83739ff8 NOT written)
                sbln = None
                try:
                    o = gdb.execute('hbreak *0x%x' % SBL_BP, to_string=True)
                    m = _re2.search(r'[Bb]reakpoint ([0-9]+)', o or ''); sbln = int(m.group(1)) if m else None
                except Exception as e:
                    log('SBL-ARM-ERR: %r' % e)
                log('=== SBL-ARMED (HW/hbreak #%s) @sblServiceRequest 0x%x ; %d qword writes (req mtx -> MTX_UNOWNED, req cv, 15x req msg cv) ===' % (sbln, SBL_BP, len(SBL_W)))
                sbl_done = False
                for _sstep in range(400):
                    try:
                        gdb.execute('continue')
                    except gdb.error as e:
                        log('SBL-CONT-END (guest exited/halted/panicked before the inject bp): %s' % e); break
                    spc = int(gdb.parse_and_eval('$pc'))
                    if spc == CFG_BP and not bv_done:
                        # fallback catch: configure_final entry (if it had not already
                        # been caught in the A53 loop above). S-60.
                        bv_done = _set_bootverbose('SBL-loop')
                        try:
                            if cfgn: gdb.execute('delete %d' % cfgn); cfgn = None
                        except Exception as e:
                            log('CFG-DEL-ERR: %r' % e)
                        continue
                    if spc != SBL_BP:
                        # only the SBL + configure_final hbreaks are armed now (a53n +
                        # all pre-switch bps deleted); a stop elsewhere is a residual-
                        # int3 case -> push through toward sblServiceRequest (bounded by
                        # the 400 budget).
                        if _sstep < 6 or _sstep % 50 == 0:
                            log('SBL-STEP %d: stop @0x%x (not the inject bp) — continuing toward sblServiceRequest' % (_sstep, spc))
                        continue
                    try:
                        lw_before = int.from_bytes(bytes(inf.read_memory(0xffffffff83c6e890, 8)), 'little')  # expect 0x2 (L-428)
                    except Exception as e:
                        lw_before = None; log('SBL-READ-BEFORE-ERR: %r' % e)
                    nok = 0
                    for (_a, _v) in SBL_W:
                        try:
                            inf.write_memory(_a, _v.to_bytes(8, 'little')); nok += 1
                        except Exception as e:
                            log('SBL-WRITE-ERR @0x%x := 0x%x : %r' % (_a, _v, e))
                    try:
                        lw_after = int.from_bytes(bytes(inf.read_memory(0xffffffff83c6e890, 8)), 'little')
                        nm_after = int.from_bytes(bytes(inf.read_memory(0xffffffff83c6e878, 8)), 'little')
                        cv_after = int.from_bytes(bytes(inf.read_memory(0xffffffff83c6e898, 8)), 'little')
                        s0_after = int.from_bytes(bytes(inf.read_memory(0xffffffff83c6e628, 8)), 'little')
                    except Exception as e:
                        lw_after = nm_after = cv_after = s0_after = None; log('SBL-READ-AFTER-ERR: %r' % e)
                    sbl_done = (nok == len(SBL_W)) and (lw_after == 0x4) and (nm_after == 0xffffffff814ec785)
                    log('*** SBL-INJECT: req-mtx lock-word before=0x%s -> wrote %d/%d qwords -> lock-word=0x%s(MTX_UNOWNED) name=0x%s(req mtx) cv=0x%s(req cv) msgcv0=0x%s(req msg cv)  cr3=0x%s  %s ***' % (
                        ('%x' % lw_before) if lw_before is not None else '?', nok, len(SBL_W),
                        ('%x' % lw_after) if lw_after is not None else '?',
                        ('%x' % nm_after) if nm_after is not None else '?',
                        ('%x' % cv_after) if cv_after is not None else '?',
                        ('%x' % s0_after) if s0_after is not None else '?',
                        p110_cr3(), 'OK' if sbl_done else 'FAILED'))
                    log('SBL-SYNTH-HARNESS: at the sblServiceRequest (FUN_809c0610) entry bp, gdb-wrote the uninitialized SBL-mailbox lock state the refused sbl_sm_service modevent (_sceSblSmServiceRequestInitialize FUN_809c0aa0) would have built: "req mtx" mtx @0x83c6e878 (lo_name=0xffffffff814ec785, lo_flags=0x01030000, mtx_lock=MTX_UNOWNED 0x4), "req cv" @0x83c6e898, and 15x "req msg cv" @0x83c6e628+n*0x28. The kernel OWN mtx_lock (FUN_806cf8d0) now acquires an unowned mutex so thread0 no longer turnstile-blocks forever on the uninit lock-word 0x2 (L-428). DAT_0x83739ff8 is left 0 so sceSblDriverSendMsg early-returns -0x25 and the service fail-softs exactly like 13.60 (make-it-exist, S-59). GDB-side because the mtx/cv are TRUE BSS the kernel zeroes at early start. CAVEAT: the SBL service is fundamentally absent -> post-devconf SBL request handlers fail-soft/NULL (acceptable, Phase-2 = Device-configuration-finished).')
                    break
                if not sbl_done:
                    log('SBL-NOFIRE-OR-FAIL: the sblServiceRequest entry inject bp did not fire or a write failed — the SBL turnstile wedge was NOT answered this run')
                try:
                    if sbln: gdb.execute('delete %d' % sbln)
                except Exception as e: log('SBL-DEL-ERR: %r' % e)
                # ===== end SBL MAILBOX MUTEX INJECT (S-59) =====
                # BOOTVERBOSE (S-60) fallback: s148-run2/run3 showed configure_final
                # executes BEFORE both the A53 and SBL inject points in this build, so
                # it is normally caught in the A53 loop above. If it still has not been
                # caught (ordering surprise), stay attached and push the guest forward
                # until the configure_final 0x805dcda0 ENTRY bp fires, set bootverbose
                # there, and only then detach so the OWN configure_final prints its OWN
                # marker on resume.
                if (not bv_done) and cfgn:
                    log('=== BOOTVERBOSE-CATCH: configure_final not yet caught; continuing (attached) toward its 0x%x entry to set bootverbose before its OWN marker test (S-60) ===' % CFG_BP)
                    for _cstep in range(400):
                        try:
                            gdb.execute('continue')
                        except gdb.error as e:
                            log('CFG-CONT-END (guest exited/halted/panicked before configure_final entry): %s' % e); break
                        cpc = int(gdb.parse_and_eval('$pc'))
                        if cpc != CFG_BP:
                            if _cstep < 6 or _cstep % 50 == 0:
                                log('CFG-STEP %d: stop @0x%x (not configure_final entry) — continuing toward it' % (_cstep, cpc))
                            continue
                        bv_done = _set_bootverbose('post-SBL')
                        break
                try:
                    if cfgn: gdb.execute('delete %d' % cfgn); cfgn = None
                except Exception as e:
                    log('CFG-DEL-ERR: %r' % e)
                if bv_done:
                    log('BOOTVERBOSE-OK (S-60): bootverbose=1 set at configure_final entry before the marker test — the kernel prints its OWN marker on resume this run')
                else:
                    log('BOOTVERBOSE-NOFIRE (S-60): configure_final 0x%x entry never reached while attached — bootverbose left 0, the literal devconf marker will stay suppressed this run' % CFG_BP)
                log('P114-STERILE: S-31 inject + A53 inject bp + SBL inject bp + bootverbose bp removed; remaining=%d — detaching, guest free-runs toward "Device configuration finished."' % len(gdb.breakpoints() or ()))
                # ===== end P114 + A53IO INJECT =====
                return True
        elif pc in HW and hbp.get(pc) and not cap_done:
            # L-215(7): FIRST trap report, caught at a report entry by a
            # HARDWARE break (DR0/DR1/DR2): vCPU stopped by the gdbstub —
            # no guest #DB handler ran, no DR6 store, no int3 in text.
            # Frame: BODY/DFH -> RDI (stub did mov rdi, rsp / call),
            # TAIL -> RSP (pre-trap GPRs still live in the registers;
            # CPU-pushed oldRIP/oldRFL at [rsp+0xe8]/[rsp+0xf0]).
            cap_done = True
            which = HW[pc]
            mon = None
            try:
                mon = gdb.execute('monitor info registers', to_string=True)
            except Exception as e:
                mon = repr(e)
            efl = reg('eflags')
            tf = (efl & 0x100) if efl is not None else None
            rspv = reg('rsp'); rbpv = reg('rbp'); ripv = reg('rip')
            frp = reg('rdi') if which != 'TAIL' else rspv
            fr = []
            if frp is not None and frp > 0x1000:
                try:
                    for i in range(32): fr.append(hex(u64(frp + i*8)))
                except Exception as e:
                    fr = ['frame-read-err:%r' % e]
            stk = []
            if rspv is not None:
                try:
                    for i in range(16): stk.append(hex(u64(rspv + i*8)))
                except Exception as e:
                    stk = ['stack-read-err:%r' % e]
            log('=== P14-CAP: first trap report via %s entry 0x%x: rip=0x%x rsp=0x%s rbp=0x%s TF=%s RFLAGS=0x%x ===' % (which, pc, ripv if ripv is not None else -1, hex(rspv) if rspv is not None else '?', hex(rbpv) if rbpv is not None else '?', tf, efl if efl is not None else -1))
            log('P14-CAP MON (DR0-7/DR6/DR7/EFER/IDT/GDT/TR):' + (mon or 'monitor unavailable'))
            log('P14-CAP REGS (live; TAIL stop = pre-trap state):' + (gdb.execute('info registers', to_string=True) or ''))
            log('P14-CAP FRAME @%s=0x%x (78=trapcode e0=oldRFL-or-stub-zero e8=oldRIP f0=oldCS(fault)/oldRFL(trap) 100=oldRSP(DF); 30-70=GPRs): %s' % ('rdi' if which != 'TAIL' else 'rsp', frp if frp is not None else -1, ' '.join(fr)))
            log('P14-CAP stack: ' + ' '.join(stk))
            for name, off in (('v1-#BP', 0x10), ('v3-#DB', 0x30), ('v6-#GP', 0x60), ('v8-#DF', 0x80), ('v14-#PF', 0xe0)):
                try:
                    g0 = u64(0xffffffff83df4300 + off); g1 = u64(0xffffffff83df4300 + off + 8)
                    log('P14-CAP IDT %s: g0=0x%x g1=0x%x' % (name, g0, g1))
                except Exception as e:
                    log('P14-CAP IDT %s: read-err %r' % (name, e))
            nums = [n for n in hbp.values() if n]
            try:
                if nums: gdb.execute('delete %s' % ' '.join(str(n) for n in nums))
                log('P14-CAP: all HW capture breaks deleted (DR0-3/DR7 restored to reset) — later kernel runs DR-free and int3-free')
            except Exception as e:
                log('P14-CAP-DEL-ERR: %r' % e)
        elif pc in (PUTC, LINW) and pbp.get(pc) and not sw_done:
            # L-211/L-213: FIRST kernel console output (either bridge) in the
            # btext->switch window. Boot 76: the early trap output does NOT
            # use these bridges (third leaf 0x80465040) — these captures are
            # a bonus for entry-phase console init, not the trap report.
            sw_done = True
            which = 'PUTC' if pc == PUTC else 'LINW'
            ch = reg('rdi'); chs = chr(ch & 0xff) if ch is not None else '?'
            rsv = reg('rsi')
            # L-212: $drN parses to 'void' in this build's gdbstub; 'monitor
            # info registers' routes QEMU's own monitor through the gdbstub
            # and DOES expose DR0-7/DR6/DR7/EFER/IDT/GDT/TR (verified via
            # QMP on the parked boot-73 VM; works in batch gdb too, boot 74
            # SNAP1). L-213: NO backslash-n escape here — the monitor text is
            # multiline already and the outer triple-quoted template would
            # turn it into a real newline, SyntaxErroring the generated
            # script (boot 74 harness death).
            mon = None
            try:
                mon = gdb.execute('monitor info registers', to_string=True)
            except Exception as e:
                mon = repr(e)
            efl = reg('eflags')
            tf = (efl & 0x100) if efl is not None else None
            rspv = reg('rsp'); rbpv = reg('rbp')
            stk = []
            if rspv is not None:
                try:
                    for i in range(16): stk.append(hex(u64(rspv + i*8)))
                except Exception as e:
                    stk = ['stack-read-err:%r' % e]
            log('=== P14-CAP: first kernel console output via %s: rdi=0x%x (%r) rsi=0x%s rip=0x%x rsp=0x%s rbp=0x%s TF=%s ===' % (which, ch if ch is not None else -1, chs, hex(rsv) if rsv is not None else '?', pc, hex(rspv) if rspv is not None else '?', hex(rbpv) if rbpv is not None else '?', tf))
            log('P14-CAP MON (monitor info registers — DR0-7/DR6/DR7/EFER/IDT/GDT/TR):' + (mon or 'monitor unavailable'))
            log('P14-CAP stack: ' + ' '.join(stk))
            # L-216: the TRUE report body (0x805f7080, target of the #DB
            # wrapper 0x805f81d0) keeps the TRAP FRAME in r14 (prologue
            # `mov r14, rdi` — callee-saved, survives the printf/bridge
            # calls) and the PER-CPU base in rbx (`mov rbx, [gs:0]`). Boot
            # 76 dumped rbx = per-CPU, not the frame (L-214's rbx
            # assumption was wrong). Frame layout (stub 0x8045bfa0/0x8045a6f0
            # + shared tail): +0x78=trapcode, +0xe0=oldRFLAGS (TF bit),
            # +0xe8=oldRIP (the #DB trigger instruction), +0xf0=oldCS(CPL),
            # +0x30..+0x70=saved GPRs. 32 qwords cover all of it.
            r14v = reg('r14')
            fr = []
            if r14v is not None and 0xffffffff80000000 <= r14v < 0xffffffff86000000:
                try:
                    for i in range(32): fr.append(hex(u64(r14v + i*8)))
                except Exception as e:
                    fr = ['frame-read-err:%r' % e]
                log('P14-CAP FRAME @r14=0x%x (78=trapcode e0=oldRFL(+TF) e8=oldRIP f0=oldCS; 30-70=GPRs): %s' % (r14v, ' '.join(fr)))
            else:
                log('P14-CAP FRAME: r14=0x%s not a plausible kernel frame ptr — first char may predate the report body' % (hex(r14v) if r14v is not None else '?'))
            # per-CPU discriminator (report body: inc [rbx+0x4c] per report;
            # or [rbx+0xed],0x20 when CPL3): one gword read each
            rbxv = reg('rbx')
            try:
                if rbxv is not None and 0xffffffff80000000 <= rbxv < 0xffffffff86000000:
                    log('P14-CAP PERCPU @rbx=0x%x: [0x4c]=0x%x [0xed]=0x%x' % (rbxv, u64(rbxv + 0x4c), u64(rbxv + 0xed) & 0xff))
                else:
                    log('P14-CAP PERCPU: rbx=0x%s not a plausible per-CPU base' % (hex(rbxv) if rbxv is not None else '?'))
            except Exception as e:
                log('P14-CAP PERCPU: read-err %r' % e)
            # delete ONLY the fired break; the other (if still armed) dies
            # at the switch stop — NO sw break survives past it (L-215(7)).
            try:
                gdb.execute('delete %s' % pbp[pc])
                log('P14-CAP-SW: break #%s at %s deleted (entry-window output)' % (pbp[pc], which))
            except Exception as e:
                log('P14-CAP-DEL-ERR: %r' % e)
        else:
            log('P14-STOP @ 0x%x (unarmed site)' % pc)
    t_end = time.time() + @DUR@
    try:
        gdb.execute('continue')          # blocking: returns at first stop
        while time.time() < t_end:
            if process_stop():
                gdb.execute('detach')
                log('=== P14-SESSION-END: detached at CR3 switch ===')
                break
            gdb.execute('continue')
        else:
            log('P14-SESSION-END: no verified sterile switch before deadline')
    except gdb.error as e:
        # L-218: 'already running' = the QMP fallback released the guest
        # before our first continue (attach raced the 30 s grace, boot 78):
        # the run is UNMONITORED — no surgery, no capture; the bps (set at
        # ARMED) are deleted immediately below; the only artifact is the
        # residual int3 window = bp-set -> probe (declared for the read
        # rule). Otherwise: program-exited after the storm halt. Either way
        # the harness t1 still snapshots via QMP.
        if 'running' in str(e):
            log('P14-LATE-ATTACH: guest already running when our first continue fired (QMP fallback won the race) — run = UNMONITORED A/B-class: no graft/densify/P21, no capture; bps deleted now (residual int3 window = set->probe, can inject one spurious #DB report); serial is not a wall verdict')
        log('P14-LOOP-END: %s' % e)
    if gdb.selected_inferior().pid:
        gdb.execute('delete')
        gdb.execute('detach')
else:
    log('=== P14-NOATTACH: gdb never reached the stub — BTEXT-HIT unknown, snapshots still valid ===')
'''.replace('@SITES@', sitestr).replace('@DUR@', dur)
open(out,"w").write("set pagination off\nset confirm off\npython\n" + py + "end\n")
PY
  [ -s "$GDBF" ] || exit 1
  # L-195: run gdb as a tracked child so the harness killer (SIGTERM) actually
  # releases the stub — boot 66: the session's gdb kept holding the stub and
  # the t1 snapshot's attach timed out ("could not connect").
  gdb -batch -nx -q -x "$GDBF" >> "$GLOG" 2>&1 &
  GPID=$!
  trap 'kill $GPID 2>/dev/null' TERM INT
  wait $GPID 2>/dev/null
  trap - TERM INT
  grep -q "BTEXT-HIT" "$GLOG" || echo "=== BTEXT-MISS: kernel entry never reached — RUN VOID (or P14-NOATTACH above) ===" | tee -a "$GLOG"
}

# >>> WALLWATCH-BEGIN — event-driven SNAP1 trigger (b87). This block is
# extracted verbatim by wp3_boot/test_wallwatch.py (durable copy); keep it byte-identical
# in boot92.sh and session92.sh (cmp of the extracted block is a gate).
wall_hms() { # $1 = nanoseconds -> seconds.tenths (one decimal, no awk fork)
  printf '%d.%d' $(( $1 / 1000000000 )) $(( ($1 % 1000000000) / 100000000 ))
}

wall_scan() { # $1 = file; print the FIRST marker on a COMPLETE line, else nothing
  # `read` returns non-zero for a final line with no trailing newline, and the
  # loop body never runs for it => a half-written line cannot match (requirement:
  # only complete lines fire). Markers are deliberately narrow: `panic:` keeps
  # its colon (the trampoline's own SYNTH line says "low-panic stub", so a bare
  # `panic` would fire at t~0 on every boot) and `kernel trap ` keeps the
  # trailing space (it is a console line prefix, not a word).
  local line
  [ -r "$1" ] || return 1
  while IFS= read -r line; do
    case "$line" in
      *"panic:"*)       printf '%s\n' 'panic:';       return 0 ;;
      *"kernel trap "*) printf '%s\n' 'kernel trap '; return 0 ;;
      "L0")             printf '%s\n' 'L0';           return 0 ;;
    esac
  done < "$1"
  return 1
}

wall_scan_l0() { # $1 = file; the low-stub park ('L' then '0', then cli;hlt)
  # P22's stub writes exactly two bytes and NEVER a newline, so its marker is an
  # unterminated last line by construction and the complete-line rule above can
  # never see it. Accept it only when the whole unterminated last field is "L0"
  # (not "xxL0"), and the caller additionally requires 600 ms of no growth — a
  # mid-write cannot fake both.
  local blob
  [ -s "$1" ] || return 1
  blob=$(cat "$1" 2>/dev/null) || return 1
  [ "${blob##*$'\n'}" = "L0" ] || return 1
  printf '%s\n' 'L0(no-newline)'
}

wall_watch() { # globals: SLOG T1 GLOG WATCH_T0. 0 = settled wall, 3 = ceiling
  local deadline now sz last=-1 quiet=0 marker=
  deadline=$(( WATCH_T0 + T1 * 1000000000 ))
  while :; do
    now=$(date +%s%N)
    if [ "$now" -ge "$deadline" ]; then
      # ceiling: snapshot anyway, loudly. Also reached when a matched file keeps
      # growing (the settle clock never completes) — never hang, never silent.
      printf '=== WALL-TIMEOUT at t=%ss — snapshotting anyway (guest may still be running) ===\n' "$T1" | tee -a "$GLOG"
      return 3
    fi
    sz=$(stat -c %s "$SLOG" 2>/dev/null || echo -1)
    if [ "$sz" = "$last" ]; then quiet=$(( quiet + 1 )); else quiet=0; last=$sz; fi
    if [ -z "$marker" ]; then
      marker=$(wall_scan "$SLOG") || marker=
      if [ -z "$marker" ] && [ "$quiet" -ge 3 ]; then
        marker=$(wall_scan_l0 "$SLOG") || marker=
      fi
      if [ -n "$marker" ]; then
        printf "=== WALL-SEEN at t=%ss (marker: '%s') ===\n" \
               "$(wall_hms $(( now - WATCH_T0 )))" "$marker" | tee -a "$GLOG"
        quiet=0; last=$sz          # the settle clock starts AT the match
      fi
    elif [ "$quiet" -ge 3 ]; then
      # 3 consecutive 200 ms polls with an unchanged size = 600 ms of silence
      # after the last write. Only now is the guest's post-wall state static.
      printf '=== WALL-SETTLED at t=%ss (no growth 600 ms) ===\n' \
             "$(wall_hms $(( $(date +%s%N) - WATCH_T0 )))" | tee -a "$GLOG"
      return 0
    fi
    sleep 0.2
  done
}
# <<< WALLWATCH-END

# Let QEMU attach its ends of the FIFOs before starting the debugger.
sleep 1
kill -0 "$QPID" 2>/dev/null || { cat qemu_err_s148.txt; exit 1; }
# L-194: the P14 session attaches while the guest is FROZEN (-S), arms its
# breakpoints, and its own `continue` releases the guest. Fallback: if the
# session never arms within 30 s, QMP cont releases the guest unmonitored
# (run still valid as an A/B class — BTEXT-HIT goes unknown, no surgery).
# L-218: the session's attach retry window now spans the full 30 s grace
# (40 x 0.75 s), so a slow attach still arms before the fallback fires.
# t=0 for the wall timer: the P14 session's first gdb resume is the guest
# release (the session arms within ~2 s). The poller itself only starts after
# the pre-existing 30 s arming grace below, so a wall that lands inside the
# grace is reported at t >= 30 s — the number is "since guest release", never a
# value invented from the poller's start.
WATCH_T0=$(date +%s%N)
p14sess $(( T1 - 30 )) &
BHPID=$!
sleep 30
if ! grep -q "P14-ARMED" "$GLOG" 2>/dev/null; then
  qmp '{"execute":"cont"}' >> "$GLOG" || { echo "FATAL: QMP cont failed (guest never started)"; kill $QPID 2>/dev/null; exit 2; }
  echo "WARN: P14 session did not arm within 30s — guest released via QMP (unmonitored)"
fi
echo "started at t0"

# SNAP1: event-driven (see the WALLWATCH block) unless the A/B control asked
# for the old fixed window. Either way T1 is the ceiling and the remainder of
# the t1 path (session kill guard, QMP stop, snapshot) is unchanged.
if [ "${PS5_FIXED_TIMING:-0}" = 1 ]; then
  echo "=== WALL-WATCH OFF (PS5_FIXED_TIMING=1): fixed t1=${T1}s window (A/B control) ===" | tee -a "$GLOG"
  sleep $(( T1 - 30 ))
else
  wall_watch || true   # 0 = settled wall, 3 = WALL-TIMEOUT (already logged)
fi
( sleep 15; kill $BHPID 2>/dev/null ) & KILLER=$!   # guard: a stuck session must not eat T1
wait $BHPID 2>/dev/null
kill $KILLER 2>/dev/null; wait $KILLER 2>/dev/null
qmp '{"execute":"stop"}' >> "$GLOG" || echo "WARN: qmp stop@t1 failed"
sleep 1
snapqmp 1

if [ "$SNAP2_ON" = 1 ]; then
  qmp '{"execute":"cont"}' >> "$GLOG"
  sleep $(( T2 - T1 ))
  qmp '{"execute":"stop"}' >> "$GLOG"
  sleep 1
  snapqmp 2
else
  # b82b-b86: SNAP2 == SNAP1 byte-for-byte; the guest is static after the wall.
  # The guest therefore stays STOPPED from the t1 stop, which is exactly the
  # state the PARK block below expects.
  echo "=== SNAP2 SKIPPED (static post-wall; PS5_SNAP2=1 to force) ===" | tee -a "$GLOG"
fi
# === PARK BLOCK (the only behavioural change vs boot92.sh) ==================
# The guest is already stopped by the QMP stop above (SNAP2 forced or skipped).
# From here: no kill, no wait, no pipe deletion, no lock removal. PS5_PARKED
# disables the EXIT trap so the QMP FIFOs and QEMU survive the shell exit.
PARK_DIRNAME=$(basename "$PS5_BOOT_IPC")
PARK_ENV="/tmp/opencode/ps5-park-${PARK_DIRNAME}.env"
SNAP_TIME=$(date -Is 2>/dev/null || date)
ROOT_DIR=$(cd ../.. && pwd)
LOCK="$ROOT_DIR/coord/BOOT.lock"
if ! cat > "$PARK_ENV" <<ENV
# PARKED PS5 14.22 session — written by session92.sh (self-describing).
# Query:  bash qread.sh <this file> "<hmp command...>"    (add --cont if running)
# End:    bash park-stop.sh <this file>   (QMP quit + IPC cleanup + BOOT.lock removal)
IPC_DIR=$PS5_BOOT_IPC
QEMU_PID=$QPID
LAUNCH_PID=$LAUNCH_PID
SERIAL=$SLOG
SERIAL_PATH=$PWD/$SLOG
GLOG=$GLOG
GLOG_PATH=$PWD/$GLOG
SNAP_TIME=$SNAP_TIME
SNAP_T2=$T2
TRAMPOLINE_SHA=$IMGBUILD_ELF_HASH
PATCHES_SHA=$IMGBUILD_INC_HASH
STARTED=$STARTED
PARKED_AT=$SNAP_TIME
BOOT_LOCK=$LOCK
ENV
then
  echo "=== PARK-FAIL: could not write $PARK_ENV — falling back to cleanup ===" | tee -a "$GLOG"
  exit 1
fi
PS5_PARKED=1
export PS5_PARKED
echo "=== PARKED: $PARK_ENV (guest stopped; qread.sh can query it) ==="
if [ -f "$LOCK" ]; then
  echo "BOOT.lock KEPT: $LOCK — the boot is not over; remove it only AFTER: bash park-stop.sh $PARK_ENV"
else
  echo "WARN: $LOCK is absent (not created by this script); park-stop.sh will still remove it if present"
fi
echo "park envelope: QEMU exits by itself ${TMO}s after launch; park-stop.sh ends it early"
echo "=== session parked: QEMU left running, guest stopped, pipes intact ==="
echo "=== $SLOG (kernel console + trampoline) ==="
tr -d '\0' < "$SLOG" 2>/dev/null
echo "=== $GLOG (snapshots) ==="
cat "$GLOG"
cp "$SLOG" "$GLOG" /tmp/opencode/ 2>/dev/null
echo "logs: $GLOG, $SLOG"
