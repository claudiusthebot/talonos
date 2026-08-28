# The appliance shape: what makes this an OS for one workload rather than a
# general-purpose machine that happens to run an agent.
#
# Deliberately does NOT set a bootloader or filesystems — those belong to the
# host/format, and setting them here breaks SD and qcow generation.
{
  config,
  lib,
  pkgs,
  ...
}:

{
  # No desktop, no docs, no printing. Every megabyte in the image is something
  # that can rot or be attacked.
  #
  # There is no `sound.enable = false` here: the option was removed in NixOS
  # 25.05 and setting it is now a hard assertion failure. Nothing pulls in ALSA
  # userspace on a headless image, so there is nothing to turn off.
  documentation.enable = lib.mkDefault false;
  documentation.nixos.enable = lib.mkDefault false;
  services.xserver.enable = lib.mkDefault false;
  fonts.fontconfig.enable = lib.mkDefault false;
  programs.command-not-found.enable = lib.mkDefault false;

  # Headless, key-only, no root login. The tailnet is the front door.
  services.openssh = {
    enable = lib.mkDefault true;
    settings = {
      PasswordAuthentication = lib.mkDefault false;
      KbdInteractiveAuthentication = lib.mkDefault false;
      PermitRootLogin = lib.mkDefault "no";
    };
  };

  services.tailscale.enable = lib.mkDefault true;

  networking = {
    useNetworkd = lib.mkDefault true;
    firewall.enable = lib.mkDefault true;
    networkmanager.enable = lib.mkDefault false;
  };

  services.timesyncd.enable = lib.mkDefault true;
  time.timeZone = lib.mkDefault "UTC";

  # Small boxes: a Pi with 1 GB and a browser-driving agent needs this.
  zramSwap.enable = lib.mkDefault true;

  # Keep enough journal to debug a crash loop, not enough to fill the disk —
  # the recurring failure mode on the machines this replaces.
  services.journald.extraConfig = lib.mkDefault ''
    SystemMaxUse=256M
    MaxRetentionSec=2week
  '';

  # A watchdog matters when nobody is logged in to notice.
  systemd.watchdog = {
    runtimeTime = lib.mkDefault "30s";
    rebootTime = lib.mkDefault "5m";
  };

  boot.tmp.cleanOnBoot = lib.mkDefault true;
  security.sudo.wheelNeedsPassword = lib.mkDefault true;

  nix.settings = {
    experimental-features = [
      "nix-command"
      "flakes"
    ];
    auto-optimise-store = lib.mkDefault true;
  };

  # Garbage: an appliance that fills its own disk is an outage.
  nix.gc = {
    automatic = lib.mkDefault true;
    dates = lib.mkDefault "weekly";
    options = lib.mkDefault "--delete-older-than 30d";
  };

  environment.systemPackages = with pkgs; [
    curl
    git
    htop
    jq
    tmux
  ];

  services.talonos.enable = lib.mkDefault true;

  system.nixos.distroName = lib.mkDefault "TalonOS";
  system.nixos.tags = [ "talonos" ];
}
