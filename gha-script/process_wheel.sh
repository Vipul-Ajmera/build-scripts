#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
echo "[DEBUG] Script directory → $SCRIPT_DIR"

WHEEL_PATH="$1"
PACKAGE="$2"
VERSION="$3"

echo "[INFO] Starting wheel processing lifecycle"
echo "[DEBUG] Wheel → $WHEEL_PATH"
echo "[DEBUG] Package → $PACKAGE"
echo "[DEBUG] Version → $VERSION"

WORKDIR="extracted_wheel"
rm -rf "$WORKDIR"
mkdir -p "$WORKDIR"

echo "[INFO] Unpacking wheel..."
if ! wheel unpack "$WHEEL_PATH" -d "$WORKDIR"; then
    echo "[ERROR] wheel unpack failed"
    exit 1
fi

EXTRACTED_DIR=$(find "$WORKDIR" -maxdepth 1 -type d ! -path "$WORKDIR" | head -n 1)

if [ -z "$EXTRACTED_DIR" ]; then
    echo "[ERROR] Extracted directory not found"
    exit 1
fi

echo "[DEBUG] Extracted dir → $EXTRACTED_DIR"

# ---------------- LICENSE ----------------
echo "[INFO] Running license injection"
if ! python "$SCRIPT_DIR/inject_license.py" "$EXTRACTED_DIR"; then
    echo "[ERROR] License injection failed"
    exit 1
fi

# ---------------- METADATA ----------------
echo "[INFO] Running metadata update"
if ! python "$SCRIPT_DIR/update_metadata.py" "$EXTRACTED_DIR"; then
    echo "[ERROR] Metadata update failed"
    exit 1
fi

# ---------------- SUFFIX ----------------
echo "[INFO] Resolving suffix from COS"
SUFFIX=$(python "$SCRIPT_DIR/resolve_suffix_cos.py" "$WHEEL_PATH" "$EXTRACTED_DIR" "$PACKAGE" "$VERSION") || {
    echo "[ERROR] Suffix resolution failed"
    exit 1
}

echo "[INFO] Resolved suffix → '$SUFFIX'"


# ---------------- PACK ----------------
echo "[INFO] Repacking wheel"
if ! wheel pack "$EXTRACTED_DIR" -d .; then
    echo "[ERROR] wheel pack failed"
    exit 1
fi

echo "[INFO] Wheel processing lifecycle completed successfully"