# NordVPN-OpenVPN-Config-fetcher
Fetch OpenVPN Configs von NordVPN (interaktiv: Server-Typ, Länder, Protokoll).

## Usage

```bash
./get_nordvpn_udp_configs.sh
```

Optionales Output-Verzeichnis:

```bash
./get_nordvpn_udp_configs.sh my-configs
```

Das Script fragt immer interaktiv:

1. Server-Typ: `all`, `standard`, `p2p`, `obfuscated`
2. Länder: `all` oder mehrere (z. B. `DE,US` oder `Germany,France`)
3. Protokoll: `udp`, `tcp` oder `both`

Optionale Umgebungsvariablen:

```bash
PARALLEL_DOWNLOADS=16 MAX_SERVERS=50 ./get_nordvpn_udp_configs.sh
```

## Requirements

- `curl`
- `jq`

Der alte Scriptname `get_nordvpn_upd_configs.sh` bleibt aus Kompatibilitätsgründen erhalten und ruft das Hauptscript auf.
