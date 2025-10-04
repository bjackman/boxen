{
  pkgs,
  ...
}:
{
  # Hard to be sure how much of this is really necessary and how
  # much is missing. The dconf bit seemed to be the thing that did the trick
  # for Firefox and wofi. This is largely taken from
  # https://www.reddit.com/r/NixOS/comments/18hdool/how_do_i_set_a_global_dark_theme_and_configure_gtk/
  # Some other bits come from Claude, I don't know where it cribbed those from.
  gtk = {
    enable = true;
    theme = {
      name = "Adwaita-dark";
      package = pkgs.gnome-themes-extra;
    };
    gtk3.extraConfig.gtk-application-prefer-dark-theme = 1;
    gtk4.extraConfig.gtk-application-prefer-dark-theme = 1;
  };
  qt = {
    enable = true;
    platformTheme.name = "adwaita";
    style = {
      name = "adwaita-dark";
      package = pkgs.adwaita-qt;
    };
  };
  home.packages = with pkgs; [
    adwaita-qt6
    qgnomeplatform-qt6
  ];
  dconf.settings = {
    "org/gnome/desktop/interface" = {
      color-scheme = "prefer-dark";
      gtk-theme = "Adwaita-dark";
    };
  };
}
