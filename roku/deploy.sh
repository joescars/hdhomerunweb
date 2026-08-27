#!/usr/bin/env bash
#
# Package and sideload the Roku app onto a Roku in Developer Mode.
#
#   ./deploy.sh                 # uses ROKU_IP / ROKU_DEV_PASSWORD from env or .env
#   ROKU_IP=192.168.1.50 ./deploy.sh
#   ./deploy.sh --package-only  # just build roku-app.zip, don't upload
#
set -euo pipefail

cd "$(dirname "$0")"

# Optional: read ROKU_IP / ROKU_DEV_PASSWORD from roku/.env (gitignored).
if [[ -f .env ]]; then
  # shellcheck disable=SC1091
  source .env
fi

ZIP_NAME="roku-app.zip"
PACKAGE_ONLY=0
[[ "${1:-}" == "--package-only" ]] && PACKAGE_ONLY=1

# --- build the package ------------------------------------------------------
# The manifest MUST sit at the zip root - zipping the parent folder is the
# single most common reason a sideload is rejected.
rm -f "$ZIP_NAME"
zip -r -q "$ZIP_NAME" manifest source components images \
  -x '*.DS_Store' -x '*/.*'

echo "Built $ZIP_NAME ($(du -h "$ZIP_NAME" | cut -f1))"

if [[ -f "$ZIP_NAME" ]]; then
  if ! unzip -l "$ZIP_NAME" | grep -qE '^\s+[0-9]+.*\smanifest$'; then
    echo "ERROR: manifest is not at the zip root - Roku will reject this." >&2
    exit 1
  fi
fi

[[ $PACKAGE_ONLY -eq 1 ]] && exit 0

# --- upload -----------------------------------------------------------------
: "${ROKU_IP:?Set ROKU_IP (e.g. export ROKU_IP=192.168.1.50) or put it in roku/.env}"
: "${ROKU_DEV_PASSWORD:?Set ROKU_DEV_PASSWORD (the Developer Mode password) or put it in roku/.env}"

echo "Uploading to http://$ROKU_IP ..."

response=$(curl -sS --fail-with-body --digest \
  -u "rokudev:$ROKU_DEV_PASSWORD" \
  -F "mysubmit=Install" \
  -F "archive=@$ZIP_NAME" \
  -F "passwd=" \
  "http://$ROKU_IP/plugin_install" 2>&1) || {
    echo "Upload failed. Check that:" >&2
    echo "  - the Roku at $ROKU_IP is in Developer Mode" >&2
    echo "  - ROKU_DEV_PASSWORD matches the password you set (not your Roku account password)" >&2
    echo "$response" >&2
    exit 1
  }

# Roku returns an HTML page; pull out the status line it embeds.
if grep -qi "Identical to previous version" <<<"$response"; then
  echo "Roku reports this build is identical to the installed one."
  echo "Bump build_version in roku/manifest to force a reinstall."
elif grep -qi "success\|received\|installed" <<<"$response"; then
  echo "Installed. Launch it from the Roku home screen."
else
  echo "Upload completed but the response was unexpected:" >&2
  sed -e 's/<[^>]*>//g' <<<"$response" | grep -v '^\s*$' | head -20 >&2
fi

echo
echo "Debug console:  telnet $ROKU_IP 8085"
