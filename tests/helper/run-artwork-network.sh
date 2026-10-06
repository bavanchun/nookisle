#!/usr/bin/env bash
set -euo pipefail
test_binary=$1
# All address changes occur after creation of fresh user and network namespaces.
# The namespace has no external interfaces/routes and dies with this foreground run.
exec unshare --user --map-root-user --net bash -euc '
  ip link set lo up
  ip address add 1.1.1.1/32 dev lo
  ip address add 1.1.1.2/32 dev lo
  exec "$1" --network-fixture
' artwork-network "$test_binary"
