terraform {
  required_providers {
    radarr = {
      source  = "devopsarr/radarr"
      version = "2.3.5"
    }
    sonarr = {
      source  = "devopsarr/sonarr"
      version = "3.4.2"
    }
  }
}

# These are configured via the environment, see the deploy wrapper.
provider "radarr" {}
provider "sonarr" {}

# Docs for the TF provider:
# https://registry.terraform.io/providers/devopsarr/radarr/latest/docs/resources/indexer
# I also figured some of this out by creating an indexer in the UI and then doing
# curl -H "X-Api-Key: $KEY" norte:9000/api/v3/indexer/
# But I deleted a bunch of fields that were set in the default.
# THEN, I used:
# tofu state show radarr_indexer.bitmagnet
# To dump the actual resource defined in the backend so I could copy that back
# into the code.

variable "bitmagnet_torznab_url" {
  type      = string
}

resource "radarr_indexer_torznab" "bitmagnet" {
  name     = "BitMagnet"
  api_path = "/api"
  base_url = var.bitmagnet_torznab_url
  # Dunno what these mean they were the backend's default.
  categories = [2000, 2030, 2040, 2045, 2060]
  enable_rss = true
  # Dunno what these means but without it the UI complains
  enable_automatic_search   = true
  enable_interactive_search = true
  priority                  = 25
}

variable "transmission_password" {
  type      = string
  sensitive = true
}

resource "radarr_download_client_transmission" "transmission" {
  name     = "Transmission"
  host     = "localhost"
  port     = 9003
  priority = 25
  enable   = true
  username = "brendan"
  password = var.transmission_password
}

resource "radarr_root_folder" "movies" {
  path = "/mnt/nas/media/radarr"
}
