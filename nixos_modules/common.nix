{
  ...
}:
{
  # Set up the default soft ulimit for open
  # file descriptors. Without this I've run into "too many open files" during
  # Nix builds.
  # This is taken from
  # https://discourse.nixos.org/t/unable-to-fix-too-many-open-files-error/27094/7
  # Claude instead suggested security.pam.loginLimits like in:
  # https://discourse.nixos.org/t/unable-to-fix-too-many-open-files-error/27094/10?u=bjackman
  # But that didn't do anything for me for whatever reason.
  systemd.extraConfig = "DefaultLimitNOFILE=65536";
  #
  # This lets you build NixOS for Arm hosts, using binfmt_misc magic and QEMU.
  # You'd think this would be really slow but it's fine in practice because
  # you're mostly getting cache hits.
  boot.binfmt.emulatedSystems = [ "aarch64-linux" ];

  # Run a regular service to optimize the Nix store.
  nix.optimise.automatic = true;

  nix.gc = {
    automatic = true;
    options = "--delete-older-than 30d";
  };
}
