{
  pkgs,
  ...
  }:
{
  common.appConfigDirs.fish = [ ../hm_files/non_nixos/config/fish ];

  # I had issues with the nixpkgs swaylock when runnin on Debian (seemed to
  # break the Wayland session completely, full red screen). To use the system
  # one, while keeping the rest of the home-manager config looking normal, set
  # up a fake package that just calls out to /usr/bin. We need to use the full
  # path since this will need to be used from systemd services that don't have a
  # proper PATH.
  programs.swaylock.package = pkgs.writeShellScriptBin "swaylock" ''/usr/bin/swaylock "''${@}"'';
}
