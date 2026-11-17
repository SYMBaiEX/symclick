#!/bin/bash
# Verify the exact archive intended for submission; no credentials are used.
set -euo pipefail
if [ "$#" -ne 1 ]; then
  echo "Usage: $0 path/to/SymClick-vVERSION-macOS-universal.zip" >&2
  exit 2
fi
archive=$1
sidecar="${archive}.sha256"
root=$(cd "$(dirname "$0")/.." && pwd)
archive_dir=$(cd "$(dirname "$archive")" && pwd)
archive_name=$(basename "$archive")
archive="$archive_dir/$archive_name"
sidecar="$archive.sha256"
fail() { echo "Release verification failed: $*" >&2; exit 1; }
[ -f "$archive" ] && [ -f "$sidecar" ] || fail "archive or checksum sidecar missing"
# Require exactly one checksum for this archive, avoiding sidecar path traversal
# and accidental verification of a different file.
expected=$(awk -v name="$archive_name" 'NR == 1 && $1 ~ /^[[:xdigit:]]+$/ && length($1) == 64 && ($2 == name || $2 == "*" name) { print tolower($1) } END { if (NR != 1) exit 1 }' "$sidecar") || fail "invalid checksum sidecar"
[ -n "$expected" ] || fail "checksum sidecar does not name the archive"
actual=$(shasum -a 256 "$archive" | awk '{print $1}')
[ "$actual" = "$expected" ] || fail "checksum mismatch"
unzip -tq "$archive" >/dev/null || fail "archive integrity check failed"
tmp=$(mktemp -d "${TMPDIR:-/tmp}/symclick-release.XXXXXX")
trap 'rm -rf "$tmp"' EXIT
ditto -x -k "$archive" "$tmp"
app="$tmp/SymClick.app"
plist="$app/Contents/Info.plist"
binary="$app/Contents/MacOS/SymClick"
[ -f "$plist" ] && [ -f "$binary" ] || fail "archive does not contain SymClick.app"
for key in CFBundleShortVersionString CFBundleVersion CFBundleIdentifier; do
  source_value=$(/usr/libexec/PlistBuddy -c "Print :$key" "$root/Info.plist")
  archive_value=$(/usr/libexec/PlistBuddy -c "Print :$key" "$plist")
  [ -n "$source_value" ] && [ "$source_value" = "$archive_value" ] || fail "$key differs from Info.plist"
  printf '%s: %s\n' "$key" "$archive_value"
done
archs=$(lipo -archs "$binary") || fail "cannot read binary architectures"
for arch in arm64 x86_64; do
  case " $archs " in
    *" $arch "*) ;;
    *) fail "missing $arch architecture" ;;
  esac
done
codesign --verify --deep --strict "$app" || fail "signature verification failed"
printf 'Architectures: arm64 x86_64\nSignature: valid\nArchive integrity: valid\nSHA-256: %s  %s\n' "$actual" "$archive_name"
printf 'Notarization: not checked\n'
