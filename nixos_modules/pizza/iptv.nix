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
# 233.50.230.0/24, port 5000) over the WAN. The FritzBox proxies the multicast
# onto the LAN via IGMP. Only Pizza ever joins the multicast group: the LG TV
# pulls an ordinary HTTP stream from Jellyfin, Jellyfin pulls from TVHeadend's
# HTTP playlist, and TVHeadend is what actually joins the group and demuxes it.
#
# This module provides three things, all still required under that topology:
#
# 1. The firewall rule below. The multicast floods in fine on enp0s31f6, but the
#    default-drop INPUT policy silently eats it before it reaches TVHeadend's
#    socket (tcpdump sees the packets because it taps before the firewall; the
#    application doesn't). Getting a channel to play AT ALL is purely this rule --
#    reverse-path filtering and FritzBox config are plausible-looking red herrings
#    for the "never plays" symptom.
#
# 2. init7-playlist: regenerates init7.m3u from Init7's live XSPF. TVHeadend's
#    IPTV automatic network reads this M3U to discover channels.
#
# 3. init7-igmp-refresh: a TEMPORARY workaround for a freeze-after-a-few-minutes
#    symptom. Cause (proven by packet capture + a controlled re-join test): the
#    FritzBox proxies the multicast onto the LAN but never sends IGMP General
#    Queries (zero IGMP seen in >125s, a full query interval). Linux only emits a
#    membership report when a socket first joins or when answering a query, so the
#    subscriber's single join-time report ages out of the FritzBox's forwarding
#    table after a couple of minutes and is never renewed -- the multicast stops
#    and the stream freezes mid-play. Confirmed the cure: re-emitting a raw IGMPv2
#    report for the joined group makes forwarding resume instantly and stay up as
#    long as reports keep coming.
#
#    The real fault is the FritzBox's missing querier, and FRITZ!OS exposes no
#    knob for it. The correct fix is a proper IGMP querier on the LAN, which has
#    to live on a box OTHER than Pizza (a host won't answer its own query --
#    tested). That arrives with the UniFi Dream Router 7 (enable IGMP snooping +
#    querier there); once it's in, DELETE init7-igmp-refresh and retest.
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

  # TEMPORARY workaround (see header): re-emit an IGMPv2 membership report every
  # INTERVAL seconds for whatever multicast groups TVHeadend currently has joined,
  # so the FritzBox's forwarding table never ages out. Groups are read live from
  # /proc/net/igmp, so this tracks the active channel with zero coupling to
  # TVHeadend and needs no list of channels. Link-local control groups
  # (224.0.0.0/24) are skipped; everything else multicast is refreshed. Delete
  # this once a real IGMP querier (UniFi Dream Router 7) is on the LAN. stdlib
  # only; a raw IGMP socket needs CAP_NET_RAW (granted in the unit).
  igmpRefresh = pkgs.writeText "init7-igmp-refresh.py" ''
    import socket
    import struct
    import sys
    import time

    iface = sys.argv[1] if len(sys.argv) > 1 else "enp0s31f6"
    interval = int(sys.argv[2]) if len(sys.argv) > 2 else 60

    def joined_groups(dev):
        # Parse /proc/net/igmp: device lines start in column 0, group lines are
        # indented and carry the group as little-endian hex (e.g. D4E632E9).
        groups, cur = [], None
        with open("/proc/net/igmp") as f:
            for line in f:
                if not line[:1].isspace():
                    parts = line.split()
                    cur = parts[1] if len(parts) > 1 else None
                elif cur == dev:
                    tok = line.split()[0]
                    try:
                        b = bytes.fromhex(tok)
                    except ValueError:
                        continue
                    if len(b) == 4:
                        groups.append(socket.inet_ntoa(b[::-1]))
        return groups

    def wanted(ip):
        first = int(ip.split(".")[0])
        return 224 <= first <= 239 and not ip.startswith("224.0.0.")

    def v2_report(group):
        body = struct.pack("!BBH4s", 0x16, 0, 0, socket.inet_aton(group))
        if len(body) % 2:
            body += b"\x00"
        s = 0
        for i in range(0, len(body), 2):
            s += (body[i] << 8) + body[i + 1]
        s = (s >> 16) + (s & 0xFFFF)
        s += s >> 16
        cksum = (~s) & 0xFFFF
        return struct.pack("!BBH4s", 0x16, 0, cksum, socket.inet_aton(group))

    raw = socket.socket(socket.AF_INET, socket.SOCK_RAW, socket.IPPROTO_IGMP)
    ifindex = socket.if_nametoindex(iface)
    raw.setsockopt(socket.IPPROTO_IP, socket.IP_MULTICAST_IF,
                   struct.pack("4s4si", b"\x00" * 4, b"\x00" * 4, ifindex))
    raw.setsockopt(socket.IPPROTO_IP, socket.IP_MULTICAST_TTL, 1)

    while True:
        targets = [g for g in joined_groups(iface) if wanted(g)]
        for g in targets:
            raw.sendto(v2_report(g), (g, 0))
        if targets:
            print("refreshed:", ", ".join(targets), flush=True)
        time.sleep(interval)
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

  # TEMPORARY: keep the FritzBox forwarding the multicast by refreshing IGMP
  # membership reports for the active channel. Remove once the UniFi Dream
  # Router 7 is the LAN's IGMP querier (see header).
  systemd.services.init7-igmp-refresh = {
    description = "Refresh IGMP membership for Init7 multicast (FritzBox querier workaround)";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      ExecStart = "${pkgs.python3}/bin/python3 ${igmpRefresh} enp0s31f6 60";
      Restart = "always";
      RestartSec = "5s";
      # Raw IGMP socket; nothing else is needed.
      DynamicUser = true;
      AmbientCapabilities = [ "CAP_NET_RAW" ];
      CapabilityBoundingSet = [ "CAP_NET_RAW" ];
      NoNewPrivileges = true;
      ProtectSystem = "strict";
      ProtectHome = true;
      ProtectKernelTunables = true;
      ProtectControlGroups = true;
      RestrictAddressFamilies = [ "AF_INET" ];
      SystemCallFilter = [ "@system-service" ];
    };
  };

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
