# Call of Duty 2 Docker Server

Call of Duty 2 dedicated server in Docker:
lightweight, minimal, and fully configurable, from a plain **vanilla server** to a fully customizable
[zk_libcod](https://github.com/ibuddieat/zk_libcod) server with Speex voice and MySQL.

## Supported platforms
- Debian 13 (default, recommended)
- Ubuntu 24.04

> [!NOTE]
> This list is not exhaustive and newer versions might work as well.

## Quick deploy (pre-built image, no build needed)

The fastest path: pull the image from GitHub Container Registry, no source code or build tools required on the server.

```bash
mkdir cod2-server && cd cod2-server
mkdir -p game libcod

# grab the compose file and env template
wget https://raw.githubusercontent.com/nawaftahir/cod2-docker/main/docker-compose.yml
wget https://raw.githubusercontent.com/nawaftahir/cod2-docker/main/.env.example -O .env

# edit .env: set NET_PORT, FS_GAME, CONFIG, LIBCOD_MODE, etc.
nano .env

# copy your game files into game/
# game/main/ - iw_00.iwd ... iw_15.iwd, localized_*.iwd, server.cfg
# game/<mod>/ - your mod files (if using FS_GAME)

docker compose up -d
```

The server answers on UDP 28960 (or whatever you set `NET_PORT` to).

```bash
docker compose logs -f          # watch the console
docker attach cod2              # interactive console (detach: CTRL-P, CTRL-Q)
```

## Quickstart (build from source)

If you want to build the image yourself (custom libcod flags, different base OS, etc.):

```bash
git clone https://github.com/nawaftahir/cod2-docker && cd cod2-docker
cp .env.example .env
# copy your game files into game/
docker compose up -d --build
```

Build with `--build-arg BASE_IMAGE=ubuntu:24.04` for an Ubuntu base instead of Debian 13.

## Features

- **Vanilla server**: run stock with zero libcod knowledge
- **libcod without image rebuilds**: baked in, fetched from a URL or CI artifact, or compiled locally from any repo/branch with custom flags
- **Full command-line control**: env-var cvars, raw params, or your own args file
- **All 1.0 / 1.2 / 1.3 binaries included**: pick with two env vars
- Speex + MySQL runtime libs always present, so any swapped `libcod2.so` just loads
- **Multi-server ready**: run any number of servers from one image, one folder per server

## Configuration

Everything is env vars in `.env`; see [docs/configuration.md](docs/configuration.md)
for the full reference. The short version:

| Var | Meaning |
|---|---|
| `COD2_VERSION` / `COD2_VARIANT` | binary pick, e.g. `1_3` + `nodelay_va_loc` ([bin/README.md](bin/README.md)) |
| `NET_PORT`, `MAXCLIENTS`, `FS_GAME`, `FS_LIBRARY`, `CONFIG`, `MAP`, `MAP_ROTATE` | the usual server basics |
| `LIBCOD_MODE` | `auto` / `off` (vanilla) / `custom` / `fetch` / `baked` |
| `COD2_SET_x=v` | becomes `+set x v` (also `COD2_SETA_*`, `COD2_SETS_*`) |
| `PARAMS`, `PARAMS_REPLACE=1` | raw args / completely custom command line |
| `PUID` / `PGID` | run the server as your host user, files stay yours |

Prefer configuring in `.cfg` files? Keep doing that: point `CONFIG` at your
`server.cfg` and put everything there; the env vars are optional shortcuts.

## Multiple servers

One image, one folder per server; each folder has its own `.env`, `game/` and
optional `libcod/`, differing in as little as `NET_PORT`. This is a first-class
use case, see [docs/multiple-servers.md](docs/multiple-servers.md).

## Logs

All server logs land in your host-side `./game/` directory: `games_mp.log`,
zk_libcod's `crash.log`, `scriptdata/`, while the live console stays in
`docker compose logs`. Nothing to dig out of `/var/lib/docker`. Details:
[docs/logs.md](docs/logs.md).

## Docs

- [docs/configuration.md](docs/configuration.md) - every env var, networking modes, ports
- [docs/libcod.md](docs/libcod.md) - libcod supply paths: baked / local build / URL / CI artifacts
- [docs/logs.md](docs/logs.md) - where every log goes
- [docs/multiple-servers.md](docs/multiple-servers.md) - several servers off one image
- [docs/migration.md](docs/migration.md) - moving an existing server into this setup

## Credits and references

This project stands on prior work by the CoD2 community:

- [ibuddieat/zk_libcod](https://github.com/ibuddieat/zk_libcod) the libcod this image targets, its [docs](https://github.com/ibuddieat/zk_libcod/tree/dev/doc) cover setups.
- [bgauduch/call-of-duty-2-docker-server](https://github.com/bgauduch/call-of-duty-2-docker-server)
- [rutkowski/cod2-docker](https://github.com/adrianrutkowski/cod2-docker)
- [Killtube: Latest cod2 linux binaries (1.0, 1.2, 1.3)](https://killtube.org/showthread.php?1719-Latest-cod2-linux-binaries-(1-0-1-2-1-3)) Server binary patches (`nodelay`, `va`, `loc`, `cracked`) by **Kung Foo Man** and **Mitch**
- [Speex](https://gitlab.xiph.org/xiph/speex)

## License

MIT
