# Stuff for a machine I sit in front of, as opposed to one that only ever runs
# coding agents.
{ pkgs, ... }:
{
  imports = [
    ./mail.nix
    ./vscode.nix
    ./zed.nix
    ./chungito-ctrl.nix
  ];

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
