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

  # Temporary while I work out some other networking stuff. I can still access
  # it on the LAN (e.g. deploy .#pizza --hostname pizza.fritz.box).
  services.tailscale.enable = false;

  networking.useDHCP = false;
  networking.networkmanager.enable = false;
  systemd.network = {
    enable = true;
    networks."10-eth-default" = {
      matchConfig.Type = "ether";
      networkConfig = {
        DHCP = "yes";
        IPv6AcceptRA = true;
      };
    };
  };
  services.resolved.enable = true;

  system.stateVersion = "25.11";
}
