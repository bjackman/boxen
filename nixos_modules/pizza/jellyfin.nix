{ ... }:
{
  imports = [
    ../jellyfin.nix
  ];

  services.declarative-jellyfin = {
    enable = true;
    system.serverName = "Pizza";
    serverId = "4cf5ccb385ba49dba3c77f902a6cbb5b"; # uuidgen -r | sed 's/-//g'
    # This bit means I have an Intel GPU.
    encoding = {
      hardwareAccelerationType = "qsv";
      # These next bits might be wrong, I'm trusting Gemini here.
      # lspci says: Intel Corporation UHD Graphics 620
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
      allowAv1Encoding = false; # UHD 620 cannot encode or decode AV1
    };
  };
}
