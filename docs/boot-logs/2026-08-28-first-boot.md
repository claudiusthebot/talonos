# First boot — 2026-08-28

Run: [33170679056](https://github.com/claudiusthebot/talonos/actions/runs/33170679056)
Host: GitHub `ubuntu-latest`, **KVM available** (so this is real virtualisation,
not TCG emulation). Test driver: `pkgs.testers.runNixOSTest`.

## Result

Green. Boot to `multi-user.target` in **16.42 s**; whole test script 23.75 s.

```
machine: waiting for unit multi-user.target
machine: (finished: waiting for unit multi-user.target, in 16.42 seconds)
machine: must succeed: systemctl is-enabled talon.service                  (0.16s)
machine: waiting for file '/var/lib/talon/.talon/config.json'              (0.09s)
machine: must succeed: jq -e '.backend == "claude" and .model == ...'      (0.07s)
machine: must succeed: test "$(stat -c %U /var/lib/talon)" = talon         (0.07s)
machine: must succeed: test "$(systemctl show -p User ...)" = talon        (0.25s)
machine: must succeed: test "$(systemctl show -p ProtectSystem ...)" = strict
machine: must succeed: test "$(systemctl show -p NoNewPrivileges ...)" = yes
machine: must succeed: /nix/store/...-talon-3.28.0/bin/talon --version     (1.52s)
3.28.0
test script finished in 23.75s
```

So: the image boots, the unit is wired in, `preStart` materialises the
declarative config into the state dir, the hardening in the unit file is really
applied by systemd, and the patchelf'd bun binary executes inside the guest.

## What the green run was hiding

Every assertion passed and the appliance was still broken. From the same
console log:

```
systemd[1]: Starting Talon agent...
systemd[1]: Started Talon agent.
talon[815]:   🦅 Talon
talon[815]: ◇  First time? ─────────────────────────────────╮
talon[815]: │  Talon is an agentic AI harness.              │
talon[815]: │  Let's get you set up.                        │
talon[815]: ┌   Setup Wizard
talon[815]: ◆  Frontend platforms (space to toggle, enter to confirm)
talon[815]: │  ◼ Telegram  — bot via @BotFather
```

`ExecStart` was bare `talon`, which upstream defines as the **interactive
menu**. With no usable config it opened the first-run setup wizard and blocked
on a keypress that cannot arrive on a headless machine — while systemd reported
`Started` and every check in this file went green.

This is exactly the failure `docs/DESIGN.md` calls the worst one for an
unattended box: not a crash, a silent wait. A crash would have been caught by
anything; this needed the console log to be read.

Two fixes, both in the following commit:

1. `ExecStart` is now `talon run` — attached foreground mode, which is what
   `Type=simple` wants. (`talon start` self-daemonizes and would double-fork out
   from under the unit. Upstream documents both traps in
   `packaging/systemd/talon-package.service`; they were there to be read before
   this was discovered the slow way.)
2. The boot test now asserts the *discriminator*: `ExecStart` must invoke `run`,
   and the journal must never contain `Setup Wizard`.

## Lesson

An assertion about systemd's opinion of a unit is not an assertion about the
process being alive in any useful sense. Ask what the check would look like if
the thing were broken — if the answer is "identical", it is not a check.
