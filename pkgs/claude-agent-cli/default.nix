# The Claude Code CLI that Talon's compiled binary actually expects.
#
# Talon shells out to a `claude` binary through @anthropic-ai/claude-agent-sdk.
# The SDK and the CLI are a *matched pair*: the SDK invokes flags that only its
# own CLI generation understands. Substituting nixpkgs' independently-versioned
# `claude-code` package produced exactly the skew you would predict:
#
#   Fatal: model discovery failed — Claude Code process exited with code 1.
#   stderr: error: unknown option '--allow-dangerously-skip-permissions'
#
# So the version here is not a free choice. It is read off the pinned Talon
# release's package-lock.json:
#
#   talon v3.28.0 → @anthropic-ai/claude-agent-sdk 0.3.235 → claude 2.1.235
#
# Bumping Talon means bumping this in the same commit. That coupling is the
# whole reason an appliance image is a better unit than "install Talon on a box"
# — the pair moves together or not at all.
{
  lib,
  stdenv,
  stdenvNoCC,
  fetchurl,
  autoPatchelfHook,
}:

let
  version = "0.3.235";

  tarball =
    arch: hash:
    fetchurl {
      url = "https://registry.npmjs.org/@anthropic-ai/claude-agent-sdk-linux-${arch}/-/claude-agent-sdk-linux-${arch}-${version}.tgz";
      inherit hash;
    };

  sources = {
    x86_64-linux = tarball "x64" "sha256-0y03V5HHcoxGZLTS5kXI1aED0SiXE2f3TMxg1NCEPS4=";
    aarch64-linux = tarball "arm64" "sha256-NX3iWUkaX/77K4W6BiYhhqilHhJedbdimguTUIC3WoY=";
  };
in
stdenvNoCC.mkDerivation {
  pname = "claude-agent-cli";
  inherit version;

  src =
    sources.${stdenvNoCC.hostPlatform.system}
      or (throw "claude-agent-cli: no CLI for ${stdenvNoCC.hostPlatform.system}");

  sourceRoot = "package";

  # Another bun single-file executable with an appended payload. Stripping it
  # produces a binary that starts and then cannot find itself.
  dontStrip = true;

  nativeBuildInputs = [ autoPatchelfHook ];
  buildInputs = [ stdenv.cc.cc.lib ];

  installPhase = ''
    runHook preInstall
    install -Dm755 claude "$out/bin/claude"
    runHook postInstall
  '';

  meta = {
    description = "Claude Code CLI matching the agent SDK compiled into a pinned Talon release";
    homepage = "https://github.com/anthropics/claude-code";
    license = lib.licenses.unfree;
    mainProgram = "claude";
    platforms = builtins.attrNames sources;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };
}
