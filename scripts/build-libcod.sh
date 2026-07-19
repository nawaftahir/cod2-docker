#!/bin/bash
# Build a libcod2.so from any repo/ref with custom doit.sh flags, WITHOUT
# rebuilding the server image. Output: ./libcod/libcod2.so - then just:
#   docker compose restart cod2
#
# Usage:
#   ./scripts/build-libcod.sh                                  # zk_libcod master, mysql1
#   ./scripts/build-libcod.sh --ref dev --args "mysql1 debug"
#   ./scripts/build-libcod.sh --repo https://github.com/you/fork --ref mybranch --args "nomysql nospeex"
set -euo pipefail
cd "$(dirname "$0")/.."

REPO="https://github.com/ibuddieat/zk_libcod"
REF="master"
ARGS="mysql1"

while [ $# -gt 0 ]; do
    case "$1" in
        --repo) REPO="$2"; shift 2 ;;
        --ref)  REF="$2";  shift 2 ;;
        --args) ARGS="$2"; shift 2 ;;
        -h|--help) grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "unknown option: $1 (see --help)" >&2; exit 1 ;;
    esac
done

mkdir -p libcod
docker compose --profile tools build libcod-builder
# shellcheck disable=SC2086
LIBCOD_REPO="$REPO" LIBCOD_REF="$REF" \
    docker compose --profile tools run --rm \
    --user "$(id -u):$(id -g)" -e HOME=/tmp libcod-builder $ARGS

echo
echo "Done: ./libcod/libcod2.so - apply with: docker compose restart cod2"
