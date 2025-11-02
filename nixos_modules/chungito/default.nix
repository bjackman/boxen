{ config, pkgs, ... }:

{
  imports = [
    ./hardware-configuration.nix
    ../brendan.nix
    ../pc.nix
    ../sway.nix
    ../impermanence.nix
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
  bjackman.impermanence.extraPersistence.directories = [
    "/var/lib/tailscale"
    {
      directory = "/var/lib/transmission";
      mode = "0755";
    }
  ];

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

  # sleep-then-hibernate doesn't work due to some Nvidia bullshit or other:
  #
  # NVRM: GPU 0000:0a:00.0: PreserveVideoMemoryAllocations module parameter is set.
  # System Power Management attempted without driver procfs suspend interface.
  # nvidia 0000:0a:00.0: PM: failed to suspend async: error -5
  # PM: Some devices failed to suspend, or early wake event detected
  #
  # So, just skip the suspend step and go right to hibernando.
  services.logind.extraConfig = ''
    SleepOperation=hibernate
  '';

  users.mutableUsers = false;

  age.secrets.transmission-rpc-password-json.file = ../../secrets/transmission-rpc-password.json.age;
  services.transmission = {
    enable = true;
    openRPCPort = true;
    settings = {
      rpc-bind-address = "0.0.0.0";
      rpc-whitelist-enabled = false;
      rpc-authentication-required = true;
      rpc-username = "brendan";
    };
    # This is a weird roundabout way to set rpc-password in the the settings.
    # The name of the option is bad, it's actually a JSON file that gets merged
    # with the settings above.
    credentialsFile = config.age.secrets.transmission-rpc-password-json.path;
  };

  age.secrets.jellyfin-admin-password-hash.file = ../../secrets/jellyfin-admin-password-hash.age;
  # https://github.com/Sveske-Juice/declarative-jellyfin/blob/main/examples/fullexample.nix
  services.declarative-jellyfin = {
    system.serverName = "Chungito Declarativo";
    serverId = "db7bd3ba3d7b404eb430715b3b977dc1"; # uuidgen -r | sed 's/-//g'
    enable = true;
    users = {
      brendan = {
        mutable = false;
        permissions.isAdministrator = true;
        hashedPasswordFile = config.age.secrets.jellyfin-admin-password-hash.path;
      };
    };
    # THIS BIT IS HARDWARE-SPECIFIC, it means I have an NVidia GPU.
    encoding = {
      hardwareAccelerationType = "nvenc";
      # These next bits might be wrong, I'm trusting Claude here.
      hardwareDecodingCodecs = [
        "h264"
        "hevc"
        "mpeg2video"
        "vc1"
        "vp8"
        "vp9"
        "av1"
      ];
      enableDecodingColorDepth10Hevc = true;
      allowHevcEncoding = true;
      allowAv1Encoding = true; # Apparently 30 series only supports decoding AV1.
    };
    libraries.Movies = {
      enabled = true;
      contentType = "movies";
      pathInfos = [ "/var/lib/transmission/Downloads" ];
      typeOptions.Movies = {
        metadataFetchers = [
          "The Open Movie Database"
          "TheMovieDb"
        ];
        imageFetchers = [
          "The Open Movie Database"
          "TheMovieDb"
        ];
      };
    };
  };
  services.jellyfin.openFirewall = true;

  # So that GDM and Gnome and stuff have a persistent monitors setup.
  environment.etc."xdg/monitors.xml".source = ../../nixos_files/chungito/monitors.xml;

  system.stateVersion = "25.05";
}
