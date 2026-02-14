#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 || $# -gt 2 ]]; then
  echo "Usage: $0 <version> [output_dir]"
  echo "Example: $0 1.0.0"
  exit 1
fi

VERSION="$1"
OUT_DIR="${2:-dist}"

PROJECT="MouseManager.xcodeproj"
SCHEME="MouseManager"
DERIVED_DATA_PATH="build/DerivedData"
APP_NAME="MouseManager.app"
APP_PATH="${DERIVED_DATA_PATH}/Build/Products/Release/${APP_NAME}"
ZIP_NAME="MouseManager-preview-v${VERSION}-macOS26.zip"
ZIP_PATH="${OUT_DIR}/${ZIP_NAME}"
SHA_PATH="${ZIP_PATH}.sha256"

echo "==> Building ${SCHEME} (Release)"
xcodebuild \
  -project "${PROJECT}" \
  -scheme "${SCHEME}" \
  -configuration Release \
  -destination "generic/platform=macOS" \
  -derivedDataPath "${DERIVED_DATA_PATH}" \
  build >/dev/null

if [[ ! -d "${APP_PATH}" ]]; then
  echo "Build succeeded but app bundle not found: ${APP_PATH}"
  exit 1
fi

mkdir -p "${OUT_DIR}"

echo "==> Creating ZIP artifact"
rm -f "${ZIP_PATH}" "${SHA_PATH}"
ditto -c -k --sequesterRsrc --keepParent "${APP_PATH}" "${ZIP_PATH}"

echo "==> Computing SHA256"
SHA256="$(shasum -a 256 "${ZIP_PATH}" | awk '{print $1}')"
printf "%s  %s\n" "${SHA256}" "${ZIP_NAME}" >"${SHA_PATH}"

echo "Created:"
echo "  ${ZIP_PATH}"
echo "  ${SHA_PATH}"
echo "SHA256: ${SHA256}"
