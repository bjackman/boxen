# To make this work run: gcloud auth application-default login
# (From the google-cloud-sdk Nix package).
terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0" 
    }
  }
}

provider "google" {
  # I created this project in the GCP Console.
  project = "nas-backup-491716" 
  region  = "europe-west6"
}

resource "google_storage_bucket" "restic_backup" {
  name     = "bjackman-bucket"
  location = "EU"
  # Note this property of the bucket is actually just a default; each object has
  # its own storage class.
  storage_class = "STANDARD"
  # No per-object ACLs, just one big ACL for the whole bucket.
  uniform_bucket_level_access = true

  lifecycle {
    prevent_destroy = true
  }

  # Store old versions of objects in case they are overwritten.
  versioning {
    enabled = true
  }

  # Transition to Archive after 30 days to avoid early-deletion penalties
  # for data that might be pruned/overwritten quickly.
  lifecycle_rule {
    condition {
      age = 30
    }
    action {
      type          = "SetStorageClass"
      storage_class = "ARCHIVE"
    }
  }

  # Clean up non-current versions after 365 days (Archive minimum)
  lifecycle_rule {
    condition {
      num_newer_versions         = 3
      days_since_noncurrent_time = 365
    }
    action {
      type = "Delete"
    }
  }
}

resource "google_service_account" "nas_backup" {
  account_id   = "nas-backupper"
  display_name = "NAS Backup Service Account"
}

resource "google_storage_bucket_iam_member" "nas_backup_writer" {
  bucket = google_storage_bucket.restic_backup.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.nas_backup.email}"
}