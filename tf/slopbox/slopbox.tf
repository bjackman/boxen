terraform {
  required_providers {
    incus = {
      source  = "lxc/incus"
      version = ">= 1.0.2"
    }
  }
}

provider "incus" {
}

variable "nixos_image_data" {
  type        = string
  description = "Path to the built rootfs or qcow2 data file"
}

variable "nixos_image_metadata" {
  type        = string
  description = "Path to the built metadata tarball"
}

resource "incus_image" "slopbox" {
  source_file = {
    data_path     = var.nixos_image_data
    metadata_path = var.nixos_image_metadata
    type = "virtual-machine"
  }
}

resource "incus_instance" "slopbox" {
  name     = "slopbox"
  type     = "virtual-machine"
  image    = incus_image.slopbox.fingerprint
  profiles = ["default"]
  running  = true
  config = {
    "security.secureboot" = false
  }
}