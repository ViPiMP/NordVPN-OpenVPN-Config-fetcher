# NordVPN-OpenVPN-Config-fetcher
Fetch OpenVPN Configs von NordVPN (UDP/TCP, optional Obfuscated-Server, Länderfilter).

## Usage

Standard (UDP, alle Länder, nicht-obfuscated):

```bash
./get_nordvpn_udp_configs.sh
```

Interaktiv (fragt nach Obfuscated + Länder oder alle):

```bash
./get_nordvpn_udp_configs.sh --interactive
```

Optionales Output-Verzeichnis:

```bash
./get_nordvpn_udp_configs.sh my-configs
```

Nicht-interaktiv mit Optionen:

```bash
./get_nordvpn_udp_configs.sh --protocol tcp --obfuscated 1 --countries DE,US
```

Optionale Umgebungsvariablen:

```bash
PARALLEL_DOWNLOADS=16 MAX_SERVERS=50 ./get_nordvpn_udp_configs.sh
```

## Optionen

- `--interactive` interaktive Abfragen
- `--protocol udp|tcp`
- `--obfuscated 0|1`
- `--countries LISTE` (`all`, `DE,US`, `Germany,France`)
- `--help`

## Requirements

- `curl`
- `jq`

Der alte Scriptname `get_nordvpn_upd_configs.sh` bleibt aus Kompatibilitätsgründen erhalten und ruft das neue Hauptscript auf.
