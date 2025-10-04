{ config, pkgs, ... }:

{
  imports = [
    ./hardware-configuration.nix
    ../brendan.nix
    ../sway.nix
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
  programs.sway.extraOptions = [ "--unsupported-gpu" ];

  services.openssh = {
    enable = true;
    settings.PasswordAuthentication = false;
  };
  services.tailscale.enable = true;

  # Didn't help:
  # https://discourse.nixos.org/t/psa-for-those-with-hibernation-issues-on-nvidia/61834

  # This gets rid of the issue where the screen is blank after
  # resume-from-suspend. No idea why.
  # https://discourse.nixos.org/t/suspend-problem/54033/3:
  hardware.nvidia.powerManagement.enable = true;
  # Something that didn't work to fix the above:
  # boot.extraModprobeConfig = ''
  #   options nvidia_modeset vblank_sem_control=0
  # '';
  # There are a few other things in these threads that I didn't try:
  # https://discourse.nixos.org/t/suspend-problem/54033/28
  # https://discourse.nixos.org/t/black-screen-after-suspend-hibernate-with-nvidia/54341/6:

  users.mutableUsers = false;

  # Note this is coupled with the fileSystems definition which is currently in
  # ./hardware-configuration.nix
  environment.persistence."/persistent" = {
    hideMounts = true; # Don't spam all these mounts in file managers.
    directories = [
      "/var/log"
      "/var/lib/bluetooth" # Apparently bluetooth pairing is system-global.
      "/var/lib/nixos" # Needed for consistent UIDs
      "/var/lib/systemd/coredump"
      "/etc/NetworkManager/system-connections"
      "/var/lib/AccountsService" # Used by GDM to remember last choice of desktop.
    ];
    files = [
      "/etc/machine-id"
    ];
  };

  system.stateVersion = "25.05";
}
