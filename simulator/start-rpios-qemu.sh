#!/bin/sh -x

SCRIPT_DIR="$(dirname "$(realpath $0)")"

. "${SCRIPT_DIR}/simulator.conf"

RASPIOS_IMG_MNT="/mnt/${RASPIOS_IMG_DIR_BASENAME}"
TEMP_RASPIOS_DIR="/tmp/${RASPIOS_IMG_DIR_BASENAME}"

KERNEL_IMG=kernel8.img
RPI_DTB=bcm2710-rpi-3-b-plus.dtb

log() {
	echo "(i)" $@
}

error() {
	echo "(!)" $@
	exit 1
}

mount_raspios_partition() {

	PART=""

	if [ "${1}" = "boot" ]; then
		PART=p1
	elif [ "${1}" = "root" ]; then
		PART=p2
	else
		error "Invalid partition specified (available: root, boot)"
	fi

	sudo mkdir -p "${RASPIOS_IMG_MNT}"
	sudo qemu-nbd -c /dev/nbd0 "${RASPIOS_IMG}"
	sudo mount /dev/nbd0${PART} "${RASPIOS_IMG_MNT}"
}

unmount_raspios() {

	sudo umount "${RASPIOS_IMG_MNT}"
	sudo qemu-nbd -d /dev/nbd0
	sudo rmdir "${RASPIOS_IMG_MNT}"
}

create_raspios_user() {

	echo "${RASPIOS_USR}" | openssl passwd -6 -stdin		\
			      | xargs -I{} echo "${RASPIOS_PWD}:{}"	\
			      | sudo tee "${RASPIOS_IMG_MNT}/userconf.txt"
	sudo touch "${RASPIOS_IMG_MNT}/ssh"
}

configure_raspios_dhcp() {

	cat <<-EOF | sudo tee -a "${RASPIOS_IMG_MNT}/etc/dhcpcd.conf"
	interface eth0
	static ip_address=${RASPIOS_IP}/${SIMULATOR_SUBNET}
	static routers=${SIMULATOR_GATEWAY}
	static domain_name_servers=${SIMULATOR_DNS}
	EOF
}

adjust_image_size() {

	IMAGE_SIZE="$(qemu-img info --output json "${RASPIOS_IMG}"	\
			| grep "virtual-size"				\
			| awk '{print $2}'				\
			| sed 's/,//')"

	SIZE_2GIB="$(echo '2 * 1024^3' | bc)"
	SIZE_2GIB_REMAINDER="$(echo "${IMAGE_SIZE} % ${SIZE_2GIB}" | bc)"

	if [ "${SIZE_2GIB_REMAINDER}" -ne 0 ]; then
		SIZE="$(echo "((${IMAGE_SIZE} / ${SIZE_2GIB}) + 1) * 2" | bc)"
		qemu-img resize "${RASPIOS_IMG}" "${SIZE}G"
	fi
}

get_raspios_image() {

	[ -d "${TEMP_RASPIOS_DIR}" ] || mkdir -p "${TEMP_RASPIOS_DIR}"

	mkdir -p "${TEMP_RASPIOS_DIR}"

	if ! [ -e "${RASPIOS_IMG}" ]; then
		[ -d "${RASPIOS_IMG_DIR}" ] || mkdir -p "${RASPIOS_IMG_DIR}"
		curl "${RASPIOS_LINK}" -o "${RASPIOS_IMG}.xz"
		xz -d "${RASPIOS_IMG}.xz" -v -e -T 0

		mount_raspios_partition "boot"
		create_raspios_user
		cp "${RASPIOS_IMG_MNT}/${KERNEL_IMG}"		\
		   "${RASPIOS_IMG_MNT}/${RPI_DTB}"		\
		   "${RASPIOS_IMG_DIR}"
		unmount_raspios

		mount_raspios_partition "root"
		#configure_raspios_dhcp
		unmount_raspios

		adjust_image_size

		tar cSvf "${RASPIOS_IMG_NAME}.tar.xz" -C "${RASPIOS_IMG_DIR}" .

		mv "${RASPIOS_IMG_NAME}.tar.xz" "${RASPIOS_IMG}.tar.xz"

		mv "${RASPIOS_IMG}"				\
		   "${RASPIOS_IMG_DIR}/${KERNEL_IMG}"		\
		   "${RASPIOS_IMG_DIR}/${RPI_DTB}"		\
		   "${TEMP_RASPIOS_DIR}"
	else
		log "Reusing image: \"${RASPIOS_IMG}.tar.xz\""

		tar xSvf "${RASPIOS_IMG}.tar.xz" -C "${TEMP_RASPIOS_DIR}"
	fi
}

create_network_bridge() {

	sudo brctl addbr "${SIMULATOR_BRIDGE}"
	sudo ip addr add "${SIMULATOR_GATEWAY}/${SIMULATOR_SUBNET}"	\
		dev "${SIMULATOR_BRIDGE}"

	docker network create --driver bridge				\
		--subnet "192.168.150.0/24"				\
		--gateway "192.168.150.1"				\
		--aux-address "android-ip=192.168.150.3"		\
		--aux-address "rpi-ip=192.168.150.4"			\
		-o "com.docker.network.bridge.name=${SIMULATOR_BRIDGE}"	\
		"${SIMULATOR_BRIDGE}"

	sudo ip link set dev "${SIMULATOR_BRIDGE}" up
}

run_raspios_docker() {

	IPTABLES="${SCRIPT_DIR}/iptables/xtables-legacy-multi"

	KERNEL_CMDLINE="rw					\
			earlyprintk				\
			console=ttyAMA0,115200			\
			dwc_otg.fiq_fsm_enable=0		\
			root=/dev/mmcblk0p2			\
			dwc_otg.lpm_enable=0			\
			rootwait				\
			panic=1					\
			random.trust_cpu=on"

	DOCKER_RASPIOS_IMG_DIR="/tmp/raspios-img"
	DOCKER_RASPIOS_IMG="${DOCKER_RASPIOS_IMG_DIR}/${RASPIOS_IMG_NAME}"

	RASPIOS_QEMU_COMM="
	/tmp/xtables iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE;\
	qemu-system-aarch64						\
		-machine raspi3b					\
		-cpu cortex-a72						\
		-m 1G							\
		-kernel \"${DOCKER_RASPIOS_IMG_DIR}/${KERNEL_IMG}\"	\
		-append \"${KERNEL_CMDLINE}\"				\
		-dtb \"${DOCKER_RASPIOS_IMG_DIR}/${RPI_DTB}\"		\
		-drive file=\"${DOCKER_RASPIOS_IMG}\",format=raw	\
		-device usb-net,netdev=net0				\
		-netdev user,id=net0					\
		-display none						\
		-serial mon:stdio"

	docker run -it -v "${RASPIOS_IMG_DIR}":/tmp/raspios-img		\
		--network "${SIMULATOR_BRIDGE}"				\
		--volume "${IPTABLES}":/tmp/xtables			\
		--ip "${RASPIOS_CONTAINER_IP}"				\
		--cap-add=NET_ADMIN					\
		--entrypoint "/bin/sh"					\
		--publish 5555:22					\
		lukechilds/dockerpi:vm -c "${RASPIOS_QEMU_COMM}"
}

cleanup_network_bridge() {

	sudo ip link del "${SIMULATOR_BRIDGE}"
	docker network rm "${SIMULATOR_BRIDGE}"
}

cleanup_temp_files() {

	rm -rf "${TEMP_RASPIOS_DIR}"
}

main() {

	get_raspios_image
	create_network_bridge
	run_raspios_docker
	cleanup_network_bridge
	cleanup_temp_files
}

main
