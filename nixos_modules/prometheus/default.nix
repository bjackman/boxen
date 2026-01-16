{
  config,
  pkgs,
  lib,
  agenix-template,
  grafana-dashboard-node-exporter-full,
  homelabConfigs,
  ...
}:
let
  admins = builtins.attrNames (lib.filterAttrs (_: u: u.admin) config.bjackman.homelab.users);
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

  # Couldn't get the stupid RBAC bullshit to work here, possibly it's
  # hobbled in the open source version.
  assertions = [
    {
      assertion = builtins.length admins <= 1;
      message = "Multiple Grafana admins defined but only one is supported";
    }
  ];

  services.prometheus = {
    enable = true;
    # No auth, assume we're behind a reverse proxy.
    listenAddress = "127.0.0.1";
    scrapeConfigs = builtins.concatMap (
      nodeConfig:
      let
        # If we try to be too clever and operate on the whole of
        # services.prometheus.exporters, things get weird. Just filter out the
        # ones we know work.
        exporters = {
          inherit (nodeConfig.services.prometheus.exporters) node smartctl;
        };
        enabledExporters = lib.filterAttrs (_: e: e.enable) exporters;
        hostName = nodeConfig.networking.hostName;
      in
      lib.mapAttrsToList (name: exporter: {
        # Note this is coupled with the dashboard/alert definitions. It
        # becomes the "job" label in Prometheus.
        job_name = "${name}_${hostName}";
        static_configs = [
          {
            targets = [ "${hostName}:${toString exporter.port}" ];
            labels.instance = hostName;
          }
        ];
      }) enabledExporters
    ) (builtins.attrValues homelabConfigs);
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

  services.grafana = {
    enable = true;
    settings = {
      server = {
        http_addr = "127.0.0.1";
        http_port = 9097;
        enable_gzip = true;
      };
      analytics = {
        check_for_updates = false;
        check_for_plugin_updates = false;
      };
      # Disable spam features
      feature_toggles = {
        featureHighlights = false;
        dashgpt = false;
        onPremToCloudMigrations = false;
      };
      news.news_feed_enabled = false;
      # See warning at the top of the module.
      security.admin_user = if admins != [ ] then builtins.head admins else null;
      "auth.proxy" = {
        enabled = true;
        header_name = "Remote-User";
      };
    };

    provision = {
      enable = true;
      datasources.settings.datasources = [
        {
          name = "Prometheus";
          type = "prometheus";
          url = "http://${config.services.prometheus.listenAddress}:${toString config.services.prometheus.port}";
          isDefault = true;
          editable = false;
        }
      ];
      dashboards.settings.providers = [
        {
          name = "Provisioned Dashboards";
          # The Wiki example points to /etc/grafana here for some reason, I
          # think this is for UI mutability. Here we are just going straght to
          # the Nix store, declarative or die.
          options.path = pkgs.linkFarm "my-dashboards" [
            # This one only partly works, but some of the graphs show "No data".
            # I debugged this with AI and it says the variables/fields/thingies
            # used by the dashboard definition aren't quite right (something
            # like "node" and "instance" are mixed up). It suggested remappping
            # them in Prometheus, which seems dumb. It also suggested
            # reconfiguring it in the dashboard UI but my brain stopped working.
            # If I'm really gonna think about this dashboarding shit I think I
            # probably wanna port it to Perses instead. I think one way to make
            # that happen would be to find some relatively simple Grafana
            # dashboards and then use the Perses CLI's `migrate` tool to
            # automatically convert them to Perses configs. Perhaps another
            # would be: https://github.com/perses/community-mixins
            {
              name = "node-exporter.json";
              path = grafana-dashboard-node-exporter-full;
            }
          ];
        }
      ];
    };
  };

  bjackman.iap.services = {
    prometheus = {
      subdomain = "prom";
      port = config.services.prometheus.port;
    };
    alertmanager = {
      subdomain = "alerts";
      port = config.services.prometheus.alertmanager.port;
    };
    grafana = {
      subdomain = "graf";
      port = config.services.grafana.settings.server.http_port;
    };
  };
}
