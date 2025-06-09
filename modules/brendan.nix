{ ... }:
{
  home = {
    username = "brendan";
    homeDirectory = "/home/brendan";
  };

  accounts.email.accounts.work = {
    address = "jackmanb@google.com";
    realName = "Brendan Jackman";
    primary = true;
  };
  # This tells the lkml module to update the rest of the account defined above.
  lkml.accountName = "work";
}
