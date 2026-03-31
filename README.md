# NordVPN-OpenVPN-Config-fetcher
Fetch all OpenVPN Configs of NordVPN

## Usage

```bash
./get_nordvpn_udp_configs.sh
```

Optional output directory:

```bash
./get_nordvpn_udp_configs.sh my-configs
```

Optional parallel download count:

```bash
PARALLEL_DOWNLOADS=16 ./get_nordvpn_udp_configs.sh
```

Optional server limit (useful for quick tests):

```bash
MAX_SERVERS=50 ./get_nordvpn_udp_configs.sh
```

## Requirements

- `curl`
- `jq`

The old script name `get_nordvpn_upd_configs.sh` still works for compatibility.
