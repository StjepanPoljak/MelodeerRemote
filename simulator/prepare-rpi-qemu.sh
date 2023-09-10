#!/bin/sh

SCRIPT_DIR="$(dirname "$(realpath $0)")"

. "${SCRIPT_DIR}/simulator.conf"

RASPIOS_XZ="/tmp/${RASPIOS_IMG_NAME}.xz"

mkdir -p "${RASPIOS_IMG_DIR}"

curl "${RASPIOS_LINK}.sha256" -o "${RASPIOS_XZ}.sha256"
ORIG_SHA256="$(cat "${RASPIOS_XZ}.sha256")"
CACHED_SHA256=""
rm -f "${RASPIOS_XZ}"

if [ -f "${RASPIOS_IMG}.xz" ]
then
	CACHED_SHA256="$(cd "${RASPIOS_IMG_DIR}" && sha256sum "${RASPIOS_IMG_NAME}.xz")"
fi

if ! [ "${ORIG_SHA256}" = "${CACHED_SHA256}" ]
then
	curl "${RASPIOS_LINK}" -o "${RASPIOS_IMG}.xz"
	rm -f "${RASPIOS_XZ}"
fi

docker pull lukechilds/dockerpi:vm

exit 0
