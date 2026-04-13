{
  imports = [
    ./jackmanb.nix
    ./sashiko.nix
  ];

  bjackman.sashiko.enable = true;

  accounts.email.accounts.corp = {
    address = "jackmanb@google.com";
    realName = "Brendan Jackman";
    primary = true;
    aerc.extraAccounts.outgoing = "/usr/bin/sendgmr -i";
  };
  lkml = {
    enable = true;
    accountRef = "corp";
  };
}
