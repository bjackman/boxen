{
  config,
  pkgs,
  modulesPath,
  nixos-hardware,
  ...
}:

{
  imports = [
    ../common.nix
    ../brendan.nix
    ../server.nix
    ./disko.nix
    ./power.nix
    "${modulesPath}/profiles/headless.nix"
    "${modulesPath}/profiles/minimal.nix"
    nixos-hardware.nixosModules.lenovo-thinkpad-t480
  ];

  boot.loader = {
    systemd-boot.enable = true;
    efi.canTouchEfiVariables = true;
  };

  networking.hostName = "pizza";

  time.timeZone = "Europe/Zurich";

  services.logind.settings.Login = {
    HandleLidSwitch = "ignore";
    HandleLidSwitchExternalPower = "ignore";
  };

  services.openssh = {
    enable = true;
    settings.PasswordAuthentication = false;
  };

  system.stateVersion = "25.11";
}
