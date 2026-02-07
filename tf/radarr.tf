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
# But I deleted a bunch of fields that were set in the default, so this might be
# missing something useful.
resource "radarr_indexer" "bitmagnet" {
  name                    = "BitMagnet"
  implementation          = "Torznab"
  config_contract         = "TorznabSettings"
  protocol                = "torrent"
  enable_automatic_search = true
  base_url                = "http://pizza:9000/torznab"
  priority                = 25
}