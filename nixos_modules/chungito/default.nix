{ config, pkgs, ... }:

{
  imports = [
    ./hardware-configuration.nix
    ../brendan.nix
  ];

  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];

  boot.loader = {
    systemd-boot.enable = true;
    efi.canTouchEfiVariables = true;
  };

  networking = {
    hostName = "chungito";
    # NixOS wiki recommends sticking to NetworkManager for laptoppy usecases,
    # this is not a laptop but it's still kinda laptoppy so let's stick to it I
    # guess.
    networkmanager.enable = true;
  };

  time.timeZone = "Europe/Zurich";

  i18n.defaultLocale = "en_GB.UTF-8";

  i18n.extraLocaleSettings = {
    LC_ADDRESS = "en_GB.UTF-8";
    LC_IDENTIFICATION = "en_GB.UTF-8";
    LC_MEASUREMENT = "en_GB.UTF-8";
    LC_MONETARY = "en_GB.UTF-8";
    LC_NAME = "en_GB.UTF-8";
    LC_NUMERIC = "en_GB.UTF-8";
    LC_PAPER = "en_GB.UTF-8";
    LC_TELEPHONE = "en_GB.UTF-8";
    LC_TIME = "en_GB.UTF-8";
  };

  services.xserver = {
    enable = true;
    displayManager.gdm.enable = true;
    desktopManager.gnome.enable = true;
  };

  services.xserver.xkb = {
    layout = "us";
    variant = "";
  };

  services.pulseaudio.enable = false;
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
  };

  nixpkgs.config.allowUnfree = true;

  # Copied from https://wiki.nixos.org/wiki/NVIDIA
  hardware.graphics.enable = true;
  services.xserver.videoDrivers = [ "nvidia" ];
  hardware.nvidia.open = true;

  # EXPERIMENTAL: Enable hyprland
  # This is nowhere near working. I managed to get the monitors working properly
  # wih this in my config (which isn't checked in):
  # monitor=HDMI-A-1,preferred,auto,auto
  # monitor=HDMI-A-2,preferred,auto-left,auto
  programs.hyprland = {
    enable = true;
    xwayland.enable = true;
  };
  environment.systemPackages = [
    pkgs.kitty # required for the default Hyprland config
  ];

  system.stateVersion = "25.05";
}
