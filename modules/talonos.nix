# services.talonos — run the Talon agent as a hardened system service.
#
# Usable on its own (import this module into any NixOS config), but it expects
# `pkgs.talon` to exist: either add the flake's overlay, or set
# `services.talonos.package` explicitly.
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.talonos;

  # The declarative half of ~/.talon/config.json. Anything not named here is
  # left alone at runtime, which matters because the agent edits its own config.
  # The backend binary is part of the image, so the image is what tells Talon
  # where it is. Explicit `settings` still win — this is a default, not a lock.
  effectiveSettings =
    (lib.optionalAttrs (cfg.claudePackage != null) {
      claudeBinary = lib.getExe cfg.claudePackage;
    })
    // cfg.settings;

  declaredConfig = pkgs.writeText "talon-config.json" (builtins.toJSON effectiveSettings);

  talonHome = "${cfg.stateDir}/.talon";
in
{
  options.services.talonos = {
    enable = lib.mkEnableOption "the Talon agent daemon";

    package = lib.mkPackageOption pkgs "talon" { };

    user = lib.mkOption {
      type = lib.types.str;
      default = "talon";
      description = "User the agent runs as. Never root: the agent executes arbitrary tools.";
    };

    group = lib.mkOption {
      type = lib.types.str;
      default = "talon";
      description = "Group the agent runs as.";
    };

    stateDir = lib.mkOption {
      type = lib.types.path;
      default = "/var/lib/talon";
      description = ''
        The one directory that is not reproducible. Holds config.json, talon.db,
        the workspace, keys and agent-authored tools. This is the backup unit —
        everything else in the image can be rebuilt from a flake ref.
      '';
    };

    settings = lib.mkOption {
      type = lib.types.attrsOf lib.types.anything;
      default = { };
      example = {
        backend = "claude";
        model = "claude-opus-5";
      };
      description = ''
        Config keys asserted by the image. Merged over the on-disk config on every
        start, so declared keys win and undeclared runtime state survives.
        Do not put secrets here — the Nix store is world-readable. Use `secretsFile`.
      '';
    };

    secretsFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      example = "/run/secrets/talon.env";
      description = ''
        systemd EnvironmentFile holding API keys and bot tokens. Read at start from
        outside the store, so secrets never enter a world-readable path or an image.
      '';
    };

    extraArgs = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Extra arguments appended to `talon run`.";
    };

    claudePackage = lib.mkOption {
      type = lib.types.nullOr lib.types.package;
      default = pkgs.claude-agent-cli or null;
      defaultText = lib.literalExpression "pkgs.claude-agent-cli";
      description = ''
        The Claude Code CLI the agent shells out to, placed on PATH and written
        into config as `claudeBinary`.

        This is not optional decoration: Talon's compiled binary does not embed
        the agent SDK's native CLI, so without it the daemon starts, fails model
        discovery and exits into a restart loop. An OS for running Talon has to
        ship the backend.

        It must also be the CLI generation that matches the agent SDK compiled
        into the pinned Talon release: nixpkgs' independently-versioned
        `claude-code` fails model discovery with
        `unknown option '--allow-dangerously-skip-permissions'`. See
        pkgs/claude-agent-cli.

        Set to null to manage the backend yourself. The CLI is unfree, so a
        configuration that keeps this default must permit it by name.
      '';
    };

    extraPackages = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      default = [ ];
      example = lib.literalExpression "[ pkgs.ffmpeg-headless pkgs.python3 ]";
      description = ''
        Packages placed on the agent's PATH. Backends (the claude/codex CLIs) and
        anything the agent's own tools shell out to belong here, so that the set of
        binaries the agent can reach is declared rather than discovered.
      '';
    };

    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Open the mesh bridge port. Off by default: prefer reaching it over the tailnet.";
    };

    bridgePort = lib.mkOption {
      type = lib.types.port;
      default = 19880;
      description = "Port the mesh bridge listens on.";
    };
  };

  config = lib.mkIf cfg.enable {
    users.users.${cfg.user} = {
      isSystemUser = true;
      inherit (cfg) group;
      home = cfg.stateDir;
      createHome = true;
      description = "Talon agent";
    };

    users.groups.${cfg.group} = { };

    networking.firewall.allowedTCPPorts = lib.mkIf cfg.openFirewall [ cfg.bridgePort ];

    systemd.services.talon = {
      description = "Talon agent";
      documentation = [ "https://github.com/dylanneve1/talon" ];
      wantedBy = [ "multi-user.target" ];
      wants = [ "network-online.target" ];
      after = [
        "network-online.target"
        "time-sync.target"
      ];

      path = cfg.extraPackages ++ lib.optional (cfg.claudePackage != null) cfg.claudePackage ++ (with pkgs; [
        bash
        coreutils
        curl
        git
        gnutar
        gzip
        jq
        openssh
      ]);

      environment = {
        HOME = cfg.stateDir;
        TALON_HOME = talonHome;
        XDG_CACHE_HOME = "${cfg.stateDir}/.cache";
        XDG_CONFIG_HOME = "${cfg.stateDir}/.config";
      };

      # Declared keys win; everything the agent wrote for itself survives.
      preStart = ''
        install -d -m 0700 "${talonHome}"
        if [ -e "${talonHome}/config.json" ]; then
          ${lib.getExe pkgs.jq} -s '.[0] * .[1]' \
            "${talonHome}/config.json" ${declaredConfig} > "${talonHome}/config.json.new"
        else
          ${lib.getExe pkgs.jq} '.' ${declaredConfig} > "${talonHome}/config.json.new"
        fi
        mv -f "${talonHome}/config.json.new" "${talonHome}/config.json"
      '';

      serviceConfig = {
        Type = "simple";
        # `run` is attached foreground mode, which is what Type=simple wants.
        # Bare `talon` is the INTERACTIVE MENU: on a headless box with no config
        # it drops into the first-run setup wizard and blocks forever while
        # systemd cheerfully reports the unit as active. `talon start`
        # self-daemonizes and would double-fork out from under the unit.
        # Upstream documents both traps in packaging/systemd/talon-package.service.
        ExecStart = lib.escapeShellArgs ([ (lib.getExe cfg.package) "run" ] ++ cfg.extraArgs);
        User = cfg.user;
        Group = cfg.group;
        WorkingDirectory = cfg.stateDir;
        EnvironmentFile = lib.mkIf (cfg.secretsFile != null) cfg.secretsFile;

        Restart = "always";
        RestartSec = 5;

        # An agent that dies quietly is worse than one that crashes loudly.
        WatchdogSec = 0;
        TimeoutStopSec = 30;

        # Hardening. Note the ceiling: the agent's whole job is running arbitrary
        # tools, so this contains blast radius rather than preventing it.
        NoNewPrivileges = true;
        PrivateTmp = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        ProtectKernelTunables = true;
        ProtectKernelModules = true;
        ProtectControlGroups = true;
        ProtectClock = true;
        ProtectHostname = true;
        RestrictSUIDSGID = true;
        RestrictRealtime = true;
        LockPersonality = true;
        ReadWritePaths = [ cfg.stateDir ];
      };
    };

    # A machine that exists to run one process should say so at the console.
    environment.etc."issue.d/10-talonos.issue".text = ''
      TalonOS — this machine exists to run Talon.
      State: ${cfg.stateDir}   Logs: journalctl -u talon -f
    '';
  };
}
