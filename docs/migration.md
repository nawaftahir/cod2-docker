# Migrating an existing server into this setup

Recommended host OS: **Debian 13** (the image default). Ubuntu 24.04 also works.

## Before you start

Back up your existing server files (game data, configs, mod folders, libcod, logs).

## Checklist

1. **Install Docker** on the new host (`curl -fsSL https://get.docker.com | sh`).
2. **Create a server folder** and grab the compose file and env template:

   ```bash
   mkdir ~/cod2-server && cd ~/cod2-server
   mkdir -p game libcod
   wget https://raw.githubusercontent.com/nawaftahir/cod2-docker/main/docker-compose.yml
   wget https://raw.githubusercontent.com/nawaftahir/cod2-docker/main/.env.example -O .env
   ```

3. **Game data** goes into `./game/`:
   - `game/main/` - `iw_00.iwd` ... `iw_15.iwd`, `localized_*_iwXX.iwd`, `server.cfg`
   - `game/<mod>/` - your mod's `.iwd`s and loose files; set `FS_GAME=<mod>`
   - anything the server wrote before (`scriptdata/`, logs, a `Library/` map folder)
     goes into the same tree; `fs_homepath` defaults to `/server/game`
4. **Edit `.env`**: either translate each `+set x v` from your old launch command to
   `COD2_SET_x=v` / the first-class vars (`NET_PORT`, `MAXCLIENTS`, `FS_GAME`,
   `CONFIG`, ...), or skip the translation entirely and paste your old command line
   into `PARAMS` with `PARAMS_REPLACE=1`.
5. **libcod**: rebuild reproducibly with
   `./scripts/build-libcod.sh --repo ... --ref ...`, or drop your existing 32-bit
   `libcod2.so` into `./libcod/`. Set `LIBCOD_MODE=off` if you ran vanilla.
6. **Ownership**: set `PUID`/`PGID` in `.env` to the host user that owns `./game`
   (check with `id`), so the server writes files as that user.
7. **Start and verify**:

   ```bash
   ENTRYPOINT_DRYRUN=1 docker compose run --rm cod2   # inspect the resolved command
   docker compose up -d && docker compose logs -f     # boot: no script compile errors
   ```

   The healthcheck goes `healthy` once the server answers `getinfo` on its port.
8. **Cut over** DNS/favorites to the new host/port and retire the old process.
