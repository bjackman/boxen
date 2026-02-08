{ ... }:
{
  imports = [
    ../jellyfin.nix
  ];

  services.jellarr.config = {
    encoding = {
      enableHardwareEncoding = true;
      # Intel graphics.
      hardwareAccelerationType = "qsv";
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
      allowHevcEncoding = true;
      allowAv1Encoding = false; # UHD 620 cannot encode or decode AV1 (says Gemini)
    };
    library = {
      virtualFolders = [
        {
          name = "Radarr Movies";
          collectionType = "movies";
          libraryOptions = {
            pathInfos = [ { path = "/mnt/nas-media/radarr"; } ];
          };
        }
      ];
    };
  };

  systemd.services.jellyfin.serviceConfig.SupplementaryGroups = [ "nas-media" ];
}
