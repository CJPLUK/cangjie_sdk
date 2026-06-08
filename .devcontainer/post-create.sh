#!/usr/bin/env bash
set -euo pipefail

sudo chown -R vscode:vscode /home/vscode/.codex
sudo chown -R vscode:vscode /home/vscode/.cursor

ARCH_name="$(uname -m)"
ENV_FILE="${HOME}/.cangjie_sdk_env"

cat > "${ENV_FILE}" <<EOF
export WORKSPACE=/workspaces/cangjie_sdk
export ARCH=${ARCH_name}
export CANGJIE_VERSION=1.5.0-dev
export STDX_VERSION=1
export SDK_NAME=linux-${ARCH_name}
EOF

SOURCE_LINE='[ -f "${HOME}/.cangjie_sdk_env" ] && . "${HOME}/.cangjie_sdk_env"'
if ! grep -Fq ".cangjie_sdk_env" "${HOME}/.bashrc"; then
    {
        printf '\n# Cangjie SDK environment\n'
        printf '%s\n' "${SOURCE_LINE}"
    } >> "${HOME}/.bashrc"
fi
