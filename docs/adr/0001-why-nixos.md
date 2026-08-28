# ADR-0001 — Build TalonOS on NixOS

**Status:** accepted (2026-08-28) · supersedes nothing

## Context

TalonOS needs, in priority order: atomic updates with real rollback, reproducible
images for x86_64 and aarch64, a declarative description of the whole machine, and a
glibc userland (the Claude and Codex CLIs ship glibc binaries; Talon itself is a bun
`--compile` executable).

Four candidates were considered.

## Options

**Buildroot / Yocto.** Smallest images, total control, the traditional appliance
answer. But we would hand-write rollback, and every dependency the agent shells out to
(Python, ffmpeg, a headless browser) becomes a recipe we maintain. Optimises image
size, which is not a constraint we have.

**mkosi + systemd-sysupdate (UKI, dm-verity, A/B).** The modern purpose-built answer,
and architecturally the closest to "appliance" done properly. Gives verity-sealed roots
and real A/B. Costs: we assemble the update server, the partition scheme and the
rollback logic ourselves, and reproducibility depends on an upstream Debian/Fedora
snapshot rather than a lock file.

**Alpine + a build script.** Simple and tiny, and wrong: musl. The vendor CLI binaries
are glibc-linked, so this trades a week of debugging loader errors for a smaller image.
Rejected on that alone.

**NixOS.** Generations give atomic switch and rollback for free. `nixos-generators`
gives qcow2, ISO and Pi SD images from one config. The flake lock makes "the same image
everywhere" true rather than aspirational. Packaging the agent is a fetch-and-patchelf
derivation because upstream already ships a self-contained binary — so the image needs
no Node, npm or bun at all.

## Decision

NixOS.

The deciding property is that **upgrading the agent becomes an OS generation**. A bad
Talon release is then a reboot rather than an incident, which is the single behaviour
that makes an unattended box in a cupboard viable.

## Consequences

Accepted costs:

- Nix is a real learning curve, and this project inherits it.
- Images are large (a few GB) next to a buildroot rootfs. We do not care yet; if we
  ever do, the answer is image slimming, not a different base.
- No dm-verity sealing today. NixOS gives immutability by convention, not by
  cryptographic enforcement. Revisit if TalonOS is ever deployed somewhere physically
  untrusted — that would be an ADR of its own, not a patch.
- We depend on `nixos-generators` for image formats.

What would overturn this: needing verity-sealed A/B updates over the air, or images
small enough for a device where a few GB is not available. Either would point back at
mkosi. Neither is true now.
