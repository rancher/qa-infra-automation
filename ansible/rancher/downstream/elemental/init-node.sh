#!/bin/bash

cd /home/ubuntu   

echo "Download element iso"
wget --no-check-certificate -O /tmp/elemental.iso $DOWNLOAD_URL

echo "Installing virt-manager"
sudo apt-get update --yes
sudo apt-get install --yes virt-manager

echo "Creating ENV variables"
export VM_NAME="vm-elemental-node"
export VM_ISO="/tmp/elemental.iso"
export VM_NET="default"
export VM_OS="slem5.3"
export VM_IMG="${VM_NAME}.qcow2"
export VM_CORES=8
export VM_DISKSIZE=60
export VM_RAMSIZE=8000

echo "Creating VM"
sudo virt-install \
--name ${VM_NAME} \
--memory ${VM_RAMSIZE} \
--vcpus ${VM_CORES} \
--os-variant=${VM_OS} \
--cdrom ${VM_ISO} \
--network network=${VM_NET},model=virtio \
--disk path=/tmp/${VM_IMG},size=${VM_DISKSIZE},bus=virtio,format=qcow2 \
--boot uefi \
--cpu host-model \
--autostart \
--noautoconsole \
--wait=-1 \
--check disk_size=off