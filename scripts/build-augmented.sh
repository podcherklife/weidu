#!/usr/bin/env bash
# Build augmented WeiDU on the host and stage artifacts for inspection.
#
# Run this from the host, not from inside the OpenCode Flatpak:
#
#   ./scripts/build-augmented.sh
#
# Output is printed live and also appended to build/build.log.
#
# Artifacts (under build/):
#   build.log          full stdout/stderr of the build and extraction
#   status.json        machine-readable result (written on success and failure)
#   version.txt        output of `<binary> --version` (success only)
#   weidu-augmented    the built binary (success only)
#
# Environment:
#   CONTAINER_RUNTIME  podman (default) or docker
#   IMAGE_TAG          image tag to build (default: weidu-augmented)
#   CONTAINER_NAME     temporary container name (default: temp-weidu)

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
BUILD_DIR="$ROOT/build"
LOG="$BUILD_DIR/build.log"
STATUS="$BUILD_DIR/status.json"
VERSION_FILE="$BUILD_DIR/version.txt"
BIN="$BUILD_DIR/weidu-augmented"
IMAGE="${IMAGE_TAG:-weidu-augmented}"
CONTAINER="${CONTAINER_NAME:-temp-weidu}"
RUNTIME="${CONTAINER_RUNTIME:-}"
REL_BIN="build/weidu-augmented"

mkdir -p "$BUILD_DIR"
rm -f "$BIN" "$VERSION_FILE" "$STATUS"
: > "$LOG"

json_escape() {
  local s=${1-}
  s=${s//\\/\\\\}
  s=${s//\"/\\\"}
  s=${s//$'\n'/\\n}
  s=${s//$'\r'/\\r}
  s=${s//$'\t'/\\t}
  printf '%s' "$s"
}

write_status() {
  local result=$1 stage=$2 code=$3 image_id=${4-} sha=${5-} size=${6-} vout=${7-}
  local git_rev git_status
  git_rev=$(git -C "$ROOT" rev-parse HEAD 2>/dev/null || echo unknown)
  git_status=$(git -C "$ROOT" status --porcelain 2>/dev/null | head -20 | tr '\n' ';' || true)
  cat > "$STATUS" <<EOF
{
  "result": "$(json_escape "$result")",
  "stage": "$(json_escape "$stage")",
  "exit_code": $code,
  "timestamp_utc": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "git_rev": "$(json_escape "$git_rev")",
  "git_status": "$(json_escape "$git_status")",
  "runtime": "$(json_escape "$RUNTIME")",
  "image_tag": "$(json_escape "$IMAGE")",
  "image_id": "$(json_escape "$image_id")",
  "binary": "$(json_escape "$REL_BIN")",
  "binary_sha256": "$(json_escape "$sha")",
  "binary_size": ${size:-0},
  "version_output": "$(json_escape "$vout")"
}
EOF
}

if [ -z "$RUNTIME" ]; then
  if command -v podman >/dev/null 2>&1; then
    RUNTIME=podman
  elif command -v docker >/dev/null 2>&1; then
    RUNTIME=docker
  else
    RUNTIME=none
  fi
fi
if [ "$RUNTIME" = none ] || ! command -v "$RUNTIME" >/dev/null 2>&1; then
  echo "ERROR: neither podman nor docker is available on PATH" >&2
  write_status failure runtime 127
  exit 127
fi

echo "== build-augmented: $IMAGE (runtime: $RUNTIME)" | tee -a "$LOG"
echo "== log: $LOG" | tee -a "$LOG"
{
  echo "== started: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "== root: $ROOT"
  echo "== git: $(git -C "$ROOT" rev-parse --short HEAD 2>/dev/null || echo unknown)"
  echo "== git status:"
  git -C "$ROOT" status --porcelain 2>/dev/null || true
  echo
} >> "$LOG"

run_stage() {
  local name=$1
  local rc
  shift
  printf '%s\n' "== [$(date -u +%H:%M:%S)] stage $name: $*" | tee -a "$LOG"
  set +e
  "$@" 2>&1 | tee -a "$LOG"
  rc=${PIPESTATUS[0]}
  set -e
  if [ "$rc" -ne 0 ]; then
    echo "FAILED: $name (exit $rc); see $LOG" >&2
    write_status failure "$name" "$rc"
    exit "$rc"
  fi
}

cleanup() {
  "$RUNTIME" rm -f "$CONTAINER" >> "$LOG" 2>&1 || true
}
trap cleanup EXIT

run_stage build "$RUNTIME" build -t "$IMAGE" "$ROOT"
"$RUNTIME" rm -f "$CONTAINER" >> "$LOG" 2>&1 || true

if [ "$RUNTIME" = docker ]; then
  run_stage create "$RUNTIME" create --name "$CONTAINER" "$IMAGE"
else
  run_stage create "$RUNTIME" create --replace --name "$CONTAINER" "$IMAGE"
fi

run_stage copy "$RUNTIME" cp "$CONTAINER:/src/weidu" "$BIN"
run_stage chmod chmod +x "$BIN"

printf '%s\n' "== stage smoke: $BIN --version" | tee -a "$LOG"
set +e
version_output=$(cd "$BUILD_DIR" && timeout 30 "$BIN" --version 2>&1)
rc=$?
set -e
printf '%s\n' "$version_output" > "$VERSION_FILE"
printf '%s\n' "$version_output" | tee -a "$LOG"
if [ "$rc" -ne 0 ]; then
  echo "FAILED: smoke test exited $rc; see $LOG" >&2
  write_status failure smoke "$rc"
  exit "$rc"
fi
if ! printf '%s' "$version_output" | grep -q -- '-augmented'; then
  echo "FAILED: version output does not contain -augmented; see $VERSION_FILE" >&2
  write_status failure smoke 1
  exit 1
fi

image_id=$("$RUNTIME" image inspect --format '{{.Id}}' "$IMAGE" 2>>"$LOG" || true)
sha=$(sha256sum "$BIN" | awk '{print $1}')
size=$(stat -c %s "$BIN")

write_status success complete 0 "$image_id" "$sha" "$size" "$version_output"

echo "OK: $BIN"
printf '%s\n' "$version_output"
echo "log: $LOG"
