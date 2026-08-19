{
  writeShellApplication,
  git,
  jq,
  openssh,
  tmux,
  util-linux,
  gerritHost ? "pizza",
  gerritPort ? 29418,
  pusher ? "slopbot",
  keyFile ? "/run/agenix/slopbot-ssh-privkey",
}:
writeShellApplication {
  name = "slop";
  runtimeInputs = [
    git
    jq
    openssh
    tmux
    util-linux
  ];
  text = ''
    gerrit_host=${gerritHost}
    gerrit_port=${toString gerritPort}
    pusher=${pusher}
    key_file=${keyFile}
  ''
  + builtins.readFile ./slop.sh;
}
