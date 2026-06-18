{ pkgs, ... }:
# Init7 TV7 IPTV -> Jellyfin Live TV. Deliberately MINIMAL: I really only ever
# watch SRF zwei, so this is the dumbest thing that works.
#
# How Init7 TV works: channels are delivered as IPv4 multicast UDP (group
# 233.50.230.0/24, port 5000) over the WAN. The FritzBox proxies the multicast
# onto the LAN via IGMP. Crucially, only Pizza ever joins the multicast group --
# the LG TV just pulls an ordinary HTTP stream from Jellyfin, and Jellyfin's
# "M3U tuner" runs ffmpeg under the hood to join the group and remux out to the
# client. SRF zwei is plain H.264 720p50 + AC-3, which the LG direct-plays, so
# normally nothing even transcodes.
#
# The ONLY thing that actually needs configuring on the host is the firewall
# rule below. The multicast floods in fine on enp0s31f6, but the default-drop
# INPUT policy silently eats it before it reaches ffmpeg's socket (tcpdump sees
# the packets because it taps before the firewall; the application doesn't).
# That one rule is the whole fix -- it is NOT an IGMP, reverse-path, or FritzBox
# problem, despite all of those being plausible-looking red herrings.
#
# Why not TVHeadend? TVHeadend is the "proper" IPTV backend and would be the
# right call if I watched real amounts of TV: it grabs EPG straight from the
# stream's embedded EIT tables (no external XMLTV to wrangle), filters out the
# junk PIDs Init7 ships (SCTE-35 / teletext / data streams), maintains a single
# shared multicast subscription, and does DVR/timeshift. But it's a second
# stateful service with its own web-UI-driven config and its own data dir to
# persist through impermanence -- not worth it for one channel. If that ever
# changes, TVHeadend slots in as a backend behind Jellyfin's native TVHeadend
# tuner type.
#
# Remaining manual step (one-off, in the Jellyfin web UI, since Live TV config
# is not declaratively expressible via jellarr):
#   Dashboard -> Live TV -> Tuner Devices -> Add -> "M3U Tuner"
#   File or URL: /var/lib/jellyfin-iptv/init7.m3u
# EPG is skipped on purpose; for a single live channel the guide adds nothing.
let
  playlistDir = "/var/lib/jellyfin-iptv";
  playlist = "${playlistDir}/init7.m3u";

  # Init7's canonical, always-current channel list. A channel's multicast group
  # changes over time (SRF zwei moved from .2 to .212 and cost me an evening of
  # debugging), so refetch this rather than hardcoding a udp:// URL.
  xspfUrl = "http://api.init7.net/tvchannels.xspf";

  # Convert Init7's XSPF into the M3U that Jellyfin's tuner wants. stdlib only,
  # written to a file (rather than pkgs.writers.writePython3) to avoid its
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
    description = "Generate Init7 IPTV M3U for Jellyfin from the live XSPF";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.python3}/bin/python3 ${xspfToM3u} ${xspfUrl} ${playlist}";
      StateDirectory = "jellyfin-iptv";
      # The generated file is read by Jellyfin, a separate service/user.
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
