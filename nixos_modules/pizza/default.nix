{
  config,
  pkgs,
  modulesPath,
  nixos-hardware,
  ...
}:

{
  imports = [
    ../common.nix
    ../brendan.nix
    ../server.nix
    ./disko.nix
    "${modulesPath}/profiles/headless.nix"
    "${modulesPath}/profiles/minimal.nix"
    nixos-hardware.nixosModules.lenovo-thinkpad-t480
  ];

  boot.loader = {
    systemd-boot.enable = true;
    efi.canTouchEfiVariables = true;
  };

  networking.hostName = "pizza";

  time.timeZone = "Europe/Zurich";

  services.logind.settings.Login = {
    HandleLidSwitch = "ignore";
    HandleLidSwitchExternalPower = "ignore";
  };

  services.openssh = {
    enable = true;
    settings.PasswordAuthentication = false;
  };

  powerManagement.powertop.enable = true;

  boot.kernelParams = [
    # Obsessively poking around with power saving shit.
    # Gemini got me to run `sudo nvme id-ctrl /dev/nvme0n1 -H | grep -A 15 "ps.*:"`
    # which said "exlat:8000" for the deepest power state. The AI claims that
    # this causes Linux to be hesitant to enter the deepest power saving state,
    # but that setting this parameter to a higher default will fix it.
    "nvme_core.default_ps_max_latency_us=10000"

    # Gemini suggests this, but... I dunno about that one buddy.
    # "pcie_aspm=force"

    # Gemini suggested this in response to seeing reports in powertop of "Audio
    # codec hwC0D2: Intel" using CPU.
    "snd_hda_intel.power_save=1"
    "snd_hda_intel.power_save_controller=Y"

    # GPU Power Management, also suggested by Gemini.
    "i915.enable_dc=2" # Enable deeper Display Core power states
    "i915.enable_fbc=1" # Framebuffer compression
    "i915.enable_psr=1" # Panel Self Refresh
  ];

  # Disable some un-needed kernel modules as an attempt to try and reduce power.
  boot.blacklistedKernelModules = [
    "iwlwifi"
    "btusb"
    "uvcvideo" # Apparently USB webcames are a common culprit for blocking deep package idle.
  ];

  # Notes:
  #
  # I'm able to query DPMS (monitor power state) with:
  #
  #   grep . /sys/class/drm/card*-*/dpms
  #
  # This command will make that switch to "Off" but I don't see a dip in power
  # usage. I suspect that while the lid is closed, there is no power usage by
  # the monitor regardless of the logical state.
  #
  #   setterm --blank force --term linux < /dev/tty1 > /dev/tty1

  system.stateVersion = "25.11";
}
