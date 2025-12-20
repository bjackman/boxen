{
  config,
  pkgs,
  declarative-jellyfin,
  agenix,
  ...
}:
{
  # Note this is just the generic parts of the config, individual machines will
  # need more specific configs. It also doesn't actually enable jellyfin.

  imports = [
    agenix.nixosModules.default
    declarative-jellyfin.nixosModules.default
  ];

  age.secrets.jellyfin-admin-password-hash.file = ../secrets/jellyfin-admin-password-hash.age;
  # https://github.com/Sveske-Juice/declarative-jellyfin/blob/main/examples/fullexample.nix
  services.declarative-jellyfin = {
    users = {
      brendan = {
        mutable = false;
        permissions.isAdministrator = true;
        hashedPasswordFile = config.age.secrets.jellyfin-admin-password-hash.path;
      };
    };
    # Experimental: Manually created, then used this to set up the right directory structure:
    # mnamer <media dir>  --episode-format "{series}/Season {season:02}/{series} - S{season:02}E{episode:02} - {title}{extension}" --batch
    libraries.TV = {
      enabled = true;
      contentType = "tvshows";
      pathInfos = [ "/var/lib/media/shows" ];
      typeOptions.Shows = {
        metadataFetchers = [
          "The Open Movie Database"
          "TheMovieDb"
        ];
        imageFetchers = [
          "The Open Movie Database"
          "TheMovieDb"
        ];
      };
    };
    libraries.Movies = {
      enabled = true;
      contentType = "movies";
      pathInfos = [ "/var/lib/transmission/Downloads" ];
      typeOptions.Movies = {
        metadataFetchers = [
          "The Open Movie Database"
          "TheMovieDb"
        ];
        imageFetchers = [
          "The Open Movie Database"
          "TheMovieDb"
        ];
      };
    };
  };
  services.jellyfin.openFirewall = true;
}
