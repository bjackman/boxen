# Insired by
# https://github.com/jhillyerd/agenix-template/blob/77cd55731e15d98edec7b9d47650bdd7f977ba5f/template.nix,
# but more flexible: instead of just envsubst-ing secrets it allows deriving
# arbitrary content via a script.
# This doesn't really do very much, it's probably not much more verbose than
# just directly writing activationScripts to generate the secrets. But, by
# encoding the output path as an option it makes it easier to write configs with
# less invisible couplings.
{
  config,
  pkgs,
  lib,
  agenix-template,
  ...
}:
let
  cfg = config.bjackman.derived-secrets;
in
{
  imports = [ agenix-template.nixosModules.default ];

  options.bjackman.derived-secrets = {
    directory = lib.mkOption {
      type = lib.types.path;
      description = "Default directory to create output files in";
      default = "/run/derived-secrets";
    };

    files = lib.mkOption {
      # Note: I'm not really sure why we do this {config, ...} thing instead of
      # using {name} here. I'm cargo-culting, and AI says it's good but I don't
      # understand why.
      type = lib.types.attrsOf (
        lib.types.submodule (
          { config, ... }:
          {
            options = {
              name = lib.mkOption {
                type = lib.types.str;
                default = config._module.args.name;
                description = "Name of the derived file";
              };

              script = lib.mkOption {
                type = lib.types.str;
                description = "Script to generate the derived output. Should write it to stdout";
              };

              path = lib.mkOption {
                type = lib.types.str;
                description = "Path (with filename) to store derived output";
                default = "${cfg.directory}/${config.name}";
              };

              user = lib.mkOption {
                type = lib.types.str;
                description = "Unix user that will own the resulting secret file";
                default = "root";
              };

              group = lib.mkOption {
                type = lib.types.str;
                description = "Unix group that will own the resulting secret file";
                default = "root";
              };

              mode = lib.mkOption {
                type = lib.types.str;
                description = "Permissions mode for the resulting secret file";
                default = "0400";
              };
            };
          }
        )
      );
      description = "Derived secret files to generate";
      default = { };
    };

    envFiles = lib.mkOption {
      type =
        with lib.types;
        attrsOf (
          submodule (
            { name, ... }:
            {
              options = {
                vars = lib.mkOption {
                  type = attrsOf path;
                  description = ''
                    Attrset mapping environment variable names to secret files that
                    will contain the desired value in the generated .env file.
                  '';
                };
                path = lib.mkOption {
                  type = path;
                  readOnly = true;
                  description = ''
                    Path of the generated .env file
                  '';
                  default = config.age-template.files."${name}.env".path;
                };
              };
            }
          )
        );
      default = { };
      description = ''
        Convenience option for generating .env files via agenix-template.
      '';
    };
  };

  config = {
    system.activationScripts = {
      derived-secrets-dir = {
        text = ''
          mkdir -p "${cfg.directory}";
          chmod 0751 "${cfg.directory}";
        '';
      };
    }
    // lib.attrsets.mapAttrs' (name: secretCfg: {
      name = "derive-secret-${name}";
      value = {
        deps = [
          "derived-secrets-dir"
          "agenix"
        ];
        text = ''
          mkdir -p "${builtins.dirOf secretCfg.path}"
          (${secretCfg.script}) > "${secretCfg.path}"
          chown "${secretCfg.user}:${secretCfg.group}" "${secretCfg.path}"
          chmod "${secretCfg.mode}" "${secretCfg.path}"
        '';
      };
    }) cfg.files;

    age-template.files = lib.mapAttrs' (
      name: cfg:
      lib.nameValuePair "${name}.env" {
        inherit (cfg) vars;
        content = lib.concatStringsSep "\n" (
          lib.mapAttrsToList (varName: _: "${varName}=\$${varName}") cfg.vars
        );
      }
    ) cfg.envFiles;
  };
}
