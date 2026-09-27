#!/bin/bash
set -euo pipefail
IPA="${1:-./Erosion.ipa}"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "== Grappa build diagnostics =="
echo "IPA: $IPA"
test -f "$IPA"
unzip -q "$IPA" -d "$TMP"
APP_BIN="$(find "$TMP/Payload" -maxdepth 2 -type f -perm -111 -name 'Erosion' -print -quit || true)"
if [[ -z "$APP_BIN" ]]; then
  echo "ERROR: could not locate Payload/Erosion.app/Erosion"
  find "$TMP/Payload" -maxdepth 3 -type f -print | head -80 || true
  exit 1
fi

echo "Binary: $APP_BIN"
echo "--- Exported symbols matching ALGetGrappaToken ---"
if command -v nm >/dev/null 2>&1; then
  nm -gj "$APP_BIN" 2>/dev/null | grep -E '^_?ALGetGrappaToken$' || true
  echo "--- all symbol mentions ---"
  nm -a "$APP_BIN" 2>/dev/null | grep -F 'ALGetGrappaToken' || true
fi

echo "--- strings mentions ---"
strings "$APP_BIN" 2>/dev/null | grep -F 'ALGetGrappaToken' || true

echo "--- project source presence ---"
test -f ./Erosion/GrappaHelper.m && echo "GrappaHelper.m: present"
test -f ./Erosion/GrappaHelper.h && echo "GrappaHelper.h: present"

echo "Diagnostics complete. No exploit/runtime operation was invoked by this script."
