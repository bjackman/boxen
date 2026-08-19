{
  config,
  lib,
  pkgs,
  homelab,
  ...
}:
{
  imports = [ ./lkml.nix ];

  age.secrets.migadu-linuxdev-password.file = ../secrets/migadu-linuxdev-password.age;
  accounts.email.accounts.linuxdev = rec {
    address = "brendan.jackman@linux.dev";
    realName = "Brendan Jackman";
    primary = lib.mkDefault true;
    aerc.extraAccounts = {
      outgoing = "smtps://brendan.jackman%40linux.dev@smtp.migadu.com:465";
      outgoing-cred-cmd = "cat ${config.age.secrets.migadu-linuxdev-password.path}";
    };
    userName = address;
    passwordCommand = "cat ${config.age.secrets.migadu-linuxdev-password.path}";
    imap.host = "imap.migadu.com";
    mbsync = {
      enable = true;
      create = "maildir";
    };
  };
  programs.mbsync.enable = true;
  services.mbsync = {
    enable = true;
    postExec = "${pkgs.notmuch}/bin/notmuch new";
    # Alternative: use services.imapnotify to trigger mbsync immediately when
    # there are new messages. But, seems fiddly, for now just run it often
    frequency = "minutely";
  };

  lkml = {
    enable = true;
    accountRef = lib.mkDefault "linuxdev";
    # Don't work here any more but still care about email sent to this address.
    extraAddresses = [ "jackmanb@google.com" ];
    tagsRepoUrl =
      # Not the iap fqdn: that resolves to the public IP, where only Caddy
      # (HTTPS) is exposed - Gerrit's SSH server is tailnet-only.
      let
        gerrit = homelab.servers.gerrit;
      in
      "ssh://brendan@${gerrit.networking.hostName}:${toString gerrit.bjackman.ports.gerrit-ssh.port}/lkml-tags";
  };
}
