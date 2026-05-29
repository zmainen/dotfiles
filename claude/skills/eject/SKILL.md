---
name: eject
description: "Safely eject external drives, SSDs, and USB media from macOS. Handles APFS containers, partitioned disks, and mounted volumes. Use when the user says eject, unmount, close the SSD, or disconnect a drive."
---

# /eject — Safely eject external media

Eject external drives, SSDs, and USB media from macOS. Handles APFS containers, partitioned disks, and mounted volumes.

## Trigger

User says "eject", "close the SSD", "unmount the drive", "disconnect the disk", or similar.

## Procedure

1. **List external media:**
   ```bash
   diskutil list external
   ```

2. **Identify the target.** Match user's description (name, size, type) to the listed disks. The physical disk (e.g. `disk4`) is what gets ejected — not the synthesized APFS container (e.g. `disk5`).

3. **Eject:**
   ```bash
   diskutil eject diskN
   ```
   where `diskN` is the **physical** external disk identifier.

4. **If eject fails** (resource busy):
   ```bash
   # Find what's using it
   sudo lsof +D /Volumes/VolumeName 2>/dev/null | head -20
   # Force unmount then eject
   diskutil unmountDisk force diskN
   diskutil eject diskN
   ```

5. **Confirm** the disk no longer appears in `diskutil list external`.

## Anti-patterns

- Don't eject synthesized/container disks (disk5, disk9) — eject the physical disk they sit on.
- Don't `diskutil unmount` individual volumes when the user wants the whole drive ejected — use `diskutil eject` on the physical disk.
- Don't force-eject without checking what's using the volume first.
