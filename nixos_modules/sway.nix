{
  config,
  ...
}:
{
  assertions = [
    {
      assertion =
        let
          # Note I'm lazy here, not sure if this is actually the right way to
          # check the driver in use, if you think you're using Nouveau but this is
          # still failing, you might be right.
          hasNvidiaDriver = builtins.elem "nvidia" config.services.xserver.videoDrivers;
          hasUnsupportedGpuFlag = builtins.elem "--unsupported-gpu" config.programs.sway.extraOptions;
        in
        !hasNvidiaDriver || hasUnsupportedGpuFlag;
      message = ''
        Sway hates the Nvidia drivers and will refuse to run without --unsupported-gpu
        flag unless you use Nouveau.
      '';
    }
  ];
  programs.sway = {
    enable = true;
    wrapperFeatures.gtk = true;
  };
}
