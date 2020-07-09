#!/usr/bin/env bash

function error {
  MSG="$*"
  echo "Unexpected state: $MSG"
  echo "Cannot continue. Exiting..."
  exit 1
}

function warn {
  cat <<-EOF

	This is no longer necessary. Proxmox now has pve-efiboot-tool

	To use pve-efiboot-tool:

	Find your EFI partitions. They're usually /dev/sda2 and /dev/sdb2, I will use /dev/sdz2 as an example:
	For each EFI partition on each drive perform the following:

	First format the EFI partition. Use --force if the this is not a new disk and the partition was previously formatted:

        pve-efiboot-tool format /dev/sdz2

	or, if necessary

	pve-efiboot-tool format /dev/sdz2 --force
	
	Then initialize the partition. This makes it bootable and adds it to the proxmox efi partition sync for multiple boot disks/partitions:

	pve-efiboot-tool init /dev/sdz2

	Any initialized partitioins' UUIDs are added to a list /etc/kernel/pve-efiboot-uuids. That's how proxmox knows what partitions to update when new kernels are installed via update. These UUIDs correspond to the EFI partition IDS in /dev/disk/by-uuid/. the list may contain old no longer existing UUIDs and will complain about them. this won't break anything but to remove the warnings just remove the UUIDs of any missing partitions that you don't expect to be reconnected later from /etc/kernel/pve-efiboot-uuids. The error will look like:
	WARN: /dev/disk/by-uuid/4590-E286 does not exist - clean '/etc/kernel/pve-efiboot-uuids'! - skipping

	If you really need to run this, supply the --yolo flag:
	zfs_raid1_uefi_boot_fixer.sh --yolo

	EOF
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

function partitionToDevice {
  echo "$1" | sed -E 's/(.*)([0-9]+$|([0-9]+n[0-9]+)p[0-9]+)/\1\3/g'
}

[ "$1" == "--yolo" ] || warn

[ -d /boot/efi ] || error "/boot/efi directory does not exist"
[ "$(zpool list | grep rpool | wc -l)" -eq 1 ] || error "ZFS pool rpool not found"

BOOTDEV_COUNT=0
BOOTPARTS=""
MOUNTPART=""
COUNTER=0

for PARTITION in $(cat /proc/partitions | grep -P '.*\d' | awk '{print "/dev/"$4}'); do
  DEVICE=$(partitionToDevice $PARTITION)
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
  DEVICE=$(partitionToDevice $PARTITION)
  [ -b "$PARTITION" ] || error "Partition $PARTITION not a block device"
  [ -b "$DEVICE" ] || error "Device $DEVICE not a block device"
  echo "Configuring partition $PARTITION on device $DEVICE"
  ((COUNTER++))
  umount /boot/efi &> /dev/null
  setupUEFIBoot "$DEVICE" "$PARTITION"
done
