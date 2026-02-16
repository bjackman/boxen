{
  config,
  pkgsUnstable,
  ...
}:
{
  # Get the description to match the "criteria" from "swaymsg -t get_outputs".

  services.kanshi = {
    enable = true;

    settings = [
      {
        profile = {
          name = "fw13-unplugged";
          outputs = [
            {
              criteria = "BOE NE135A1M-NY1 Unknown";
              scale = 1.5;
            }
          ];
        };
      }
      {
        profile = {
          name = "sandy-office";
          outputs = [
            {
              criteria = "LG Electronics LG ULTRAFINE 508NTGYKX551";
              position = "0,0";
              scale = 1.5;
            }
            {
              criteria = "eDP-1";
              # To the right of the big boi. X is 3840 / 1.5.
              position = "2560,0";
            }
          ];
        };
      }
      {
        profile = {
          name = "home-office";
          outputs = [
            {
              criteria = "Google Inc. P2718EC C9240002";
              # On the left
              position = "0,0";
            }
            {
              criteria = "Dell Inc. DELL P2720DC 81WTK01403MS";
              # To the right of the Google one
              position = "2560,0";
            }
            {
              # This should match both my personal and my work laptop.
              criteria = "eDP-1";
              # Below the Dell one.
              position = "2560,1440";
            }
          ];
        };
      }
      {
        profile = {
          name = "corp-office";
          outputs = [
            {
              criteria = "Lenovo Group Limited P27h-20 V906YLCP";
              position = "0,0";
            }
            {
              criteria = "Samsung Electric Company LS27A600U HNMR402251";
              # To the right of the Lenovo one
              position = "2560,0";
            }
            {
              # This should match both my personal and my work laptop.
              criteria = "eDP-1";
              # Below the Lenovo one.
              position = "0,1440";
            }
          ];
        };
      }
      {
        profile = {
          name = "corp-office-hotdesk";
          outputs = [
            {
              # Massive 3840x2160
              criteria = "Lenovo Group Limited LEN P32p-20 VNA6XK1W";
              position = "0,0";
              scale = 1.25;
            }
            {
              # This should match both my personal and my work laptop.
              criteria = "eDP-1";
              # Below the massive one
              position = "0,2160";
            }
          ];
        };
      }
      {
        profile = {
          name = "corp-at-hotdesk";
          outputs = [
            {
              # 32inch but lower res
              criteria = "Dell Inc. DELL P3223QE 7W80N04";
              mode = "3840x2160";
              position = "0,0";
              scale = 1.25;
            }
            {
              # This should match both my personal and my work laptop.
              criteria = "eDP-1";
              # Below the massive one
              position = "0,2160";
            }
          ];
        };
      }
      {
        profile = {
          name = "corp-jp-hotdesk";
          outputs = [
            {
              criteria = "eDP-1";
              position = "0,0";
            }
            {
              # Smaller one, put to the right of laptop
              criteria = "Dell Inc. DELL U2722DE 3L50FH3";
              position = "1920,0";
            }
          ];
        };
      }
    ];
  };
}
