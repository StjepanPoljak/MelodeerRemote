#!/bin/sh

SCRIPT_DIR="$(dirname "$(realpath $0)")"

. "${SCRIPT_DIR}/simulator.conf"

export ANDROID_X86_IMG
export ANDROID_IP
export SIMULATOR_SUBNET_MASK
export SIMULATOR_GATEWAY
export SIMULATOR_BRIDGE

./qemu-console.exp

exit 0
