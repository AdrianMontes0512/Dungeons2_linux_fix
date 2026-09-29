#!/bin/sh
# Build src/xgameruntime.dll from src/xgameruntime.c.
# Uses a MinGW-w64 cross compiler if installed, otherwise zig (zig cc).
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
SRC="$ROOT/src/xgameruntime.c"
OUT="$ROOT/src/xgameruntime.dll"
FLAGS="-shared -O2 -Wall -Wextra"

if command -v x86_64-w64-mingw32-gcc-posix >/dev/null 2>&1; then
    x86_64-w64-mingw32-gcc-posix $FLAGS -o "$OUT" "$SRC"
elif command -v x86_64-w64-mingw32-gcc >/dev/null 2>&1; then
    x86_64-w64-mingw32-gcc $FLAGS -o "$OUT" "$SRC"
elif command -v zig >/dev/null 2>&1; then
    zig cc -target x86_64-windows-gnu $FLAGS -o "$OUT" "$SRC"
else
    cat >&2 <<'EOF'
No Windows cross compiler found. Install one of:

  Arch           sudo pacman -S mingw-w64-gcc
  Debian/Ubuntu  sudo apt install gcc-mingw-w64-x86-64
  Fedora         sudo dnf install mingw64-gcc
  any distro     zig (https://ziglang.org/download/), no root needed
EOF
    exit 1
fi
rm -f "$ROOT/src/xgameruntime.lib" "$ROOT/src/xgameruntime.pdb"
echo "Built $OUT"
sha256sum "$OUT"
