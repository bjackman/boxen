{
  config,
  pkgs,
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
    ../incus.nix
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

  bjackman.impermanence.enable = true;

  # So that GDM and Gnome and stuff have a persistent monitors setup.
  environment.etc."xdg/monitors.xml".source = ../../nixos_files/chungito/monitors.xml;

  programs.steam.enable = true;

  # https://wiki.nixos.org/wiki/Maintainers:Fastly#Cache_v2_plans
  nix.settings.substituters = [ "https://aseipp-nix-cache.global.ssl.fastly.net" ];

  # Try to build Darwin stuff on Romy's MacBook...
  nix.buildMachines = [
    {
      hostName = "macbook-air-8";
      sshUser = "romybinswanger";
      # ay caramba
      sshKey = "${config.users.users.brendan.home}/.ssh/id_ed25519";
      # From base64 -w0, for some fucking reason lmao
      publicHostKey = "c3NoLWVkMjU1MTkgQUFBQUMzTnphQzFsWkRJMU5URTVBQUFBSUp2anpnOG11WGRsczFDZ2sxVnJ6TWRrOW1EdGY1Uk8vYTh0MEJzRU5NRjkK";
      system = "aarch64-darwin";
      supportedFeatures = [
        "nix-command"
        "flakes"
      ];
    }
  ];
  nix.distributedBuilds = true;
  # Optional: if you want the Linux box to offload everything it can't do locally
  nix.extraOptions = ''
    builders-use-substitutes = true
  '';

  # For finding ESPHome devices on the LAN.
  services.avahi = {
    enable = true;
    nssmdns4 = true;
    nssmdns6 = true;
  };

  virtualisation = {
    containers.enable = true;
    podman = {
      enable = true;
      dockerCompat = true;
      defaultNetwork.settings.dns_enabled = true;
    };
  };
  users.users.brendan = {
    extraGroups = [
      "podman"
    ];
  };

  system.stateVersion = "25.05";
}
