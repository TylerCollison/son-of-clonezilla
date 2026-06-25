#!/bin/bash
# update-fstab.sh - Update /etc/fstab with the new partition UUID
# Usage: update-fstab.sh <target_partition>
# Example: update-fstab.sh /dev/sda2

set -e

TARGET_PARTITION="$1"

if [ -z "$TARGET_PARTITION" ]; then
    echo "Usage: $0 <target_partition>"
    echo "Example: $0 /dev/sda2"
    exit 1
fi

# Get the root partition device (assuming it's the first partition on the disk)
ROOT_PARTITION=$(echo "$TARGET_PARTITION" | sed 's/[0-9]*$//')

ROOTFS_MOUNT="/mnt/rootfs"

echo "Getting new UUID for $TARGET_PARTITION..."
NEW_UUID=$(blkid -s UUID -o value "$TARGET_PARTITION" 2>/dev/null)

if [ -z "$NEW_UUID" ]; then
    echo "Error: Could not retrieve UUID for $TARGET_PARTITION"
    exit 1
fi

echo "New UUID: $NEW_UUID"

# Mount root filesystem
echo "Mounting root filesystem..."
mkdir -p "$ROOTFS_MOUNT"
mount "$TARGET_PARTITION" "$ROOTFS_MOUNT" 2>/dev/null || {
    echo "Error: Could not mount $TARGET_PARTITION"
    exit 1
}

# Mount additional filesystems needed for chroot
echo "Mounting auxiliary filesystems..."
mount -B /dev "$ROOTFS_MOUNT/dev" 2>/dev/null || true
mount -B /dev/pts "$ROOTFS_MOUNT/pts" 2>/dev/null || true
mount --bind /proc "$ROOTFS_MOUNT/proc" 2>/dev/null || true
mount --bind /sys "$ROOTFS_MOUNT/sys" 2>/dev/null || true

# Backup fstab
echo "Backing up /etc/fstab..."
chroot "$ROOTFS_MOUNT" cp /etc/fstab /etc/fstab.bak 2>/dev/null

# Ask if user wants to clean up old fstab entries
read -p "Do you want to remove other fstab entries (except the root partition)? This will remove all entries that don't match the current filesystem." -r
CLEANUP_ENTRIES=false
echo    # Move to a new line
if [[ $REPLY =~ ^[Yy]$ ]]; then
  CLEANUP_ENTRIES=true
fi

if [ -n "$NEW_UUID" ]; then
  if [ "$CLEANUP_ENTRIES" = true ]; then
    # Update fstab: replace UUID, remove other non-root entries
    echo "Updating /etc/fstab (with cleanup)..."
    chroot "$ROOTFS_MOUNT" awk -v new_uuid="$NEW_UUID" -v root=/ \
      'BEGIN { printed_root=0 }
       $2 == "/" && $1 ~ /^UUID=/ {
         $1 = "UUID=" new_uuid
         print
         printed_root=1
         next
       }
       $2 != root { next }
       { print }
      ' /etc/fstab.bak | chroot "$ROOTFS_MOUNT" tee /etc/fstab > /dev/null
  else
    # Just update the root UUID
    echo "Updating /etc/fstab..."
    chroot "$ROOTFS_MOUNT" awk -v new_uuid="$NEW_UUID" '$2 == "/" && $1 ~ /^UUID=/ { $1 = "UUID=" new_uuid } { print }' /etc/fstab.bak | chroot "$ROOTFS_MOUNT" tee /etc/fstab > /dev/null
  fi
else
  echo "Warning: UUID not available, skipping fstab update"
fi

echo "fstab updated successfully"

# Cleanup
echo "Cleaning up mounts..."
umount "$ROOTFS_MOUNT/proc" 2>/dev/null || true
umount "$ROOTFS_MOUNT/sys" 2>/dev/null || true
umount "$ROOTFS_MOUNT/dev" 2>/dev/null || true
umount "$ROOTFS_MOUNT/pts" 2>/dev/null || true
umount "$ROOTFS_MOUNT" 2>/dev/null || true

exit 0
