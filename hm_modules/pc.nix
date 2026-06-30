# Stuff for a computer with a keyboard and screens.
{ config, osConfig, ... }:
{
  imports = [
    ./sway.nix
    ./monitors.nix
    ./agent-host-context.nix
  ];

  bjackman.agentHostContext = ''
    # Operating on this host

    This is one of my personal NixOS workstations
    (${osConfig.networking.hostName}), configured from the "boxen" flake checked
    out at `${config.bjackman.configCheckout}`, if you need to understand how
    the system is set up you can read that config.

    On NixOS I tend not to install much into the global environment, e.g. you
    might find that there's no `python3` in $PATH. But, you are free to run
    stuff from nixpkgs. This is a fully flake-based system so you can do that
    with `nix run nixpkgs#<package>`. If you need the latest version, use `nix
    run nixpkgs-unstable#<package>` instead. You can also use `nix shell
    nixpkgs#<package> -c <command>` to run commands in a shell that has the
    package installed.
    
    My default shell is Fish, you can just use Fish syntax if you like or for
    nontrival commands you can just explicitly run them via `bash -c`.
  '';
}
