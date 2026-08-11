{ pkgs, ... }:
{
  # MagicDNS only starts answering once tailscaled has finished coming up on the
  # network, which lags the unit going active - most visibly when a config
  # switch restarts tailscaled underneath units that are being started in the
  # same transaction. Ordering after tailscaled.service isn't enough for
  # anything that reaches another node by name; require an instance of this
  # instead, e.g. x-systemd.requires=magicdns-ready@norte.service.
  systemd.services."magicdns-ready@" = {
    description = "Wait for MagicDNS to resolve %I";
    requires = [ "tailscaled.service" ];
    after = [ "tailscaled.service" ];
    scriptArgs = "%I";
    script = ''
      until ${pkgs.getent}/bin/getent hosts "$1" >/dev/null; do
        sleep 1
      done
    '';
    serviceConfig = {
      Type = "oneshot";
      # Deliberately not RemainAfterExit: a later tailscaled restart would leave
      # it active but stale, and re-checking costs one getent when DNS is up.
      TimeoutStartSec = "90s";
    };
  };
}
