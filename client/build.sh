#!/bin/sh

SCRIPT_DIR="$(dirname $0)"

(cd "${SCRIPT_DIR}" && ../docker/docker-run.sh)
