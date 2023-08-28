#!/bin/sh

docker build -t android-build .

docker volume create			\
	--driver local			\
	--opt type=none			\
	--opt device=~/.android-sdk	\
	--opt o=bind			\
	android-sdk-cache
