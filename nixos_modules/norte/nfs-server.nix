{ config, ... }:
{
  # Create /mnt/nas/media, let anyone read it. Members of media-writers can
  # write it. This is defined explicitly here while other subtrees aren't,
  # that's just coz they were created before I set up NixOS on this node.
  users.groups.media-writers = { };
  systemd.tmpfiles.settings = {
    "10-mnt-nas-media" = {
      "/mnt/nas/media" = {
        d = {
          group = "media-writers";
          mode = "0775";
          user = "root";
        };
      };
    };
  };
  # We are gonna set up an NFS server with anonuid and all_squash, which means
  # we don't care about the ID of whoever is accessing it we're just gonna
  # consider them as having this particular UID.
  # Create a user that we can use for this purpose, this way we know what the
  # UID means.
  users.users.nfs-media = {
    isSystemUser = true;
    group = "nfs-media";
    uid = 900;
  };
  users.groups.nfs-media.gid = 900;
  # WARNING: no_subtree_check means that if you know an inode number you can
  # leak files from outside of the exported directories (from the same
  # filesystem). Hopefully this is OK since we are restricting access to stuff
  # local to the LAN...?
  services.nfs.server = {
    enable = true;
    exports =
      let
        uid = builtins.toString config.users.users.nfs-media.uid;
        gid = builtins.toString config.users.groups.nfs-media.gid;
      in
      # WARNING: The path of this export is coupled with the client
      # configuration. If you change it you'll need to update the users too.
      ''
        /mnt/nas/media 192.168.0.0/16(ro,all_squash,anonuid=${uid},anongid=${gid},no_subtree_check)
      '';
  };
  networking.firewall.allowedTCPPorts = [ 2049 ];
}
