{
  ...
}:
{
  powerManagement.powertop.enable = true;

  # Disable some un-needed kernel modules as an attempt to try and reduce power.
  boot.blacklistedKernelModules = [
    "iwlwifi"
    "btusb"
    "uvcvideo" # Apparently USB webcames are a common culprit for blocking deep package idle.
    # I was seeing a bunch of 'Audio codec hwC0D2: Intel' in powertop's Overview
    # tab, disabling this driver completely makes that go away.
    "snd_hda_intel"
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
  #
  # Powertop still shows that a bunch of USB devices are keeping the package
  # from entering deep sleep. Gemini guided me to try a bunch of stuff to try
  # and fix this but none of it works. When I rmmod xhci_pci, the power usage
  # increases a bunch! Oh well, it's pretty low already.
}
