#!/bin/bash
# cod2-server-docker entrypoint: pick binary, pick libcod, build the command
# line from env vars, drop privileges, exec the server.
# Full reference: docs/configuration.md
set -euo pipefail

log() { echo "[cod2] $*"; }

# ------------------------------------------------------------------
# 1. Privileges: if running as root, fix ownership then drop to PUID/PGID
# ------------------------------------------------------------------
PUID="${PUID:-1000}"
PGID="${PGID:-1000}"
if [ "$(id -u)" = "0" ]; then
    current_uid="$(id -u cod2)"
    current_gid="$(id -g cod2)"
    if [ "$current_gid" != "$PGID" ]; then groupmod -o -g "$PGID" cod2; fi
    if [ "$current_uid" != "$PUID" ]; then usermod -o -u "$PUID" cod2; fi
    chown cod2:cod2 /server /server/libcod /server/libcod/fetched 2>/dev/null || true
    # game data is usually a bind mount owned by the host user; only chown on request
    if [ "${CHOWN_GAME_DIR:-0}" = "1" ]; then chown -R cod2:cod2 /server/game; fi
    exec setpriv --reuid cod2 --regid cod2 --init-groups env HOME=/server "$0" "$@"
fi
export HOME="${HOME:-/server}"

# ------------------------------------------------------------------
# 2. Server binary
# ------------------------------------------------------------------
COD2_VERSION="${COD2_VERSION:-1_3}"
COD2_VARIANT="${COD2_VARIANT:-}"
if [ -n "${COD2_BINARY:-}" ]; then
    BIN="$COD2_BINARY"
else
    BIN="/server/bin/cod2_lnxded_${COD2_VERSION}${COD2_VARIANT:+_${COD2_VARIANT}}"
fi
if [ ! -x "$BIN" ]; then
    log "ERROR: server binary not found: $BIN"
    log "available binaries:"
    ls -1 /server/bin/ | sed 's/^/  /'
    exit 1
fi
log "binary: $BIN"

# ------------------------------------------------------------------
# 3. libcod selection
#    LIBCOD_MODE: auto (default) | off | custom | fetch | baked
#    auto precedence: custom (bind mount) > fetched > baked
# ------------------------------------------------------------------
LIBCOD_MODE="${LIBCOD_MODE:-auto}"
CUSTOM_SO="/server/libcod/custom/libcod2.so"
FETCHED_SO="/server/libcod/fetched/libcod2.so"
BAKED_SO="/server/libcod/libcod2.so.default"
chosen_so=""

# Accepts a direct .so URL, a .zip (GitHub Actions artifacts come zipped), or a
# GitHub artifact name via LIBCOD_ARTIFACT (+ optional LIBCOD_COMMIT). Artifact
# API downloads need GITHUB_TOKEN (any GitHub account's token works).
fetch_libcod() {
    local url="${LIBCOD_URL:-}"
    local auth=()
    [ -n "${GITHUB_TOKEN:-}" ] && auth=(-H "Authorization: Bearer $GITHUB_TOKEN")

    if [ -f "$FETCHED_SO" ] && [ "${LIBCOD_URL_FORCE:-0}" != "1" ]; then
        return 0
    fi

    if [ -n "${LIBCOD_ARTIFACT:-}" ]; then
        local repo="${LIBCOD_ARTIFACT_REPO:-ibuddieat/zk_libcod}"
        log "libcod: resolving artifact '$LIBCOD_ARTIFACT' from $repo${LIBCOD_COMMIT:+ @ ${LIBCOD_COMMIT}}"
        if [ -z "${GITHUB_TOKEN:-}" ]; then
            log "ERROR: LIBCOD_ARTIFACT requires GITHUB_TOKEN (GitHub only serves artifacts to authenticated users)"
            exit 1
        fi
        url="$(curl -fsSL "${auth[@]}" \
            "https://api.github.com/repos/$repo/actions/artifacts?name=${LIBCOD_ARTIFACT}&per_page=100" \
            | jq -r --arg sha "${LIBCOD_COMMIT:-}" \
                '[.artifacts[] | select(.expired == false) | select($sha == "" or (.workflow_run.head_sha | startswith($sha)))][0].archive_download_url // empty')"
        if [ -z "$url" ]; then
            log "ERROR: no matching non-expired artifact found (name=$LIBCOD_ARTIFACT commit=${LIBCOD_COMMIT:-any})"
            exit 1
        fi
    fi

    if [ -z "$url" ]; then
        log "ERROR: LIBCOD_MODE=fetch but neither LIBCOD_URL nor LIBCOD_ARTIFACT is set"
        exit 1
    fi

    log "libcod: downloading $url"
    curl -fsSL --retry 3 "${auth[@]}" -o "$FETCHED_SO.tmp" "$url"
    # GitHub artifacts arrive as zip files; unpack the .so out of them
    if [ "$(head -c2 "$FETCHED_SO.tmp")" = "PK" ]; then
        local tmpdir; tmpdir="$(mktemp -d)"
        unzip -o -q "$FETCHED_SO.tmp" -d "$tmpdir"
        local so; so="$(find "$tmpdir" -name '*.so' | head -n1)"
        if [ -z "$so" ]; then
            log "ERROR: downloaded zip contains no .so"
            rm -rf "$tmpdir" "$FETCHED_SO.tmp"
            exit 1
        fi
        mv "$so" "$FETCHED_SO.tmp"
        rm -rf "$tmpdir"
    fi
    mv "$FETCHED_SO.tmp" "$FETCHED_SO"
}

case "$LIBCOD_MODE" in
    off)    ;;
    custom) chosen_so="$CUSTOM_SO" ;;
    fetch)  fetch_libcod; chosen_so="$FETCHED_SO" ;;
    baked)  chosen_so="$BAKED_SO" ;;
    auto)
        if [ -f "$CUSTOM_SO" ]; then chosen_so="$CUSTOM_SO"
        elif [ -n "${LIBCOD_URL:-}" ] || [ -n "${LIBCOD_ARTIFACT:-}" ]; then fetch_libcod; chosen_so="$FETCHED_SO"
        elif [ -f "$FETCHED_SO" ]; then chosen_so="$FETCHED_SO"
        else chosen_so="$BAKED_SO"
        fi ;;
    *) log "ERROR: unknown LIBCOD_MODE '$LIBCOD_MODE' (auto|off|custom|fetch|baked)"; exit 1 ;;
esac

if [ "$LIBCOD_MODE" = "off" ]; then
    log "libcod: DISABLED (vanilla server)"
else
    if [ ! -f "$chosen_so" ]; then
        log "ERROR: libcod library not found: $chosen_so (mode: $LIBCOD_MODE)"
        exit 1
    fi
    log "libcod: $chosen_so (mode: $LIBCOD_MODE, sha256: $(sha256sum "$chosen_so" | cut -c1-16)...)"
    if [ -f "$chosen_so.info" ]; then
        log "libcod build: $(cat "$chosen_so.info")"
    fi
fi
# LD_PRELOAD is applied only on the final exec - exporting it here would spam
# "wrong ELF class" warnings from every 64-bit helper command
export LD_LIBRARY_PATH="/lib/i386-linux-gnu:/usr/lib/i386-linux-gnu${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"

# ------------------------------------------------------------------
# 4. Command line
# ------------------------------------------------------------------
ARGS=()
add_set() { ARGS+=("+$1" "$2" "$3"); }

if [ "${PARAMS_REPLACE:-0}" = "1" ]; then
    # fully custom command line, nothing generated
    # shellcheck disable=SC2086
    ARGS=(${PARAMS:-})
else
    # shellcheck disable=SC2086
    [ -n "${PARAMS_BEFORE:-}" ] && ARGS+=(${PARAMS_BEFORE})

    add_set set dedicated "${DEDICATED:-2}"
    add_set set fs_basepath "${FS_BASEPATH:-/server/game}"
    add_set set fs_homepath "${FS_HOMEPATH:-/server/game}"
    add_set set net_port "${NET_PORT:-28960}"
    [ -n "${FS_GAME:-}" ]      && add_set set fs_game "$FS_GAME"
    [ -n "${FS_LIBRARY:-}" ]   && add_set set fs_library "$FS_LIBRARY"
    [ -n "${MAXCLIENTS:-}" ]   && add_set set sv_maxclients "$MAXCLIENTS"
    [ -n "${SV_HOSTNAME:-}" ]  && add_set set sv_hostname "$SV_HOSTNAME"

    # COD2_SET_foo=bar  -> +set foo bar   (same for SETA / SETS); space-safe
    for kind in set seta sets; do
        prefix="COD2_${kind^^}_"
        while IFS='=' read -r name value; do
            [ -z "$name" ] && continue
            add_set "$kind" "${name#"$prefix"}" "$value"
        done < <(env | grep "^${prefix}" || true)
    done

    [ -n "${CONFIG:-}" ] && ARGS+=("+exec" "$CONFIG")
    [ -n "${MAP:-}" ]    && ARGS+=("+map" "$MAP")
    [ "${MAP_ROTATE:-0}" = "1" ] && ARGS+=("+map_rotate")

    # shellcheck disable=SC2086
    [ -n "${PARAMS:-}" ]       && ARGS+=(${PARAMS})
    # shellcheck disable=SC2086
    [ -n "${PARAMS_AFTER:-}" ] && ARGS+=(${PARAMS_AFTER})
fi

# ------------------------------------------------------------------
# 5. Logs to stdout (optional)
# ------------------------------------------------------------------
if [ "${LOG_TO_STDOUT:-0}" = "1" ]; then
    logdir="${FS_HOMEPATH:-/server/game}/${FS_GAME:-main}"
    mkdir -p "$logdir"
    ln -sf /proc/1/fd/1 "$logdir/games_mp.log" || true
fi

# ------------------------------------------------------------------
# 6. Launch
# ------------------------------------------------------------------
log "command: $BIN ${ARGS[*]}"
if [ "${ENTRYPOINT_DRYRUN:-0}" = "1" ]; then
    log "dry run requested, exiting"
    exit 0
fi
# run from the (host-mounted) game dir: zk_libcod writes crash.log to the cwd
cd "${FS_HOMEPATH:-/server/game}"
if [ -n "$chosen_so" ]; then
    exec env LD_PRELOAD="$chosen_so" "$BIN" "${ARGS[@]}"
else
    exec "$BIN" "${ARGS[@]}"
fi
