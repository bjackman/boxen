# Stuff for my user but on computers with screens and a keyboard and shit.
{ pkgs, ... }:
{
  imports = [ ./impermanence.nix ];

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

  users.users.brendan.extraGroups = [
    "networkmanager"
    # Required for waybar etc to be able to query capslock status.
    "input"
  ];

  # NixOS wiki recommends sticking to NetworkManager for laptoppy usecases, this
  # is not a laptop-specific module but it's still kinda laptoppy so let's stick
  # to it I guess.
  networking.networkmanager.enable = true;

  hardware.bluetooth.enable = true;

  services.tailscale.enable = true;

  bjackman.impermanence.extraPersistence.users.brendan.files = [
    ".claude.json" # yuck
  ];

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
    ".vscode-shared"
    ".ollama" # yuck
    ".claude" # yuck
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
}
