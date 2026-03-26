{
  config,
  lib,
  pkgs,
  agenix,
  ...
}:
let
  cfg = config.bjackman.sashiko;
  tomlFormat = pkgs.formats.toml { };
in
{
  imports = [
    agenix.homeManagerModules.default
  ];

  options.bjackman.sashiko = {
    enable = lib.mkEnableOption "sashiko";

    llmAPIKeyFile = lib.mkOption {
      description = "Path to file containing LLM service API key";
      type = lib.types.str;
    };

    settings = lib.mkOption {
      description = ''
        Settings for Sashiko, populates Settings.toml.

        Note this sets up a few defaults that seem uncontroversial but this
        isn't enough to actually make Sashiko work, you need to also configure
        extra stuff like the 'ai' options.
      '';
      type = lib.types.submodule {
        freeformType = tomlFormat.type;
        options = {
          database.url = lib.mkOption {
            type = lib.types.str;
            default = "${config.xdg.stateHome}/sashiko/sashiko.db";
          };
          database.token = lib.mkOption {
            type = lib.types.str;
            default = "";
          };
          mailing_lists.track = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = [ ];
          };
          nntp.server = lib.mkOption {
            type = lib.types.str;
            default = "nntp.lore.kernel.org";
          };
          nntp.port = lib.mkOption {
            type = lib.types.port;
            default = 119;
          };
        };
      };
      default = { };
    };
  };

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      # Generic config
      {
        xdg.configFile."sashiko/Settings.toml".source =
          tomlFormat.generate "sashiko-settings.toml" cfg.settings;

        systemd.user.services.sashiko = {
          Unit.Description = "Sashiko service";
          Service = {
            # Sashiko is currently hardcoded to read settings from the CWD so we
            # just switch to the config dir.
            WorkingDirectory = "${config.xdg.configHome}/sashiko";
            ExecStart = pkgs.writeShellScript "sashiko-service" ''
              export LLM_API_KEY=$(cat ${cfg.llmAPIKeyFile})
              exec ${pkgs.sashiko}/bin/sashiko
            '';
            Restart = "on-failure";

            ProtectHome = false;
            ProtectSystem = false;
            ReadOnlyPaths = [ ];

            PassEnvironment = [ "PATH" "HOME" "USER" "XDG_RUNTIME_DIR" ];
          };
          Install.WantedBy = [ "default.target" ];
        };
      }

      # My config
      {
        age.secrets.gemini-api-key.file = ../secrets/gemini-api-key.age;
        bjackman.sashiko = {
          llmAPIKeyFile = config.age.secrets.gemini-api-key.path;
          settings = {
            ai = {
              provider = "gemini";
              model = "gemini-3.1-pro-preview";
              max_input_tokens = 900000;
              max_interactions = 50;
              temperature = 1.0;
            };
            server = {
              host = "127.0.0.1";
              port = 8080;
            };
            git.repository_path = "third_party/linux";
            review = {
              concurrency = 20;
              worktree_dir = "review_trees";
              timeout_seconds = 7200;
              max_retries = 3;
              ignore_files = [
                "MAINTAINERS"
                ".mailmap"
                ".gitignore"
                "LICENSES/"
              ];
            };
          };
        };
      }
    ]
  );
}
