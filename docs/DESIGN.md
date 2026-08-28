# TalonOS design

## The thing that is actually hard

Booting an agent is a systemd unit. That is not a project.

The reason an *operating system* is the right shape is that Talon breaks the
assumptions a normal appliance image is built on:

- **It writes its own code.** Scripts, skills, plugins, MCP servers with their own
  Python venvs and `node_modules`. The set of executables on the box at week four is
  not the set that was in the image.
- **It holds long-lived secrets.** Bot tokens, API keys, OAuth cookies, TOTP seeds,
  device keys. These cannot live in the Nix store, which is world-readable.
- **It is a network peer, not a service.** Mesh bridge, tailnet, companion devices,
  cert pinning. Identity has to be established at first boot and survive updates.
- **It is expected to be alone.** No operator is logged in. A silent hang is the worst
  failure mode, worse than a crash.

An immutable OS is designed to forbid the first of those. So the central design
decision is *where the line goes*, not whether to have one.

## The line

```
/nix/store        immutable, reproducible, rebuilt from a flake ref
/etc, /usr        generated; nothing hand-edited survives
/var/lib/talon    THE state. mutable, backed up, never rebuilt
```

Everything the agent authors lives under `/var/lib/talon` — config, database,
workspace, namespace, keys, venvs, agent-written tools. That directory is the backup
unit and the migration unit. Wipe the disk, flash a new image, restore that one path,
and the machine is itself again.

What we explicitly do **not** do: try to make agent-authored tools reproducible. They
are data, not build inputs. Pretending otherwise would either cripple the agent or
produce a flake that lies.

What this buys: the failure mode of "the agent broke its own environment" is a reboot
into the previous generation, and the failure mode of "the disk died" is a re-flash
plus a restore.

## Updates

Three things update on different clocks, and conflating them is how appliances die:

| Layer | Cadence | Mechanism | Rollback |
|---|---|---|---|
| OS (kernel, systemd, base) | slow | new generation | reboot to previous |
| Talon itself | fast, upstream releases | new generation (pinned binary) | reboot to previous |
| Agent-authored tools | continuous, by the agent | none — it is state | restore from backup |

Because Talon is a pinned release binary in the store, upgrading the agent *is* an OS
generation. That is the whole argument for this design: a bad agent release becomes a
reboot, not an incident.

## Provisioning

First boot has no tokens, no tailnet and no operator. The intended flow:

1. Image boots, generates a device keypair into `/var/lib/talon`.
2. A one-shot unit prints a short pairing code to console and, if a network is up,
   registers with the mesh bridge named in the image.
3. The operator approves it from an existing Talon (`list_devices` → approve).
4. Secrets arrive over that channel into `/var/lib/talon/secrets`, never into an image.

No default password, no baked-in token, no "remember to change this". Not built yet;
tracked as milestone v0.3 in [ROADMAP.md](../ROADMAP.md).

## Hardening, honestly

The agent runs arbitrary tools by design. Sandboxing it *from itself* is theatre.
What the unit in `modules/talonos.nix` actually achieves:

- it is not root, and cannot become root (`NoNewPrivileges`);
- it can only write one directory (`ProtectSystem=strict` + `ReadWritePaths`);
- it cannot touch kernel tunables, modules, the clock or cgroups;
- secrets enter via `EnvironmentFile` from outside the store.

What it does not achieve: preventing the agent from doing anything harmful *within*
its own state and network reach. That is a policy problem, not a systemd one.

## Non-goals

- A desktop, a GUI installer, or a general-purpose distro.
- Running anything other than Talon and its dependencies.
- Forking Talon. Agent behaviour is upstream's; boot, image and update are ours.
- Multi-tenant. One machine, one agent, one owner.
