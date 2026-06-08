FROM mcr.microsoft.com/devcontainers/base:ubuntu-24.04

COPY bash_aliases /home/vscode/.bash_aliases

ARG LLVM_VERSION=16.0.6

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

USER vscode

ENV CC=clang \
    CXX=clang++

# Install cursor-agent
RUN curl https://cursor.com/install -fsS | bash
ENV PATH="/home/vscode/.local/bin:${PATH}"
