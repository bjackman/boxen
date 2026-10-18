# Units on pizza that evaluate whole NixOS configs. Evaluation is the expensive
# phase and it grows with the flake, so throttle before Gerrit's JVM feels it
# and die before the OOM killer gets to choose. A unit that failed is an alert;
# a JVM that was picked instead is a lost review queue. See gerrit_ci.md.
#
# These bound only the evaluation: builds run in nix-daemon, outside the unit.
{ lib, config, ... }:
let
  limits = {
    MemoryHigh = "3G";
    MemoryMax = "4G";
    # MemoryMax doesn't count swap, so without this the unit swaps its way past
    # it and fills the host's swap instead of dying.
    MemorySwapMax = "2G";
    # It can't use them - evaluation is the bottleneck and it's single-threaded
    # - and Jellyfin can.
    CPUQuota = "400%";
    Nice = 10;
    IOSchedulingClass = "idle";
  };
in
{
  systemd.services.gerrit-ci = lib.mkIf config.bjackman.gerritCi.enable {
    serviceConfig = limits;
  };
}
