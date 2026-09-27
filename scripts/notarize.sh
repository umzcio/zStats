#!/bin/bash
# Submit an app or DMG to Apple, require acceptance, and staple its ticket.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ARTIFACT="${1:?Usage: bash scripts/notarize.sh path/to/zStats.app-or.dmg}"
CONFIG="$ROOT/scripts/.notary-config.local"
[[ -f "$CONFIG" ]] || { printf 'Missing scripts/.notary-config.local; see scripts/notary-config.example.\n' >&2; exit 1; }
source "$CONFIG"
: "${NOTARY_KEY:?Missing NOTARY_KEY}" "${NOTARY_KEY_ID:?Missing NOTARY_KEY_ID}" "${NOTARY_ISSUER:?Missing NOTARY_ISSUER}"
KEY_PATH="${NOTARY_KEY/#\~/$HOME}"
[[ -f "$KEY_PATH" ]] || { printf 'Notarization private key file not found.\n' >&2; exit 1; }
[[ -e "$ARTIFACT" ]] || { printf 'Artifact not found: %s\n' "$ARTIFACT" >&2; exit 1; }
mkdir -p "$ROOT/dist/notarization"
WORK="$(mktemp -d "$ROOT/dist/notarization/submission.XXXXXX")"
case "$ARTIFACT" in
    *.app)
        codesign --verify --deep --strict "$ARTIFACT"
        UPLOAD="$WORK/application.zip"
        ditto -c -k --sequesterRsrc --keepParent "$ARTIFACT" "$UPLOAD"
        ;;
    *.dmg)
        codesign --verify --strict "$ARTIFACT"
        UPLOAD="$ARTIFACT"
        ;;
    *) printf 'Expected a signed .app or .dmg.\n' >&2; exit 1 ;;
esac
printf 'Submitting %s to Apple…\n' "$(basename "$ARTIFACT")"
printf 'Submission result: %s/result.json\n' "$WORK"
xcrun notarytool submit "$UPLOAD" --key "$KEY_PATH" --key-id "$NOTARY_KEY_ID" \
    --issuer "$NOTARY_ISSUER" --wait --output-format json > "$WORK/result.json"
python3 - "$WORK/result.json" <<'PY'
import json, sys
with open(sys.argv[1]) as file:
    result = json.load(file)
print('Submission:', result.get('id', 'unknown'), '—', result.get('status', 'unknown'))
if result.get('status') != 'Accepted':
    sys.exit('Apple did not accept this submission. Inspect the submission log before distributing it.')
PY
xcrun stapler staple "$ARTIFACT"
xcrun stapler validate "$ARTIFACT"
printf 'Notarized and stapled: %s\n' "$ARTIFACT"
