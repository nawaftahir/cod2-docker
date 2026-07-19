# Logs & console

## Live console (attach)

The server console is fully interactive, like running `cod2_lnxded` in a screen:

```bash
docker attach cod2        # live console; type commands (map, status, say, ...)
```

Detach with **CTRL-P then CTRL-Q**. Do NOT press CTRL-C: that kills the server.
For read-only watching, prefer `docker compose logs -f` (safe to CTRL-C).
With multiple servers, attach by each one's `container_name`.


Design goal: **every log the server produces lives in your bind-mounted `./game/`
directory on the host**. Nothing important is buried inside the container or in
`/var/lib/docker`.

## Where each log goes

| Log | Written by | Location |
|---|---|---|
| Console output | engine + libcod prints | `docker compose logs` (container stdout) |
| `games_mp.log` | engine (`+set logfile 1`, `g_log`) | `./game/<fs_game or main>/games_mp.log` |
| `crash.log` | zk_libcod (stack trace on segfault etc.) | `./game/crash.log` |
| `console_mp.log` | engine (if `logfile 2`) | `./game/<fs_game or main>/` |
| MySQL/module logs, `scriptdata/` | libcod / GSC | under `./game/...` per their config |

Why it works: `fs_homepath` defaults to `/server/game` (the `./game` bind mount) so
everything path-relative the engine writes lands there, and the entrypoint runs the
server **with `./game` as working directory**, which is where zk_libcod writes its
`crash.log` (it uses the cwd).

## Engine log cvars quick reference

- `logfile 0|1|2` - 0 off, 1 buffered `games_mp.log`, 2 also `console_mp.log`, unbuffered
- `g_log <name>` - change the game log filename (relative to `fs_game`)
- `g_logSync 1` - flush every line (slower, but nothing lost on a crash)

Set them in `server.cfg`, in `game/cod2.args`, or via env (`COD2_SET_logfile=1`).

## Console log in `docker logs` vs on disk

Container stdout (`docker compose logs -f`) always has the live console, including
libcod's `[LIBCOD]` lines and the entrypoint's resolved command/libcod choice.
If you also want `games_mp.log` mirrored into `docker logs`, set `LOG_TO_STDOUT=1`,
but then it is **not** on disk anymore (it becomes a symlink to stdout). Most setups
should keep the default `0`: file on disk in `./game`, console in `docker logs`.

## Log rotation

Docker's own json log can grow; cap it in compose if the server is chatty:

```yaml
    logging:
      driver: json-file
      options: { max-size: "20m", max-file: "3" }
```

`games_mp.log` rotation is your call on the host (logrotate or a cron task); it's a
plain file in `./game`.
