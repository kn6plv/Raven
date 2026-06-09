# Crow USB Storage

Crow keeps the application core on the node and can use an attached USB storage volume as the data layer on AREDN nodes.

This feature is intended to reduce writes to node flash while keeping Crow boot-safe. If the external volume is missing or unhealthy, Crow should continue running from node storage and report a degraded storage state instead of crashing.

## Storage layout

When USB storage is healthy, Crow uses:

- `/mnt/crow/data` for JSON state, message stores, node database, and other platform data
- `/mnt/crow/winlink/forms` for Winlink and form storage
- `/mnt/crow/images` for persistent uploaded images

The Crow runtime, package files, and minimal configuration remain on internal node storage.

## Degraded mode

Crow periodically verifies that the USB volume is mounted, writable, and has enough free space. If the check fails, the platform switches to degraded mode:

- the core service remains running
- the user is alerted that storage is degraded
- temporary fallback storage is used under `/tmp/apps/raven/degraded`
- image uploads fall back to `/tmp/apps/raven/images`

This protects the node from a hard failure when a USB stick is removed, fails, or fills up.

## Persistent image quota

When USB storage is enabled, images are persistent under `/mnt/crow/images`. A timer prunes old image files so the image directory remains under the configured quota.

Default values:

- image quota: 64 MB
- minimum free space: 16 MB
- health check interval: 1 minute
- image prune interval: 5 minutes

The cleanup policy removes the oldest files first and only acts inside the Crow-managed image directory.

## Runtime configuration

Example configuration override:

```json
{
  "storage": {
    "mode": "usb",
    "mountpoint": "/mnt/crow",
    "label": "CROWDATA",
    "image_quota_mb": 64,
    "min_free_mb": 16
  }
}
```

To return to internal node storage:

```json
{
  "storage": {
    "mode": "internal"
  }
}
```

## Platform API

The AREDN platform now exposes storage helper functions:

- `storageStatus()` returns active storage state
- `storageScan()` lists removable storage candidates
- `storageMount()` attempts to activate configured USB storage
- `storageDisable()` switches back to internal storage
- `storageImageQuota(mb)` updates the image quota and prunes if needed

The platform storage path function now routes normal data, Winlink/form storage, and images through the active storage root. Existing code should continue using `platform.load()`, `platform.store()`, `platform.loadbinary()`, and `platform.storebinary()`.

## Safety notes

Destructive setup should require explicit user confirmation and should refuse internal flash, rootfs, overlay, or non-removable block devices. The Crow core should never be moved to the USB volume.
