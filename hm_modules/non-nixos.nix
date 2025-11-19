{
  pkgs,
  nixpkgs, # from specialArgs
  ...
}:
let
  # I had issues with various Wayland apps when running on Debian (some just don't
  # do anything, swaylock seemed to break the Wayland session completely, full red
  # screen). To use the system version of these apps, while keeping the rest of
  # the home-manager config looking normal, set up a fake package that just calls
  # out to /usr/bin. We need to use the full path since this will need to be used
  # from systemd services that don't have a proper PATH. The home-manage swayidle
  # setup is hard-coded to assume the package contains a bin/ directory (it uses
  # lib.getExe) hence writeShellScriptBin here.
  mkUsrBinPkg = name: pkgs.writeShellScriptBin name ''/usr/bin/${name} "''${@}"'';
  # Alternatively, nixGL seems to allow running graphical packages just fine.
  # This configuration doesnt' take care of installing nixGL since IIUC that
  # would make the whole config need --impure. Instead, just assume that it has
  # been installed to the profile separately with `nix profile install
  # github:guibou/nixGL --impure` so that the impurity is "contained".
  # This might work fine for all the tools currently using mkUsrBinPkg, I just
  # haven't bothered to try it.
  mkNixGLPkg = bin: pkgs.writeShellScriptBin (builtins.baseNameOf bin) ''nixGL ${bin} "''${@}"'';
in
{
  bjackman.appConfigDirs.fish = [ ../hm_files/non_nixos/config/fish ];

  programs.swaylock.package = mkUsrBinPkg "swaylock";
  services.swayidle.package = mkUsrBinPkg "swayidle";
  programs.kitty.package = mkUsrBinPkg "kitty";
  programs.wezterm.package = mkNixGLPkg "${pkgs.wezterm}/bin/wezterm";

  # Set up the flake registry for nixpkgs to point to the version used by this
  # configuration, which means you can do `nix run nixpkgs#foo` and not have to
  # download the latest unstable nixpkgs.
  # IIRC this happens automatically at the system level on NixOS, I need to
  # figure out how that works to see if there's a way to avoid the nixpkgs
  # special arg here.
  nix.registry.nixpkgs.flake = nixpkgs;
}
