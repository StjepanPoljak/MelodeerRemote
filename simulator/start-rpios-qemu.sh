#!/bin/sh

SCRIPT_DIR="$(dirname "$(realpath $0)")"

. "${SCRIPT_DIR}/simulator.conf"

TEMP_RASPIOS_IMG="/tmp/${RASPIOS_IMG_NAME}"
RASPIOS_IMG_MNT="/mnt/${RASPIOS_IMG_NAME}"

ANDROID_X86_IMG_MNT="/mnt/android-x86"
ANDROID_X86_TEMP="/tmp/android-x86"

xz -d raspios-img/2023-05-03-raspios-bullseye-armhf-lite.img.xz -v -e -T 0 -c > "${TEMP_RASPIOS_IMG}"

sudo mkdir -p "${RASPIOS_IMG_MNT}"

sudo qemu-nbd -c /dev/nbd0 "${TEMP_RASPIOS_IMG}"
sudo mount /dev/nbd0p1 "${RASPIOS_IMG_MNT}"

echo "${RASPIOS_USR}" | openssl passwd -6 -stdin		\
		      | xargs -I{} echo "${RASPIOS_PWD}:{}"	\
		      | sudo tee "${RASPIOS_IMG_MNT}/userconf.txt"

sudo umount "${RASPIOS_IMG_MNT}"
sudo mount /dev/nbd0p2 "${RASPIOS_IMG_MNT}"

cat <<EOF | sudo tee -a "${RASPIOS_IMG_MNT}/etc/dhcpcd.conf"
interface eth0
static ip_address=${RASPIOS_IP}/${SIMULATOR_SUBNET}
static routers=${SIMULATOR_GATEWAY}
static domain_name_servers=${SIMULATOR_DNS}
EOF

sudo umount "${RASPIOS_IMG_MNT}"
sudo qemu-nbd -d /dev/nbd0
sudo rmdir "${RASPIOS_IMG_MNT}"

# mkdir -p "${ANDROID_X86_TEMP}"
# sudo mkdir -p "${ANDROID_X86_IMG_MNT}"
# sudo qemu-nbd -c /dev/nbd0 "${ANDROID_X86_IMG}"
# sudo mount /dev/nbd0p1 "${ANDROID_X86_IMG_MNT}"

# ANDROID_X86_SRC="${ANDROID_X86_IMG_MNT}$(awk 'f { print; f = 0 } { if ($0 ~ /^title Android-x86 [^ ]*$/) { f = 1 } }' "${ANDROID_X86_IMG_MNT}/grub/menu.lst" | sed -n 's/^.*SRC=\([^ ]*\).*$/\1/p')"

# sudo umount "${ANDROID_X86_IMG_MNT}"
# sudo qemu-nbd -d /dev/nbd0

sudo brctl addbr "${SIMULATOR_BRIDGE}"
sudo brctl addif "${SIMULATOR_BRIDGE}" enp4s0f1
sudo ip addr add "${SIMULATOR_GATEWAY}/${SIMULATOR_SUBNET}" dev "${SIMULATOR_BRIDGE}"
sudo ip link set dev "${SIMULATOR_BRIDGE}" up

docker network create --driver bridge --subnet "${SIMULATOR_NETWORK}" --gateway "${SIMULATOR_GATEWAY}" -o "com.docker.network.bridge.name=${SIMULATOR_BRIDGE}" "${SIMULATOR_BRIDGE}"

#sudo qemu-system-x86_64 -cpu host -enable-kvm -m 2048 -drive file=/home/${USER}/android.img,format=qcow2,index=0 -net nic -net bridge,br=${SIMULATOR_BRIDGE} &
#QEMU_PID=$!

export TEMP_RASPIOS_IMG
export SIMULATOR_BRIDGE
export RASPIOS_USR
export RASPIOS_PWD

./rpi-console.exp
#docker run -it -v ${TEMP_RASPIOS_IMG}:/sdcard/filesystem.img --network "${SIMULATOR_BRIDGE}" lukechilds/dockerpi:vm

sudo ip link del "${SIMULATOR_BRIDGE}"
docker network rm "${SIMULATOR_BRIDGE}"
#sudo kill ${QEMU_PID}

# sudo qemu-nbd -c /dev/nbd0 "${ANDROID_X86_IMG}"
# sudo mount /dev/nbd0p1 "${ANDROID_X86_IMG_MNT}"
# sudo umount "${ANDROID_X86_IMG_MNT}"
# sudo qemu-nbd -d /dev/nbd0
# sudo rmdir "${ANDROID_X86_IMG_MNT}"
# rm -rf "${ANDROID_X86_TEMP}"

rm -f "${TEMP_RASPIOS_IMG}"
