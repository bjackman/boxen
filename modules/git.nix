{ pkgs, ... }:
{
  programs.git = {
    enable = true;

    package = pkgs.gitFull;

    extraConfig = {
      push = {
        default = "upstream";
        autoSetupRemote = true;
      };

      diff = {
        renames = "true";
        mnemonicPrefix = "true";
        wsErrorHighlight = "all";
        tool = "meld";
        algorithm = "histogram";
        colorMoved = "plain";
      };

      help.autocorrect = 3;

      color.ui = "true";

      rebase = {
        autosquash = "true";
        updateRefs = "true";
      };

      branch.sort = "-committerdate";
      tag.sort = "version:refname";

      rerere = {
        enabled = 1;
        autoUpdate = "true";
      };

      checkout.workers = 0; # Use num_cpu

      column.ui = "auto";

      fetch.prune = "true";

      merge.conflictStyle = "zdiff3";

      init.defaultBranch = "master";
    };

    aliases = {
      lgg = "log --color --graph --pretty=format:'%Cred%h%Creset -%C(yellow)%d%Creset %s %Cgreen(%cr) %C(bold blue)<%an>%Creset'";
      lg = "log --color --pretty=format:'%Cred%h%Creset -%C(yellow)%d%Creset %s %Cgreen(%cr) %C(bold blue)<%an>%Creset'";
      uncommit = "reset HEAD@{1}";
    };
  };
}
