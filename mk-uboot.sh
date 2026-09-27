#!/bin/bash

export ARCH=arm
export CROSS_COMPILE=arm-linux-gnueabihf-

LOCALPATH=$(pwd)
OUT=${LOCALPATH}/out
TOOLPATH=${LOCALPATH}/rkbin/tools
BOARD=$1

PATH=$PATH:$TOOLPATH

finish() {
	echo -e "\e[31m MAKE UBOOT IMAGE FAILED.\e[0m"
	exit -1
}
trap finish ERR

if [ $# != 1 ]; then
	BOARD=rk3288-evb
fi

[ ! -d ${OUT} ] && mkdir ${OUT}
[ ! -d ${OUT}/u-boot ] && mkdir ${OUT}/u-boot
[ ! -d ${OUT}/u-boot/spi ] && mkdir ${OUT}/u-boot/spi

SPI_IMAGE=${OUT}/u-boot/spi/spi_image.img


prepare_rk3588_trust_blobs() {
	local rkbin_root="${LOCALPATH}/rkbin"
	local trust_ini="${rkbin_root}/RKTRUST/RK3588TRUST.ini"
	local bl31_rel bl32_rel

	if [ ! -f "${trust_ini}" ]; then
		echo "ERROR: missing ${trust_ini}" >&2
		return 1
	fi

	bl31_rel=$(sed -n '/^PATH=.*_bl31_.*\.elf$/s/^PATH=//p' "${trust_ini}" | head -n 1 | tr -d '\r')
	bl32_rel=$(sed -n '/^PATH=.*_bl32_.*\.bin$/s/^PATH=//p' "${trust_ini}" | head -n 1 | tr -d '\r')

	if [ -z "${bl31_rel}" ] || [ ! -f "${rkbin_root}/${bl31_rel}" ]; then
		echo "ERROR: BL31 not found from ${trust_ini}: ${bl31_rel}" >&2
		return 1
	fi

	if [ -z "${bl32_rel}" ] || [ ! -f "${rkbin_root}/${bl32_rel}" ]; then
		echo "ERROR: BL32/OP-TEE not found from ${trust_ini}: ${bl32_rel}" >&2
		return 1
	fi

	install -m 0644 "${rkbin_root}/${bl31_rel}" bl31.elf
	install -m 0644 "${rkbin_root}/${bl32_rel}" tee.bin

	echo "Using BL31: ${rkbin_root}/${bl31_rel}"
	echo "Using BL32: ${rkbin_root}/${bl32_rel}"
}

generate_spi_image() {
	dd if=/dev/zero of=$SPI_IMAGE bs=1M count=0 seek=16
	parted -s $SPI_IMAGE mklabel gpt
	parted -s $SPI_IMAGE unit s mkpart idbloader 64 7167
	parted -s $SPI_IMAGE unit s mkpart vnvm 7168 7679
	parted -s $SPI_IMAGE unit s mkpart reserved_space 7680 8063
	parted -s $SPI_IMAGE unit s mkpart reserved1 8064 8127
	parted -s $SPI_IMAGE unit s mkpart uboot_env 8128 8191
	parted -s $SPI_IMAGE unit s mkpart reserved2 8192 16383
	parted -s $SPI_IMAGE unit s mkpart uboot 16384 32734

	if [ -e "${OUT}/u-boot/spi/idbloader.img" ] && [ -e "${OUT}/u-boot/spi/u-boot.itb" ]; then
		dd if=${OUT}/u-boot/spi/idbloader.img of=$SPI_IMAGE seek=64 conv=notrunc
		dd if=${OUT}/u-boot/spi/u-boot.itb of=$SPI_IMAGE seek=16384 conv=notrunc
	else
		dd if=${OUT}/u-boot/idbloader.img of=$SPI_IMAGE seek=64 conv=notrunc
		dd if=${OUT}/u-boot/u-boot.itb of=$SPI_IMAGE seek=16384 conv=notrunc
	fi
}

source $LOCALPATH/build/board_configs.sh $BOARD

if [ $? -ne 0 ]; then
	exit
fi

echo -e "\e[36m Building U-boot for ${BOARD} board! \e[0m"
echo -e "\e[36m Using ${UBOOT_DEFCONFIG} \e[0m"

cd ${LOCALPATH}/u-boot

if [ "${CHIP}" == "rk3588s" ] || [ "${CHIP}" == "rk3588" ]; then
	make ${UBOOT_DEFCONFIG}
	prepare_rk3588_trust_blobs
	make spl/u-boot-spl.bin u-boot.dtb u-boot.itb
	./tools/mkimage -n rk3588 -T rksd -d ../rkbin/bin/rk35/rk3588_ddr_lp4_1866MHz_lp4x_2112MHz_lp5_2400MHz_v1.19.bin:spl/u-boot-spl.bin idbloader.img
	cp u-boot.itb ${OUT}/u-boot/
	cp idbloader.img ${OUT}/u-boot/
	cp ../rkbin/bin/rk35/rk3588_spl_loader_v1.19.113.bin ${OUT}/u-boot
	if [ -n "$UBOOT_SPI_DEFCONFIG" ]; then
		make distclean
		make ${UBOOT_SPI_DEFCONFIG}
		prepare_rk3588_trust_blobs
		make spl/u-boot-spl.bin u-boot.dtb u-boot.itb
		./tools/mkimage -n rk3588 -T rksd -d ../rkbin/bin/rk35/rk3588_ddr_lp4_1866MHz_lp4x_2112MHz_lp5_2400MHz_v1.19.bin:spl/u-boot-spl.bin idbloader.img
		cp u-boot.itb ${OUT}/u-boot/spi/
		cp idbloader.img ${OUT}/u-boot/spi/
		cp ../rkbin/bin/rk35/rk3588_spl_loader_v1.19.113.bin ${OUT}/u-boot/spi/
	fi
	generate_spi_image
        $TOOLPATH/loaderimage --pack --uboot ./arch/arm/dts/rk3588s-divine-d.dtb uboot.img 0x200000

        cp uboot.img ${OUT}/u-boot/
        echo "uboot.img is ready"
fi

echo -e "\e[36m U-boot IMAGE READY! \e[0m"
