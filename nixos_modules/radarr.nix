{ config, ... }:
let
  ports = config.bjackman.ports;
  iap = config.bjackman.iap;
in
{
  imports = [
    ./ports.nix
    ./iap.nix
    ./postgres.nix
    ./derived-secrets.nix
  ];

  bjackman.ports = {
    radarr = { };
  };

  bjackman.iap.services = {
    inherit (ports) radarr;
  };

  users.groups.radarr-api = { };
  age.secrets.radarr-api-key = {
    file = ../secrets/radarr-api-key.age;
    mode = "0740";
    group = "radarr-api";
  };
  bjackman.derived-secrets.envFiles.radarr.vars = {
    RADARR__AUTH__APIKEY = config.age.secrets.radarr-api-key.path;
  };

  services.radarr = {
    enable = true;
    openFirewall = true;
    settings = {
      server = {
        port = ports.radarr.port;
        bindaddress = "*";
      };
      auth.method = "External";
    };
    environmentFiles = [ config.bjackman.derived-secrets.envFiles.radarr.path ];
  };

  # This is a bit ridiculous lol. Recyclarr is a tool that pulls down
  # recommendations from something called TRaSH Guides and then via some crazy
  # YAML templating magic configures them into Radarr. I kinda struggle to
  # believe that this is really necessary but I dunno it does seem to be worth
  # following the "normal" way of doing things even if it seems a bit bonkers.
  # I don't really want to be forced to run this thing on the same node as
  # Radarr (I have to run Radarr on the storage node so it can create hardlinks)
  # but hopefully it's lightweight enough not to matter, so we just squash it
  # into this module.
  #
  # While setting this up I fiddled around with it a bit and ended up deciding
  # not to change any defaults but I do think I learned some stuff (this is
  # actually stuff about Radarr rather than about Recyclarr):
  # A Quality Definition associates a name with some area in the parameter space
  # of media files.
  # A Profile is a definition of ordered preferences about what kind of Quality
  # of file to download.
  # When you add a piece of media in Radarr, you select a Profile and that
  # determines how Radarr decides which version of that media to download.
  # Custom Formats are about weighting the preferences within a profile
  # according to other details about how the media is encoded.
  #
  # Something potentially dodgy about this configuration is that it strictly
  # prefers 4K and will download staggeringly large files if there are no
  # reasonable encodings available.
  services.recyclarr = {
    enable = true;
    group = "radarr-api";
    # I got this by running `recyclarr config create --template uhd-bluray-web`
    # and then translating the generated YAMl file into Nix.
    configuration.radarr.uhd-bluray-web = {
      base_url = "http://localhost:${toString ports.radarr.port}";
      api_key._secret = config.age.secrets.radarr-api-key.path;
      # I think that the Thing Recyclarr Actually Does is primarily about
      # providing the templates that we instantiate here.
      include = [
        { template = "radarr-quality-definition-movie"; }
        { template = "radarr-quality-profile-uhd-bluray-web"; }
        { template = "radarr-custom-formats-uhd-bluray-web"; }
      ];
      custom_formats = [
        # IIUC this is about avoiding downloads of files that only contain Dolby
        # Video encoding. I don't understand how it does that.
        { trash_ids = [ "9c38ebb7384dada637be8899efa68e6f" ]; }
      ];
    };
  };
}
