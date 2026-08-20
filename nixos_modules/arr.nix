{ config, pkgsUnstable, ... }:
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
    sonarr = { };
  };

  bjackman.iap.services = {
    inherit (ports) radarr sonarr;
  };

  users.groups.arr-api = { };
  age.secrets.arr-api-key = {
    file = ../secrets/arr-api-key.age;
    mode = "0740";
    group = "arr-api";
  };

  bjackman.derived-secrets.envFiles.radarr.vars = {
    RADARR__AUTH__APIKEY = config.age.secrets.arr-api-key.path;
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

  bjackman.derived-secrets.envFiles.sonarr.vars = {
    SONARR__AUTH__APIKEY = config.age.secrets.arr-api-key.path;
  };
  services.sonarr = {
    enable = true;
    openFirewall = true;
    settings = {
      server = {
        port = ports.sonarr.port;
        bindaddress = "*";
      };
      auth.method = "External";
    };
    environmentFiles = [ config.bjackman.derived-secrets.envFiles.sonarr.path ];
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
    group = "arr-api";
    # 8.6.0 in stable doesn't understand the v8 schema below - it rejects
    # trash_id on a quality profile.
    package = pkgsUnstable.recyclarr;
    # Transcribed from radarr/templates/uhd-bluray-web.yml and
    # sonarr/templates/web-1080p.yml in recyclarr/config-templates. That repo
    # is always tracked at master and has no versioning, so a schema change
    # upstream breaks this with no deploy on our side; when it does, re-read
    # the templates rather than patching the error away.
    configuration = {
      radarr.uhd-bluray-web = {
        base_url = "http://localhost:${toString ports.radarr.port}";
        api_key._secret = config.age.secrets.arr-api-key.path;
        quality_definition.type = "movie";
        quality_profiles = [
          {
            trash_id = "64fb5f9858489bdac2af690e27c8f42f"; # UHD Bluray + WEB
            reset_unmatched_scores.enabled = true;
          }
        ];
        custom_format_groups.add = [
          { trash_id = "ff204bbcecdd487d1cefcefdbf0c278d"; } # [Optional] Golden Rule UHD
          { trash_id = "a3ac6af01d78e4f21fcb75f601ac96df"; } # [Unwanted] Unwanted Formats
        ];
        custom_formats = [
          # IIUC this is about avoiding downloads of files that only contain Dolby
          # Video encoding. I don't understand how it does that.
          { trash_ids = [ "9c38ebb7384dada637be8899efa68e6f" ]; } # SDR
        ];
      };
      # Hm, this defines a "Web-1080p" profile that is probably way higher
      # quality than what I want. Leaving it in here coz it does seem to work
      # but it behaves pretty similar to the Radarr one above, i.e. downloads
      # very large files. Maybe I want
      # https://github.com/Dictionarry-Hub/profilarr not sure.
      sonarr.web-1080p = {
        base_url = "http://localhost:${toString ports.sonarr.port}";
        api_key._secret = config.age.secrets.arr-api-key.path;
        quality_definition.type = "series";
        quality_profiles = [
          {
            trash_id = "72dae194fc92bf828f32cde7744e51a1"; # WEB-1080p
            reset_unmatched_scores.enabled = true;
          }
        ];
        custom_format_groups.add = [
          { trash_id = "158188097a58d7687dee647e04af0da3"; } # [Optional] Golden Rule HD
          { trash_id = "74aff4168620ed49dcc67e92b2c2a5b4"; } # [Optional] Language Profiles
          { trash_id = "85fae4a2294965b75710ef2989c850eb"; } # [Streaming Services] HD/UHD boost
          { trash_id = "59c3af66780d08332fdc64e68297098f"; } # [Unwanted] Unwanted Formats
        ];
        # IIUC these are about allowing certain extra-compressed formats. Golden
        # Rule HD scores them way down; this wins because the first score for a
        # format wins.
        custom_formats = [
          {
            trash_ids = [
              "47435ece6b99a0b477caf360e79ba0bb" # x265 (HD)
              "9b64dff695c2115facf1b6ea59c9bd07" # x265 (no HDR/DV)
            ];
            assign_scores_to = [
              {
                name = "WEB-1080p";
                # AI suggested increasing the score here to get more
                # space-efficient files. The template sets this differently.
                score = 100;
              }
            ];
          }
        ];
      };
    };
  };
}
