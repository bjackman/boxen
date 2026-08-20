# The probe client and server, built from the go-tools module but packaged
# separately: the server runs on homelab hosts, which have no business
# depending on the closure of the tools that drive Claude Code.
{
  buildGoModule,
  lib,
  makeWrapper,
  openssh,
  sshUser ? "slopbot",
  keyFile ? "/run/agenix/slopbot-probe-ssh-privkey",
  knownHostsFile ? "/etc/ssh/ssh_known_hosts",
  hosts ? [
    "pizza"
    "norte"
  ],
}:
buildGoModule {
  pname = "slop-probe";
  version = "0.1.0";
  src = ./.;
  vendorHash = null;

  subPackages = [
    "cmd/slop-probe"
    "cmd/slop-probe-server"
  ];

  nativeBuildInputs = [ makeWrapper ];

  # See slop-tools.nix on why these are flags and not ldflags.
  flags = lib.escapeShellArgs [
    "--ssh-user=${sshUser}"
    "--key-file=${keyFile}"
    "--known-hosts-file=${knownHostsFile}"
    "--hosts=${lib.concatStringsSep "," hosts}"
  ];

  postFixup = ''
    wrapProgram $out/bin/slop-probe --add-flags "$flags" \
      --prefix PATH : ${lib.makeBinPath [ openssh ]}
  '';
}
