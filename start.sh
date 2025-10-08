#!/usr/bin/env bash
set -euo pipefail

# Paths
IMG_RELEASE="/app/release"
PERSISTENT="/data/release"
PB_DIR_NAME="pocketbase"
PB_BIN="${PERSISTENT}/${PB_DIR_NAME}/pocketbase"
PB_DATA_DIR="${PERSISTENT}/${PB_DIR_NAME}/pb_data"   # where PB will store DB/logs
VERSION_FILE="VERSION"

mkdir -p "${PERSISTENT}"
chmod 0755 "${PERSISTENT}"

# Helper: copy whole release (tar preserves perms) from image -> persistent
_copy_release_to_persistent() {
  echo "Copying release from image -> persistent..."
  (cd "${IMG_RELEASE}" && tar -cf - .) | (cd "${PERSISTENT}" && tar -xpf -)
  echo "Copy complete."
}

# If persistent release empty => initial copy
if [ -z "$(ls -A "${PERSISTENT}" 2>/dev/null)" ]; then
  echo "Persistent release is empty. Initializing..."
  _copy_release_to_persistent
  # write the version marker if image had one (keeps consistency)
  if [ -f "${IMG_RELEASE}/${VERSION_FILE}" ]; then
    cp -p "${IMG_RELEASE}/${VERSION_FILE}" "${PERSISTENT}/${VERSION_FILE}" || true
  fi
else
  echo "Persistent release already present. Performing merge-check..."

  # If image has VERSION and differs from persistent VERSION, perform upgrade copy (safe)
  if [ -f "${IMG_RELEASE}/${VERSION_FILE}" ]; then
    IMG_VER=$(cat "${IMG_RELEASE}/${VERSION_FILE}" || true)
    PERSIST_VER=$(cat "${PERSISTENT}/${VERSION_FILE}" 2>/dev/null || true)

    if [ "${IMG_VER}" != "${PERSIST_VER}" ]; then
      echo "Detected image VERSION '${IMG_VER}' != persistent VERSION '${PERSIST_VER}'."
      echo "Will copy missing/updated files from image -> persistent while preserving existing data."
      # copy via tar but avoid clobbering existing files: extract to temp and rsync-like copy
      TMPDIR=$(mktemp -d)
      (cd "${IMG_RELEASE}" && tar -cf - .) | (cd "${TMPDIR}" && tar -xpf -)
      # move files that do not already exist in persistent; do not overwrite anything by default
      cd "${TMPDIR}"
      find . -type d -print0 | xargs -0 -I{} mkdir -p "${PERSISTENT}/{}"
      # copy files only if target doesn't exist
      find . -type f -print0 | while IFS= read -r -d '' f; do
        if [ ! -e "${PERSISTENT}/${f}" ]; then
          install -m 0644 "${f}" "${PERSISTENT}/${f}"
        else
          # if it's the pocketbase binary, we may choose to overwrite based on policy:
          if [ "${f}" = "${PB_DIR_NAME}/pocketbase" ]; then
            echo "PocketBase binary exists in persistent. Overwriting binary to new image version."
            install -m 0755 "${f}" "${PERSISTENT}/${f}"
          fi
        fi
      done
      rm -rf "${TMPDIR}"
      # update persistent VERSION
      cp -pf "${IMG_RELEASE}/${VERSION_FILE}" "${PERSISTENT}/${VERSION_FILE}" || true
      echo "Merge-upgrade complete."
    else
      echo "Image VERSION matches persistent VERSION (${IMG_VER}). No merge needed."
    fi
  else
    # No VERSION found; ensure any missing files (dist, pb_migrations, etc) are present in persistent
    echo "No VERSION file found in image. Ensuring missing files from image are copied (without overwriting)."
    TMPDIR=$(mktemp -d)
    (cd "${IMG_RELEASE}" && tar -cf - .) | (cd "${TMPDIR}" && tar -xpf -)
    cd "${TMPDIR}"
    find . -type d -print0 | xargs -0 -I{} mkdir -p "${PERSISTENT}/{}"
    find . -type f -print0 | while IFS= read -r -d '' f; do
      if [ ! -e "${PERSISTENT}/${f}" ]; then
        install -m 0644 "${f}" "${PERSISTENT}/${f}"
      fi
    done
    rm -rf "${TMPDIR}"
    echo "Merge-check complete."
  fi
fi

# Ensure pocketbase binary is executable
if [ -f "${PB_BIN}" ]; then
  chmod +x "${PB_BIN}" || true
else
  echo "ERROR: pocketbase binary not found at ${PB_BIN}"
  exit 1
fi

# Ensure PB data dir exists
mkdir -p "${PB_DATA_DIR}"
chmod 0755 "${PB_DATA_DIR}"

# cd into pocketbase dir inside persisted release and start services
cd "${PERSISTENT}/${PB_DIR_NAME}"

# graceful shutdown handler for PB
_term() {
  echo "Caught termination signal, stopping pocketbase..."
  kill -TERM "${PB_PID}" 2>/dev/null || true
  wait "${PB_PID}" || true
  exit 0
}
trap _term SIGINT SIGTERM

echo "Starting PocketBase on 127.0.0.1:8090 using --dir='${PB_DATA_DIR}' ..."
# start pocketbase; ensure we use the binary from the persisted volume
./pocketbase serve --dir="${PB_DATA_DIR}" --http="127.0.0.1:8090" &

PB_PID=$!

# small wait to let PB bind
sleep 1

# Start nginx; make sure it serves from /data/release/dist (see provided nginx.conf snippet)
echo "Starting nginx (foreground) ..."
exec nginx -g "daemon off;"
