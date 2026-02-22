{
  config,
  pkgs,
  lib,
  agenix-template,
  homelab,
  ...
}:
let
  admins = builtins.attrNames (lib.filterAttrs (_: u: u.isAdmin) config.bjackman.homelab.users);
in
{
  imports = [
    agenix-template.nixosModules.default
    ../iap.nix
    ../impermanence.nix
    ../node-exporter.nix
    ./rules.nix
    ./perses.nix
  ];

  services.prometheus = {
    enable = true;
    # No auth, assume we're behind a reverse proxy.
    listenAddress = "127.0.0.1";
    scrapeConfigs =
      let
        # Given the name of an exporter configured via
        # services.prometheus.exporters.$name, generate a scrape config that
        # scrapes that exporter from all the hosts in the homelab that enable
        # the exporter.
        mkScrapeConfig = exporterName: {
          job_name = exporterName;
          static_configs =
            let
              exporterEnabled = c: c.services.prometheus.exporters.${exporterName}.enable;
              nodes = builtins.filter exporterEnabled (builtins.attrValues homelab.nodes);
            in
            builtins.map (
              nodeConfig:
              let
                hostName = nodeConfig.networking.hostName;
                exporter = nodeConfig.services.prometheus.exporters.${exporterName};
              in
              {
                targets = [ "${hostName}:${toString exporter.port}" ];
                labels.instance = hostName;
              }
            ) nodes;
        };
      in
      # This only works for certain exporters, never bothered to look carefully
      # into why. So we just list the ones that are actually used.
      map mkScrapeConfig [
        "node"
        "smartctl"
        "zfs"
      ]
      ++ [
        # Restic exporters are defined via my own special option, define scrapes
        # for those.
        {
          job_name = "restic";
          static_configs =
            let
              # Takes a node's configuration and returns scrape targets for each of
              # its restic exporters.
              nodeTargets =
                nodeConfig:
                let
                  hostName = nodeConfig.networking.hostName;
                in
                lib.mapAttrsToList (_: instance: {
                  targets = [ "${hostName}:${toString instance.port}" ];
                  labels.instance = "${hostName}_${instance.name}";
                }) nodeConfig.bjackman.restic-exporter.instances;
              # Not all nodes will import the module so the restic-exporter
              # option might not exist.
              nodes = builtins.filter (c: c.bjackman ? restic-exporter) (builtins.attrValues homelab.nodes);
            in
            lib.concatMap nodeTargets nodes;
        }
        # Note the whole point of mDNS (Avahi) is supposed to be service
        # discovery - Prometheus's service discovery mechanism doesn't natively
        # support it but there are bridges. It isn't really necessary to
        # hard-code the scrape targets like this, but it's nice and simple.
        {
          job_name = "esphome";
          static_configs = [
            {
              # This is assuming nsswitch is configured with Avahi support -
              # this is done in NixOS via services.avahi.
              targets = [ "air-1-bedroom-7dd3bc.local" ];
              labels.instance = "Bedroom Air";
            }
          ];
        }
      ];

    ruleFiles = [
      # I over-engineered this coz I thought I was gonna write some complex
      # rules that depend on other parts of the config. But then I changed my
      # mind about that lol.
      (pkgs.writers.writeJSON "prometheus-rules.json" config.bjackman.prometheus.rules)
    ];
    alertmanager = {
      enable = true;
      # Copied from
      # https://github.com/bjackman/nas/blob/486592769ca3fa7e186438520e745c485b116ebd/templates/alertmanager.yaml.jinja2
      # I'd probably like to replace this with ntfy.sh - see the stash/ntfy
      # branch.
      configuration = {
        route = {
          receiver = "email-me";
          group_by = [ "alertname" ];
        };
        receivers = [
          {
            name = "email-me";
            email_configs = [
              (
                let
                  addr = "bhenryj0117@gmail.com";
                in
                {
                  from = addr;
                  to = addr;
                  smarthost = "smtp.gmail.com:587";
                  auth_username = addr;
                  auth_identity = addr;
                  # These settings are processed via envsubst, we can use this to
                  # inject secrets.
                  auth_password = "$ALERTMANAGER_GMAIL_PASSWORD";
                }
              )
            ];
          }
        ];
      };
      environmentFile = config.age-template.files."alertmanager.env".path;
    };
    alertmanagers = [
      {
        static_configs = [
          { targets = [ "localhost:${toString config.services.prometheus.alertmanager.port}" ]; }
        ];
      }
    ];
  };
  age.secrets.alertmanager-gmail-password.file = ../../secrets/alertmanager-gmail-password.age;
  age-template.files."alertmanager.env" = {
    vars.pass = config.age.secrets.alertmanager-gmail-password.path;
    content = ''ALERTMANAGER_GMAIL_PASSWORD="$pass"'';
  };

  # For finding ESPHome devices on the LAN. Note this seems to be a bit fragile
  # wrt dual-stack, at least on NixOS 25.11 - seems like maybe if the ESPHome
  # devices are IPv4-only, this needs to also be IPv4-only, and if it's dual
  # stack this needs to be dual stack.
  services.avahi = {
    enable = true;
    nssmdns4 = true;
    nssmdns6 = true;
  };

  bjackman.impermanence.extraPersistence.directories =
    let
      service = config.systemd.services.prometheus.serviceConfig;
    in
    [
      {
        directory = service.WorkingDirectory;
        mode = "0770";
        user = service.User;
      }
    ];

  bjackman.iap.services = {
    prometheus = {
      subdomain = "prom";
      port = config.services.prometheus.port;
    };
    alertmanager = {
      subdomain = "alerts";
      port = config.services.prometheus.alertmanager.port;
    };
  };
}
