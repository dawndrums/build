#!/bin/bash -e

export ARCH=arm
export CROSS_COMPILE=arm-linux-gnueabihf-

BOARD=$1
DEFCONFIG=""
DTB=""
KERNELIMAGE=""
CHIP=""
UBOOT_DEFCONFIG=""

case ${BOARD} in
	"divine-d.")
                DEFCONFIG=divine_d_linux_defconfig
                UBOOT_DEFCONFIG=divine-d-rk3588s_defconfig
                DTB=rk3588s-divine-d.dtb
                export ARCH=arm64
                export CROSS_COMPILE=aarch64-none-linux-gnu-
                CHIP="rk3588s"
                ;;

	*)
		echo "board '${BOARD}' not supported!"
		exit -1
		;;
esac

#build on native arm64
if [ "X$(uname -m)" == "Xaarch64" -a "X${ARCH}" == "Xarm64" ]; then
        unset ARCH
        unset CROSS_COMPILE
fi
