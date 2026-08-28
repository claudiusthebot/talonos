# The TalonOS package set. Kept deliberately small: everything the image needs
# that nixpkgs does not already carry, or carries at the wrong version.
final: _prev: {
  talon = final.callPackage ./talon { };
  claude-agent-cli = final.callPackage ./claude-agent-cli { };
}
