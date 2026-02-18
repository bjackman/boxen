# Started hacking this together to have a VM a bit like stapelberg's to run LLM
# coding agents. Goal was to have something that worked in Google corp. But, I
# forgot that you aren't supposed to run VMs in Google corp. Authing with corp
# credentials on a non-Corp device (VM) is not supported. Gave up.
{
  lib,
  pkgs,
  inputs,
  username,
  slopSrc,
  ...
}:
let
  nixosConfig = inputs.nixpkgs.lib.nixosSystem {
    inherit (pkgs.stdenv.hostPlatform) system;

    modules = [
      inputs.microvm.nixosModules.microvm
      (
        { config, ... }:
        {
          system.stateVersion = lib.trivial.release;
          networking.hostName = "slopbox";

          microvm = {
            # Must use QEMU: Firecracker doesn' support virtiofs, CHV doesn't
            # support SLIRP networking.
            hypervisor = "qemu";
            mem = 8192;
            vcpu = 8;
            socket = null;
            writableStoreOverlay = "/nix/.rw-store";
            shares = [
              {
                tag = "ro-store";
                source = "/nix/store";
                mountPoint = "/nix/.ro-store";
              }
              {
                tag = "src";
                source = slopSrc;
                mountPoint = "/src";
                securityModel = "mapped";
              }
            ];
            interfaces = [
              {
                type = "user";
                id = "usernet";
                mac = "02:00:00:00:00:01";
              }
            ];
            volumes = [
              {
                image = "nix-store-overlay.img";
                mountPoint = config.microvm.writableStoreOverlay;
                size = 2048;
              }
            ];
            qemu.extraArgs = [
              "-device"
              "vhost-vsock-pci,guest-cid=101"
            ];
          };

          users.users.${username} = {
            isNormalUser = true;
            home = "/home/${username}";
            extraGroups = [ "wheel" ];
            initialHashedPassword = "";
          };
          security.sudo.wheelNeedsPassword = false;
          services.getty.autologinUser = username;

          services.openssh = {
            enable = true;
            settings.PermitEmptyPasswords = "yes";
          };
          security.pam.services.sshd.allowNullPassword = true;

          environment.systemPackages = with pkgs; [
            coreutils
            curl
            findutils
            gawk
            git
            gnugrep
            gnused
            util-linux
          ];

          nix.settings.experimental-features = [
            "nix-command"
            "flakes"
            "local-overlay-store"
            "read-only-local-store"
          ];
        }
      )
    ];
  };
in
nixosConfig.config.microvm.declaredRunner
