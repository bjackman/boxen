{
  config,
  lib,
  pkgs,
  inputs,
  home-manager,
  pkgsUnstable,
  homelab,
  ...
}:
let
  slop = config.bjackman.slopClient.packages;
in
{
  imports = [
    ../remote-control.nix
    ../slop-client.nix
    home-manager.nixosModules.home-manager
  ];

  age.secrets.udr7-api-key = {
    file = ../../secrets/udr7-api-key.age;
    mode = "400";
    owner = "claude";
  };

  bjackman.slopClient.user = "claude";

  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;
    backupFileExtension = "backup";
    users.claude.imports = [ ../../hm_modules/pizza-claude.nix ];
    extraSpecialArgs = inputs // {
      inherit pkgsUnstable homelab;
    };
  };

  # Logging in is interactive: sudo -u claude -H /etc/profiles/per-user/claude/bin/claude auth login
  bjackman.remoteControl.claude = {
    description = "Claude Code Remote Control server for boxen";
    checkout.keyFilePath = config.age.secrets.slopbot-ssh-privkey.path;
    sessionName = "pizza: boxen";
    permissionMode = "bypassPermissions";
    extraArgs = [
      "--spawn"
      "worktree"
    ];
    after = [ "home-manager-claude.service" ];
    path = [
      "/etc/profiles/per-user/claude"
      "/run/current-system/sw"
      pkgs.bashInteractive
      slop.slop-tools
      slop.slop-probe
    ];
    memoryMax = "3G";
    cpuQuota = "400%";
  };
}
