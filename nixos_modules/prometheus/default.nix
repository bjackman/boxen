{
  config,
  pkgs,
  agenix-template,
  ...
}:
{
  imports = [
    agenix-template.nixosModules.default
    ../iap.nix
    ./rules.nix
  ];

  services.prometheus = {
    enable = true;
    # No auth, assume we're behind a reverse proxy.
    listenAddress = "127.0.0.1";
    scrapeConfigs = [
      {
        job_name = "node";
        static_configs = [
          {
            targets = [ "localhost:${toString config.services.prometheus.exporters.node.port}" ];
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
    exporters.node = {
      enable = true;
      enabledCollectors = [
        "cpu"
        "diskstats"
        "ethtool"
        "filefd"
        "filesystem"
        "hwmon"
        "loadavg"
        "meminfo"
        "nfs"
        "nvme"
        "os"
        "pcidevice"
        "systemd"
        "watchdog"
      ];
    };
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
      security.disable_initial_admin_creation = true;
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
