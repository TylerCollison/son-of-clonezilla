#!/usr/bin/env bash
set -euo pipefail

############################################################
# CONFIG
############################################################

WORKDIR="$(pwd)/build"
MOUNT_DIR="/mnt/clonezilla_usb"

mkdir -p "$WORKDIR"

echo "========================================"
echo " SoCZ USB Builder "
echo "========================================"

############################################################
# 1. USB DEVICE WIZARD
############################################################

USB_DEVICE="${1:-}"

if [[ -z "$USB_DEVICE" ]]; then
  echo ""
  echo "Available removable devices:"
  lsblk -dpno NAME,SIZE,MODEL,TRAN | grep -E "usb|sd" || true
  echo ""
  read -rp "Enter target USB device (e.g. /dev/sdb): " USB_DEVICE
fi

if [[ ! -b "$USB_DEVICE" ]]; then
  echo "ERROR: Invalid device $USB_DEVICE"
  exit 1
fi

############################################################
# 2. DESTRUCTIVE CONFIRMATION
############################################################

echo ""
echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
echo " WARNING: THIS WILL ERASE THE ENTIRE USB"
echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
echo "Target: $USB_DEVICE"
echo ""

read -rp "Type YES to continue: " CONFIRM
[[ "$CONFIRM" == "YES" ]] || exit 1

############################################################
# 3. DOWNLOAD CLONEZILLA
############################################################

echo "[1/5] Fetching latest Clonezilla..."

VERSION=$(curl -fsSL \
  "https://sourceforge.net/projects/clonezilla/files/clonezilla_live_stable/" \
  | grep -oE 'clonezilla_live_stable/[0-9]+\.[0-9]+\.[0-9]+-[0-9]+' \
  | sed 's#.*/##' \
  | sort -V \
  | tail -1)

ISO_NAME="clonezilla-live-${VERSION}-amd64.iso"

URL="https://sourceforge.net/projects/clonezilla/files/clonezilla_live_stable/${VERSION}/${ISO_NAME}/download"

echo "Version: $VERSION"

ISO_FILE="$WORKDIR/$ISO_NAME"

if [ -f "$ISO_FILE" ]; then
    echo "Latest ISO already downloaded"
else
    wget -O "$ISO_FILE" "$URL"
fi

file "$ISO_FILE" | grep -q "ISO 9660" || {
  echo "ERROR: Invalid ISO. Delete the file at $WORKDIR/$ISO_NAME and try again"
  exit 1
}

############################################################
# 4. WIPE + PARTITION USB (FAT32)
############################################################

echo "[2/6] Partitioning USB (MSDOS)..."

sudo wipefs -a "$USB_DEVICE"

sudo parted "$USB_DEVICE" --script mklabel msdos
sudo parted "$USB_DEVICE" --script mkpart primary fat32 1MiB 100%
sudo parted "$USB_DEVICE" --script set 1 boot on

sleep 2

PARTITION="${USB_DEVICE}1"

############################################################
# 5. FORMAT USB
############################################################

echo "[3/6] Formatting USB to FAT32..."

sudo mkfs.vfat -F32 "$PARTITION"

############################################################
# 6. MOUNT USB
############################################################

echo "[4/6] Mounting USB..."

sudo mkdir -p "$MOUNT_DIR"
sudo mount "$PARTITION" "$MOUNT_DIR"

############################################################
# 7. EXTRACT ISO TO USB
############################################################

echo "[5/6] Extracting Clonezilla ISO to USB..."

sudo apt-get update >/dev/null 2>&1 || true
command -v 7z >/dev/null 2>&1 || sudo apt-get install -y p7zip-full

sudo 7z x "$ISO_PATH" -o"$MOUNT_DIR" >/dev/null

############################################################
# 8. INJECT CUSTOM SCRIPTS
############################################################

echo "[6/6] Adding SoCZ files..."

if [[ -d overlay/live ]]; then
  sudo cp -r overlay/live/ "$MOUNT_DIR" || true
fi

############################################################
# 9. OPTIONAL GRUB PATCH
############################################################

if [[ -f "$MOUNT_DIR/boot/grub/grub.cfg" && -f overlay/boot/grub/grub.cfg.patch ]]; then
  echo "Applying GRUB patch..."
  sudo patch "$MOUNT_DIR/boot/grub/grub.cfg" < overlay/boot/grub/grub.cfg.patch || true
fi

############################################################
# 10. FINALIZE
############################################################

sync
sudo umount "$MOUNT_DIR"

echo ""
echo "========================================"
echo " SUCCESS"
echo " USB READY: $USB_DEVICE"
echo "========================================"