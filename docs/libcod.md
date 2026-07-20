# libcod supply paths

[zk_libcod](https://github.com/ibuddieat/zk_libcod) is loaded via `LD_PRELOAD`. The image
is built so that **which `.so` you run never requires an image rebuild**: the runtime
always ships the 32-bit Speex and MySQL client libraries, so a `libcod2.so` built with or
without those features loads either way.

`LIBCOD_MODE` picks the source; every start logs the chosen file and its sha256.

## `off` - vanilla server

No `LD_PRELOAD` at all. A completely stock CoD2 dedicated server.

## `baked` - the image default

The Dockerfile compiles zk_libcod at **image build time** and stores it inside the
image. It follows the same three `.env` values as the local builder:

```dotenv
LIBCOD_REPO=https://github.com/ibuddieat/zk_libcod
LIBCOD_REF=master
LIBCOD_BUILD_ARGS=mysql1     # doit.sh flags: mysql1|mysql2|nomysql, nospeex, debug, unsafe
```

but ONLY when the image is (re)built:

```bash
docker compose build && docker compose up -d
```

Changing these values in `.env` does nothing to a running baked libcod until you
rebuild the image. If you want ".env change + restart" without image rebuilds,
use the local builder recipe above (`custom` mode) instead.

Every mode's startup log shows exactly what is loaded:

```
[cod2] libcod: /server/libcod/custom/libcod2.so (mode: custom, sha256: 76a14935...)
[cod2] libcod build: repo=... ref=dev commit=9556175 args=mysql1 built=2026-07-20T15:34:05Z
```

If the `commit=` there is not what you expect, the wrong supply path is selected;
check `LIBCOD_MODE`.

## Recipe: image cached, libcod always fresh from the latest commit

The most common setup: the server image (OS, 32-bit libs, Speex, binaries) is built
once and cached; only libcod is compiled locally, from the latest commit, whenever
you want.

One-time, in `.env`:

```dotenv
LIBCOD_MODE=custom                                   # only ever run my locally-built .so
LIBCOD_REPO=https://github.com/ibuddieat/zk_libcod
LIBCOD_REF=dev                                       # branch tip = latest commit at build time
LIBCOD_BUILD_ARGS=mysql1                             # doit.sh flags: mysql1|mysql2|nomysql, nospeex, debug, unsafe
```

Build (and later: update) libcod, then restart:

```bash
docker compose --profile tools run --rm libcod-builder
docker compose up -d
```

The builder does a fresh clone every run, so re-running these two commands always
compiles the latest `LIBCOD_REF` commit. The server image is never rebuilt. The
startup log prints the sha256 of the `.so` in use so you can verify the swap.

Note: in `custom` mode the server refuses to start until `./libcod/libcod2.so`
exists, i.e. until the builder has run once. Use `LIBCOD_MODE=auto` instead if you
want fallback to the baked libcod when no local build is present.

## `custom` - build locally, hot-swap

```bash
./scripts/build-libcod.sh --repo <git url> --ref <branch|tag|sha> --args "mysql2 debug"
docker compose restart cod2
```

This runs the `libcod-builder` image (same toolchain that baked the default: 32-bit g++,
Speex, MySQL client headers) and writes `./libcod/libcod2.so`, which is bind-mounted
into the server. In `auto` mode a file there always wins. Delete the file to fall back.

Use this to update libcod to a newer commit at any time: re-run the script, restart
the container, done. The same path works for any zk_libcod-compatible repo or branch,
and for build flags the CI artifacts never include (`unsafe`, `debug`, Speex).

Equivalent without the helper:

```bash
LIBCOD_REPO=<url> LIBCOD_REF=<ref> docker compose --profile tools run --rm libcod-builder mysql2 debug
```

## `fetch` - download a prebuilt .so or CI artifact

### Any direct URL

```dotenv
LIBCOD_MODE=fetch        # or leave auto; a set LIBCOD_URL/LIBCOD_ARTIFACT is used automatically
LIBCOD_URL=https://example.com/builds/libcod2.so
```

Works with any HTTP(S) file. If the download is a **zip** (GitHub artifacts are), the
`.so` inside is extracted automatically. Downloaded once and cached; set
`LIBCOD_URL_FORCE=1` for one start to re-download.

### zk_libcod GitHub Actions artifacts (specific commits)

Upstream CI builds an artifact for **every commit** on `dev`, in six flavours:

| Artifact name | OS | MySQL |
|---|---|---|
| `libcod2_debian_mysql1` | Debian 13 | mysql1 |
| `libcod2_debian_mysql2` | Debian 13 | mysql2 |
| `libcod2_debian_no_mysql` | Debian 13 | none |
| `libcod2_ubuntu_mysql1` / `_mysql2` / `_no_mysql` | Ubuntu 24.04 | ... |

**Caveats:** all CI artifacts are built `nospeex`, and never `debug`/`unsafe`. If you
need voice, debug symbols, or unsafe functions, use the local builder instead.
Artifacts expire after a while (GitHub retention), and downloading them requires a
GitHub token (any account's token with public-repo read works).

```dotenv
LIBCOD_ARTIFACT=libcod2_debian_mysql1
#LIBCOD_COMMIT=1a2b3c4          # optional: pin a commit (sha prefix); latest otherwise
#LIBCOD_ARTIFACT_REPO=ibuddieat/zk_libcod   # any repo with the same CI layout
GITHUB_TOKEN=github_pat_...
```

The entrypoint resolves the newest non-expired artifact matching name (+ commit),
downloads and unzips it. Pick the flavour matching your image base (`debian_*` for the
default Debian 13 image, `ubuntu_*` for a `BASE_IMAGE=ubuntu:24.04` build).

## `auto` (default) - precedence

`./libcod/libcod2.so` (custom) > `LIBCOD_URL`/`LIBCOD_ARTIFACT` fetch > baked default.

## MySQL variants

- `mysql1` - kungfooman/IzNoGoD implementation: multi-connection, multi-threaded,
  good for remote DB sessions. This is the baked default.
- `mysql2` - VoroN implementation: single connection/thread, lighter, good for a
  local DB.
- `nomysql` - none.

## Speex voice

Baked and custom builds compile against 32-bit Speex automatically; pass `nospeex`
in the build args to leave voice out. Note zk_libcod's tuning docs: Speex adds
roughly 500 MB RAM per server when enabled.

## ffmpeg

`getSoundDuration` needs `ffprobe`. It's off by default (~300 MB); build the image
with `--build-arg WITH_FFMPEG=1` if you use it.
