# Roadmap

Long-term project, single maintainer, no deadline pressure. Milestones are ordered by
dependency, not by date. Each one ends with something that can be demonstrated, not
something that can be described.

## v0.1 — it builds ✅

- [x] Flake with package, module and image targets
- [x] `pkgs.talon` from the upstream release binary
- [x] `services.talonos` hardened unit
- [x] Appliance profile (headless, key-only ssh, zram, journal caps)
- [x] CI green on `nix flake check --all-systems`
- [x] `nix build .#talon` verified to produce a binary that runs

**Done** — [run 33169325570](https://github.com/claudiusthebot/talonos/actions/runs/33169325570):
flake evaluates on x86_64 and aarch64, and `./result/bin/talon --version` prints
`3.28.0` on a clean runner. Building is not the claim; executing is.

## v0.2 — it boots  ← we are here

- [x] qcow2 image builds in CI — 2.2 GB, 13m13s ([run 33169590715](https://github.com/claudiusthebot/talonos/actions/runs/33169590715))
- [x] Boots under QEMU and reaches `multi-user.target` — 16.42 s ([run 33170679056](https://github.com/claudiusthebot/talonos/actions/runs/33170679056))
- [x] Console log committed to [`docs/boot-logs/`](docs/boot-logs/2026-08-28-first-boot.md) as evidence
- [x] Boot test guards against the first-run wizard blocking a headless boot
- [x] `talon run` starts the real daemon (seeds prompts, initialises the DB, brings up the frontend)
- [x] The backend CLI ships in the image and is declared to Talon as `claudeBinary`
- [x] The agent stays up: model discovery passes, zero restarts, FUSE namespace
      mounted, action gateway on :19876, native bridge serving on :19880
- [ ] Pi 5 SD image boots on actual hardware
- [ ] A client connects to the bridge and gets an answer

**Done when:** a booted VM answers a message. Not before — everything above is
the machine being ready to, which is not the same claim.

## v0.3 — it provisions

- [ ] First-boot device keypair + pairing code on console
- [ ] Mesh registration against an existing Talon, operator-approved
- [ ] Secrets delivered post-boot; nothing sensitive in any image
- [ ] `talonos-installer` splits into its own repo at this point

**Done when:** a flashed SD card joins the mesh without anyone editing a file on it.

## v0.4 — it updates

- [ ] Pinned upstream Talon release, bumped by a bot PR with hash verification
- [ ] `talonos-update` unit: fetch generation, switch, health-check, auto-rollback
- [ ] Documented recovery: what to do when the new generation cannot reach the network

**Done when:** a deliberately broken release rolls itself back unattended.

## v0.5 — it survives

- [ ] State backup/restore of `/var/lib/talon` to a remote target
- [ ] Restore onto a blank machine reproduces the agent's identity and memory
- [ ] Health telemetry: watchdog, disk floor, agent-alive check

**Done when:** a wiped machine is restored to a working agent from backup alone.

## v1.0 — someone else can use it

- [ ] Published images with checksums
- [ ] Install docs that assume no Nix knowledge
- [ ] `talonos.dev` (its own repo)
- [ ] Tested on: VPS, Pi 5, an old laptop

## Deliberately not doing

- A GUI or installer wizard
- Multi-agent or multi-tenant hosting
- Forking Talon
- Optimising image size before anything has booted
