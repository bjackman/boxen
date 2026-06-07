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
  # Keeps the pre-26.05 path to avoid migrating profile data on each machine.
  # To adopt the XDG default instead:
  #   1. Set programs.firefox.configPath = "${config.xdg.configHome}/mozilla/firefox";
  #   2. On each machine: mv ~/.mozilla/firefox "$XDG_CONFIG_HOME/mozilla/firefox"
  #   3. Update the impermanence directory in nixos_modules/pc.nix from
  #      ".mozilla/firefox" to ".config/mozilla/firefox" (or whatever $XDG_CONFIG_HOME resolves to).
  programs.firefox.configPath = ".mozilla/firefox";
  programs.vscode.enable = true;

  bjackman.nix-warmups = [
    "github:bjackman/boxen/master#nixosConfigurations.${osConfig.networking.hostName}.config.system.build.toplevel"
  ];
}
