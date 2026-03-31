#!/usr/bin/env bash

# Backward-compatible wrapper with old typo filename ("upd" instead of "udp").
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "$SCRIPT_DIR/get_nordvpn_udp_configs.sh" "$@"
