{
  writeShellApplication,
  git,
  tmux,
  util-linux,
  forgejoSsh ? "ssh://forgejo@pizza:9002",
  owner ? "brendan",
  keyFile ? "/run/agenix/slopbot-ssh-privkey",
}:
writeShellApplication {
  name = "slop";
  runtimeInputs = [
    git
    tmux
    util-linux
  ];
  text = ''
    forgejo_ssh=${forgejoSsh}
    owner=${owner}
    key_file=${keyFile}
  ''
  + builtins.readFile ./slop.sh;
}
