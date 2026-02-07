terraform {
  required_providers {
    radarr = {
      source  = "devopsarr/radarr"
      version = "2.3.5"
    }
  }
}

# Leave these empty, use env
provider "radarr" {
  # url     = ENV: RADARR_URL
  # api_key = ENV: RADARR_API_KEY
}

# Docs for the TF provider:
# https://registry.terraform.io/providers/devopsarr/radarr/latest/docs/resources/indexer
# I also figured some of this out by creating an indexer in the UI and then doing
# curl -H "X-Api-Key: $KEY" norte:9000/api/v3/indexer/
# But I deleted a bunch of fields that were set in the default.
# THEN, I used:
# tofu state show radarr_indexer.bitmagnet
# To dump the actual resource defined in the backend so I could copy that back
# into the code.
moved {
  from = radarr_indexer.bitmagnet
  to   = radarr_indexer_torznab.bitmagnet
}

resource "radarr_indexer_torznab" "bitmagnet" {
  name            = "BitMagnet"
  api_path        = "/api"
  base_url        = "http://pizza:9000/torznab"
  # Dunno what these mean they were the backend's default.
  categories      = [2000, 2030, 2040, 2045, 2060]
  enable_rss      = true
  priority        = 25
}