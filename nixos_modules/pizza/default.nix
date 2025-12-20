{
  config,
  pkgs,
  modulesPath,
  ...
}:

{
  imports = [
    ../common.nix
    ../brendan.nix
    ../server.nix
    ./disko.nix
    "${modulesPath}/profiles/headless.nix"
    "${modulesPath}/profiles/minimal.nix"
  ];

  boot.loader = {
    systemd-boot.enable = true;
    efi.canTouchEfiVariables = true;
  };

  networking.hostName = "pizza";

  time.timeZone = "Europe/Zurich";

  services.openssh = {
    enable = true;
    settings.PasswordAuthentication = false;
  };

  system.stateVersion = "25.11";
}
