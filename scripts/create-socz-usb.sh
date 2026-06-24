#!/usr/bin/env bash
set -euo pipefail

############################################################
# CONFIG
############################################################

WORKDIR="$(pwd)/build"
ISO_PATH="$WORKDIR/clonezilla.iso"

mkdir -p "$WORKDIR"

echo "========================================"
echo " Clonezilla USB Custom Builder"
echo "========================================"

############################################################
# 1. SELECT USB DEVICE (WIZARD OR ARG)
############################################################

USB_DEVICE="${1:-}"

if [[ -z "$USB_DEVICE" ]]; then
  echo ""
  echo "No USB device provided as argument."
  echo "Detecting removable devices..."
  echo ""

  lsblk -dpno NAME,SIZE,MODEL,TRAN | grep -E "usb|sd" || true

  echo ""
  read -rp "Enter target USB device (e.g. /dev/sdb): " USB_DEVICE
fi

# Validate device exists
if [[ ! -b "$USB_DEVICE" ]]; then
  echo "ERROR: $USB_DEVICE is not a valid block device."
  exit 1
fi

############################################################
# 2. DESTRUCTIVE WARNING
############################################################

echo ""
echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
echo " WARNING: DESTRUCTIVE OPERATION "
echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
echo ""
echo "Target device: $USB_DEVICE"
echo ""
echo "THIS WILL COMPLETELY ERASE THE DEVICE ABOVE."
echo "ALL DATA ON IT WILL BE LOST."
echo ""

read -rp "Type YES to continue, anything else to abort: " CONFIRM

if [[ "$CONFIRM" != "YES" ]]; then
  echo "Aborted."
  exit 1
fi

echo "Proceeding..."
echo ""

############################################################
# 3. GET LATEST CLONEZILLA
############################################################

echo "[1/5] Fetching latest Clonezilla version..."

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

echo "[2/5] Downloading ISO..."

wget \
  --content-disposition \
  --trust-server-names \
  -O "$ISO_PATH" \
  "$URL"

file "$ISO_PATH" | grep -q "ISO 9660" || {
  echo "ERROR: Invalid ISO"
  exit 1
}

############################################################
# 5. WRITE ISO TO USB
############################################################

echo "[3/5] Writing ISO to USB (THIS WILL ERASE DEVICE)..."

sync

sudo dd if="$ISO_PATH" of="$USB_DEVICE" bs=4M status=progress conv=fsync

sync

echo "Write complete."

############################################################
# MOUNT ISO (NOT USB)
############################################################

echo "[4/5] Mounting ISO (loop device)..."

ISO_MOUNT="/mnt/clonezilla_iso"
sudo mkdir -p "$ISO_MOUNT"

sudo mount -o loop "$ISO_PATH" "$ISO_MOUNT"

############################################################
# COPY CUSTOM FILES INTO USB AFTER DD IS DONE
############################################################

echo "[5/5] Injecting scripts onto USB..."

USB_MOUNT="/mnt/usb_live"
sudo mkdir -p "$USB_MOUNT"

# try auto-detect USB partition
PARTITION=$(lsblk -lnpo NAME "$USB_DEVICE" | tail -n1)

sudo mount "$PARTITION" "$USB_MOUNT"

sudo mkdir -p "$USB_MOUNT/live/custom-scripts"
sudo cp -r overlay/live/* "$USB_MOUNT/live/custom-scripts/" || true

############################################################
# 8. CLEANUP
############################################################

echo "Unmounting USB..."

sudo umount "$ISO_MOUNT"
sudo umount "$USB_MOUNT"

echo ""
echo "========================================"
echo " SUCCESS"
echo " USB ready: $USB_DEVICE"
echo "========================================"