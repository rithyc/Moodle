#!/bin/bash

timeStamp=$(date +'%y%m%d_%H%M%S')
echo "=> VMSS Extension Started [$timeStamp]"

# Specific for this instance
if [[ $1 =~ ^gluster-vm-(.+)$ ]]; then
  glusterNode="$1"
else
  printf "Syntax: $0 <glusterVMName>\n"
  exit 10
fi
glusterVolume=data

set -ex

# gluster
sudo add-apt-repository ppa:gluster/glusterfs-3.10 -y
sudo apt-get -y update
sudo apt-get -y install glusterfs-client

# Mount gluster fs for /moodle
sudo mkdir -p /moodle
sudo chown www-data /moodle
sudo chmod 770 /moodle
sudo echo -e 'Adding Gluster FS to /etc/fstab and mounting it'
grep -q "/moodle.*glusterfs" /etc/fstab || echo "$glusterNode:/$glusterVolume /moodle glusterfs defaults,_netdev,log-level=WARNING,log-file=/var/log/gluster.log 0 0" >> /etc/fstab
mount /moodle

# look for the chained configurator
echo "=> Chaining the custom node configuration"
if [ -f /moodle/scripts/unmoodle_vmss_newnode.sh ]; then
  sh /moodle/scripts/unmoodle_vmss_newnode.sh > /var/log/unmoodle_vmss_newnode.log
fi

echo "=> VMSS Extension Done [$timeStamp]"
