#!/bin/bash
# Clones and compiles a libcod (zk_libcod-compatible) repo, drops libcod2.so
# into $OUT_DIR. Runs inside the libcod-builder image, both at image build
# time and on demand via `scripts/build-libcod.sh` / the compose tools profile.
#
# Env:  LIBCOD_REPO  git URL          (default: ibuddieat/zk_libcod)
#       LIBCOD_REF   branch/tag/sha   (default: master)
#       OUT_DIR      output directory (default: /out)
# Args: passed to doit.sh verbatim (mysql1|mysql2|nomysql, nospeex, debug, unsafe)
set -euo pipefail

LIBCOD_REPO="${LIBCOD_REPO:-https://github.com/ibuddieat/zk_libcod}"
LIBCOD_REF="${LIBCOD_REF:-master}"
OUT_DIR="${OUT_DIR:-/out}"
# doit.sh flags: positional args win, else LIBCOD_BUILD_ARGS env (from .env)
if [ $# -gt 0 ]; then
    ARGS=("$@")
else
    # shellcheck disable=SC2206
    ARGS=(${LIBCOD_BUILD_ARGS:-})
fi

# doit.sh prompts interactively unless a mysql variant is explicit - never hang
has_mysql_arg=0
for a in "${ARGS[@]:-}"; do
    case "$a" in mysql1|mysql2|nomysql) has_mysql_arg=1 ;; esac
done
if [ "$has_mysql_arg" = "0" ]; then
    echo "[build-libcod] no mysql1/mysql2/nomysql given, defaulting to mysql1"
    ARGS+=("mysql1")
fi

echo "[build-libcod] repo:  $LIBCOD_REPO"
echo "[build-libcod] ref:   $LIBCOD_REF"
echo "[build-libcod] args:  ${ARGS[*]}"

workdir="$(mktemp -d)"
trap 'rm -rf "$workdir"' EXIT
git clone "$LIBCOD_REPO" "$workdir/libcod"
git -C "$workdir/libcod" checkout "$LIBCOD_REF"

# zk_libcod keeps its build in code/; older forks build from the repo root
if [ -f "$workdir/libcod/code/doit.sh" ]; then
    cd "$workdir/libcod/code"
else
    cd "$workdir/libcod"
fi
bash doit.sh "${ARGS[@]}"

so="$(find bin -name 'libcod2*.so' | head -n1)"
if [ -z "$so" ]; then
    echo "[build-libcod] ERROR: build produced no libcod2*.so in bin/" >&2
    exit 1
fi
mkdir -p "$OUT_DIR"
cp "$so" "$OUT_DIR/libcod2.so"
echo "[build-libcod] done: $OUT_DIR/libcod2.so ($(sha256sum "$OUT_DIR/libcod2.so" | cut -c1-16)...)"
