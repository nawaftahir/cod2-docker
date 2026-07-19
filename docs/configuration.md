# Configuration reference

All runtime configuration is env vars (usually via `.env`). The entrypoint logs the
fully resolved command line at every start; `ENTRYPOINT_DRYRUN=1` prints it and exits.

Prefer `.cfg` files? Everything cvar-like can live in your `server.cfg` as usual;
the env vars below are optional shortcuts, not requirements.

## Server binary

| Var | Default | Meaning |
|---|---|---|
| `COD2_VERSION` | `1_3` | `1_0a`, `1_2c`, `1_3` |
| `COD2_VARIANT` | *(empty)* | suffix without leading `_`, e.g. `nodelay_va_loc`, `cracked` |
| `COD2_BINARY` | *(unset)* | absolute path to a custom bind-mounted binary; overrides the two above |

The binary used is `/server/bin/cod2_lnxded_<VERSION>[_<VARIANT>]`. On a wrong pick the
entrypoint errors and lists what's available. Variant matrix: [bin/README.md](../bin/README.md).

## Basics

| Var | Default | Maps to |
|---|---|---|
| `NET_PORT` | `28960` | `+set net_port` |
| `MAXCLIENTS` | *(unset)* | `+set sv_maxclients` |
| `SV_HOSTNAME` | *(unset)* | `+set sv_hostname` |
| `FS_GAME` | *(unset)* | `+set fs_game` (mod folder under `game/`) |
| `FS_LIBRARY` | *(unset)* | `+set fs_library` (extra maps/library folder) |
| `FS_BASEPATH` / `FS_HOMEPATH` | `/server/game` | filesystem roots |
| `DEDICATED` | `2` | `1` = LAN, `2` = internet (master server heartbeat) |
| `CONFIG` | *(unset)* | `+exec <file>` |
| `MAP` | *(unset)* | `+map <map>` |
| `MAP_ROTATE` | `0` | `1` appends `+map_rotate` |

Filesystem note: `fs_basepath` and `fs_homepath` both default to `/server/game`,
which is your bind-mounted `./game` folder. Everything the server reads and writes
(paks, mods, logs, `scriptdata/`, a `Library/` folder for map libraries) lives there
on the host, owned by `PUID:PGID`.

## Arbitrary cvars

Any env var named `COD2_SET_<name>`, `COD2_SETA_<name>`, or `COD2_SETS_<name>` becomes
`+set <name> <value>` / `+seta` / `+sets`. Values with spaces are safe.

```dotenv
COD2_SET_sv_punkbuster=0
COD2_SET_g_gametype=sd
COD2_SETA_scr_sd_timelimit=2.5
```

## Raw command line and args file

| Var | Meaning |
|---|---|
| `PARAMS_BEFORE` | raw args inserted before all generated args |
| `PARAMS` | raw args appended after generated args |
| `PARAMS_AFTER` | raw args appended last |
| `PARAMS_REPLACE=1` | ignore everything generated; run exactly `cod2_lnxded $PARAMS` |
| `ARGS_FILE` | path to an args file, default `/server/game/cod2.args` |

**Args file**: if `game/cod2.args` exists, its contents are appended to the command
line, so you can keep launch parameters in a file next to your configs instead of
editing `.env`. Lines starting with `#` and blank lines are ignored:

```
# game/cod2.args
+set sv_punkbuster 0
+set g_gametype sd
+exec tournament.cfg
```

With `PARAMS_REPLACE=1` the args file (plus `PARAMS`) becomes the entire command line.

`PARAMS_REPLACE=1` is the escape hatch for full control; the healthcheck then
derives the port from a `+set net_port <p>` inside `PARAMS` (or set `CHECK_PORT`).

## libcod

See [libcod.md](libcod.md). Summary: `LIBCOD_MODE` = `auto` (default) | `off` | `custom` |
`fetch` | `baked`; `LIBCOD_URL` / `LIBCOD_ARTIFACT` for fetch mode.

## Container behaviour

| Var | Default | Meaning |
|---|---|---|
| `PUID` / `PGID` | `1000` | uid/gid the server runs as; match your host user (`id`) so game files stay editable over SFTP/shell |
| `CHOWN_GAME_DIR` | `0` | `1` = chown -R the game dir to PUID:PGID at start |
| `LOG_TO_STDOUT` | `0` | `1` = mirror `games_mp.log` to `docker logs` |
| `ENTRYPOINT_DRYRUN` | `0` | `1` = print resolved command + libcod choice, exit 0 |
| `CHECK_PORT` | *(derived)* | healthcheck port override |

## Networking

CoD2 uses a **single UDP port** (`net_port`, default 28960) for everything: game
traffic, rcon, and server queries. Choose one of two compose modes:

### `network_mode: host` (default)

The container shares the host's network stack directly, exactly like a bare
(non-docker) server process: no NAT, real client IPs, master-server heartbeat just
works, and whatever port the server binds (from `.env` OR from your `.cfg`) is
immediately reachable, subject only to your firewall. Recommended on a game VPS.

In host mode there are no docker port mappings to maintain: setting `net_port` in
your config file alone is enough.

### Bridged with port mappings

The classic docker way: the container lives on a private network and you publish
ports through NAT. Comment out `network_mode: host` and use `ports:` instead.
Open UDP for each thing that needs it:

| What | Ports to publish |
|---|---|
| Game server | the `net_port` in use, e.g. `28960:28960/udp` |
| Extra instances | one line per server, e.g. `28970:28970/udp` |
| External rcon tools / web panels | same game port, no extra line |
| Proxy / relay sidecars (UDP proxies, socat forwards, query relays) | whatever port the sidecar listens on, one line each |

Caveats in bridged mode:

- If you set `net_port` only in a `.cfg`, docker cannot see it: you must keep the
  `ports:` mapping in compose in sync by hand (and set `CHECK_PORT` for the
  healthcheck). With host mode this problem does not exist.
- Client IPs appear as the docker bridge gateway unless your proxy passes them
  through; bans and IP logs will be wrong. If real IPs matter, use host mode.
- Keep the published host port identical to the container port; the master server
  advertises the port the server thinks it uses.

Firewall: allow the chosen UDP port(s); the game itself needs no TCP.
