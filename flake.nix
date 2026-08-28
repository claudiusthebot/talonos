{
  description = "TalonOS — a minimal, immutable Linux appliance whose only job is to run Talon";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";
    nixos-generators = {
      url = "github:nix-community/nixos-generators";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      nixos-generators,
      ...
    }:
    let
      inherit (nixpkgs) lib;

      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];

      forAllSystems = f: lib.genAttrs systems f;

      # claude-code is unfree. Allow exactly it rather than opening the gate:
      # an appliance that needs one proprietary binary should say which one.
      allowClaudeCode = pkg: builtins.elem (lib.getName pkg) [ "claude-code" ];

      pkgsFor =
        system:
        import nixpkgs {
          inherit system;
          overlays = [ self.overlays.default ];
          config.allowUnfreePredicate = allowClaudeCode;
        };

      # Every TalonOS artifact — image or rebuilt machine — is these three things
      # plus a host-specific tail.
      baseModules = [
        self.nixosModules.talonos
        self.nixosModules.appliance
        { nixpkgs.overlays = [ self.overlays.default ]; }
      ];

      image =
        {
          system,
          format,
          modules ? [ ],
        }:
        nixos-generators.nixosGenerate {
          inherit system format;
          modules = baseModules ++ [ ./hosts/image.nix ] ++ modules;
        };
    in
    {
      overlays.default = import ./pkgs/overlay.nix;

      nixosModules = {
        talonos = import ./modules/talonos.nix;
        appliance = import ./modules/appliance.nix;
        default = self.nixosModules.talonos;
      };

      packages = forAllSystems (
        system:
        let
          pkgs = pkgsFor system;
        in
        {
          talon = pkgs.talon;
          default = pkgs.talon;
        }
        // lib.optionalAttrs (system == "x86_64-linux") {
          image-qcow2 = image {
            inherit system;
            format = "qcow";
          };
          image-iso = image {
            inherit system;
            format = "install-iso";
          };
        }
        // lib.optionalAttrs (system == "aarch64-linux") {
          image-sd = image {
            inherit system;
            format = "sd-aarch64";
          };
        }
      );

      # x86_64 only: a VM test cannot be built on a machine that cannot run the
      # guest, and pretending otherwise just breaks `nix flake check` elsewhere.
      checks = forAllSystems (
        system:
        lib.optionalAttrs (system == "x86_64-linux") {
          boot = import ./checks/boot.nix {
            pkgs = pkgsFor system;
            inherit self;
          };
        }
      );

      # For people who want the appliance shape on a machine they already own:
      #   nixos-rebuild switch --flake github:claudiusthebot/talonos#appliance
      nixosConfigurations.appliance = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = baseModules ++ [ ./hosts/appliance.nix ];
      };

      devShells = forAllSystems (
        system:
        let
          pkgs = pkgsFor system;
        in
        {
          default = pkgs.mkShellNoCC {
            packages = with pkgs; [
              nixfmt-rfc-style
              statix
              deadnix
            ];
          };
        }
      );

      formatter = forAllSystems (system: (pkgsFor system).nixfmt-rfc-style);
    };
}
