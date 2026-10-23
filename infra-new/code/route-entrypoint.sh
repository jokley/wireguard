#!/bin/sh
set -eu

readonly peer_subnet="100.64.0.0/24"
readonly wireguard_gateway="172.30.90.2"

if [ "$(id -u)" -ne 0 ]; then
  echo "route-entrypoint: root is required only to install the container route" >&2
  exit 1
fi

# Never let code-server generate a password-bearing fallback configuration.
if [ ! -r /etc/code-server/config.yaml ]; then
  echo "route-entrypoint: required non-sensitive config is missing or unreadable" >&2
  exit 1
fi

# `replace` is idempotent and modifies only this container's network namespace.
ip -4 route replace "${peer_subnet}" via "${wireguard_gateway}"

if [ -z "${CODE_SERVER_PASSWORD:-}" ]; then
  echo "CODE_SERVER_PASSWORD must be set in the local environment" >&2
  exit 1
fi

# code-server expects PASSWORD. Keep the application-facing name out of Compose,
# map the local variable only in memory, and remove the source name afterwards.
code_server_password="${CODE_SERVER_PASSWORD}"
unset CODE_SERVER_PASSWORD
# A hashed credential would take precedence over PASSWORD. The explicit CLI
# config selects the image-owned, non-sensitive file instead of a home config.
unset HASHED_PASSWORD CODE_SERVER_CONFIG
export PASSWORD="${code_server_password}"
unset code_server_password

# Drop root permanently and start the application directly. Keep the existing
# environment, but force identity/home variables to
# agree with uid/gid 1000. The exec chain leaves no root shell, while dumb-init
# remains PID 1 for signal forwarding and child reaping.
exec gosu coder:coder env \
  HOME=/home/coder \
  USER=coder \
  LOGNAME=coder \
  dumb-init /usr/bin/code-server "$@"
