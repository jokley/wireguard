#!/bin/sh
set -eu

readonly peer_subnet="100.64.0.0/24"
readonly wireguard_gateway="172.30.90.2"

ip -4 route replace "${peer_subnet}" via "${wireguard_gateway}"

# Keep the dedicated network namespace alive for edge-nginx. This helper owns no
# application data and has no host mounts.
exec sleep infinity
