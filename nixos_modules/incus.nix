{ pkgs, ... }:
let
  dhcpPorts = [
    53
    67
  ];
in
{
  imports = [ ./impermanence.nix ];

  # Incus only supports nftables on NixOS.
  networking.nftables.enable = true;

  virtualisation.incus = {
    enable = true;
    preseed = {
      networks = [
        {
          config = {
            "ipv4.address" = "10.0.100.1/24";
            "ipv4.nat" = "true";
            "dns.domain" = "incus";
          };
          name = "incusbr0";
          type = "bridge";
        }
      ];
      profiles = [
        {
          devices = {
            eth0 = {
              name = "eth0";
              network = "incusbr0";
              type = "nic";
            };
            root = {
              path = "/";
              pool = "default";
              size = "64GiB";
              type = "disk";
            };
          };
          name = "default";
        }
      ];
      storage_pools = [
        {
          config = {
            source = "/var/lib/incus/storage-pools/default";
          };
          driver = "dir";
          name = "default";
        }
      ];
    };
  };

  bjackman.impermanence.extraPersistence.directories = [ "/var/lib/incus" ];

  networking.firewall.interfaces.incusbr0 = {
    allowedTCPPorts = dhcpPorts;
    allowedUDPPorts = dhcpPorts;
  };

  users.users.brendan.extraGroups = [ "incus-admin" ];

  # Want resolved so that the dns.domain setting of the bridge network
  services.resolved.enable = true;
  # https://linuxcontainers.org/incus/docs/main/howto/network_bridge_resolved/#make-the-resolved-configuration-persistent
  systemd.services."incus-dns-config" = {
    description = "Incus per-link DNS configuration for incusbr0";
    bindsTo = [ "sys-subsystem-net-devices-incusbr0.device" ];
    after = [ "sys-subsystem-net-devices-incusbr0.device" ];
    wantedBy = [ "sys-subsystem-net-devices-incusbr0.device" ];

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = [
        "${pkgs.systemd}/bin/resolvectl dns incusbr0 10.0.100.1"
        "${pkgs.systemd}/bin/resolvectl domain incusbr0 ~incus"
        "${pkgs.systemd}/bin/resolvectl dnssec incusbr0 off"
        "${pkgs.systemd}/bin/resolvectl dnsovertls incusbr0 off"
      ];
      ExecStopPost = "${pkgs.systemd}/bin/resolvectl revert incusbr0";
    };
  };
}
