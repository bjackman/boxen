{ pkgs, config, ... }:
let
  persesConfig = {
    security = {
      encryption_key_file = config.age.secrets.perses-encryption-key.path;
      # Site is hosted behind SSL, so set this, shrug.
      cookie.secure = true;
    };
  };
in
{
  imports = [
    ../iap.nix
  ];

  environment.systemPackages = [ pkgs.perses ];

  systemd.services.perses = {
    after = [ "network.target" ];
    wantedBy = [ "multi-user.target" ];

    serviceConfig = {
      ExecStart =
        let
          configFile = pkgs.writeText "perses-config.json" (builtins.toJSON persesConfig);
          listenAddr = "127.0.0.1:${toString config.bjackman.iap.services.perses.port}";
        in
        "${pkgs.perses}/bin/perses --config ${configFile} --web.listen-address ${listenAddr}";
      Restart = "always";
      User = "perses";
      Group = "perses";

      RuntimeDirectory = "perses";
      StateDirectory = "perses";
      WorkingDirectory = "/var/lib/perses";

      ProtectSystem = "full";
      ProtectHome = true;
      PrivateTmp = true;
      NoNewPrivileges = true;
      CapabilityBoundingSet = ""; # Removes all kernel capabilities
      RestrictRealtime = true;
      BindReadOnlyPaths = [
        config.age.secrets.perses-encryption-key.path
      ];
    };

    confinement.enable = true;
  };
  users.users.perses = {
    isSystemUser = true;
    group = "perses";
  };
  users.groups.perses = { };

  age.secrets.perses-encryption-key = {
    file = ../../secrets/perses-encryption-key.age;
    mode = "440";
    group = config.systemd.services.perses.serviceConfig.Group;
  };

  bjackman.iap.services.perses.port = 8097;
}
