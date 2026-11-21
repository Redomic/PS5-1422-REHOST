# FAQ

**What is this, in one sentence?**
A genuine PlayStation 5 14.22 kernel, booted on an ordinary PC under QEMU with no Sony hypervisor,
far enough to finish configuring its devices — with a complete, honest account of everything that
made it possible.

**Is the kernel emulated?**
No. The PS5 and this PC share the same processor family (x86-64, AMD), so the kernel runs its own
code directly. What is reconstructed is the *environment* a console would normally prepare before
the kernel starts — see [glossary: rehost](glossary.md).

**Can I run it without a PlayStation?**
You can run the harness, but not the boot — you supply your own, legally obtained, 14.22 kernel
image. This repository contains no firmware. See [reproducing.md](reproducing.md) for what you
need and [provenance.md](provenance.md) for the artifact identities to check yours against.

**Can it run games?**
No. There is no game execution here and no path toward one. The parts of the kernel a game path
would need are shipped by Sony as filler bytes, not recoverable code (see
[glossary: int3 hole](glossary.md)), and the project's goal is the kernel's own
`Device configuration finished.` marker, not userland. This is research and interoperability work,
not a way to play anything.

**Why boot it with no hypervisor? Isn't the hypervisor part of the console?**
It is — and running without it is the point. The hypervisor's role in the boot (the services the
kernel calls into) is answered directly by the harness and by modelled hardware in QEMU, which is
both simpler and more transparent than reproducing Sony's `lv1`. The hypervisor image was studied
to learn what those calls expect, but it is never executed.

**How do I know the boot is real and not a trick?**
Every run records the moment the kernel's own entry point executes
([glossary: the gate](glossary.md)); without it, the run is discarded. The complete logs in
[`../evidence/logs/`](../evidence/logs/) contain that checkpoint and every substitution the boot
relied on, each announcing itself — so a run is self-describing rather than something to take on
faith. The verification discipline is in [`../METHODOLOGY.md`](../METHODOLOGY.md) §2.

**What are the "62 patches"? Isn't a patched kernel a fake kernel?**
The patches don't change the kernel's logic; they supply the values the missing boot chain would
have provided, so the kernel's *unmodified* code runs. 62 is the baseline — the remainder that
stands in for parts of the console QEMU cannot be, such as a secure processor and its keys. Each is
listed and reversible in the [synthetic register](synthetic-register.md).

**What do I need to run it?**
An AMD x86-64 host with nested virtualization, QEMU 8.2.2 built with the device models, the usual
build tools, and your own kernel image. Full list and steps: [reproducing.md](reproducing.md).

**What about vulnerabilities — did you find any?**
Reaching device configuration exercises the kernel's device and driver code under a debugger, which
is the research purpose. Anything found is reported privately to the vendor through coordinated
disclosure and is deliberately not part of this release. This repository names no flaw and includes
no proof-of-concept.

**Is this legal?**
It is security research and interoperability analysis on firmware obtained for that purpose,
distributing no copyrighted code or keys and enabling no piracy. See
[provenance.md](provenance.md) for the full scope-and-legality statement. You are responsible for
obtaining any firmware you use lawfully in your own jurisdiction.

**Can I build on this?**
Yes — that's much of the point. The [methodology](../METHODOLOGY.md) is written to be reused on other
versions or other targets, and the [synthetic register](synthetic-register.md) and
[harness manifest](../harness/MANIFEST.md) tell you exactly where each stand-in lives and how to
retire it by modelling the real thing.
