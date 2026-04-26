# Transmission Migration

## Background

Transmission is currently deployed as a NixOS service on the `norte` node (a Raspberry Pi 5).

### Deployment Details

- **Service:** Transmission 4 (`pkgs.transmission_4`).
- **Node:** `norte`.
- **Storage:**
  - Downloads and incomplete files are stored on a ZFS pool named `nas` under `/mnt/nas/media/transmission`.
  - Specifically, `download-dir` is `/mnt/nas/media/transmission/downloads` and `incomplete-dir` is `/mnt/nas/media/transmission/incomplete`.
- **Networking:**
  - RPC is enabled and bound to `0.0.0.0`.
  - The RPC port is dynamically assigned via `bjackman.ports.transmission.port`.
- **Security:**
  - RPC authentication is required (user: `brendan`).
  - The password is managed via `agenix` and provided to Transmission through a JSON credentials file.
  - Transmission runs as a member of the `media-writers` group to ensure it can write to the media directories.

### Interacting Systems

- **Radarr & Sonarr:** Both run locally on `norte` (to support hardlinking) and interact with Transmission via its RPC API to manage downloads.
- **Jellyfin Notifier:** A custom systemd service on `norte` that uses `watchexec` to monitor the media directories and trigger library rescans in Jellyfin via its API when new files are added.
- **Terraform (`tf/arr`):** Used to configure the download client settings within Radarr and Sonarr, passing the Transmission RPC credentials and port.
- **Jellyfin:** Consumes the media files downloaded by Transmission and organized by Radarr/Sonarr.

## Strategy

The goal is to move the Transmission daemon to `pizza` to offload processing from the Raspberry Pi (`norte`), while keeping the actual data on the ZFS pool hosted by `norte`.

### 1. Storage Access

`pizza` already has a Samba mount to `norte`'s media share at `/mnt/nas-media`. Transmission on `pizza` will be configured to use this mount for its download and incomplete directories.

### 2. RPC Communication

Radarr and Sonarr (remaining on `norte` for local hardlinking performance) will communicate with Transmission on `pizza` over the network. The Terraform configuration will be updated to point to `pizza`'s hostname instead of `localhost`.

### 3. Path Mapping

Since `pizza` and `norte` see the same storage at different paths:

- `norte`: `/mnt/nas/media/transmission/downloads`
- `pizza`: `/mnt/nas-media/transmission/downloads`

Remote Path Mappings will be configured in Radarr and Sonarr to ensure they can correctly locate the finished downloads reported by Transmission.

## Migration Plan

### Phase 1: Prepare `pizza`

1. **Configure Transmission on `pizza`**: Update `nixos_modules/pizza/default.nix` to ensure Transmission uses the Samba mount paths.
1. **Permissions**: Ensure the `transmission` user on `pizza` has the necessary permissions to write to `/mnt/nas-media` (via the `nas-media` group).

### Phase 2: Update Infrastructure Code

1. **Service Mapping**: Update the `homelab` data structure (likely in `flake.nix`) to point the `transmission` service to the `pizza` node.
1. **Terraform Update**: Modify `tf/arr/arr.tf` to use the dynamic hostname for the Transmission download client.
1. **RPC Secret**: Ensure the Transmission RPC secret is available to `pizza`.

### Phase 3: Execution

1. **Stop & Disable**: Stop the Transmission service on `norte` and remove it from its configuration.
1. **Deploy `pizza`**: Apply the new configuration to `pizza` to start the Transmission service.
1. **Apply Terraform**: Run the `deploy-arr-tf` script to update Radarr and Sonarr's connection settings.
1. **Path Mappings**: Manually (or via Terraform if supported) add the Remote Path Mappings to Radarr and Sonarr.

### Phase 4: Validation

1. Verify Transmission RPC is reachable from `norte`.
1. Trigger a test download in Radarr/Sonarr.
1. Confirm the file is downloaded by `pizza` to the NAS.
1. Confirm Radarr/Sonarr successfully imports the file using a hardlink on `norte`.

## Assessment: Success at Addressing OOMs

The primary driver for this migration is that `norte` (a Raspberry Pi 5) is RAM-underprovisioned for its current workload, leading to OOMs when Transmission's random I/O patterns interact with ZFS. This design is highly likely to succeed for several reasons:

### 1. Offloading Process Memory

Transmission manages hundreds of peer connections and maintains its own piece cache. On a machine with limited RAM already constrained by ZFS ARC requirements, this process competition is a major factor in OOM events. Moving the daemon to `pizza` removes this direct pressure entirely.

### 2. Structured I/O via Samba

Torrent clients perform aggressive, asynchronous, small-block random I/O. This pattern is particularly stressful for ZFS metadata management and can lead to unreclaimable kernel allocations (as noted in `norte`'s current `zfs.nix` tuning). By moving Transmission to `pizza` and using a Samba mount:

- `pizza` handles the piece reassembly and caching in its own (presumably more abundant) RAM.
- `norte` interacts with the I/O requests through `smbd`, which provides a more structured and buffered interface to the ZFS pool than a local torrent client.

### 3. Preservation of Hardlinks

By keeping Radarr and Sonarr on `norte`, we maintain the ability to perform local hardlinks once a download is complete. This avoids the massive I/O overhead of copying files across the network (or within the NAS) during the "import" phase, which itself could trigger further memory pressure or I/O wait issues.

### 4. Summary

This design effectively turns `norte` into a dedicated storage and "organizer" node, while offloading the volatile and I/O-intensive "downloader" role to `pizza`. This separation of concerns is a classic architectural pattern for overcoming resource constraints on edge hardware.
