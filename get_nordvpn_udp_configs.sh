#!/usr/bin/env bash

set -euo pipefail

API_URL="https://api.nordvpn.com/v1/servers?limit=20000"
OUTPUT_DIR="${1:-nordvpnconfigs}"
PARALLEL_DOWNLOADS="${PARALLEL_DOWNLOADS:-8}"
MAX_SERVERS="${MAX_SERVERS:-0}"

usage() {
  cat <<USAGE
Usage:
  ./get_nordvpn_udp_configs.sh [output_dir]

Das Script ist immer interaktiv und fragt nacheinander:
  1) Server-Typ (alle, standard, p2p, obfuscated)
  2) Länder (all oder mehrere, z. B. DE,US)
  3) Protokoll (tcp, udp, beide)

Umgebungsvariablen:
  PARALLEL_DOWNLOADS  Anzahl paralleler Downloads (Default: 8)
  MAX_SERVERS         Max. Anzahl Server für Tests (0 = unbegrenzt)
USAGE
}

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  usage
  exit 0
fi

read -r -p "Server-Typ wählen [all/standard/p2p/obfuscated] (Default: all): " server_type
server_type="${server_type:-all}"
server_type="${server_type,,}"

case "$server_type" in
  all|standard|p2p|obfuscated) ;;
  *)
    echo "Fehler: Ungültiger Server-Typ '$server_type'. Erlaubt: all, standard, p2p, obfuscated"
    exit 1
    ;;
esac

read -r -p "Welche Länder? (all oder z. B. DE,US / Germany,France): " countries
COUNTRY_FILTER="${countries:-all}"

read -r -p "Protokoll wählen [udp/tcp/both] (Default: udp): " protocol_choice
protocol_choice="${protocol_choice:-udp}"
protocol_choice="${protocol_choice,,}"

case "$protocol_choice" in
  udp)
    WANT_UDP=1
    WANT_TCP=0
    ;;
  tcp)
    WANT_UDP=0
    WANT_TCP=1
    ;;
  both|beide)
    WANT_UDP=1
    WANT_TCP=1
    ;;
  *)
    echo "Fehler: Ungültiges Protokoll '$protocol_choice'. Erlaubt: udp, tcp, both"
    exit 1
    ;;
esac

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

if ! command -v jq >/dev/null 2>&1; then
  echo "Fehler: 'jq' ist nicht installiert, wird aber benötigt."
  exit 1
fi

echo "Lade Serverliste von der NordVPN API ..."
curl -fsSL "$API_URL" -o "$tmp_dir/servers.json"

echo "Erzeuge Serverliste ..."
jq -r '
  .[]
  | select(.status == "online")
  | {
      hostname: .hostname,
      country_code: (.locations[0].country.code // .country // ""),
      country_name: (.locations[0].country.name // ""),
      has_udp: any(.technologies[]?.identifier; . == "openvpn_udp"),
      has_tcp: any(.technologies[]?.identifier; . == "openvpn_tcp"),
      has_standard: any(.technologies[]?.identifier; . == "standard_vpn_servers"),
      has_p2p: any(.technologies[]?.identifier; . == "p2p"),
      has_obfuscated: any(.technologies[]?.identifier; . == "obfuscated_servers")
    }
  | select(.hostname != null and (.hostname|type == "string") and (.hostname|length > 0))
  | [.hostname, .country_code, .country_name, .has_udp, .has_tcp, .has_standard, .has_p2p, .has_obfuscated]
  | @tsv
' "$tmp_dir/servers.json" > "$tmp_dir/serverlist.tsv"

if [[ ! -s "$tmp_dir/serverlist.tsv" ]]; then
  echo "Fehler: Keine passenden Server gefunden."
  exit 1
fi

normalized_countries="$(echo "$COUNTRY_FILTER" | tr '[:lower:]' '[:upper:]' | tr -d ' ')"
> "$tmp_dir/configlinklist.txt"

while IFS=$'\t' read -r hostname country_code country_name has_udp has_tcp has_standard has_p2p has_obfuscated; do
  case "$server_type" in
    standard) [[ "$has_standard" == "true" ]] || continue ;;
    p2p) [[ "$has_p2p" == "true" ]] || continue ;;
    obfuscated) [[ "$has_obfuscated" == "true" ]] || continue ;;
    all) ;;
  esac

  if [[ "$normalized_countries" != "ALL" ]]; then
    upper_code="$(echo "$country_code" | tr '[:lower:]' '[:upper:]')"
    upper_name="$(echo "$country_name" | tr '[:lower:]' '[:upper:]')"
    match=0
    IFS=',' read -ra wanted <<< "$normalized_countries"
    for c in "${wanted[@]}"; do
      [[ -z "$c" ]] && continue
      if [[ "$upper_code" == "$c" || "$upper_name" == "$c" ]]; then
        match=1
        break
      fi
    done
    [[ "$match" -eq 0 ]] && continue
  fi

  if [[ "$WANT_UDP" -eq 1 && "$has_udp" == "true" ]]; then
    echo "https://downloads.nordcdn.com/configs/files/ovpn_udp/servers/${hostname}.udp.ovpn" >> "$tmp_dir/configlinklist.txt"
  fi
  if [[ "$WANT_TCP" -eq 1 && "$has_tcp" == "true" ]]; then
    echo "https://downloads.nordcdn.com/configs/files/ovpn_tcp/servers/${hostname}.tcp.ovpn" >> "$tmp_dir/configlinklist.txt"
  fi
done < "$tmp_dir/serverlist.tsv"

sort -u -o "$tmp_dir/configlinklist.txt" "$tmp_dir/configlinklist.txt"

if [[ "$MAX_SERVERS" -gt 0 ]]; then
  head -n "$MAX_SERVERS" "$tmp_dir/configlinklist.txt" > "$tmp_dir/configlinklist-limited.txt"
  mv "$tmp_dir/configlinklist-limited.txt" "$tmp_dir/configlinklist.txt"
fi

if [[ ! -s "$tmp_dir/configlinklist.txt" ]]; then
  echo "Fehler: Keine Config-Links für den gewählten Filter gefunden."
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
