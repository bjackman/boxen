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
