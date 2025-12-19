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
    (modulesPath + "/installer/cd-dvd/installation-cd-minimal.nix")
  ];

  networking.hostName = "pizza";

  time.timeZone = "Europe/Zurich";

  services.openssh = {
    enable = true;
    settings.PasswordAuthentication = false;
  };

  system.stateVersion = "25.11";
}
