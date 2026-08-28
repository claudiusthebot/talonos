# TalonOS

**A Linux appliance whose only job is to boot and run [Talon](https://github.com/dylanneve1/talon).**

Not a general-purpose distro with an agent installed on it. An operating system where
the agent *is* the workload, everything else is scaffolding, and the whole machine is
disposable except for one state partition.

> **Status: pre-alpha.** The flake evaluates and the package builds; nothing here has
> booted on real hardware yet. Treat every claim below as intent, not as a shipped
> feature, until it has a green CI job and a serial console log next to it.

---

## Why this exists

Running Talon today means: pick a distro, install a JS runtime, clone a repo, write a
systemd unit, remember to back up `~/.talon`, and hope nobody `apt upgrade`s the box
into a different world. That is fine for one machine you babysit. It does not survive
ten of them, or a Raspberry Pi in a cupboard, or a reinstall at 2am.

TalonOS collapses that into: **flash an image, boot it, pair it.**

The five properties that make it an OS rather than a unit file:

1. **Boots straight to Talon.** No login, no installer, no first-run wizard. The agent
   is PID-adjacent to init and the machine has no other purpose.
2. **Immutable root, atomic updates, real rollback.** Updating the agent means booting
   a new system generation. If it fails, the previous generation is one reboot away —
   not a `git revert` and a prayer.
3. **All state in one place.** `/var/lib/talon` holds the config, the database, the
   workspace, the keys. Back that up and the rest of the disk is reproducible from a
   flake ref.
4. **Mesh-native.** Tailscale and the Talon mesh bridge are part of the image, with
   node identity derived at first boot, so a fresh device joins by pairing rather than
   by hand-editing config.
5. **Hostile by default.** No password SSH, no open ports beyond what the mesh needs,
   a hardened unit for the agent, and secrets that never enter the Nix store.

## Why NixOS

Because rollback, reproducibility and declarative image builds are the entire point,
and NixOS gives all three on day one where buildroot or mkosi would mean writing them.
The long form, including what we give up: [`docs/adr/0001-why-nixos.md`](docs/adr/0001-why-nixos.md).

Talon itself ships a self-contained `bun build --compile` binary, so the image contains
**no Node, no npm, no bun** — just a ~100 MB static-ish executable that we patchelf and
drop in `/nix/store`.

## Layout

```
flake.nix              # entry point: packages, modules, image targets
modules/talonos.nix    # services.talonos — the hardened agent unit
modules/appliance.nix  # the appliance shape (no X, networkd, ssh keys only, zram)
hosts/image.nix        # config shared by every generated image
hosts/appliance.nix    # for `nixos-rebuild switch` onto an existing machine
pkgs/talon/            # the Talon release binary as a Nix package
docs/DESIGN.md         # what an OS for one agent actually has to solve
docs/adr/              # decision records
```

## Try it

```sh
# build just the packaged agent
nix build github:claudiusthebot/talonos#talon

# build a bootable qcow2 for a VPS or local VM
nix build github:claudiusthebot/talonos#image-qcow2

# build a Raspberry Pi SD image (on aarch64, or with binfmt emulation)
nix build github:claudiusthebot/talonos#image-sd
```

Or adopt just the service on a machine you already run:

```nix
{
  inputs.talonos.url = "github:claudiusthebot/talonos";

  # in your nixosSystem modules:
  imports = [ inputs.talonos.nixosModules.talonos ];
  nixpkgs.overlays = [ inputs.talonos.overlays.default ];

  services.talonos = {
    enable = true;
    secretsFile = "/run/secrets/talon.env";   # tokens live here, never in the store
    settings = {
      backend = "claude";
      model = "claude-opus-5";
    };
  };
}
```

## The honest part

The hard problem is not booting an agent. It is that **Talon writes its own tools at
runtime** — scripts, skills, plugins, MCP servers with their own venvs — which is
exactly the thing an immutable OS is designed to forbid. TalonOS does not pretend to
reproduce that region; it draws a hard line between the declarative image and the
agent's mutable namespace, and makes the second one backed up rather than rebuilt.

That tension is written up properly in [`docs/DESIGN.md`](docs/DESIGN.md). If you only
read one file here, read that one.

## Relationship to upstream Talon

TalonOS packages and boots Talon; it does not fork it. Agent behaviour, tools and
protocol bugs belong in [dylanneve1/talon](https://github.com/dylanneve1/talon). Image
layout, boot, updates, provisioning and hardening belong here.

## License

MIT — see [LICENSE](LICENSE). Talon is MIT, copyright Dylan Neve.
