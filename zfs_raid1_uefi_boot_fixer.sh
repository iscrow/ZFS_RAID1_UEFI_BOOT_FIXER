#!/usr/bin/env bash

function error {
  MSG="$*"
  echo "Unexpected state: $MSG"
  echo "Cannot continue. Exiting..."
  exit 1
}

function setupUEFIBoot {
  local DEVICE=$1
  local PARTITION=$2
  local MOUNT="/boot/efi$COUNTER"
  local LABEL="BOOT_EFI_$COUNTER"
  FSTAB="/dev/disk/by-label/$LABEL $MOUNT vfat defaults,nofail 0 1"

  umount $MOUNT &> /dev/null
  mkdir $MOUNT &> /dev/null
  mkfs.vfat $PARTITION || error "Error formatting $PARTITION"
  fatlabel $PARTITION $LABEL || error "Error labeling $PARTITION"
  mount $PARTITION $MOUNT || error "Error mounting $PARTITION"
  [ "$(grub-probe -d $PARTITION)" == "fat" ] || error "Partition $PARTITION not formatted as fat filesystem"
  update-grub || error "Error running grub update"
  grub-install --directory=/usr/lib/grub/x86_64-efi --efi-directory=$MOUNT $DEVICE || error "Error running grub-install on $DEVICE"
  grep -q "$FSTAB" /etc/fstab || echo "$FSTAB" >> /etc/fstab
  [ -z "$MOUNTPART" ] && MOUNTPART="$PARTITION"
}

[ -d /boot/efi ] || error "/boot/efi directory does not exist"
[ "$(zpool list | grep rpool | wc -l)" -eq 1 ] || error "ZFS pool rpool not found"

BOOTDEV_COUNT=0
BOOTPARTS=""
MOUNTPART=""
COUNTER=0

for PARTITION in $(cat /proc/partitions | grep -P '.*\d' | awk '{print "/dev/"$4}'); do
  DEVICE=$(echo $PARTITION | sed -E 's|(.*)p[0-9]+|\1|g')
  echo "Checking device $DEVICE partition $PARTITION"
  [ "$(fdisk -l "$DEVICE" 2>/dev/null | grep "$PARTITION " | grep '512M EFI System' | wc -l)" -eq 1 ] || continue
  echo "Device $DEVICE and partition $PARTITION are valid candidates"
  ((BOOTDEV_COUNT++))
  BOOTPARTS+="$PARTITION "
done

[ "$BOOTDEV_COUNT" -eq 2 ] || error "Did not find 2 EFI System partitions"
echo
echo "Detected both EFI partitions $BOOTPARTS"
echo

for PARTITION in $BOOTPARTS; do
  DEVICE=$(echo $PARTITION | sed -E 's|(.*)p[0-9]+|\1|g')
  [ -b "$PARTITION" ] || error "Partition $PARTITION not a block device"
  [ -b "$DEVICE" ] || error "Device $DEVICE not a block device"
  echo "Configuring partition $PARTITION on device $DEVICE"
  ((COUNTER++))
  umount /boot/efi &> /dev/null
  setupUEFIBoot "$DEVICE" "$PARTITION"
done
