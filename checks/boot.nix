# Does it boot?
#
# `nix build .#image-qcow2` succeeding proves a disk image can be assembled. It
# proves nothing about whether the result reaches userspace, whether the unit is
# wired in, or whether the binary we patchelf'd runs anywhere except a build
# runner. This boots the actual appliance config under QEMU and checks.
#
# Note what is NOT asserted: that talon.service is *active*. With no credentials
# the daemon exits and systemd restarts it. A test that demanded `active` would
# pass only when CI held a working token, which makes it a test of the secret
# store rather than of the OS. Assert what is true.
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

      services.talonos.settings = {
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
        "jq -e '.backend == \"claude\" and .model == \"claude-opus-5\"' "
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

    # The packaged binary runs inside the booted image, not just on a builder.
    print(machine.succeed("${pkgs.lib.getExe pkgs.talon} --version"))

    machine.shutdown()
  '';
}
