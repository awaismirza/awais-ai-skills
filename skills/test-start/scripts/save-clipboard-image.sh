#!/usr/bin/env bash
# Save the image currently on the macOS clipboard to a PNG file.
# Usage: save-clipboard-image.sh <output-path.png>
# Exits 0 and prints the path on success; exits 1 with a message if the
# clipboard holds no image (e.g. the user only dropped it into chat, which
# does NOT put it on the clipboard — ask them to Cmd+C / re-screenshot).
set -euo pipefail
OUT="${1:?usage: save-clipboard-image.sh <output-path.png>}"
mkdir -p "$(dirname "$OUT")"

RESULT=$(osascript - "$OUT" <<'APPLESCRIPT'
on run argv
  set outPath to item 1 of argv
  try
    set f to (open for access POSIX file outPath with write permission)
    write (the clipboard as «class PNGf») to f
    close access f
    return "ok"
  on error e
    try
      close access f
    end try
    return "ERROR: " & e
  end try
end run
APPLESCRIPT
)

if [[ "$RESULT" == ok* ]] && [[ -s "$OUT" ]]; then
  echo "$OUT"
  exit 0
fi
rm -f "$OUT" 2>/dev/null || true
echo "NO_IMAGE_ON_CLIPBOARD: $RESULT" >&2
exit 1
