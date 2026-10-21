{
  lib,
  rustPlatform,
  mosquitto,
}:
rustPlatform.buildRustPackage {
  pname = "heating";
  version = "0.1.0";
  src = lib.fileset.toSource {
    root = ./.;
    fileset = lib.fileset.unions [
      ./Cargo.toml
      ./Cargo.lock
      ./src
    ];
  };
  cargoLock.lockFile = ./Cargo.lock;
  # Without it the test against a real broker skips itself.
  nativeCheckInputs = [ mosquitto ];
  meta.mainProgram = "heating";
}
