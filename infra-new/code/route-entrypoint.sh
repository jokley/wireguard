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

# Drop root permanently before invoking the verified upstream entrypoint. Keep
# the existing environment (including PASSWORD and TZ), but force identity/home
# variables to agree with uid/gid 1000. Both gosu and the upstream entrypoint use
# exec, so no root shell remains and signals reach dumb-init/code-server.
exec gosu coder:coder env \
  HOME=/home/coder \
  USER=coder \
  LOGNAME=coder \
  /usr/bin/entrypoint.sh "$@"
