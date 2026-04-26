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
  type = string
}

variable "transmission_password" {
  type      = string
  sensitive = true
}

variable "transmission_username" {
  type      = string
  sensitive = true
}

variable "transmission_port" {
  type      = number
  sensitive = true
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

variable "transmission_host" {
  type = string
}

resource "radarr_download_client_transmission" "transmission" {
  name     = "Transmission"
  host     = var.transmission_host
  port     = var.transmission_port
  priority = 25
  enable   = true
  username = var.transmission_username
  password = var.transmission_password
}

# Remote Path Mappings are required because Transmission (on pizza) and
# Radarr/Sonarr (on norte) see the same files at different paths.
# Transmission reports paths like /mnt/nas-media/..., but Radarr needs to find
# them at /mnt/nas/media/... to perform local hardlinks.
resource "radarr_remote_path_mapping" "transmission_pizza" {
  host        = var.transmission_host
  remote_path = "/mnt/nas-media/transmission/downloads/"
  local_path  = "/mnt/nas/media/transmission/downloads/"
}

resource "radarr_root_folder" "movies" {
  path = "/mnt/nas/media/radarr"
}

resource "sonarr_indexer_torznab" "bitmagnet" {
  name       = "BitMagnet"
  api_path   = "/api"
  base_url   = var.bitmagnet_torznab_url
  enable_rss = true
  # Dunno what these means but without it the UI complains
  enable_automatic_search   = true
  enable_interactive_search = true
  priority                  = 25
}

resource "sonarr_download_client_transmission" "transmission" {
  name     = "Transmission"
  host     = var.transmission_host
  port     = var.transmission_port
  priority = 25
  enable   = true
  username = var.transmission_username
  password = var.transmission_password
}

# See radarr_remote_path_mapping for explanation.
resource "sonarr_remote_path_mapping" "transmission_pizza" {
  host        = var.transmission_host
  remote_path = "/mnt/nas-media/transmission/downloads/"
  local_path  = "/mnt/nas/media/transmission/downloads/"
}

resource "sonarr_root_folder" "movies" {
  path = "/mnt/nas/media/sonarr"
}
