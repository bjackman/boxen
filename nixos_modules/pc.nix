# Stuff for my user but on computers with screens and a keyboard and shit.
{
  pkgs,
  config,
  agenix,
  agenix-template,
  ...
}:
{
  imports = [
    ./impermanence.nix
    agenix.nixosModules.default
    agenix-template.nixosModules.default
  ];

  boot.loader = {
    systemd-boot.enable = true;
    efi.canTouchEfiVariables = true;
  };

  i18n = {
    defaultLocale = "en_GB.UTF-8";
    extraLocaleSettings = {
      LC_ADDRESS = "en_GB.UTF-8";
      LC_IDENTIFICATION = "en_GB.UTF-8";
      LC_MEASUREMENT = "en_GB.UTF-8";
      LC_MONETARY = "en_GB.UTF-8";
      LC_NAME = "en_GB.UTF-8";
      LC_NUMERIC = "en_GB.UTF-8";
      LC_PAPER = "en_GB.UTF-8";
      LC_TELEPHONE = "en_GB.UTF-8";
      LC_TIME = "en_GB.UTF-8";
    };
  };

  services.xserver = {
    enable = true;
  };
  services.displayManager.gdm.enable = true;
  services.desktopManager.gnome.enable = true;

  services.xserver.xkb = {
    layout = "us";
    variant = "";
  };

  services.pulseaudio.enable = false;
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
  };

  nixpkgs.config.allowUnfree = true;

  users.users.brendan.extraGroups = [
    "networkmanager"
    # Required for waybar etc to be able to query capslock status.
    "input"
  ];

  # NixOS wiki recommends sticking to NetworkManager for laptoppy usecases, this
  # is not a laptop-specific module but it's still kinda laptoppy so let's stick
  # to it I guess.
  networking.networkmanager.enable = true;
  # Something somewhere seems to cause networking.wireless to get enabled when
  # I'm trying to build an installer image, which causes an error due to
  # networkmanager also being enabled. Disable it explicitly.
  networking.wireless.enable = false;

  services.tailscale.enable = true;

  bjackman.impermanence.extraPersistence.users.brendan.directories = [
    "Downloads"
    "Music"
    "Pictures"
    "Documents"
    "Videos"
    "src"
    ".cache"
    ".local/share/z"
    ".local/share/fish"
    ".local/share/zed"
    ".local/share/Steam"
    ".steam"
    # VSCode has a bunch of yucky stateful shit that leaks into .config and I
    # can't be bothered to figure it out, just persist the whole mess.
    ".config/Code"
    ".vscode"
    ".gemini" # yuck
    {
      directory = ".mozilla/firefox";
      mode = "0700";
    }
    {
      directory = ".local/share/keyrings";
      mode = "0700";
    }
    {
      directory = ".ssh";
      mode = "0700";
    }
  ];

  # Import secret containing GitHub PAT
  age.secrets.github-pat.file = ../secrets/github-pat.age;
  # Template the PAT into a Nix config file that sets the access-tokens
  # appropriately. Note this isn't Nix code it's the weird nix settiongs format.
  age-template.files."access-tokens-conf" = {
    vars.token = config.age.secrets.github-pat.path;
    content = "access-tokens = github.com=$token";
  };
  # Import that runtime-generated Nix file into the Nix config.
  nix.extraOptions = ''
    !include ${config.age-template.files."access-tokens-conf".path}
  '';
}
