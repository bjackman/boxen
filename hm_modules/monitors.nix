{
  config,
  pkgsUnstable,
  ...
}:
let
  # Presets for known monitors with their physical resolutions.
  presets = {
    fw13 = {
      criteria = "BOE NE135A1M-NY1 Unknown";
      width = 2256;
      height = 1504;
    };
    eDP = {
      criteria = "eDP-1";
      width = 2256;
      height = 1504;
    };
    corp-laptop = {
      criteria = "eDP-1";
      width = 1920;
      height = 1080;
    };
    lg-ultrafine = {
      criteria = "LG Electronics LG ULTRAFINE 508NTGYKX551";
      width = 3840;
      height = 2160;
    };
    dell-p2720dc = {
      criteria = "Dell Inc. DELL P2720DC 81WTK01403MS";
      width = 2560;
      height = 1440;
    };
    google-p2718ec = {
      criteria = "Google Inc. P2718EC C9240002";
      width = 2560;
      height = 1440;
    };
    lenovo-p27h = {
      criteria = "Lenovo Group Limited P27h-20 V906YLCP";
      width = 2560;
      height = 1440;
    };
    samsung-s27a = {
      criteria = "Samsung Electric Company LS27A600U HNMR402251";
      width = 2560;
      height = 1440;
    };
    lenovo-p32p = {
      criteria = "Lenovo Group Limited LEN P32p-20 VNA6XK1W";
      width = 3840;
      height = 2160;
    };
    dell-p3223qe = {
      criteria = "Dell Inc. DELL P3223QE 7W80N04";
      width = 3840;
      height = 2160;
    };
    lenovo-t32ud = {
      criteria = "Lenovo Group Limited T32UD-40 *";
      width = 3840;
      height = 2160;
    };
  };

  # Safe integer division for common scales to avoid Nix float-to-string issues.
  # Kanshi positions must be integers in logical pixels.
  divScale =
    val: scale:
    if scale == 1.0 then
      val
    else if scale == 1.25 then
      (val * 4) / 5
    else if scale == 1.5 then
      (val * 2) / 3
    else if scale == 2.0 then
      val / 2
    else
      builtins.throw "Unsupported scale: ${toString scale}";

  # Helper to create a Kanshi profile with relative positioning.
  makeProfile = name: layoutSpecs: {
    profile = {
      inherit name;
      outputs =
        (builtins.foldl'
          (
            acc: spec:
            let
              monitorName = spec.name or spec.monitor.criteria;
              monitor = spec.monitor;
              scale = spec.scale or 1.0;

              logicalWidth = divScale monitor.width scale;
              logicalHeight = divScale monitor.height scale;

              # Calculate position
              pos =
                if spec ? x && spec ? y then
                  { inherit (spec) x y; }
                else if spec ? rightOf then
                  let
                    ref = acc.resolved.${spec.rightOf};
                  in
                  {
                    x = ref.x + ref.logicalWidth;
                    y = ref.y;
                  }
                else if spec ? leftOf then
                  let
                    ref = acc.resolved.${spec.leftOf};
                  in
                  {
                    x = ref.x - logicalWidth;
                    y = ref.y;
                  }
                else if spec ? above then
                  let
                    ref = acc.resolved.${spec.above};
                  in
                  {
                    x = ref.x;
                    y = ref.y - logicalHeight;
                  }
                else if spec ? below then
                  let
                    ref = acc.resolved.${spec.below};
                  in
                  {
                    x = ref.x;
                    y = ref.y + ref.logicalHeight;
                  }
                else
                  {
                    x = 0;
                    y = 0;
                  };

              resolved = {
                inherit (monitor) criteria;
                inherit scale logicalWidth logicalHeight;
                inherit (pos) x y;
              };

              kanshiOutput = {
                inherit (monitor) criteria;
                position = "${toString pos.x},${toString pos.y}";
              }
              // (if spec ? scale then { inherit scale; } else { })
              // (if spec ? mode then { inherit (spec) mode; } else { });
            in
            {
              resolved = acc.resolved // {
                ${monitorName} = resolved;
              };
              outputs = acc.outputs ++ [ kanshiOutput ];
            }
          )
          {
            resolved = { };
            outputs = [ ];
          }
          layoutSpecs
        ).outputs;
    };
  };
in
{
  services.kanshi = {
    enable = true;
    settings = [
      (makeProfile "fw13-unplugged" [
        {
          monitor = presets.fw13;
          scale = 1.5;
        }
      ])

      (makeProfile "sandy-office" [
        {
          monitor = presets.lg-ultrafine;
          name = "main";
          mode = "3840x2160";
          scale = 1.0;
        }
        {
          monitor = presets.eDP;
          rightOf = "main";
        }
      ])

      (makeProfile "home-office" [
        {
          monitor = presets.google-p2718ec;
          name = "left";
        }
        {
          monitor = presets.dell-p2720dc;
          name = "right";
          rightOf = "left";
        }
        {
          monitor = presets.eDP;
          below = "right";
        }
      ])

      (makeProfile "corp-office" [
        {
          monitor = presets.lenovo-p27h;
          name = "left";
        }
        {
          monitor = presets.samsung-s27a;
          name = "right";
          rightOf = "left";
          scale = 1.0;
          mode = "2560x1440 @ 74.998 Hz";
        }
        {
          monitor = presets.eDP;
          below = "left";
          scale = 1.0;
        }
      ])

      (makeProfile "corp-office-hotdesk" [
        {
          monitor = presets.lenovo-p32p;
          name = "main";
          scale = 1.25;
        }
        {
          monitor = presets.eDP;
          below = "main";
        }
      ])

      (makeProfile "corp-at-hotdesk" [
        {
          monitor = presets.dell-p3223qe;
          name = "main";
          mode = "3840x2160";
          scale = 1.25;
        }
        {
          monitor = presets.eDP;
          below = "main";
        }
      ])

      (makeProfile "corp-crbn-hotdesk" [
        {
          monitor = presets.corp-laptop;
          name = "laptop";
        }
        {
          monitor = presets.lenovo-t32ud;
          rightOf = "laptop";
          mode = "3840x2160";
          scale = 1.25;
        }
      ])
    ];
  };
}
