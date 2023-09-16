#!/bin/sh

if [ "$(id -u)" -ne 0 ]; then
	echo "(!) Please run install script as the root user."
	exit 1
fi

MDSERVER_DIR=/opt/melodeer-server

mkdir -p "${MDSERVER_DIR}"

cp files/__main__.py "${MDSERVER_DIR}"

cp files/melodeer-service.service /etc/avahi/services

avahi-daemon --reload

cp files/melodeer-server.service /etc/systemd/system/melodeer-server.service

systemctl enable melodeer-server.service
systemctl start melodeer-server.service

