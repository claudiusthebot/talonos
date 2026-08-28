# Talon is distributed as a self-contained `bun build --compile` binary, so this
# is a fetch-and-patchelf derivation rather than a JS build. That is a deliberate
# trade: we give up building from source (and the audit trail that comes with it)
# in exchange for an image with no Node, no npm and no bun in it at all.
#
# Hashes below are the ones published in the release's SHA256SUMS, re-encoded as
# SRI. To bump: change `version`, then re-encode both digests from the new
# SHA256SUMS (`nix hash convert --hash-algo sha256 --to sri <hex>`).
{
  lib,
  stdenv,
  stdenvNoCC,
  fetchurl,
  autoPatchelfHook,
}:

let
  version = "3.28.0";

  sources = {
    x86_64-linux = fetchurl {
      url = "https://github.com/dylanneve1/talon/releases/download/v${version}/talon-linux-x64";
      hash = "sha256-G6xLB5SdNUOhqQoruh5SQ5a3Z0bkasz/JAXYkXm25ss=";
    };
    aarch64-linux = fetchurl {
      url = "https://github.com/dylanneve1/talon/releases/download/v${version}/talon-linux-arm64";
      hash = "sha256-PE7u+JjtSeEWNt8kC+zP4+hx04U9Cymh7pzuZ1Xcm7U=";
    };
  };
in
stdenvNoCC.mkDerivation {
  pname = "talon";
  inherit version;

  src =
    sources.${stdenvNoCC.hostPlatform.system}
      or (throw "talon: no release binary for ${stdenvNoCC.hostPlatform.system}");

  dontUnpack = true;

  # A bun single-file executable carries its own payload appended to the ELF.
  # Stripping it is how you get a binary that runs and then explodes at import.
  dontStrip = true;

  nativeBuildInputs = [ autoPatchelfHook ];
  buildInputs = [ stdenv.cc.cc.lib ];

  installPhase = ''
    runHook preInstall
    install -Dm755 "$src" "$out/bin/talon"
    runHook postInstall
  '';

  meta = {
    description = "Multi-frontend AI agent with tool access, cron jobs, triggers and plugins";
    homepage = "https://github.com/dylanneve1/talon";
    license = lib.licenses.mit;
    mainProgram = "talon";
    platforms = builtins.attrNames sources;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };
}
