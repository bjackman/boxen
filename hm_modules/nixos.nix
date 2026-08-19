{
  config,
  osConfig,
  ...
}:
{
  imports = [
    ./nix-warmup.nix
    ./agent-host-context.nix
  ];

  bjackman.appConfigDirs.fish = [ ../hm_files/nixos/config/fish ];
  bjackman.configCheckout = "${config.home.homeDirectory}/src/boxen";

  bjackman.nix-warmups = [
    "github:bjackman/boxen/master#nixosConfigurations.${osConfig.networking.hostName}.config.system.build.toplevel"
  ];

  bjackman.agentHostContext = ''
    You're running on a NixOS host. I tend not to install much into the global
    environment, e.g. you might find that there's no `python3` in $PATH. But,
    you are free to run stuff from nixpkgs. This is a fully flake-based system
    so you can do that with `nix run nixpkgs#<package>`. If you need the latest
    version, use `nix run nixpkgs-unstable#<package>` instead. You can also use
    `nix shell nixpkgs#<package> -c <command>` to run commands in a shell that
    has the package installed.
  '';
}
