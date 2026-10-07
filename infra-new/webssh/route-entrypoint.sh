#!/bin/sh
set -eu

readonly peer_subnet="100.64.0.0/24"
readonly wireguard_gateway="172.30.90.2"

if [ "$(id -u)" -ne 0 ]; then
  echo "route-entrypoint: root is required only to install the container route" >&2
  exit 1
fi

# `replace` is idempotent and affects only this container's network namespace.
ip -4 route replace "${peer_subnet}" via "${wireguard_gateway}"

# Drop root permanently before starting WebSSH. su-exec replaces itself with
# wssh, so no root shell remains and signals reach the application directly.
exec su-exec webssh:webssh env \
  HOME=/home/webssh \
  USER=webssh \
  LOGNAME=webssh \
  wssh "$@"
