{ pkgs, ... }:
{
  imports = [
    ./common.nix
  ];
  users.users.brendan = {
    isNormalUser = true;
    description = "Brendan Jackman";
    extraGroups = [
      "networkmanager"
      "wheel"
      # Required for hyprland stuff to be able to query capslock status.
      "input"
    ];
    shell = pkgs.fish;
    openssh.authorizedKeys.keys = [
      "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQDMi2QRJG+/nM2ekysSUT6h1uNlSmo31ubSK28DrGVezoh2MaPXz6XWMpJtDvr9FHHOVpsCTFxFQ9A7DTqgFy0NxwTHJhK5bevxaWYRkv43H8EMR9pJXYMDAtj7Gk+NNK5ssGZm2P+cTl9r5QZOm0PaVUUeoA/KxbVCNEenOCHM5Lv2RrXGufJL1ukRL6I83fl3ilfgEOz2RBG3QQGahVqYfZq/mfo07U0vad9RX7y6I+8Ap8XSCe33yfO0338yPf0A69p90xtpiJyYyAtVN+0KT552wpMtPjprXt5mrpYDLZvW6vBu0mFGkmDoz3ekb+MmWJVlE9f1VyjHpmA1bRn18gQ73egrGlVWvPHpAJ3gl5bKtc30Md/M4u3tyauDoAnqOs/FAqvClDz1Yav+5Ck5umnDSXXWH/WToX9AUsevjLQq1uB2QJU6oYeEIpEHWC4dUtgPXrX/SYDSGmqA5xOqboyn39oIcNWXTOrqnes52bBlOW3/zCX51EIx/tiG3LU= brendan@brendan-thinkpad"
    ];
    # Generated with mkpasswd -m yescrypt -R 9
    # This is my old Google password that was taken by the anti-phising corp
    # Chrome extension.
    hashedPassword = "$y$jDT$8TtWoQ/AR0OfOz2gALnXV/$sat6aCoiZL/beGefyjMKZnoRNz/C47cQiwDHfQXEiz1";
  };
  programs.fish.enable = true;
  programs.steam.enable = true;

  # TODO: This is coupled with the chungito configuration (assuming /persistent exists).
  environment.persistence."/persistent".users.brendan = {
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
  };
}
