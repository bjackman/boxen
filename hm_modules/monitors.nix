{
  config,
  pkgsUnstable,
  ...
}:
{
  # Get the description from "swaymsg -t get_outputs"
  wayland.windowManager.sway.config.output = {
    # On the left
    "Google Inc. P2718EC C9240002" = {
      position = "0 0";
    };
    # One at my mum's place:
    "LG Electronics LG ULTRAFINE 508NTGYKX551" = {
      position = "0 0";
      scale = "1.5";
    };
    # To the right of the Google one
    "Dell Inc. DELL P2720DC 81WTK01403MS" = {
      position = "2560 0";
    };
  };

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
        profile.name = "sandy-office";
        profile.outputs = [
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
      }
    ];
  };
}
