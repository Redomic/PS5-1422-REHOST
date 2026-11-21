# Glossary

The project's vocabulary, in plain terms. If a word in the other documents is doing more work
than it should, it is probably defined here.

**Rehost.** Running a kernel built for one machine on a different machine by rebuilding the
environment it expects, rather than translating its instructions. Because a PS5 and this PC share
the same processor family, the kernel's own code runs directly; only the surrounding world has to
be reconstructed. This is what separates the project from an emulator.

**The boot chain.** The sequence of stages a console runs before the kernel — a security
processor, a bootloader, a hypervisor — each handing the next a more prepared machine. Collectively
they give the kernel its page tables, a memory map, a device list, boot settings, and services to
call. On a PC none of it exists, so it has to be supplied by other means.

**Trampoline.** The small piece of code this project runs in place of the console's boot chain. It
switches the processor into the right mode, builds the page tables, hands the kernel its memory map
and boot settings, and jumps to the kernel's entry point. It is "the platform" — the part that
would always exist, on any machine, under any kernel.

**Synthetic.** Any behaviour shown to the kernel that did not come from Sony: a faked device
response, an invented table value, a boot setting the boot chain would normally supply, a
hypervisor call answered by the harness, or a call skipped because the code it targets is missing
from the dump. Each one stands in for a piece of the console that is absent here. Every synthetic
is listed in the [synthetic register](synthetic-register.md) with what it pretends to be, what the
kernel receives, and how to remove it.

**Patch.** The concrete implementation of a synthetic — an entry in the trampoline's patch table
that changes what the kernel reads at a specific address. The baseline boot stands on 62 of them.

**Make it exist (the governing rule).** When the kernel fails a check, supply what it was looking
for so the kernel's *own* code succeeds — do not delete the check. A satisfied check is evidence
you understood what the kernel wanted; a deleted check teaches you nothing and moves the failure
somewhere harder to attribute.

**The three moves.** How the patch set is kept to only what is genuinely needed: *remove what
never runs* (delete stand-ins the boot never reaches), *model what is* (build the real hardware in
QEMU so the kernel's driver runs against it), and *guards aren't inert* (a stand-in that the boot
does reach is load-bearing and can only be retired by modelling the thing it covers, not by
deletion).

**The gate / BTEXT-HIT.** The single checkpoint that proves a run is real: the harness records the
moment control reaches the kernel's own entry point (internally `BTEXT-HIT`). If it never fires,
the kernel never truly started, a stray jump may have produced whatever printed afterward, and the
run is discarded regardless of how convincing its output looks.

**CR3 domain.** `CR3` is the processor register naming the active page tables. The harness checks
that the tables live at a fault are the *kernel's* own, not the trampoline's — otherwise the
memory being read isn't the kernel's and any conclusion from it is void.

**Control read.** A deliberate read of a known-nonzero location included in every memory snapshot.
A read of empty or wrong memory returns zeros with a success code, so without a control read
"zero" is ambiguous — it could mean "the address was wrong," not "the value is zero."

**Graft.** Writing the trampoline's own page-table entries into the kernel's page tables at the
moment the kernel switches to them, so the handoff is seamless and the kernel keeps a consistent
view of memory across the switch.

**`int3` hole / code absent.** Roughly a sixth of the kernel's executable region is filler bytes
(the `int3` instruction), not real code — Sony ships it that way, confirmed against an unrelated
console dump. A call into a hole cannot be answered, only skipped, and the project records the
reason as "code absent" rather than treating it as a check it chose to bypass.

**Loader environment.** A set of boot-time settings (on FreeBSD-derived systems, the `kenv`) that
the boot chain normally hands the kernel. A few values the kernel reads from it — a timer setting,
a memory tunable — have to be supplied here because nothing earlier ran to set them.

**Device model.** A piece of hardware implemented inside QEMU so the kernel's real driver has
something genuine to talk to, replacing a faked "the device answered" response. The included
worked example is the timer (HPET) southbridge.

**Parked VM.** A boot that stops and stays alive instead of exiting, so its memory and registers
can be inspected with as many queries as needed from a single launch — the alternative to
re-booting once per question.

**Writer ≠ auditor.** Whoever builds a fix does not get to certify it. Verification is done from
the logs and the image by someone trying to *disprove* the result, on the assumption that any
apparent success might be an artifact until the evidence rules that out.

**Device configuration finished.** The kernel's own message, printed when its device-probe loop
completes — the point this project set out to reach. As on a real boot, the path there tolerates
individual devices failing; it does not tolerate one hanging.

**S-xx / P-xx / L-xx.** The identifiers used in the register and comments: `S-xx` is a synthetic,
`P-xx` is the patch that implements it, `L-xxx` is a logged experiment in the project's internal
ledger (not published here) that introduced or changed it.
