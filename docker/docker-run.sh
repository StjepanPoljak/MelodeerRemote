#!/bin/sh

CURR_DIR="$(pwd)"
GRADLE_CACHE=/home/$(id -un)/.gradle
WORKDIR="/opt/$(basename "${CURR_DIR}")" 

mkdir -p ${GRADLE_CACHE}

docker run -it --rm					\
	-v "${CURR_DIR}":"${WORKDIR}"			\
	-v "${GRADLE_CACHE}":/root/.gradle		\
	-v android-sdk-cache:/opt/android-sdk		\
	--workdir "${WORKDIR}"				\
	android-build
