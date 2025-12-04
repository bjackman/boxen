{
  pkgs,
  ...
}:
{
  home.packages = [
    pkgs.bjackman.spellcheck_commitmsg
    pkgs.bjackman.spellcheck_commitmsgs
  ];
}
