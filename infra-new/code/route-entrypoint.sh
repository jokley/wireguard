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

# Drop root permanently and start the application directly. Keep the existing
# environment (including PASSWORD and TZ), but force identity/home variables to
# agree with uid/gid 1000. The exec chain leaves no root shell, while dumb-init
# remains PID 1 for signal forwarding and child reaping.
exec gosu coder:coder env \
  HOME=/home/coder \
  USER=coder \
  LOGNAME=coder \
  dumb-init /usr/bin/code-server "$@"
