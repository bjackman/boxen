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
    ./agent-host-context.nix
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
  # Profile dir must be named "default" on every machine; Home Manager generates
  # profiles.ini from this attrset and won't preserve a pre-existing random name.
  programs.firefox.profiles.default.settings = {
    # Restore the previous session; pinned tabs are only restored as part of it.
    "browser.startup.page" = 3;
  };
  programs.vscode.enable = true;

  bjackman.nix-warmups = [
    "github:bjackman/boxen/master#nixosConfigurations.${osConfig.networking.hostName}.config.system.build.toplevel"
  ];

  bjackman.agentHostContext = ''
    You're running on a NixOS host. I tend not to install much into the global
    environment, e.g. you might find that there's no `python3` in $PATH. But,
    you are free to run stuff from nixpkgs. This is a fully flake-based system
    so you can do that with `nix run nixpkgs#<package>`. If you need the latest
    version, use `nix run nixpkgs-unstable#<package>` instead. You can also use
    `nix shell nixpkgs#<package> -c <command>` to run commands in a shell that
    has the package installed.
  '';
}
