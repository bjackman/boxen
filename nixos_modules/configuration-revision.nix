{
  lib,
  config,
  self,
  ...
}:
let
  revision = config.bjackman.configurationRevision;
in
{
  options.bjackman.configurationRevision = lib.mkOption {
    type = lib.types.nullOr lib.types.str;
    default = self.shortRev or self.dirtyRev or "dirty";
    description = ''
      Commit of this flake the system was built from, written to
      configuration-revision in the system's top level.
    '';
  };

  # Not system.configurationRevision: nixos-version bakes that in, which puts it
  # in system-path and so rebuilds most of the system for every commit. Here
  # only the top level changes.
  config.system.systemBuilderCommands = lib.mkIf (revision != null) ''
    echo -n ${lib.escapeShellArg revision} > $out/configuration-revision
  '';
}
