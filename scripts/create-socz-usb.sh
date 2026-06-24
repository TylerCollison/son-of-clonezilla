#!/usr/bin/env bash
set -euo pipefail

############################################################
# CONFIG
############################################################

WORKDIR="$(pwd)/build"
ISO_PATH="$WORKDIR/clonezilla.iso"

MOUNT_DIR="/mnt/clonezilla_usb"

mkdir -p "$WORKDIR"

echo "========================================"
echo " Clonezilla USB Builder (Stable Mode)"
echo "========================================"

############################################################
# 1. USB DEVICE WIZARD
############################################################

USB_DEVICE="${1:-}"

if [[ -z "$USB_DEVICE" ]]; then
  echo ""
  echo "No USB device provided."
  echo "Detected block devices:"
  echo ""

  lsblk -dpno NAME,SIZE,MODEL,TRAN | grep -E "usb|sd" || true

  echo ""
  read -rp "Enter target USB device (e.g. /dev/sdb): " USB_DEVICE
fi

if [[ ! -b "$USB_DEVICE" ]]; then
  echo "ERROR: Invalid block device: $USB_DEVICE"
  exit 1
fi

############################################################
# 2. DESTRUCTIVE CONFIRMATION
############################################################

echo ""
echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
echo " WARNING: THIS WILL ERASE THE USB DEVICE"
echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
echo ""
echo "Target: $USB_DEVICE"
echo ""

read -rp "Type YES to continue: " CONFIRM

if [[ "$CONFIRM" != "YES" ]]; then
  echo "Aborted."
  exit 1
fi

############################################################
# 3. FETCH LATEST CLONEZILLA
############################################################

echo "[1/4] Fetching latest Clonezilla version..."

VERSION=$(curl -fsSL \
  "https://sourceforge.net/projects/clonezilla/files/clonezilla_live_stable/" \
  | grep -oE 'clonezilla_live_stable/[0-9]+\.[0-9]+\.[0-9]+-[0-9]+' \
  | sed 's#.*/##' \
  | sort -V \
  | tail -1)

ISO_NAME="clonezilla-live-${VERSION}-amd64.iso"

URL="https://sourceforge.net/projects/clonezilla/files/clonezilla_live_stable/${VERSION}/${ISO_NAME}/download"

echo "Version: $VERSION"

############################################################
# 4. DOWNLOAD ISO
############################################################

echo "[2/4] Downloading ISO..."

wget \
  --content-disposition \
  --trust-server-names \
  -O "$ISO_PATH" \
  "$URL"

file "$ISO_PATH" | grep -q "ISO 9660" || {
  echo "ERROR: Download failed or invalid ISO"
  exit 1
}

############################################################
# 5. WRITE ISO TO USB
############################################################

echo "[3/4] Writing ISO to USB (DD)..."

sync

sudo dd if="$ISO_PATH" of="$USB_DEVICE" bs=4M status=progress conv=fsync

sync

echo "Write complete."

############################################################
# 6. DETECT USB PARTITION (CRITICAL FIX)
############################################################

echo "[4/4] Detecting mounted filesystem..."

sleep 5

lsblk -f "$USB_DEVICE"

PARTITION=$(lsblk -lnpo NAME,FSTYPE "$USB_DEVICE" \
  | awk '$2=="vfat" || $2=="iso9660" {print $1; exit}')

if [[ -z "$PARTITION" ]]; then
  echo ""
  echo "ERROR: No mountable partition found on USB."
  echo "Run: lsblk -f"
  exit 1
fi

echo "Using partition: $PARTITION"

############################################################
# 7. MOUNT USB
############################################################

echo "Mounting USB..."

sudo mkdir -p "$MOUNT_DIR"
sudo mount "$PARTITION" "$MOUNT_DIR"

############################################################
# 8. INJECT CUSTOM FILES
############################################################

echo "Injecting custom scripts..."

if [[ -d overlay/live ]]; then
  sudo mkdir -p "$MOUNT_DIR/live/custom-scripts"
  sudo cp -r overlay/live/* "$MOUNT_DIR/live/custom-scripts/" || true
fi

############################################################
# 9. OPTIONAL GRUB PATCH
############################################################

if [[ -f overlay/boot/grub/grub.cfg.patch ]]; then
  echo "Applying GRUB patch..."
  sudo patch -d "$MOUNT_DIR" -p0 < overlay/boot/grub/grub.cfg.patch || true
fi

sudo sync

############################################################
# 10. CLEANUP
############################################################

echo "Unmounting USB..."

sudo umount "$MOUNT_DIR"

echo ""
echo "========================================"
echo " SUCCESS"
echo " USB READY: $USB_DEVICE"
echo "========================================"