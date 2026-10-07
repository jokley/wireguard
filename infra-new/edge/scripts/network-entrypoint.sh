#!/bin/sh
set -eu

readonly peer_subnet="100.64.0.0/24"
readonly wireguard_gateway="172.30.90.2"

if [ "$(id -u)" -ne 0 ]; then
  echo "edge-network must start as root to configure its container route" >&2
  exit 1
fi

ip -4 route replace "${peer_subnet}" via "${wireguard_gateway}"

# Keep the dedicated network namespace alive for edge-nginx. This helper owns no
# application data and has no host mounts. Drop root and all effective
# capabilities before entering the long-running namespace-holder process.
exec su-exec edge-network:edge-network env \
  HOME=/home/edge-network \
  USER=edge-network \
  LOGNAME=edge-network \
  sleep infinity
