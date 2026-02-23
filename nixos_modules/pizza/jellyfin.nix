{ pkgs, ... }:
{
  imports = [
    ../jellyfin.nix
  ];

  hardware.graphics.enable = true;
  # Tried this to fix an issue, it didn't fix the issue, but these groups do own
  # interesting looking files so whatever maybe it makes sense.
  users.users.jellyfin.extraGroups = [
    "video"
    "render"
  ];

  services.jellarr.config = {
    encoding = {
      enableHardwareEncoding = true;
      # Intel graphics.
      hardwareAccelerationType = "vaapi";
      # This stuff all comes from Gemini, it could definitely be wrong.
      hardwareDecodingCodecs = [
        "h264"
        "hevc"
        "mpeg2video"
        "vc1"
        "vp8"
        "vp9"
      ];
      enableDecodingColorDepth10Hevc = true;
      # AI suggested I enable this when switching to VAAPI, I dunno whatever.
      enableDecodingColorDepth10Vp9 = true;
      allowHevcEncoding = true;
      allowAv1Encoding = false; # UHD 620 cannot encode or decode AV1 (says Gemini)
    };
    library = {
      virtualFolders = [
        {
          name = "Movies";
          collectionType = "movies";
          libraryOptions = {
            pathInfos = [ { path = "/mnt/nas-media/radarr"; } ];
          };
        }
        {
          name = "TV Shows";
          collectionType = "tvshows";
          libraryOptions = {
            pathInfos = [ { path = "/mnt/nas-media/sonarr"; } ];
          };
        }
      ];
    };
    network = {
      knownProxies = [ "127.0.0.1" ];
    };
  };

  systemd.services.jellyfin.serviceConfig.SupplementaryGroups = [ "nas-media" ];
}
