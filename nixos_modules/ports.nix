# Trick to allocate a unique port to each service.
# You can just set bjackman.ports.foo = {} and then access
# config.bjackman.ports.foo.port and get a unique port among everything else
# using this option in the config.
# It might not really make sense that this is completely separate from iap.nix,
# not sure.
{ lib, config, ... }:
let
  cfg = config.bjackman.ports;
  portMapping =
    with lib;
    listToAttrs (imap0 (i: name: nameValuePair name (9000 + i)) (attrNames cfg));
in
{
  options.bjackman.ports = lib.mkOption {
    type =
      with lib.types;
      attrsOf (
        submodule (
          { name, ... }:
          {
            options.port = lib.mkOption {
              type = types.int;
              default = portMapping.${name};
              readOnly = true;
            };
          }
        )
      );
  };
}
