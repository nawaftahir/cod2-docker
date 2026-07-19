# Running multiple servers

Multi-server is a first-class use case: **one image, one folder per server**. Each
folder holds its own `docker-compose.yml` (or a copy of the repo's), `.env`, `game/`,
and optional `libcod/`. Servers share nothing except the image, so each one can run
a different mod, a different libcod, even a different binary version.

```
~/servers/
├── public/        # .env: NET_PORT=28960, FS_GAME=mymod
├── scrim/         # .env: NET_PORT=28962, FS_GAME=zpam336
└── bots/          # .env: NET_PORT=28965
```

Per server:

```bash
cd ~/servers/scrim
cp /path/to/cod2-docker/{docker-compose.yml,.env.example} .
mv .env.example .env
# edit .env: unique NET_PORT; give the compose service its own container_name
docker compose up -d
```

Notes:

- With `network_mode: host` (default) only `NET_PORT` must differ. In bridged mode,
  publish each server's UDP port instead.
- Set a distinct `container_name` per folder (or remove the field and let compose
  name it after the folder).
- Shared big files: point several servers at one read-only `main/` with two mounts,
  e.g. `- /data/cod2/main:/server/game/main:ro` plus a per-server writable mod
  folder mount.
- Each server can use a different libcod: a different `./libcod/libcod2.so` per
  folder, or different `LIBCOD_URL`/`LIBCOD_ARTIFACT` values.
- A shared map `Library/` works the same way: mount it into each server's game dir
  (read-only is fine) and set `FS_LIBRARY` accordingly.
- Speex-enabled libcod costs ~500 MB RAM per server; budget accordingly.
