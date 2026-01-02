{ lib, ... }:
{
  options.bjackman.homelab.users = lib.mkOption {
    description = "The users for remote services. Use the add-user script to add users.";
    # IIUC the function passed to submodule also gets a `name` argument but
    # using this instead of config._module.args.name seems to be dispreferred. I
    # don't really understand why so this is a bit of a cargo-cult exercise.
    type =
      with lib.types;
      attrsOf (
        submodule (
          { config, ... }:
          {
            options = {
              name = lib.mkOption {
                type = str;
                description = "Username.";
                default = config._module.args.name;
              };
              displayName = lib.mkOption {
                type = str;
                default = lib.strings.toSentenceCase config.name;
                description = "Username in display format.";
              };
              admin = lib.mkOption {
                type = bool;
                default = false;
                description = "Whether the user has administrative rights.";
              };
            };
          }
        )
      );
    default = lib.importJSON ./users.json;
  };
}
