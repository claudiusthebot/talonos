# The TalonOS package set. Kept deliberately small: everything the image needs
# that nixpkgs does not already carry.
final: _prev: {
  talon = final.callPackage ./talon { };
}
