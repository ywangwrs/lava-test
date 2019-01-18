#!/bin/bash

if [ -z $4 ]; then
     echo "Usage:"
     echo "    $0 <telnet_port> <host_ip> <arm|arm64|x86_64|ppc|mips64> <kernel> <ext4> <dtb>"
     exit 0
fi

HOST_IP=$1
PORT=$2
MODEL=$3
KERNEL=$4
EXT4=$5

if [ "$MODEL" == 'arm' ]; then
     if [ -z $5 ]; then
         echo "dtb file is needed for running qemu-system-arm."
         exit 0
     else
         DTB=$5
     fi
     qemu_cmd='qemu-system-arm'
     base_opts='-machine vexpress-a9 -cpu cortex-a9 -m 256 -nographic'
     mac_addr='52:54:aa:12:34:01'
     tap_dev='mytap0'
     dtb_opts="-dtb $DTB"
     virtio_rng_opts=""
     virtio_net_opts="-device virtio-net-device,netdev=net0,mac=${mac_addr}"
elif [ "$MODEL" == 'arm64' ]; then
     qemu_cmd='qemu-system-aarch64'
     base_opts='-machine virt -cpu cortex-a57 -m 2048 -nographic'
     mac_addr='52:54:bb:12:34:01'
     tap_dev='mytap1'
     dtb_opts=""
     virtio_rng_opts="-device virtio-rng-pci"
     virtio_net_opts="-device virtio-net-device,netdev=net0,mac=${mac_addr}"
elif [ "$MODEL" == 'x86_64' ]; then
     qemu_cmd='qemu-system-x86_64'
     base_opts='-cpu core2duo -m 256 -nographic'
     mac_addr='52:54:cc:12:34:01'
     tap_dev='mytap2'
     dtb_opts=""
     virtio_rng_opts="-device virtio-rng-pci"
     virtio_net_opts=""
elif [ "$MODEL" == 'ppc' ]; then
     qemu_cmd='qemu-system-ppc'
     base_opts='-machine mac99 -cpu G4 -m 256 -nographic'
     mac_addr='52:54:dd:12:34:01'
     tap_dev='mytap3'
     virtio_rng_opts="-device virtio-rng-pci"
     virtio_net_opts="-device virtio-net-pci,netdev=net0,mac=${mac_addr}"
elif [ "$MODEL" == 'mips64' ]; then
     qemu_cmd='qemu-system-mips64'
     base_opts='-machine malta -m 256 -nographic'
     mac_addr='52:54:ee:12:34:01'
     tap_dev='mytap4'
     virtio_rng_opts="-device virtio-rng-pci"
     virtio_net_opts="-device virtio-net-pci,netdev=net0,mac=${mac_addr}"
else
     echo "This type of QEMU - $MODEL - is not supported for now."
     exit 0
fi

console_opts="-serial telnet:${HOST_IP}:${PORT},server"
kernel_opts="-kernel ${KERNEL}"

if [ "$MODEL" == 'x86_64' ]; then
     append_opts="-append 'root=/dev/vda rw highres=off console=ttyS0 mem=256M'"
     rootfs_opts="-drive file=${EXT4},if=virtio,format=raw $virtio_rng_opts"
     network_opts=""
else
     if [ "$MODEL" == 'ppc' ] || [ "$MODEL" == 'mips64' ]; then
         rootfs_opts="-drive file=${EXT4},if=virtio,format=raw $virtio_rng_opts"
     else
         rootfs_opts="-device virtio-blk-device,drive=disk0 -drive id=disk0,file=${EXT4},if=none,format=raw $virtio_rng_opts"
     fi

     network_opts="-netdev tap,id=net0,ifname=${tap_dev},script=no,downscript=no $virtio_net_opts"
     append_opts="-append 'root=/dev/vda rw highres=off console=ttyAMA0,115200 ip=dhcp'"
fi

cd /opt/qemu_scripts

echo "$qemu_cmd $base_opts $kernel_opts $dtb_opts \\"
echo "$rootfs_opts \\"
echo "$network_opts \\"
echo "$append_opts \\"
echo "$console_opts"

cmd="$qemu_cmd $base_opts $kernel_opts $rootfs_opts $dtb_opts $network_opts $append_opts $console_opts > /dev/null &"

eval $cmd

