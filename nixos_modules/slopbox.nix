{
  config,
  lib,
  pkgs,
  homelab,
  modulesPath,
  ...
}:
let
  slop = config.bjackman.slopClient.packages;
in
{
  imports = [
    ./brendan.nix
    ./common.nix
    ./server.nix
    ./slop-client.nix
    "${modulesPath}/virtualisation/incus-virtual-machine.nix"
    # Note it's unusual to directly import brendan-home.nix from a host's
    # top-level module, usually they'll import pc.nix, but this is a VM.
    ./brendan-home.nix
  ];

  services.openssh = {
    enable = true;
    settings.PasswordAuthentication = false;
  };
  security.sudo.wheelNeedsPassword = false;

  networking.hostName = "slopbox";

  # Disable firewall for faster boot and less hassle;
  # we are behind a layer of NAT anyway.
  networking.firewall.enable = false;

  nix = {
    # Disable optimisation as this doesn't work with a writable store
    # overlay.
    optimise.automatic = false;
  };

  # Generate SSH host keys at a location that persists between boots.
  services.openssh.hostKeys = [
    {
      path = "/var/slopbox/ssh_host_ed25519_key";
      type = "ed25519";
    }
  ];

  age.identityPaths = map (key: key.path) config.services.openssh.hostKeys;

  # I dunno what this does but without it I get an error when trying to use Home
  # Manager.
  # https://discourse.nixos.org/t/error-gdbus-error-org-freedesktop-dbus-error-serviceunknown-the-name-ca-desrt-dconf-was-not-provided-by-any-service-files/29111
  programs.dconf.enable = true;

  # We're gonna be building a disk image for this and it's really annoying to
  # invalidate that hash so don't include the config reviison.
  system.configurationRevision = null;

  boot.loader = {
    timeout = 0;
    # The image's ESP is only 249M and a 6.18 kernel+initrd is ~42M, so we
    # can't keep many generations around before it fills up.
    systemd-boot.configurationLimit = 4;
  };

  bjackman.slopClient.user = "brendan";

  environment.systemPackages = builtins.attrValues slop;

  # Runs as me rather than as a service user: it drives the same sessions I
  # attach to interactively, and Claude Code keys those by home directory.
  systemd.services.slop-handler = {
    description = "Drive agent sessions from Gerrit review comments";
    # Claude Code refuses to run its Bash tool without a POSIX shell, and
    # systemd sets SHELL from passwd, where mine is fish. /run/current-system
    # is on the path so that the agent sees the same tools I would.
    environment.SHELL = lib.getExe pkgs.bashInteractive;
    path = [
      "/run/current-system/sw"
      pkgs.bashInteractive
    ];
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      ExecStart = "${slop.slop-tools}/bin/slop-handler";
      User = "brendan";
      StateDirectory = "slop-handler";
      Restart = "on-failure";
      RestartSec = "30s";
    };
  };

  home-manager.users.brendan.imports = [ ../hm_modules/slopbox.nix ];

  system.stateVersion = "25.11";
}
