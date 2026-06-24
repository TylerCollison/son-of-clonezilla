#!/bin/bash
# Load DRBL setting and functions
DRBL_SCRIPT_PATH="${DRBL_SCRIPT_PATH:-/usr/share/drbl}"
DRBL_CONFIG_PATH="${DRBL_SCRIPT_PATH:-/etc/drbl}"

IMAGE_REPO_PATH="/home/partimag"
BOOT_PARTITION_PATH="/home/user/bootpart"
ISO_PARTITION_PATH="/home/user/isopart"
WINDOWS_PATH="/home/user/windows"
FILE_SYSTEMS=("exfat" "fat32" "ext2" "ext3" "ext4" "ntfs")
TRANSFER_UTILITIES=("7z", "dd")

# Load Clonezilla live functions and configuration
source $DRBL_SCRIPT_PATH/sbin/drbl-conf-functions
source $DRBL_CONFIG_PATH/conf/drbl-ocs.conf
source $DRBL_SCRIPT_PATH/sbin/ocs-functions && source /etc/ocs/ocs-live.conf

# Load language files. For English, use "en_US.UTF-8". For Traditional Chinese, use "zh_TW.UTF-8"
ask_and_load_lang_set en_US.UTF-8 

# Select a disk for the boot partition
lsblk -a -o NAME,LABEL,PARTUUID,PARTLABEL,SIZE
echo "Select a disk for the boot partition: "
availableBootDiskLine=$(lsblk -lando PATH)
availableBootDiskArray=($availableBootDiskLine)
select targetBootDisk in "${availableBootDiskArray[@]}"
do
    test -n "$targetBootDisk" && break
    echo ">>> Invalid disk selection!!! Try Again"
done

# Ask if the user wants to create a new boot partition
read -p "Do you want to create a new boot partition? " -r
echo    # Move to a new line
if [[ $REPLY =~ ^[Yy]$ ]]
then
  # User has confirmed. Create new partition on selected disk
  if bash "./createBasePartition.sh" "$targetBootDisk" "256" "MB"; then
    bootPartition=$(bash "./getLastOSPartition.sh" "$targetBootDisk")
  else
    # Failed to create new partition; restart
    echo "Error: failed to create new boot partition on selected disk"
    exec $(readlink -f "$0")
  fi
else
  # User has denied; Select an existing boot partition
  lsblk -a -o NAME,LABEL,PARTUUID,PARTLABEL,SIZE
  echo "Select the boot partition: "
  availablePartitionLine=$(lsblk -lano PATH | grep "$targetBootDisk")
  availablePartitionArray=($availablePartitionLine)
  select bootPartition in "${availablePartitionArray[@]}"
  do
      test -n "$bootPartition" && break
      echo ">>> Invalid partition selection!!! Try Again"
  done
fi

if fsck.vfat "$bootPartition"; then
  echo "The boot partition has a FAT32 filesystem"
else
  echo "The boot partition does not have a FAT32 filesystem or it may be damaged"
  # Ask if the user wants to format the boot partition
  read -p "Do you want to format the boot partition to FAT32? (Note: this will erase all data on the partition) " -r
  echo    # Move to a new line
  if [[ $REPLY =~ ^[Yy]$ ]]
  then
    mkfs.vfat -F32 "$bootPartition"
    if fsck.vfat "$bootPartition"; then
      echo "Boot partition successfully formatted to FAT32"
    else
      # Failed to create filesystem
      echo "Error: failed to create a FAT32 filesystem on the boot partition"
      exec $(readlink -f "$0")
    fi
  fi
fi

# Mount the boot partition
mkdir "$BOOT_PARTITION_PATH"
mount "$bootPartition" "$BOOT_PARTITION_PATH"

# Setup the boot partition
bootPartitionNumber=$(echo "${bootPartition##*[!0-9]}")
if bash "./setupBootPartition.sh" "$targetBootDisk" "$BOOT_PARTITION_PATH" "$bootPartitionNumber"; then
  echo "The boot partition has been configured correctly"
else
  echo "Warning: The boot partition is not configured correctly; some operations may fail"
fi

# Select a disk to manage
lsblk -a -o NAME,LABEL,PARTUUID,PARTLABEL,SIZE
echo "Select a disk to manage: "
availableDiskLine=$(lsblk -lando PATH)
availableDiskArray=($availableDiskLine)
select targetDisk in "${availableDiskArray[@]}"
do
    test -n "$targetDisk" && break
    echo ">>> Invalid disk selection!!! Try Again"
done
targetDiskName=${targetDisk//"/dev/"}

# Mount the image repo
prep-ocsroot

# Select an image to restore
echo "Select an ISO to restore: "
imageISOs=$(ls $IMAGE_REPO_PATH)
imageRepoISOArray=($imageISOs)
select image in "${imageRepoISOArray[@]}"
do
    test -n "$image" && break
    echo ">>> Invalid disk selection!!! Try Again"
done

# Get size for partition
read -p "Enter the size (in GB) for the new ISO partition: " -r
echo # Move to a new line
partitionSize="$REPLY"

# Create new partition
if bash "./createBasePartition.sh" "$targetDisk" "$partitionSize" "GB"; then
  targetPartitionPath=$(bash "./getLastOSPartition.sh" "$targetDisk")
  targetPartitionName=${targetPartitionPath//"/dev/"}

  echo "Select a transfer utility: "
  select util in "${TRANSFER_UTILITIES[@]}"
  do
      test -n "$util" && break
      echo ">>> Invalid utility selection!!! Try Again"
  done

  if [[ "$util" = "dd" ]]; then
    dd if="$IMAGE_REPO_PATH/$image" of="$targetPartitionPath" bs=4M status=progress
  fi

  if [[ "$util" = "7z" ]]; then
    echo "Select a filesystem for the new partition: "
    select filesystemType in "${FILE_SYSTEMS[@]}"
    do
        test -n "$filesystemType" && break
        echo ">>> Invalid filesystem selection!!! Try Again"
    done

    # Setup exfat filesystem on new partition
    if [[ "$filesystemType" = "exfat" ]]; then
      mkfs.exfat "$targetPartitionPath"
      if fsck.exfat "$targetPartitionPath"; then
        echo "Filesystem check passed."
      else
        echo "Filesystem check failed."
      fi 
    fi

    # Setup fat32 filesystem on new partition
    if [[ "$filesystemType" = "fat32" ]]; then
      mkfs.vfat -F32 "$targetPartitionPath"
      if fsck.vfat "$targetPartitionPath"; then
        echo "Filesystem check passed."
      else
        echo "Filesystem check failed."
      fi 
    fi

    # Setup ext2 filesystem on new partition
    if [[ "$filesystemType" = "ext2" ]]; then
      mkfs.ext2 "$targetPartitionPath"
      if fsck.ext2 "$targetPartitionPath"; then
        echo "Filesystem check passed."
      else
        echo "Filesystem check failed."
      fi 
    fi

    # Setup ext3 filesystem on new partition
    if [[ "$filesystemType" = "ext3" ]]; then
      mkfs.ext3 "$targetPartitionPath"
      if fsck.ext3 "$targetPartitionPath"; then
        echo "Filesystem check passed."
      else
        echo "Filesystem check failed."
      fi 
    fi

    # Setup ext4 filesystem on new partition
    if [[ "$filesystemType" = "ext4" ]]; then
      mkfs.ext4 "$targetPartitionPath"
      if fsck.ext4 "$targetPartitionPath"; then
        echo "Filesystem check passed."
      else
        echo "Filesystem check failed."
      fi 
    fi

    # Setup ntfs filesystem on new partition
    if [[ "$filesystemType" = "ntfs" ]]; then
      mkfs.ntfs "$targetPartitionPath"
      if fsck.ntfs "$targetPartitionPath"; then
        echo "Filesystem check passed."
      else
        echo "Filesystem check failed."
      fi 
    fi

    # Mount the boot partition
    mkdir "$ISO_PARTITION_PATH"
    mount "$targetPartitionPath" "$ISO_PARTITION_PATH"

    # Unzip the ISO to the new partition
    7z x "$IMAGE_REPO_PATH/$image" -o"$ISO_PARTITION_PATH"
  fi

  # Add the grub entry for the new partition
  echo "Adding grub entry for new partition"
  bash "./restoreGrub.sh" "$IMAGE_REPO_PATH/$image" "$BOOT_PARTITION_PATH" "$targetPartitionPath"

  # Ask if this is a Windows ISO
  read -p "Is this a Windows ISO and/or should it be visible to Windows installations? " -r
  echo    # Move to a new line
  if [[ $REPLY =~ ^[Yy]$ ]]
  then
    # Mount the Windows partition
    mkdir "$WINDOWS_PATH"
    mount "$targetPartitionPath" "$WINDOWS_PATH"

    # Set the partition type to "Microsoft Basic Data" (11)
    # This must be done for Windows ISO installations to work properly
    # For other ISO installs, setting the partition type to 11 will 
    # make the partition visible to Windows installations
    sfdisk --part-type "$targetDisk" "$targetPartitionNumber" "EBD0A0A2-B9E5-4433-87C0-68B6B72699C7"
  fi
  
else
  echo "Error: failed to create new partition"
  exit 1;
fi
