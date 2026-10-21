#!/usr/bin/env bash
# Usage: container/opencode-import-auth.sh [compose provider, e.g. "docker compose" or podman-compose]
set -euo pipefail

read -ra compose <<< "${1:-docker compose}"
cd "$(dirname "$0")/.."

umask 077
auth_dir=$(mktemp -d)
trap 'rm -rf "$auth_dir"' EXIT
opencode auth export > "$auth_dir/auth.json"

export FIXUID=${FIXUID:-$(id -u)}
export OPENCODE_AUTH_EXPORT="$auth_dir/auth.json"
"${compose[@]}" run --rm _import-auth
