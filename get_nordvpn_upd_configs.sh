#!/usr/bin/env bash

set -euo pipefail

API_URL="https://api.nordvpn.com/v1/servers?limit=20000"
DOWNLOAD_BASE_URL="https://downloads.nordcdn.com/configs/files/ovpn_udp/servers"
OUTPUT_DIR="${1:-nordvpnconfigs}"
PARALLEL_DOWNLOADS="${PARALLEL_DOWNLOADS:-8}"
MAX_SERVERS="${MAX_SERVERS:-0}"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

if ! command -v jq >/dev/null 2>&1; then
  echo "Fehler: 'jq' ist nicht installiert, wird aber benötigt."
  exit 1
fi

echo "Lade Serverliste von der NordVPN API ..."
curl -fsSL "$API_URL" -o "$tmp_dir/servers.json"

echo "Erzeuge Liste aller UDP OpenVPN Config-Links ..."
jq -r '
  .[]
  | select(.status == "online")
  | select(any(.technologies[]?.identifier; . == "openvpn_udp"))
  | .hostname
  | select(type == "string" and length > 0)
  | "\(.)"
' "$tmp_dir/servers.json" \
  | sort -u \
  | sed "s#^#${DOWNLOAD_BASE_URL}/#; s#\$#.udp.ovpn#" \
  > "$tmp_dir/configlinklist.txt"

if [[ "$MAX_SERVERS" -gt 0 ]]; then
  head -n "$MAX_SERVERS" "$tmp_dir/configlinklist.txt" > "$tmp_dir/configlinklist-limited.txt"
  mv "$tmp_dir/configlinklist-limited.txt" "$tmp_dir/configlinklist.txt"
fi

if [[ ! -s "$tmp_dir/configlinklist.txt" ]]; then
  echo "Fehler: Keine UDP OpenVPN Config-Links gefunden."
  echo "Die API-Antwort hat sich evtl. geändert."
  exit 1
fi

mkdir -p "$OUTPUT_DIR"
touch "$tmp_dir/failed.txt"

echo "Lade $(wc -l < "$tmp_dir/configlinklist.txt") Dateien nach '$OUTPUT_DIR' ..."
xargs -P"$PARALLEL_DOWNLOADS" -I{} bash -c '
  url="$1"
  out_dir="$2"
  failed_file="$3"
  if ! curl -fsSL -O --output-dir "$out_dir" "$url"; then
    echo "$url" >> "$failed_file"
  fi
' _ {} "$OUTPUT_DIR" "$tmp_dir/failed.txt" < "$tmp_dir/configlinklist.txt"

failed_count="$(wc -l < "$tmp_dir/failed.txt")"
if [[ "$failed_count" -gt 0 ]]; then
  echo "Warnung: $failed_count Dateien konnten nicht geladen werden."
  echo "Beispiel(e):"
  head -n 10 "$tmp_dir/failed.txt"
fi

echo "Fertig."
