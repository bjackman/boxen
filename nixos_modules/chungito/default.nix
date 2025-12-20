{
  config,
  pkgs,
  declarative-jellyfin,
  ...
}:

{
  imports = [
    ./hardware-configuration.nix
    ../common.nix
    ../brendan-weak-password.nix
    ../pc.nix
    ../server.nix
    ../sway.nix
    ../impermanence.nix
    ../transmission.nix
    declarative-jellyfin.nixosModules.default
  ];

  networking.hostName = "chungito";

  time.timeZone = "Europe/Zurich";

  # Copied from https://wiki.nixos.org/wiki/NVIDIA
  hardware.graphics.enable = true;
  services.xserver.videoDrivers = [ "nvidia" ];
  hardware.nvidia.open = true;
  programs.sway.extraOptions = [ "--unsupported-gpu" ];

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
  services.logind.settings.Login.SleepOperation = "hibernate";

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
    # Experimental: Manually created, then used this to set up the right directory structure:
    # mnamer <media dir>  --episode-format "{series}/Season {season:02}/{series} - S{season:02}E{episode:02} - {title}{extension}" --batch
    libraries.TV = {
      enabled = true;
      contentType = "tvshows";
      pathInfos = [ "/var/lib/media/shows" ];
      typeOptions.Shows = {
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

  # TODO: These don't really belong in chungito module
  bjackman.impermanence.extraPersistence.directories = [
    "/var/lib/tailscale"
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
      ".vscode"
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

  programs.steam.enable = true;

  system.stateVersion = "25.05";
}
