#!/bin/sh
set -eu

readonly peer_subnet="100.64.0.0/24"
readonly wireguard_gateway="172.30.90.2"

if [ "$(id -u)" -ne 0 ]; then
  echo "route-entrypoint: root is required only to install the container route" >&2
  exit 1
fi

# `replace` is idempotent and modifies only this container's network namespace.
ip -4 route replace "${peer_subnet}" via "${wireguard_gateway}"

# Preserve the upstream image's entrypoint behavior and make code-server the
# main process so it receives container signals directly.
exec /usr/bin/entrypoint.sh "$@"
