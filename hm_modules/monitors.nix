{
  config,
  pkgs,
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
    dell-u3225qe-a = {
      criteria = "Dell Inc. DELL U3225QE GZBTLJ4";
      width = 3840;
      height = 2160;
    };
    dell-u3225qe-b = {
      criteria = "Dell Inc. DELL U3225QE J0CTLJ4";
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
              // (if spec ? mode then { inherit (spec) mode; } else { })
              // (if spec ? status then { inherit (spec) status; } else { });
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
  # Sway resets outputs to its own config on reload, trigger a Kanshi reload to
  # override it.
  wayland.windowManager.sway.config.startup = [
    {
      command = "${config.services.kanshi.package}/bin/kanshictl reload";
      always = true;
    }
  ];

  services.kanshi = {
    enable = true;
    settings =
      let
        homeMonitors = [
          {
            monitor = presets.google-p2718ec;
            name = "left";
          }
          {
            monitor = presets.dell-p2720dc;
            name = "right";
            rightOf = "left";
          }
        ];
        chungitoDesk = right: [
          {
            monitor = presets.dell-u3225qe-a;
            name = "left";
            mode = "3840x2160@119.999Hz";
            scale = 1.25;
          }
          {
            monitor = right;
            rightOf = "left";
            mode = "3840x2160@119.999Hz";
            scale = 1.25;
          }
        ];
      in
      [
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
            scale = 1.25;
          }
          {
            monitor = presets.eDP;
            rightOf = "main";
          }
        ])

        (makeProfile "home-office" homeMonitors)
        (makeProfile "home-office-laptop" (
          homeMonitors
          ++ [
            {
              monitor = presets.eDP;
              below = "right";
            }
          ]
        ))

        # 4K120 exceeds the 3070 Ti's DP 1.4 bandwidth so this relies on DSC.
        # Seemed to work fine when tested.
        (makeProfile "chungito-desk" (chungitoDesk presets.dell-u3225qe-b))

        # The right monitor is also daisy-chained off the left one for the Mac,
        # so it appears as two heads with the same description. nvidia names
        # the connectors differently depending on whether MST detection
        # happened at boot or on hotplug, so instead of matching by name,
        # enable whichever head can do 4K120 (only the direct link has the
        # bandwidth).
        (
          let
            right = presets.dell-u3225qe-b;
            scale = 1.25;
            mode = "3840x2160@119.999Hz";
            enableDirectHead = pkgs.writeShellApplication {
              name = "kanshi-enable-direct-head";
              runtimeInputs = [
                pkgs.sway
                pkgs.jq
              ];
              text = ''
                head=$(swaymsg -t get_outputs -r | jq -r '
                  [.[] | select(.make + " " + .model + " " + .serial == "${right.criteria}")
                       | select(any(.modes[]; .width == 3840 and .height == 2160 and .refresh == 119999))
                       | .name] | first // empty')
                if [[ -z "$head" ]]; then
                  echo "no head for ${right.criteria} supports ${mode}" >&2
                  exit 1
                fi
                swaymsg output "$head" enable mode ${mode} \
                  position ${toString (divScale presets.dell-u3225qe-a.width scale)} 0 scale ${toString scale}
              '';
            };
            base = makeProfile "chungito-desk-daisy-chain" [
              {
                monitor = presets.dell-u3225qe-a;
                mode = "3840x2160@119.999Hz";
                inherit scale;
              }
              {
                monitor = right;
                status = "disable";
              }
              {
                monitor = right;
                status = "disable";
              }
            ];
          in
          base
          // {
            profile = base.profile // {
              exec = [ (pkgs.lib.getExe enableDirectHead) ];
            };
          }
        )
      ];
  };
}
