FROM docker.io/library/ubuntu:24.04 AS builder

ARG LLVM_VERSION=16.0.6
ARG UID=1001

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    python3 \
    build-essential \
    cmake \
    ninja-build \
    libssl-dev \
    tar \
    git \
    curl \
    rsync \
    sudo \
    clang-16 \
    && update-alternatives --install /usr/bin/clang clang /usr/bin/clang-16 100 \
        --slave /usr/bin/clang++ clang++ /usr/bin/clang++-16 \
    && clang --version | grep -F "${LLVM_VERSION}" \
    && rm -rf /var/lib/apt/lists/*

ENV CC=clang \
    CXX=clang++

RUN useradd --create-home -u $UID --non-unique --shell /bin/bash dev
USER dev

FROM builder AS opencode

RUN mkdir -p /home/dev/.config/opencode /home/dev/.local/share/opencode
RUN touch /home/dev/.local/share/opencode/auth.json
RUN curl -fsSL https://opencode.ai/install | bash

FROM builder AS devcontainer

USER root

RUN apt-get update && apt-get install -y --no-install-recommends \
    apt-utils \
    bash-completion \
    gnupg2 \
    htop \
    iproute2 \
    iputils-ping \
    jq \
    less \
    lldb-16 \
    locales \
    lsb-release \
    man-db \
    nano \
    procps \
    software-properties-common \
    unzip \
    vim \
    wget \
    zip \
    zsh \
    && update-alternatives --install /usr/bin/lldb lldb /usr/bin/lldb-16 100 \
    && rm -rf /var/lib/apt/lists/*

USER dev
