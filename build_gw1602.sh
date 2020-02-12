#!/bin/bash

export PATH=$PATH:$HOME/gw_1602/staging_dir/toolchain-arm_cortex-a9+neon_gcc-5.2.0_musl-1.1.12_eabi/bin
export STAGING_DIR=$HOME/gw_1602/staging_dir
export CROSS_COMPILE=arm-openwrt-linux-

make gwventana_config
make
