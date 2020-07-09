# ZFS_RAID1_UEFI_BOOT_FIXER
If you have a ZFS RAID1 setup over multiple devices and you'd like to be able to UEFI boot from any one of them, this script may help

This is no longer necessary. Proxmox now has pve-efiboot-tool

To use:
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

Lastly, you can use pve-efiboot-tool refresh to update all partitions but this happen automatically on kernel update.

