# Stuff for a machine I sit in front of, as opposed to one that only ever runs
# coding agents.
{
  config,
  lib,
  pkgs,
  osConfig ? null,
  ...
}:
{
  imports = [
    ./sway.nix
    ./monitors.nix
    ./dark-mode.nix
    ./mail.nix
    ./vscode.nix
    ./zed.nix
    ./chungito-ctrl.nix
    ./agent-host-context.nix
  ];

  config = lib.mkMerge [
    {
      home.packages = with pkgs; [
        llm-agents.antigravity-cli
        vlc
        nautilus
      ];

      programs.kitty = {
        enable = true;
        settings = {
          enable_audio_bell = false;
          allow_remote_control = true;
          # This configures the separate scrollback buffer that is only accessible
          # via the pager magic, not the "live" scrollback that you can interact
          # with via the mouse. It's recommended to keep the latter small for perf.
          # Megabytes.
          scrollback_pager_history_size = 128;
        };
      };
      # Allow creating new terminals on remote hosts (connected via kitten ssh).
      programs.fish.shellAbbrs.klo = "kitty @ launch --type=os-window --cwd=current fish";

      bjackman.nix-warmups = [
        "github:bjackman/limmat-kernel-nix/master#devShells.${pkgs.stdenv.hostPlatform.system}.kernel"
        "github:bjackman/boxen/master#devShells.${pkgs.stdenv.hostPlatform.system}.default"
        "github:sashiko-dev/sashiko#devShells.${pkgs.stdenv.hostPlatform.system}.default"
      ];
    }

    # Off NixOS the browser and editors come from the distro or Flatpak, which
    # is also why vscode.nix and zed.nix only ever configure them.
    (lib.mkIf (osConfig != null) {
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
    })
  ];
}
