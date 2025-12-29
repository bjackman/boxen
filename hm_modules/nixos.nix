{
  pkgs,
  config,
  osConfig,
  ...
}:
{
  imports = [
    ./dark-mode.nix
    ./nix-warmup.nix
  ];
  bjackman.appConfigDirs.fish = [ ../hm_files/nixos/config/fish ];
  bjackman.configCheckout = "${config.home.homeDirectory}/src/boxen";
  programs.firefox.enable = true;
  programs.vscode.enable = true;

  bjackman.nix-warmups = [
    "github:bjackman/boxen/master#nixosConfigurations.${osConfig.networking.hostName}.config.system.build.toplevel"
  ];
}
