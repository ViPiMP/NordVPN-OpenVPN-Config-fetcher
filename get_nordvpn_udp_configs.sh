#!/usr/bin/env bash

# Backward-compatible wrapper with corrected filename ("udp" instead of "upd").
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "$SCRIPT_DIR/get_nordvpn_upd_configs.sh" "$@"
