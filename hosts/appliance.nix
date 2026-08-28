# Turn an existing x86_64 machine into a TalonOS appliance:
#   nixos-rebuild switch --flake github:claudiusthebot/talonos#appliance
#
# Assumes a single ext4 root labelled `nixos` and a UEFI ESP labelled `BOOT`.
# Override in your own flake if that is not your layout.
{ lib, ... }:

{
  boot.loader.systemd-boot.enable = lib.mkDefault true;
  boot.loader.efi.canTouchEfiVariables = lib.mkDefault true;

  fileSystems."/" = lib.mkDefault {
    device = "/dev/disk/by-label/nixos";
    fsType = "ext4";
  };

  fileSystems."/boot" = lib.mkDefault {
    device = "/dev/disk/by-label/BOOT";
    fsType = "vfat";
  };

  # The backend CLI is unfree. Allow those packages by name; a blanket
  # allowUnfree would quietly permit anything a future dependency drags in.
  nixpkgs.config.allowUnfreePredicate =
    pkg:
    builtins.elem (lib.getName pkg) [
      "claude-agent-cli"
      "claude-code"
    ];

  networking.hostName = lib.mkDefault "talonos";
  system.stateVersion = lib.mkDefault "25.05";
}
