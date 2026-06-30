{ pkgs, ... }:
# Init7 TV7 IPTV: the network-level glue for receiving Init7's multicast and
# generating the channel list. The actual IPTV backend is TVHeadend
# (tvheadend.nix), which reads the M3U this module generates, joins the
# multicast, demuxes each channel and re-streams a clean TS to Jellyfin. We need
# TVHeadend in front of Jellyfin because Init7 ships junk PIDs (SCTE-35 / data
# streams) that make Jellyfin mis-probe some channels like ITV; see tvheadend.nix
# for the full diagnosis.
#
# How Init7 TV works: channels are delivered as IPv4 multicast UDP (group
# 233.50.230.0/24, port 5000) over the WAN. The UniFi Dream Router 7 routes the
# multicast onto the LAN via its IGMP proxy (see the UDR7 dependency note below).
# Only Pizza ever joins the multicast group: the LG TV pulls an ordinary HTTP
# stream from Jellyfin, Jellyfin pulls from TVHeadend's HTTP playlist, and
# TVHeadend is what actually joins the group and demuxes it.
#
# This module provides two things:
#
# 1. The firewall rule below. The multicast floods in fine on enp0s31f6, but the
#    default-drop INPUT policy silently eats it before it reaches TVHeadend's
#    socket (tcpdump sees the packets because it taps before the firewall; the
#    application doesn't). Getting a channel to play AT ALL is purely this rule --
#    reverse-path filtering and upstream-router config are plausible-looking red
#    herrings for the "never plays" symptom.
#
# 2. init7-playlist: regenerates init7.m3u from Init7's live XSPF. TVHeadend's
#    IPTV automatic network reads this M3U to discover channels.
#
# UDR7 dependency (NOT captured in this repo -- it lives in the router's own
# state, so a factory-reset will silently break IPTV): the Dream Router 7 must
# route Init7's WAN multicast onto the LAN. Required config:
#   - enable IGMP Snooping on the LAN network (Settings -> Networks -> Default);
#   - mark the Init7 WAN (Internet 2) as the IGMP-proxy upstream:
#       igmp_proxy_upstream=true, igmp_proxy_for="all"
#     This has no UI control -- set it via the controller API
#     (PUT /proxy/network/api/s/default/rest/networkconf/<wan _id>).
# Without it the multicast never reaches enp0s31f6 and nothing plays.
#
# History: this replaced a FritzBox, which proxied the multicast itself but --
# because FRITZ!OS never sent IGMP General Queries -- let the subscriber's
# membership age out of its forwarding table, freezing the stream after a couple
# of minutes. That needed an init7-igmp-refresh service (re-emitting IGMPv2
# reports) as a workaround. The UDR7's igmpproxy queries its downstream itself,
# so that hack is gone (removed 2026-06-30).
#
# Jellyfin's tuner points at TVHeadend, not this M3U directly (manual one-off in
# the Jellyfin web UI, since Live TV config isn't expressible via jellarr):
#   Dashboard -> Live TV -> Tuner Devices -> Add -> "M3U Tuner"
#   File or URL: http://127.0.0.1:9981/playlist/channels.m3u
# EPG is not set up yet (deferred); until it is, Jellyfin's guide will be empty.
let
  playlistDir = "/var/lib/jellyfin-iptv";
  playlist = "${playlistDir}/init7.m3u";

  # Init7's canonical, always-current channel list. A channel's multicast group
  # changes over time (SRF zwei moved from .2 to .212 and cost me an evening of
  # debugging), so refetch this rather than hardcoding a udp:// URL.
  xspfUrl = "http://api.init7.net/tvchannels.xspf";

  # Convert Init7's XSPF into the M3U that TVHeadend's IPTV network reads. stdlib
  # only, written to a file (rather than pkgs.writers.writePython3) to avoid its
  # build-time flake8 linting.
  xspfToM3u = pkgs.writeText "init7-xspf-to-m3u.py" ''
    import sys
    import urllib.request
    import xml.etree.ElementTree as ET

    NS = "{http://xspf.org/ns/0/}"
    url, out_path = sys.argv[1], sys.argv[2]

    data = urllib.request.urlopen(url, timeout=30).read()
    root = ET.fromstring(data)

    lines = ["#EXTM3U"]
    for track in root.iter(NS + "track"):
        loc = track.find(NS + "location")
        title = track.find(NS + "title")
        if loc is None or not (loc.text or "").strip():
            continue
        name = (title.text if title is not None else "") or "Unknown"
        lines.append('#EXTINF:-1 tvg-name="' + name + '",' + name)
        lines.append(loc.text.strip())

    with open(out_path, "w") as f:
        f.write("\n".join(lines) + "\n")
    print("wrote", len(lines) // 2, "channels to", out_path)
  '';
in
{
  # THE fix. Scoped to the multicast address space + port 5000 so it survives
  # Init7 renumbering channels, while never exposing any unicast service.
  networking.firewall.extraCommands = ''
    iptables -A nixos-fw -p udp -d 224.0.0.0/4 --dport 5000 -j nixos-fw-accept
  '';
  networking.firewall.extraStopCommands = ''
    iptables -D nixos-fw -p udp -d 224.0.0.0/4 --dport 5000 -j nixos-fw-accept || true
  '';

  # Keep the M3U fresh from Init7's live playlist.
  systemd.services.init7-playlist = {
    description = "Generate Init7 IPTV M3U for TVHeadend from the live XSPF";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.python3}/bin/python3 ${xspfToM3u} ${xspfUrl} ${playlist}";
      StateDirectory = "jellyfin-iptv";
      # The generated file is read by TVHeadend, a separate service/user.
      UMask = "0022";
    };
  };
  systemd.timers.init7-playlist = {
    description = "Refresh Init7 IPTV M3U daily";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "2min";
      OnCalendar = "daily";
      Persistent = true;
    };
  };
}
