#!/bin/sh

MDSERVER_DIR=/home/${USER}/melodeer-server

mkdir -p "${MDSERVER_DIR}"

cp files/__main__.py files/requirements.txt "${MDSERVER_DIR}"

pip3 install -r "${MDSERVER_DIR}/requirements.txt"

sudo cp files/melodeer-service.service /etc/avahi/services

avahi-daemon --reload
