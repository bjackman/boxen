# This module is for tracking stuff where different hosts have coupled
# configurations. It lets hosts refer to each other and also "export"
# information needed to query each other etc.
# TODO: I think a better way to achieve this would be to pass in the other
# nodes' configs as flake refs, along with an attrset reporting which nodes
# serve which services.
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
        default = lanOnlyValue "http://pizza.fritz.box:8096";
      };
    };
  };
}
