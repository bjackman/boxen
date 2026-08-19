# Stuff for a computer with a keyboard and screens.
{ config, osConfig, ... }:
{
  imports = [
    ./sway.nix
    ./monitors.nix
    ./workstation.nix
    ./dark-mode.nix
    ./agent-host-context.nix
  ];

  programs.firefox.enable = true;
  # Keeps the pre-26.05 path to avoid migrating profile data on each machine.
  # To adopt the XDG default instead:
  #   1. Set programs.firefox.configPath = "${config.xdg.configHome}/mozilla/firefox";
  #   2. On each machine: mv ~/.mozilla/firefox "$XDG_CONFIG_HOME/mozilla/firefox"
  #   3. Update the impermanence directory in nixos_modules/pc.nix from
  #      ".mozilla/firefox" to ".config/mozilla/firefox" (or whatever $XDG_CONFIG_HOME resolves to).
  programs.firefox.configPath = ".mozilla/firefox";
  # Profile dir must be named "default" on every machine; Home Manager generates
  # profiles.ini from this attrset and won't preserve a pre-existing random name.
  programs.firefox.profiles.default.settings = {
    # Restore the previous session; pinned tabs are only restored as part of it.
    "browser.startup.page" = 3;
  };
  programs.vscode.enable = true;

  bjackman.agentHostContext = ''
    # Operating on this host

    This is one of my personal NixOS workstations
    (${osConfig.networking.hostName}), configured from the "boxen" flake checked
    out at `${config.bjackman.configCheckout}`, if you need to understand how
    the system is set up you can read that config.
  '';
}
