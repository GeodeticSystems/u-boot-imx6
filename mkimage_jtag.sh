#!/bin/bash
#
# mkimage_jtag v1.0.0
# Copyright 2014 Gateworks Corporation <support@gateworks.com>
#
# create a binary image suitable for IMX6 targets for jtag_usbv4
#
# usage: mkimage_jtag [<SPL> <u-boot.img>]|[<SPL> <u-boot.img> <ubi>]|[<ubi>]
#
# Examples:
#   # create jtagable bin containing just bootloader (will not overwrite all)
#   mkimage_jtag <SPL> <u-boot.img> > uboot.bin
#   # create jtagable bin containing bootloader+ubi (will overwrite all)
#   mkimage_jtag <SPL> <u-boot.img> <ubi> > image.bin 
#   # create jtagable bin containing ubi (will not overwrite bootloader/env)
#   mkimage_jtag <ubi> > image.bin 
#
# This puts a simple header around the binary parts that make up a bootable
# image, sending the output to stdout.
#
# The header consists of the following structure (little-endian):
#
# u16 magic: GW
# u16 erase_mode:
#      0=erase entire flash (use only on first header)
#      1=erase none (perform no erase)
#      2=erase part (erase only this part - offset must align with flash block)
#      3=erase to end (erase from this part to end of device)
# u32 offset: byte offset in flash (logical) to program this data
#      (this must align with a flash block boundary if erasing part or to end
#       and otherwise must align with a flashs page boundary)
# u32 dsize: byte size of this data segment
# u32 psize: part size of this data segment
#
# The psize value is only used in the special case where dsize=0 which
# specifies a bootstream.  This must be the first part in a series of parts 
# and is programmed in a specific fashion on NAND FLASH in accordance with
# the requirements of the i.MX6 BOOT ROM.  In this case the data must
# be an i.MX6 bootlet containing an IVT and DCD, such as u-boot.imx.
#

ERASE_ALL=0
ERASE_NON=1
ERASE_PRT=2
ERASE_END=3

error() {
	echo "$@" 1>&2
	exit
}

debug() {
	echo "$@" 1>&2
}

getmode() {
	case $1 in
		$ERASE_ALL) echo "all";;
		$ERASE_NON) echo "segment";;
		$ERASE_PRT) echo "partition";;
		$ERASE_END) echo "to-end";;
	esac
}

getsize() {(
	local mult=1
	local val=$1
	local suffix regex

	shopt -s nocasematch
	for suffix in '' K M G; do
        	regex="^([0-9]+)(${suffix}i?B?)?\$"
		[[ $val =~ $regex ]] && {
			echo $((${BASH_REMATCH[1]} * mult))
			return 0
		}
        	regex="^0x([0-9A-Fa-f]+)(${suffix}i?B?)?\$"
		[[ $1 =~ $regex ]] && {
			echo $((0x${BASH_REMATCH[1]} * mult))
			return 0
		}

		((mult *= 1024))
	done
	echo "invalid size: $1" >&2
	return 1
)}

# output binary u32
# $1 int
u32() {
	b0=$(( $(($1>>24)) & 0xff))
	b1=$(( $(($1>>16)) & 0xff))
	b2=$(( $(($1>>8)) & 0xff))
	b3=$(( $(($1>>0)) & 0xff))

	/usr/bin/printf "\\x$(/usr/bin/printf "%x" $b3)"
	/usr/bin/printf "\\x$(/usr/bin/printf "%x" $b2)"
	/usr/bin/printf "\\x$(/usr/bin/printf "%x" $b1)"
	/usr/bin/printf "\\x$(/usr/bin/printf "%x" $b0)"
}

# output binary u16
# $1 int
u16() {
	b0=$(( $(($1>>8)) & 0xff))
	b1=$(( $(($1>>0)) & 0xff))

	/usr/bin/printf "\\x$(/usr/bin/printf "%x" $b1)"
	/usr/bin/printf "\\x$(/usr/bin/printf "%x" $b0)"
}

# emit a part
# $1 file
# $2 erase_mode
# $3 offset
# $4 size (only needed if offset==0 for bootloader part size)
emit()
{
	local file=$1
	local erase_mode=$2
	local offset=$3
	local part_size=${4:-0}
	local fsize

	if [ $(($part_size)) -eq 0 ]; then
		debug "$(/usr/bin/printf "  emit %s@0x%08x erase:%s\n" $file $offset $(getmode $erase_mode))"
	else
		debug "$(/usr/bin/printf "  emit %s@0x%08x-0x%08x erase:%s\n" $file $offset $((offset+part_size)) $(getmode $erase_mode))"
	fi

	[ "$file" -a -r "$file" ] || error "invalid file '$file'"
	fsize=$(ls -lL $file | awk '{print $5}')

	/usr/bin/printf "GW" # magic
	u16 $erase_mode
	u32 $offset
	u32 $fsize
	u32 $part_size
	cat $file
}

# Scripted usage: space separated list of:
#  file@offset[-end]
#  if -end not specified will erase up to size of file (rounded to end of block)
#  if end not specified will erase to end of device
#
# Examples:
#  - update falcon mode kernel at 18MB:
#  mkimage_jtag -s uImage@18M
#  - update SPL and uboot with full erase:
#  mkimage_jtag -e SPL@0 u-boot.img@14M
#  - erase env
#  dd if=/dev/zero of=env bs=1M count=1 && ./mkimage_jtag -s env@16M
[ "$1" = "-s" -o "$1" = "-e" ] && {
	mode=$1
	count=0
        #regex="^([0-9]+)(${suffix}i?B?)?\$"
	# <file>@<start>-<end>
        #regex="^(.+)@([0-9A-Z]+)-([0-9A-Z]+)\$"
	shift
	while [ "$1" ]; do
		count=$((count+1))
		str=$1
		shift

		if [ $count -eq 1 -a $mode = "-e" ]; then
			mode=$ERASE_ALL
		else
			mode=$ERASE_NON
		fi

		#debug "  parsing param${count}:$str"
		# file@start-end
		if [[ $str =~ ^(.*)@(.*)-(.+)$ ]]; then
			file=${BASH_REMATCH[1]}
			start=$(getsize ${BASH_REMATCH[2]})
			end=$(getsize ${BASH_REMATCH[3]})
			size=$(/usr/bin/printf "0x%x" $((end-start)))
			emit $file $mode $start $size
		# file@start-
		elif [[ $str =~ ^(.*)@(.*)-$ ]]; then
			file=${BASH_REMATCH[1]}
			start=$(getsize ${BASH_REMATCH[2]})
			emit $file $ERASE_END $start
		# file@start
		elif [[ $str =~ ^(.*)@(.*)$ ]]; then
			file=${BASH_REMATCH[1]}
			start=$(getsize ${BASH_REMATCH[2]})
			emit $file $mode $start
		else
			error "invalid parameter: $str"
		fi
	done
	exit
}


# output image to stdout
case $# in
	# ubi (w/o touching bootloader+env)
	1)
	debug "rootfs (erase to end):"
	emit $1 $ERASE_END 0x1100000	# rootfs@17MB- (erase to end)
	;;

	# bootloader (SPL + u-boot.img) w/o eraseing env/ubi 
	2)
	debug "SPL + u-boot.img (bootloader only):"
	emit $1 $ERASE_PRT 0 0xE00000	# SPL@0-14MB
	emit $2 $ERASE_PRT 0x0E00000 0x0200000	# u-boot@14MB-16MB
	;;

	# erase entire part and program SPL + u-boot.img + ubi
	3)
	debug "SPL + u-boot.img + ubi (full erase):"
	emit $1 $ERASE_ALL 0 0xE00000	# SPL@0-14MB
	emit $2 $ERASE_NON 0x0E00000	# u-boot@14MB
	emit $3 $ERASE_NON 0x1100000	# rootfs@17MB
	;;

	# erase entire part and program SPL + u-boot.img + kernel + ubi
	# mtdparts=nand:16m(uboot),10m(env),-(rootfs)
	4)
	debug "SPL + u-boot.img + kernel + ubi (full erase):"
	emit $1 $ERASE_ALL 0 0xE00000	# SPL@0-14MB
	emit $2 $ERASE_NON 0x0E00000	# u-boot@14MB
	emit $3 $ERASE_NON 0x1200000	# kernel@18MB
	emit $4 $ERASE_NON 0x1c00000	# rootfs@28MB-
	;;

	# erase entire part and program SPL + u-boot.img + env + kernel + ubi
	# mtdparts=nand:16m(uboot),10m(env),-(rootfs)
	5)
	debug "SPL + u-boot.img + env + kernel + ubi:"
	emit $1 $ERASE_ALL 0 0xE00000	# SPL@0-14MB
	emit $2 $ERASE_NON 0x0E00000	# u-boot@14MB
	emit $3 $ERASE_NON 0x1000000	# env@16MB
	emit $4 $ERASE_NON 0x1200000	# kernel@18MB
	emit $5 $ERASE_NON 0x1c00000	# rootfs@28MB-
	;;

	# usage
	*)
	echo "usage: $0 [<SPL> <u-boot.img>]|[<SPL> <u-boot.img> <ubi>]|[<ubi>]"
	exit 1
	;;
esac
