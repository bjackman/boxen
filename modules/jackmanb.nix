{ config, ... }:
{
  home = {
    username = "jackmanb";
    homeDirectory = "/usr/local/google/home/jackmanb";

    # I don't know why this is necessary but for some reason I don't get PATH set
    # up on gLinux.
    sessionPath = [ "${config.home.profileDirectory}/bin" ];
  };
}
