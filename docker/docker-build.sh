#!/bin/sh

docker build -t android-build .

docker volume create android-sdk-cache
