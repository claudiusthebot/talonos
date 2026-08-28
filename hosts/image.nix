# Config shared by every generated image (qcow2 / ISO / SD).
# The bootloader and filesystem layout come from the nixos-generators format,
# so nothing here may touch them.
{ lib, ... }:

{
  networking.hostName = lib.mkDefault "talonos";

  # First boot has no keys and no tailnet. Ship a console-visible pairing path
  # rather than a default password — see docs/DESIGN.md §Provisioning.
  users.users.root.initialHashedPassword = lib.mkDefault "!";

  system.stateVersion = lib.mkDefault "25.05";
}
