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
  systemctl = "${config.systemd.package}/bin/systemctl";
  greeterSettingsPath = pkgs.writeText "GreeterSettings.qml" ''
    pragma Singleton

    import Quickshell

    Singleton {
        readonly property string hostName: ${builtins.toJSON config.networking.hostName}
        readonly property string userName: "brendan"
        readonly property list<string> sessionCommand: ${builtins.toJSON [ "${sway}/bin/sway" ]}
        readonly property list<string> powerOffCommand: ${builtins.toJSON [ systemctl "poweroff" ]}
        readonly property list<string> rebootCommand: ${builtins.toJSON [ systemctl "reboot" ]}
    }
  '';
  greeterConfigDir = pkgs.runCommand "quickshell-greeter" { } ''
    mkdir $out
    cp ${../nixos_files/greeter}/*.qml $out/
    for f in Theme Bevel PushButton BarText Icons; do
      cp ${../hm_files/common/quickshell}/$f.qml $out/
    done
    cp ${greeterSettingsPath} $out/GreeterSettings.qml
  '';
  wallpaperPath = ../hm_files/common/clouds_95-4k.png;
  greeterSwayConfigPath = pkgs.writeText "greeter-sway-config" ''
    xwayland disable
    swaybg_command ${lib.getExe pkgs.swaybg}
    output * bg ${wallpaperPath} fill
    exec ${lib.getExe kanshiCfg.package} --config ${kanshiConfigPath}
    exec "${lib.getExe pkgs.quickshell} --path ${greeterConfigDir}; ${sway}/bin/swaymsg exit"
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
  fonts.packages = with pkgs; [
    # For bzmenu/pwmenu
    nerd-fonts.symbols-only
    # For the greeter's icons.
    font-awesome
  ];

  # Run the greeter under sway so it gets the same output layout as the session.
  services.greetd = {
    enable = true;
    settings.default_session.command = "${sway}/bin/sway --config ${greeterSwayConfigPath}";
  };
}
