FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt update -y && apt install -y curl unzip zip && rm -rf /var/lib/apt/lists/*

RUN curl -s "https://get.sdkman.io" | bash

RUN bash -c 'source "$HOME/.sdkman/bin/sdkman-init.sh"; sdk install java && sdk install kotlin && sdk install gradle'

RUN mkdir -p /opt/android-sdk && \
    curl -o /tmp/sdk-tools.zip https://dl.google.com/android/repository/commandlinetools-linux-10406996_latest.zip && \
    unzip -q /tmp/sdk-tools.zip -d /opt/android-sdk && \
    rm /tmp/sdk-tools.zip

ENV ANDROID_SDK_ROOT /opt/android-sdk
ENV PATH=$PATH:${ANDROID_SDK_ROOT}/cmdline-tools/bin

RUN bash -c "source \"\$HOME/.sdkman/bin/sdkman-init.sh\"; yes | sdkmanager --licenses --sdk_root=${ANDROID_SDK_ROOT}"

ENTRYPOINT [ "/bin/bash", "-c", "source ~/.sdkman/bin/sdkman-init.sh; $0 $@" ]
