# This module is for tracking stuff where different hosts have coupled
# configurations. It lets hosts refer to each other and also "export"
# information needed to query each other etc.
{ config, lib, ... }:
let
  cfg = config.bjackman;
  lanOnlyValue =
    val:
    if cfg.onHomeLan then val else throw "Can't get '${val}' unless options.bjackman.onHomeLan is set";
in
{
  options.bjackman = {
    onHomeLan = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Set this if the node is at home on the LAN.";
    };

    servers = {
      nfs = {
        hostname = lib.mkOption {
          type = lib.types.str;
          default = lanOnlyValue "norte.fritz.box";
        };
        mediaMount = lib.mkOption {
          type = lib.types.path;
          default = "/mnt/nas/media";
        };
      };
      jellyfin.url = lib.mkOption {
        type = lib.types.str;
        # TODO: This is quietly coupled with the port elsewhere :/
        default = lanOnlyValue "http://jellyfin.fritz.box:8096";
      };
    };
  };
}
