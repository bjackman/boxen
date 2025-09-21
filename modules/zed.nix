{ ... }:
{
  programs.zed-editor = {
    enable = true;
    # Don't install it - I'll take care of that separately (probably via
    # Flatpak) since I'm not using NixOS and installing graphical programs
    # from Nix is a pain.
    package = null;
    userSettings = {
      vim_mode = true;
      base_keymap = "VSCode";
    };
    userKeymaps = [
      {
        context = "Workspace";
        bindings = {
          "ctrl-x 2" = "pane::SplitVertical";
          "ctrl-x 1" = "pane::JoinAll";
          "ctrl-x k" = "pane::CloseActiveItem";
        };
      }
      {
        context = "Editor";
        bindings = {
          "ctrl-f" = "buffer_search::Deploy";
          "alt-." = "editor::GoToDefinition";
          "ctrl-t" = "pane::GoBack";
          "ctrl-d" = "editor::SelectNext";
          "ctrl-v" = "vim::Paste";
          "ctrl-x" = null;
          "ctrl-x o" = "workspace::ActivateNextPane";
          "ctrl-x r" = "editor::ReloadFile";
          "ctrl-c /" = "editor::ToggleComments";
          "alt-?" = "editor::FindAllReferences";
          "ctrl-R" = ["projects::OpenRecent" {create_new_window = false;}];
        };
      }
    ];
  };
}
