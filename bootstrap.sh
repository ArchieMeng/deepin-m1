#!/usr/bin/env bash

# SPDX-License-Identifier: MIT

set -o errexit
set -o nounset
set -o pipefail
set -o xtrace

cd "$(dirname "$0")"

unset LC_CTYPE
unset LANG

export DEBOOTSTRAP=debootstrap
MIRROR=https://community-packages.deepin.com/beige/

build_rootfs()
{
(
    mkdir -p cache
	sudo mount -o loop media testing
	sudo eatmydata ${DEBOOTSTRAP} --keyring /usr/share/keyrings/deepin-archive-camel-keyring.gpg --cache-dir=`pwd`/cache --arch=arm64 --include bash-completion,clang,fish,pciutils,wpasupplicant,vim,tmux,curl,wget,grub-efi-arm64,ca-certificates,sudo,openssh-client,gdisk,cryptsetup,wireless-regdb,zsh,zstd beige testing $MIRROR

    cd testing

    sudo mkdir -p boot/efi/m1n1 etc/X11/xorg.conf.d

    sudo bash -c 'echo deepin > etc/hostname'

	sudo bash -c "cat ../../files/sources.list > etc/apt/sources.list"

	sudo chroot . apt update
	sudo chroot . apt upgrade -y

    sudo cp ../../files/glanzmann.list etc/apt/sources.list.d/
    sudo cp ../../files/thomas-glanzmann.gpg etc/apt/trusted.gpg.d/
    sudo cp ../../files/hosts etc/hosts
    sudo cp ../../files/resolv.conf etc/resolv.conf
    sudo cp ../../files/quickstart.txt root/
    sudo cp ../../files/interfaces etc/network/interfaces
    sudo cp ../../files/wpa.conf etc/wpa_supplicant/wpa_supplicant.conf
    sudo cp ../../files/rc.local etc/rc.local
    sudo cp ../../files/30-modeset.conf etc/X11/xorg.conf.d/30-modeset.conf
    sudo cp ../../files/blacklist.conf etc/modprobe.d/
    sudo cp ../../files/99asahi etc/apt/preferences.d/

    sudo cp ../../files/grub etc/default/grub
    sudo -- perl -p -i -e 's/root:x:/root::/' etc/passwd

    sudo -- ln -s lib/systemd/systemd init
    sudo chroot . apt update
    sudo chroot . apt install -y linux-firmware m1n1 linux-image-asahi
    sudo chroot . apt clean
    sudo rm -r var/lib/apt/lists/* || true
)
}

build_dd()
{
(
    sudo rm -f media
    fallocate -l 15G media
    mkdir -p testing
    mkfs.ext4 media
    tune2fs -O extents,uninit_bg,dir_index -m 0 -c 0 -i 0 media
    sudo mount -o loop media testing
    sudo rm -rf testing/init testing/boot/efi/m1n1
    sudo umount testing
)
}

build_efi()
{
(
    sudo rm -rf EFI
    mkdir -p EFI/boot EFI/debian
	cp testing/usr/lib/grub/arm64-efi/monolithic/grubaa64.efi EFI/boot/bootaa64.efi
    export INITRD=`ls -1 testing/boot/ | grep initrd`
    export VMLINUZ=`ls -1 testing/boot/ | grep vmlinuz`
    export UUID=`blkid -s UUID -o value media`
    cat > EFI/debian/grub.cfg <<EOF
search.fs_uuid ${UUID} root
linux (\$root)/boot/${VMLINUZ} root=UUID=${UUID} rw net.ifnames=0 usbcore.autosuspend=-1
initrd (\$root)/boot/${INITRD}
boot
EOF
)
}

build_asahi_installer_image()
{
(
   sudo rm -rf aii
   mkdir -p aii/esp/m1n1
   cp -a EFI aii/esp/
   cp testing/usr/lib/m1n1/boot.bin aii/esp/m1n1/boot.bin
   ln media aii/media
   sudo umount media
   cd aii
   zip -r9 ../deepin-base.zip esp media
)
}

build_desktop_rootfs_image()
{
	CHROOT=testing
	sudo mount -o loop media ${CHROOT} || echo
	sudo mount proc-live -t proc ${CHROOT}/proc
	sudo mount devpts-live -t devpts -o gid=5,mode=620 ${CHROOT}/dev/pts || true
	sudo mount sysfs-live -t sysfs ${CHROOT}/sys
	sudo chroot testing apt update
	sudo chroot testing env DEBIAN_FRONTEND=noninteractive apt install -y $(grep -Ev "^linux" ../files/filesystem.packages | awk '{print $1}')
	sudo chroot testing apt clean
	sudo rm -r testing/var/lib/apt/lists/* || true

	# sudo chroot testing useradd -m -s /bin/bash hiweed
	# sudo chroot testing usermod -aG sudo hiweed
	# echo "Set passwd for default user hiweed"
	# sudo chroot testing bash -c 'echo -e "1\n1" | passwd hiweed'
    
    # Fix network issues
    sudo sed -i 's/managed=false/managed=true/' testing/etc/NetworkManager/NetworkManager.conf
    # Enable deepin-installer-first-boot and disable deepin-installer
    sudo chroot testing sed -i 's/no-first-boot/default/g' /usr/share/deepin-installer/configs/settings/default_settings.ini
    sudo chroot testing sed -i 's/test//g' /usr/share/deepin-installer/tools/deepin-installer-first-boot-preinit
    sudo chroot testing sed -i 's/update_apt_sources/# update_apt_sources/g' /usr/share/deepin-installer/tools/hooks/first_boot/14_cleanup_system.job
    sudo chroot testing ln -s /usr/lib/systemd/system/deepin-installer-first-boot.service /etc/systemd/system/basic.target.wants/deepin-installer-first-boot.service
    sudo chroot testing rm /etc/systemd/system/basic.target.wants/deepin-installer.service


	sudo umount -l ${CHROOT}/proc
	sudo umount -l ${CHROOT}/dev/pts
	sudo umount -l ${CHROOT}/sys

    sudo rm -rf ${CHROOT}/init ${CHROOT}/boot/efi/m1n1
	
	sudo rm -rf aii
    mkdir -p aii/esp/m1n1
    cp -a EFI aii/esp/
    cp testing/usr/lib/m1n1/boot.bin aii/esp/m1n1/boot.bin
    sudo umount -l ${CHROOT}

    ln media aii/media
    cd aii
    zip -r9 ../deepin-desktop.zip esp media
}

mkdir -p build
cd build

build_dd
build_rootfs
build_efi
# build_asahi_installer_image
build_desktop_rootfs_image
