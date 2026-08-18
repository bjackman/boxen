{
  config,
  inputs,
  self,
  ...
}:
{
  imports = [
    ./homelab.nix
    ./nixpkgs.nix
  ];

  # This is a bit of a magical dance to get packages defined in this flake
  # to be available as flake outputs (so they can easily be tested) and also
  # exposed into the Home Manager module system. We define the packages in a
  # nixpkgs overlay. We then consume the overlay into pkgs above (so Home
  # Manager modules can consume the packages). Then we expose them as flake
  # outputs here below.
  # Note the overlay itself is system-agnostic, it's just a function that
  # refers to whatever nixpkgs instance it's called on.
  # https://discourse.nixos.org/t/multiple-packages-in-the-same-flake-that-depend-on-each-other/69673/5
  flake.overlays.default = final: prev: {
    # Put all the packages defined this way under the "bjackman" key so it's
    # obvious at the usage site that they come from an overlay.
    bjackman = {
      homepage = final.callPackage ../packages/homepage { src = ../packages/homepage; };
      notmuch-get-dead-addresses = final.callPackage ../packages/notmuch-get-dead-addresses { };
      notmuch-propagate-mute = final.callPackage ../packages/notmuch-propagate-mute { };
      spellcheck_commitmsg = final.callPackage ../packages/spellcheck_commitmsg { };
      spellcheck_commitmsgs = final.callPackage ../packages/spellcheck_commitmsgs { };
      slopclone = final.callPackage ../packages/slopclone { };
      slop = final.callPackage ../packages/slop { };
      slop-tools = final.callPackage ../packages/slop-tools { inherit (final.llm-agents) claude-code; };
      tvheadend = final.callPackage ../packages/tvheadend { src = inputs.tvheadend; };
    };
  };

  perSystem =
    let
      inherit (config.bjackman) homelab;
    in
    {
      pkgs,
      config,
      ...
    }:
    {
      packages = pkgs.bjackman // {
        # This is really a "check" but having it in there is super fucking
        # annoying because it causes deploy-rs to fail. So, just put it as a
        # package and we can have Limmat build it.
        format = config.treefmt.build.check self;
        add-user = pkgs.callPackage ../packages/add-user.nix { };
        deploy-tf-arr = pkgs.callPackage ../tf/arr/deploy.nix { inherit homelab; };
        deploy-tf-slopbox = pkgs.callPackage ../tf/slopbox/deploy.nix { inherit self; };
      };
    };
}
