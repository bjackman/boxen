# This module is for tracking stuff where different hosts have coupled
# configurations. It lets hosts refer to each other and also "export"
# information needed to query each other etc.
{ config, lib, ... }:
let
  cfg = config.bjackman;

  mkLanFqdn =
    fqdn:
    if cfg.onHomeLan then
      fqdn
    else
      throw "Can't get FQDN '${fqdn}' unless options.bjackman.onHomeLan is set";

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
          default = mkLanFqdn "norte.fritz.box";
        };
        mediaMount = lib.mkOption {
          type = lib.types.path;
          default = "/mnt/nas/media";
        };
      };
      jellyfin = lib.mkOption {
        type = lib.types.str;
        default = mkLanFqdn "jellyfin.fritz.box";
      };
    };
  };
}
