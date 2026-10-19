#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WINDOWS_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
MANIFEST="$WINDOWS_DIR/src/CaptureApp.Platform/Ocr/ocr-models.json"
CACHE_DIR="$WINDOWS_DIR/.ocr-models"
mkdir -p "$CACHE_DIR"

while IFS=$'\t' read -r model_id model_url model_sha model_bytes dict_url dict_sha; do
  [[ -n "$model_id" ]] || continue

  ensure_file() {
    local target="$1"
    local url="$2"
    local expected_sha="$3"
    local expected_bytes="${4:-}"
    local actual_sha actual_bytes tmp

    if [[ -f "$target" ]]; then
      actual_sha="$(shasum -a 256 "$target" | awk '{print $1}')"
      actual_bytes="$(wc -c < "$target" | tr -d ' ')"
      if [[ "$actual_sha" == "$expected_sha" && ( -z "$expected_bytes" || "$actual_bytes" == "$expected_bytes" ) ]]; then
        return
      fi
      rm -f "$target"
    fi

    tmp="$target.partial"
    rm -f "$tmp"
    echo "Downloading $(basename "$target")"
    curl --fail --location --retry 3 --output "$tmp" "$url"
    actual_sha="$(shasum -a 256 "$tmp" | awk '{print $1}')"
    actual_bytes="$(wc -c < "$tmp" | tr -d ' ')"
    if [[ "$actual_sha" != "$expected_sha" ]]; then
      rm -f "$tmp"
      echo "SHA-256 mismatch for $(basename "$target"): $actual_sha" >&2
      return 1
    fi
    if [[ -n "$expected_bytes" && "$actual_bytes" != "$expected_bytes" ]]; then
      rm -f "$tmp"
      echo "Byte count mismatch for $(basename "$target"): $actual_bytes (expected $expected_bytes)" >&2
      return 1
    fi
    mv "$tmp" "$target"
  }

  ensure_file "$CACHE_DIR/$model_id.onnx" "$model_url" "$model_sha" "$model_bytes"
  ensure_file "$CACHE_DIR/$model_id.dict.txt" "$dict_url" "$dict_sha"
done < <(python3 - "$MANIFEST" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as manifest_file:
    models = json.load(manifest_file)
for model in models:
    print("\t".join(str(model[key]) for key in ("id", "url", "sha256", "bytes", "dictUrl", "dictSha256")))
PY
)

echo "All OCR model assets are present and verified in $CACHE_DIR"
