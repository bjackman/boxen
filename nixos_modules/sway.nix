{
  pkgs,
  config,
  lib,
  ...
}:
let
  sway = config.programs.sway.package;
  kanshiCfg = config.home-manager.users.brendan.services.kanshi;
  kanshiConfigPath = config.home-manager.users.brendan.xdg.configFile."kanshi/config".source;
  greeterSwayConfigPath = pkgs.writeText "greeter-sway-config" ''
    xwayland disable
    exec ${lib.getExe kanshiCfg.package} --config ${kanshiConfigPath}
    exec "${lib.getExe config.programs.regreet.package}; ${sway}/bin/swaymsg exit"
  '';
in
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
  # For bzmenu/pwmenu
  fonts.packages = with pkgs; [ nerd-fonts.symbols-only ];

  # Run the greeter under sway so it gets the same output layout as the session.
  programs.regreet.enable = true;
  services.greetd.settings.default_session.command = lib.concatStringsSep " " [
    "${pkgs.coreutils}/bin/env"
    "XDG_DATA_DIRS=${config.services.displayManager.sessionData.desktops}/share"
    "${sway}/bin/sway --config ${greeterSwayConfigPath}"
  ];
  bjackman.impermanence.extraPersistence.directories = [ "/var/lib/regreet" ];
}
