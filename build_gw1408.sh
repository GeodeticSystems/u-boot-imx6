#!/bin/bash

export PATH=$PATH:$HOME/gw_1408/staging_dir/toolchain-arm_cortex-a9+neon_gcc-4.8-linaro_uClibc-0.9.33.2_eabi/bin
export STAGING_DIR=$HOME/gw_1408/staging_dir
export CROSS_COMPILE=arm-openwrt-linux-

make gwventana_config
make
