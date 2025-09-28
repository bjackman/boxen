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
}
