#!/bin/bash
# update-grub-chroot.sh - Update GRUB configuration in a chroot environment
# Usage: update-grub-chroot.sh <target_partition>

set -e

TARGET_PARTITION="$1"
ROOTFS_MOUNT="/mnt/rootfs"

if [ -z "$TARGET_PARTITION" ]; then
    echo "Usage: $0 <target_partition>"
    echo "Example: $0 /dev/sda2"
    exit 1
fi

# Get the root partition device (assuming it's the first partition on the disk)
ROOT_PARTITION=$(echo "$TARGET_PARTITION" | sed 's/[0-9]*$//')

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
mount --bind /run "$ROOTFS_MOUNT/run" 2>/dev/null || true

if command -v update-grub > /dev/null 2>&1; then
    echo "Running update-grub..."
    chroot "$ROOTFS_MOUNT" update-grub 2>&1
elif command -v grub-mkconfig > /dev/null 2>&1; then
    echo "update-grub not found, running grub-mkconfig..."
    echo "Note: This will generate a new GRUB configuration."
    read -p "Do you want to proceed with grub-mkconfig? (y/N) " -r
    echo    # Move to a new line
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        chroot "$ROOTFS_MOUNT" grub-mkconfig -o /boot/grub/grub.cfg 2>&1 || \
        chroot "$ROOTFS_MOUNT" grub-mkconfig -p /dev/$ROOT_PARTITION 2>&1
    else
        echo "Skipping grub-mkconfig"
    fi
else
    echo "Warning: Neither update-grub nor grub-mkconfig found"
fi

echo "GRUB configuration updated successfully"

# Cleanup
echo "Cleaning up mounts..."
umount "$ROOTFS_MOUNT/proc" 2>/dev/null || true
umount "$ROOTFS_MOUNT/sys" 2>/dev/null || true
umount "$ROOTFS_MOUNT/dev" 2>/dev/null || true
umount "$ROOTFS_MOUNT/pts" 2>/dev/null || true
umount "$ROOTFS_MOUNT/run" 2>/dev/null || true
umount "$ROOTFS_MOUNT" 2>/dev/null || true

exit 0
