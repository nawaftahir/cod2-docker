# Migrating an existing server into this setup

Checklist for moving a bare-metal or older-container CoD2 server here.

1. **Make a server folder** (see [multiple-servers.md](multiple-servers.md)) and
   copy `docker-compose.yml` + `.env.example` (renamed to `.env`).
2. **Game data** goes to `./game/`:
   - `game/main/` - `iw_00.iwd` ... `iw_15.iwd`, `localized_*_iwXX.iwd`, `server.cfg`
   - `game/<mod>/` - your mod's `.iwd`s and loose files; set `FS_GAME=<mod>`
   - anything the server wrote before (`scriptdata/`, logs, a `Library/` map folder)
     goes into the same tree; `fs_homepath` defaults to the same `/server/game`
3. **Old launch command**: either translate each `+set x v` to `COD2_SET_x=v` / the
   first-class vars (`NET_PORT`, `MAXCLIENTS`, `FS_GAME`, `CONFIG`, ...), or skip the
   translation entirely and paste your old command line into `PARAMS` in `.env`,
   with `PARAMS_REPLACE=1` to keep it exact.
4. **libcod**: rebuild your build reproducibly with
   `./scripts/build-libcod.sh --repo ... --ref ...`, or drop your existing 32-bit
   `libcod2.so` into `./libcod/`. `LIBCOD_MODE=off` if you ran vanilla.
5. **Ownership**: set `PUID`/`PGID` in `.env` to the host user that owns `./game`
   (check with `id`), so the server writes files as that user and everything stays
   editable from the host.
6. **Start & verify**:

   ```bash
   ENTRYPOINT_DRYRUN=1 docker compose run --rm cod2   # inspect the resolved command
   docker compose up -d && docker compose logs -f     # boot: no script compile errors
   ```

   The healthcheck goes `healthy` once the server answers `getinfo` on its port.
7. **Cut over** DNS/favorites to the new host/port and retire the old process.
