#!/bin/sh

set -x

if [ "$2" == "" ] ; then
  echo "the parameters are <zfs_file_system> <device_to_boot>"
  exit 1
fi

boot_device="$2"
zfs_filesystem="$1"
zfs_filesystem_path=`zfs get -H mountpoint "${zfs_filesystem}" | awk '{ print $3 }'`
if [ ! -e "${zfs_filesystem_path}" ] ; then
  echo "${zfs_filesystem} is not mount (expected to be in ${zfs_filesystem_path})"
fi
zfs_filesystem_path="${zfs_filesystem_path}/"
 
system_filesystem="${zfs_filesystem}/system"
system_filesystem_path="${zfs_filesystem_path}system/"
root_filesystem="${system_filesystem}/root"
root_filesystem_path="${system_filesystem_path}root/"
boot_label="zfs_boot"
boot_volume_path="/mnt/${boot_label}/"
tmp_file="/tmp/file"

if [ ! -e "/dev/${boot_device}" ] ; then
  echo "the boot device doesn't exist ${boot_device}"
  exit 1
fi
if [ "${zfs_filesystem}" = "" ] ; then
  echo "please set the pool name in the first parameter"
  exit 1
fi
zpool export "${zfs_filesystem}"
if [ "$?" != "0" ] ; then
  echo "I can't unmount '${zfs_filesystem}'"
  exit 1
fi
zpool import "${zfs_filesystem}"
if [ "$?" != "0" ] ; then
  echo "I can't mount '${zfs_filesystem}'"
  exit 1
fi
if [ -e "${boot_volume_path}" ] ; then
  echo "${boot_volume_path} should be empty"
  exit 1
fi
 
###################################
# Create zpool
 
zfs create "${system_filesystem}"
if [ "$?" != "0" ] ; then
  echo "can not zfs create ${system_filesystem}"
  exit 1
fi
zfs create "${root_filesystem}"
if [ "$?" != "0" ] ; then
  echo "can not zfs create ${system_filesystem}"
  exit 1
fi
 
#zfs list "${zfs_filesystem}/swap" > /dev/null 2> /dev/null
#if [ "$?" != "0" ] ; then
#  zfs create -V 1g "${zfs_filesystem}/swap"
#  zfs set org.freebsd:swap=on "${zfs_filesystem}/swap"
#  zfs set checksum=off "${zfs_filesystem}/swap"
#fi
 
###################################
#create ufs boot device
 
if [ 1 = 0 ] ; then
  gpart create -s mbr "${boot_device}"
  if [ "$?" != "0" ]; then
    echo "Please destroy '{boot_device}' device"
    exit 1
  fi
  gpart add -t freebsd "${boot_device}"
  gpart set -a active -i 1 "${boot_device}"
  gpart create -s bsd "${boot_device}s1"
  gpart add -t freebsd-ufs "${boot_device}s1"
  gpart bootcode -b /boot/boot0 "${boot_device}"
  gpart bootcode -b /boot/boot "${boot_device}s1"
  boot_partition="${boot_device}s1a"
  newfs "/dev/${boot_partition}"
  glabel label "${boot_label}" "${boot_partition}"
else
  gpart create -s gpt "${boot_device}"
  if [ "$?" != "0" ]; then
    echo "Please destroy '{boot_device}' device"
    exit 1
  fi
  gpart add -b 34 -s 128 -t freebsd-boot "${boot_device}"
  gpart bootcode -b /boot/pmbr -p /boot/gptboot -i 1 "${boot_device}"
  gpart add -t freebsd-ufs -l "${boot_label}" "${boot_device}"
  boot_partition="${boot_device}p2"
  newfs "/dev/${boot_partition}"
  glabel label "${boot_label}" "${boot_partition}"
fi
if [ -e "${boot_volume_path}" ] ; then
  rm -fr "${boot_volume_path}"
fi
mkdir "${boot_volume_path}"
mount "/dev/${boot_partition}" "${boot_volume_path}"
 
cp -a /boot "${boot_volume_path}boot"
cp /boot/zfs/zpool.cache "${boot_volume_path}boot/zfs/zpool.cache"
echo 'zfs_load="YES"' >> "${boot_volume_path}boot/loader.conf"
echo "vfs.root.mountfrom=\"zfs:${root_filesystem}\"" >> "${boot_volume_path}boot/loader.conf"
echo 'vfs.root.mountfrom.options="rw"' >> "${boot_volume_path}boot/loader.conf"
 
umount "${boot_volume_path}"
rmdir "${boot_volume_path}"
 
###################################
# copy current / to zfs file system
 
which rsync > /dev/null 2> /dev/null
if [ "$?" != "0" ] ; then
  pkg_add -r rsync
fi

rsync -xa / "${root_filesystem_path}"

mv "${root_filesystem_path}etc/fstab" "${root_filesystem_path}etc/fstab.old"
echo "/dev/${boot_partition} ${boot_volume_path} ufs rw 1 1" >> "${root_filesystem_path}etc/fstab"
echo "${root_filesystem} / zfs rw 0 0" >> "${root_filesystem_path}etc/fstab"

root_device=`stat -f "%Dd" /`
storage_device=`stat -f "%Dd" "${zfs_filesystem_path}"`
for file in `ls /`; do
  file_device=`stat -f "%Dd" "/${file}"`
  if [ "${file_device}" != "${root_device}" -a "${file}" != "dev" -a "${file_device}" != "${storage_device}" ] ; then
    zfs create "${system_filesystem}/${file}"
    rsync -xa "/${file}" "${system_filesystem_path}"
    echo "${system_filesystem}/${file} /${file} zfs rw 0 0" >> "${root_filesystem_path}etc/fstab"
  fi
done

if [ ! -e "${root_filesystem_path}dev" ] ; then
  mkdir "${root_filesystem_path}dev"
fi

relative=`echo "${boot_volume_path}" | tail -c +2`
if [ ! -e "${root_filesystem_path}${relative}" ] ; then
  mkdir "${root_filesystem_path}${relative}"
fi
if [ -e "${root_filesystem_path}boot" ] ; then
  rm -fr "${root_filesystem_path}boot"
fi
ln -s "${relative}boot" "${root_filesystem_path}"
chflags -h sunlink "${root_storage_path}boot"
 
cat "${root_filesystem_path}etc/rc.conf" | grep -v "zfs_enable" > "${tmp_file}"
echo 'zfs_enable="YES"' >> "${tmp_file}"
mv "${tmp_file}" "${root_filesystem_path}etc/rc.conf"
