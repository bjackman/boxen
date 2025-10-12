# Stuff for my user but on computers with screens and a keyboard and shit.
{ pkgs, ... }:
{
  programs.steam.enable = true;

  users.users.brendan.extraGroups = [
    "networkmanager"
    # Required for waybar etc to be able to query capslock status.
    "input"
  ];

  bjackman.impermanence.extraPersistence.users.brendan = {
    directories = [
      "Downloads"
      "Music"
      "Pictures"
      "Documents"
      "Videos"
      "src"
      ".cache"
      ".local/share/z"
      ".local/share/fish"
      ".local/share/zed"
      ".local/share/Steam"
      ".steam"
      {
        directory = ".mozilla/firefox";
        mode = "0700";
      }
      {
        directory = ".ssh";
        mode = "0700";
      }
      {
        directory = ".local/share/keyrings";
        mode = "0700";
      }
    ];
    files = [
      ".config/monitors.xml"
      ".config/gnome-initial-setup-done"
    ];
  };
}
