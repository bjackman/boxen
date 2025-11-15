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
      # VSCode has a bunch of yucky stateful shit that leaks into .config and I
      # can't be bothered to figure it out, just persist the whole mess.
      ".config/Code"
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
      ".config/gnome-initial-setup-done"
    ];
  };
}
