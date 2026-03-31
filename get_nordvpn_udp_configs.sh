#!/usr/bin/env bash

set -euo pipefail

API_URL="https://api.nordvpn.com/v1/servers?limit=20000"
OUTPUT_DIR="nordvpnconfigs"
output_set=0
PARALLEL_DOWNLOADS="${PARALLEL_DOWNLOADS:-8}"
MAX_SERVERS="${MAX_SERVERS:-0}"
PROTOCOL="${PROTOCOL:-udp}"          # udp|tcp
OBFUSCATED="${OBFUSCATED:-0}"        # 0|1
COUNTRY_FILTER="${COUNTRY_FILTER:-all}" # all | DE,US | Germany,France
INTERACTIVE=0

usage() {
  cat <<USAGE
Usage:
  ./get_nordvpn_udp_configs.sh [output_dir] [--interactive]

Optionen:
  --interactive       Fragt interaktiv nach Obfuscated-Servern und Ländern.
  --protocol udp|tcp  OpenVPN-Protokoll (Default: udp, via env PROTOCOL auch möglich).
  --obfuscated 0|1    Nur Obfuscated-Server laden (Default: 0, via env OBFUSCATED).
  --countries LISTE   Länderfilter, z. B. DE,US oder Germany,France oder all.
  --help              Diese Hilfe anzeigen.

Umgebungsvariablen:
  PARALLEL_DOWNLOADS  Anzahl paralleler Downloads (Default: 8)
  MAX_SERVERS         Max. Anzahl Server für Tests (0 = unbegrenzt)
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --interactive)
      INTERACTIVE=1
      shift
      ;;
    --protocol)
      PROTOCOL="${2:-}"
      shift 2
      ;;
    --obfuscated)
      OBFUSCATED="${2:-}"
      shift 2
      ;;
    --countries)
      COUNTRY_FILTER="${2:-all}"
      shift 2
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    --*)
      echo "Unbekannte Option: $1"
      usage
      exit 1
      ;;
    *)
      if [[ "$output_set" -eq 0 ]]; then
        OUTPUT_DIR="$1"
        output_set=1
      else
        echo "Unerwartetes Argument: $1"
        usage
        exit 1
      fi
      shift
      ;;
  esac
done

if [[ "$INTERACTIVE" -eq 1 ]]; then
  read -r -p "Obfuscated-Server laden? (j/N): " reply
  case "${reply,,}" in
    j|ja|y|yes) OBFUSCATED=1 ;;
    *) OBFUSCATED=0 ;;
  esac

  if [[ "$OBFUSCATED" -eq 1 && "$PROTOCOL" == "udp" ]]; then
    echo "Hinweis: Für Obfuscated-Server ist meist TCP sinnvoll."
    read -r -p "Protokoll wählen (udp/tcp, Default tcp): " proto
    PROTOCOL="${proto:-tcp}"
  else
    read -r -p "Protokoll wählen (udp/tcp, Default ${PROTOCOL}): " proto
    if [[ -n "${proto:-}" ]]; then
      PROTOCOL="$proto"
    fi
  fi

  read -r -p "Welche Länder? (all oder z. B. DE,US / Germany,France): " countries
  COUNTRY_FILTER="${countries:-all}"
fi

if [[ "$PROTOCOL" != "udp" && "$PROTOCOL" != "tcp" ]]; then
  echo "Fehler: --protocol muss udp oder tcp sein."
  exit 1
fi

if [[ "$OBFUSCATED" != "0" && "$OBFUSCATED" != "1" ]]; then
  echo "Fehler: --obfuscated muss 0 oder 1 sein."
  exit 1
fi

DOWNLOAD_BASE_URL="https://downloads.nordcdn.com/configs/files/ovpn_${PROTOCOL}/servers"
TECH_IDENTIFIER="openvpn_${PROTOCOL}"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

if ! command -v jq >/dev/null 2>&1; then
  echo "Fehler: 'jq' ist nicht installiert, wird aber benötigt."
  exit 1
fi

echo "Lade Serverliste von der NordVPN API ..."
curl -fsSL "$API_URL" -o "$tmp_dir/servers.json"

echo "Erzeuge Serverliste (Protokoll: $PROTOCOL, Obfuscated: $OBFUSCATED) ..."
jq -r --arg tech "$TECH_IDENTIFIER" --argjson obf "$OBFUSCATED" '
  .[]
  | select(.status == "online")
  | select(any(.technologies[]?.identifier; . == $tech))
  | if $obf == 1 then select(any(.technologies[]?.identifier; . == "obfuscated_servers")) else . end
  | {
      hostname: .hostname,
      country_code: (.locations[0].country.code // .country // ""),
      country_name: (.locations[0].country.name // "")
    }
  | select(.hostname != null and (.hostname|type == "string") and (.hostname|length > 0))
  | [.hostname, .country_code, .country_name]
  | @tsv
' "$tmp_dir/servers.json" > "$tmp_dir/serverlist.tsv"

if [[ ! -s "$tmp_dir/serverlist.tsv" ]]; then
  echo "Fehler: Keine passenden Server gefunden."
  exit 1
fi

normalized_countries="$(echo "$COUNTRY_FILTER" | tr '[:lower:]' '[:upper:]' | tr -d ' ')"
> "$tmp_dir/configlinklist.txt"

while IFS=$'\t' read -r hostname country_code country_name; do
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

  echo "${DOWNLOAD_BASE_URL}/${hostname}.${PROTOCOL}.ovpn" >> "$tmp_dir/configlinklist.txt"
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
