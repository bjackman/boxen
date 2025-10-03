{
  pkgs,
  ...
}:
# I had issues with various Wayland apps when running on Debian (some just don't
# do anything, swaylock seemed to break the Wayland session completely, full red
# screen). To use the system version of these apps, while keeping the rest of
# the home-manager config looking normal, set up a fake package that just calls
# out to /usr/bin. We need to use the full path since this will need to be used
# from systemd services that don't have a proper PATH. The home-manage swayidle
# setup is hard-coded to assume the package contains a bin/ directory (it uses
# lib.getExe) hence writeShellScriptBin here.
let
  mkUsrBinPkg = name: pkgs.writeShellScriptBin name ''/usr/bin/${name} "''${@}"'';
in
{
  common.appConfigDirs.fish = [ ../hm_files/non_nixos/config/fish ];

  programs.swaylock.package = mkUsrBinPkg "swaylock";
  services.swayidle.package = mkUsrBinPkg "swayidle";
  programs.kitty.package = mkUsrBinPkg "kitty";
}
