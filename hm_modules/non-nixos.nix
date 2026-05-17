{
  pkgs,
  config,
  nixpkgs, # from specialArgs
  ...
}:
{
  bjackman.appConfigDirs.fish = [ ../hm_files/non_nixos/config/fish ];

  # Set up the flake registry for nixpkgs to point to the version used by this
  # configuration, which means you can do `nix run nixpkgs#foo` and not have to
  # download the latest unstable nixpkgs.
  # IIRC this happens automatically at the system level on NixOS, I need to
  # figure out how that works to see if there's a way to avoid the nixpkgs
  # special arg here.
  nix.registry.nixpkgs.flake = nixpkgs;

  systemd.user.systemctlPath = "/usr/bin/systemctl";

  bjackman.nix-warmups = [
    # Note this might not actually be the configuration we're currently
    # building (e.g. we might be building a config named $USER@$HOST). But
    # this is probably similar enough that it's helpful to have it warm.
    "github:bjackman/boxen/master#homeConfigurations.${config.home.username}.activationPackage"
  ];

  targets.genericLinux.enable = true;

  # Desktop entry to run VS Code forcing native Wayland mode, with a workaround
  # flag to make fractional scaling work.
  # According to Gemini, VS Code does have a native way to configure these flags
  # but the maintainers have advised against relying on that for the Wayland
  # setup because of the way Electron initialisation happens.
  xdg.desktopEntries.vscode-wayland = {
    name = "Visual Studio Code (Wayland)";
    genericName = "Text Editor`";
    exec = "code --enable-features=UseOzonePlatform,WaylandWindowDecorations --disable-features=WaylandFractionalScaleV1 --ozone-platform-hint=auto --unity-launch .config/home-manager";
    terminal = false;
    categories = [ "Development" "TextEditor" "IDE" ];
    icon = "code";
    settings = {
      StartupNotify = "true";
      Keywords = "vscode;vs;code;";
    };
  };
}
