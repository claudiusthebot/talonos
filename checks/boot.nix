# Does it boot?
#
# `nix build .#image-qcow2` succeeding proves a disk image can be assembled. It
# proves nothing about whether the result reaches userspace, whether the unit is
# wired in, or whether the binary we patchelf'd runs anywhere except a build
# runner. This boots the actual appliance config under QEMU and checks.
#
# The first version of this test passed while the appliance was broken: every
# assertion was about systemd's opinion of the unit, and systemd's opinion was
# "active" while the process sat in an interactive setup wizard waiting for a
# keypress that could never arrive. See docs/boot-logs/2026-08-28-first-boot.md.
# The assertions below are chosen to fail if that happens again.
#
# Still NOT asserted: that the agent reaches a backend. That needs credentials,
# and a test that demanded them would be a test of the CI secret store.
{ pkgs, self }:

pkgs.testers.runNixOSTest {
  name = "talonos-boot";

  nodes.machine =
    { lib, ... }:
    {
      imports = [
        self.nixosModules.talonos
        self.nixosModules.appliance
      ];

      # pkgs already carries the TalonOS overlay, and the test framework pins
      # nixpkgs.pkgs for its nodes, so the package is passed rather than
      # re-overlaid.
      services.talonos.package = pkgs.talon;

      # `native` is the client-bridge frontend: upstream's isConfigured() treats
      # it as configured with no credential at all, so this exercises a real
      # daemon start without a secret anywhere near CI.
      services.talonos.settings = {
        frontend = "native";
        backend = "claude";
        model = "claude-opus-5";
      };

      # QEMU has no hardware watchdog; leaving this set only adds a way for a
      # slow test host to reboot itself mid-run.
      systemd.watchdog.runtimeTime = lib.mkForce null;

      virtualisation.memorySize = 2048;
      virtualisation.diskSize = 8192;

      system.stateVersion = "25.05";
    };

  testScript = ''
    machine.start()
    machine.wait_for_unit("multi-user.target")

    # Wired into boot, not merely present on disk.
    machine.succeed("systemctl is-enabled talon.service")

    # preStart materialised the declarative config into the state dir, and the
    # keys the image declares are the keys that ended up there.
    machine.wait_for_file("/var/lib/talon/.talon/config.json")
    machine.succeed(
        "jq -e '.frontend == \"native\" and .backend == \"claude\"' "
        "/var/lib/talon/.talon/config.json"
    )

    # The state dir belongs to the agent, and the agent is not root.
    machine.succeed('test "$(stat -c %U /var/lib/talon)" = talon')
    machine.succeed('test "$(systemctl show -p User --value talon.service)" = talon')

    # Hardening actually applied, rather than being written down in a unit file.
    machine.succeed(
        'test "$(systemctl show -p ProtectSystem --value talon.service)" = strict'
    )
    machine.succeed(
        'test "$(systemctl show -p NoNewPrivileges --value talon.service)" = yes'
    )

    # THE regression guard: the unit must invoke the attached daemon, never the
    # interactive menu.
    machine.succeed(
        "systemctl show -p ExecStart --value talon.service | grep -qw run"
    )

    # And it must never reach the first-run wizard on a machine with no console.
    machine.sleep(15)
    print(machine.succeed("journalctl -u talon.service --no-pager | tail -n 40"))
    machine.fail('journalctl -u talon.service --no-pager | grep -q "Setup Wizard"')

    # The backend CLI ships with the image, so this specific fatal must be gone.
    # Not asserted: that the agent authenticates. That needs a credential, and a
    # test that needed one would be testing the CI secret store again.
    machine.fail(
        'journalctl -u talon.service --no-pager | grep -q "Native CLI binary"'
    )
    # And the path written into config actually points at an executable, rather
    # than at a store path that was never realised.
    machine.succeed(
        'test -x "$(jq -r .claudeBinary /var/lib/talon/.talon/config.json)"'
    )

    # The packaged binary runs inside the booted image, not just on a builder.
    print(machine.succeed("${pkgs.lib.getExe pkgs.talon} --version"))

    machine.shutdown()
  '';
}
