#!/usr/bin/env bash
set -euo pipefail

sudo chown -R vscode:vscode /home/vscode/.codex
sudo chown -R vscode:vscode /home/vscode/.cursor
sudo chown -R vscode:vscode /home/vscode/.vscode-server
sudo chown -R vscode:vscode /home/vscode/.config/Cursor

# install codex cli globally, VSCode plugn is a piece of crap!
curl -fsSL https://chatgpt.com/codex/install.sh | CODEX_NON_INTERACTIVE=1 sh

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
