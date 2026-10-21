# Trick to allocate a unique port to each service.
# You can just set bjackman.ports.foo = {} and then access
# config.bjackman.ports.foo.port and get a unique port among everything else
# using this option in the config.
# It might not really make sense that this is completely separate from iap.nix,
# not sure.
{ lib, config, ... }:
let
  cfg = config.bjackman.ports;
  allocated = lib.filter (name: cfg.${name}.fixedPort == null) (lib.attrNames cfg);
  portMapping = with lib; listToAttrs (imap0 (i: name: nameValuePair name (9000 + i)) allocated);
  byPort = lib.groupBy (name: toString cfg.${name}.port) (lib.attrNames cfg);
  clashes = lib.filterAttrs (_: names: lib.length names > 1) byPort;
in
{
  options.bjackman.ports = lib.mkOption {
    type =
      with lib.types;
      attrsOf (
        submodule (
          { name, config, ... }:
          {
            options.fixedPort = lib.mkOption {
              type = types.nullOr types.port;
              default = null;
              description = ''
                Port to use instead of an allocated one, for a service that
                clients expect on its well-known port. It doesn't move anyone
                else's allocation.
              '';
            };
            options.port = lib.mkOption {
              type = types.int;
              default = if config.fixedPort != null then config.fixedPort else portMapping.${name};
              readOnly = true;
            };
          }
        )
      );
  };

  config.assertions = [
    {
      assertion = clashes == { };
      message = "bjackman.ports has services sharing a port: ${
        lib.concatStringsSep "; " (lib.mapAttrsToList (port: names: "${port}: ${toString names}") clashes)
      }";
    }
  ];
}
