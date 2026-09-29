#!/bin/sh
# Install the Minecraft Dungeons II Gaming Services stand-in for Proton.
#
#   ./install.sh                     find the game in your Steam libraries
#   ./install.sh --game-dir DIR      use this game folder instead
#
# What it does (nothing else):
#   1. Copies xauth.py to ~/.local/share/dungeons2-compat (the DLL looks there).
#   2. Creates a Python venv there with the "cryptography" package.
#   3. Copies src/xgameruntime.dll next to Dungeons.exe, next to
#      Dungeons-Win64-Shipping.exe and into the game's Proton prefix.
set -eu

APPID=1912410
GAME_NAME="Minecraft Dungeons II"
ROOT=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
DLL="$ROOT/src/xgameruntime.dll"
# Fixed by the DLL: it runs xauth.py from $HOME/.local/share/dungeons2-compat.
DEST="$HOME/.local/share/dungeons2-compat"
GAME_DIR=${GAME_DIR:-}

die() { echo "Error: $*" >&2; exit 1; }

while [ $# -gt 0 ]; do
    case "$1" in
        --game-dir) [ $# -ge 2 ] || die "--game-dir needs a path"; GAME_DIR=$2; shift 2 ;;
        --game-dir=*) GAME_DIR=${1#--game-dir=}; shift ;;
        -h|--help) sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) die "unknown option $1 (see --help)" ;;
    esac
done

[ -f "$DLL" ] || die "missing $DLL. Build it with ./build.sh"

if pgrep -f "Dungeons-Win64-Shipping.exe" >/dev/null 2>&1; then
    die "the game is running. Quit it completely first (a running game keeps the old DLL)."
fi

# --- 1. helper files -------------------------------------------------------
mkdir -p "$DEST"
if [ "$ROOT" != "$(CDPATH= cd -- "$DEST" && pwd)" ]; then
    cp -f "$ROOT/xauth.py" "$DEST/xauth.py"
    echo "Copied xauth.py to $DEST"
fi
chmod 755 "$DEST/xauth.py"

# --- 2. Python venv with cryptography --------------------------------------
PY=${PYTHON:-/usr/bin/python3}
[ -x "$PY" ] || PY=$(command -v python3 || true)
[ -n "$PY" ] || die "Python 3 is required (xauth.py runs under it)."

VENV="$DEST/.venv"
if [ ! -x "$VENV/bin/python3" ]; then
    echo "Creating a Python virtual environment in $VENV"
    "$PY" -m venv "$VENV" >/dev/null 2>&1 || true
fi
if [ -x "$VENV/bin/python3" ] && ! "$VENV/bin/python3" -c "import cryptography" >/dev/null 2>&1; then
    echo "Installing cryptography into $VENV"
    "$VENV/bin/python3" -m pip install --quiet --disable-pip-version-check cryptography >/dev/null 2>&1 || true
fi
if [ ! -x "$VENV/bin/python3" ] || ! "$VENV/bin/python3" -c "import cryptography" >/dev/null 2>&1; then
    cat >&2 <<'EOF'
Could not set up the Python virtual environment. Install Python's venv
support, then run ./install.sh again:

  Debian/Ubuntu  sudo apt install python3-venv
  Fedora         sudo dnf install python3
  Arch           sudo pacman -S python
EOF
    exit 1
fi

# --- 3. find the game -------------------------------------------------------
# Print every library path listed in a libraryfolders.vdf (paths may contain spaces).
vdf_paths() {
    sed -n 's/^[[:space:]]*"path"[[:space:]]*"\(.*\)"[[:space:]]*$/\1/p' "$1" | sed 's/\\\\/\\/g'
}

LIB=
if [ -n "$GAME_DIR" ]; then
    GAME_DIR=$(CDPATH= cd -- "$GAME_DIR" 2>/dev/null && pwd) || die "game folder not found"
    # .../steamapps/common/<game>  ->  library root is three levels up
    LIB=$(dirname "$(dirname "$(dirname "$GAME_DIR")")")
else
    for steam in "${STEAM_ROOT:-}" \
        "$HOME/.local/share/Steam" \
        "$HOME/.steam/steam" \
        "$HOME/.steam/root" \
        "$HOME/.var/app/com.valvesoftware.Steam/.local/share/Steam" \
        "$HOME/.var/app/com.valvesoftware.Steam/data/Steam" \
        "$HOME/snap/steam/common/.local/share/Steam"; do
        vdf="$steam/steamapps/libraryfolders.vdf"
        [ -f "$vdf" ] || continue
        LIB=$( { echo "$steam"; vdf_paths "$vdf"; } | while IFS= read -r lib; do
            if [ -f "$lib/steamapps/appmanifest_$APPID.acf" ]; then echo "$lib"; break; fi
        done )
        [ -z "$LIB" ] || break
    done
    [ -n "$LIB" ] || die "$GAME_NAME (app $APPID) is not in any Steam library.
Pass the folder yourself:  ./install.sh --game-dir \"/path/to/steamapps/common/$GAME_NAME\""
    GAME_DIR="$LIB/steamapps/common/$GAME_NAME"
fi

SHIP="$GAME_DIR/Dungeons/Binaries/Win64"
PFX="$LIB/steamapps/compatdata/$APPID/pfx/drive_c/windows/system32"
[ -f "$GAME_DIR/Dungeons.exe" ] || die "Dungeons.exe not found in $GAME_DIR"
[ -d "$SHIP" ] || die "missing $SHIP"

echo "Game folder: $GAME_DIR"
for dir in "$GAME_DIR" "$SHIP"; do
    cp -f "$DLL" "$dir/xgameruntime.dll"
    echo "Installed $dir/xgameruntime.dll"
done
if [ -d "$PFX" ]; then
    cp -f "$DLL" "$PFX/xgameruntime.dll"
    echo "Installed $PFX/xgameruntime.dll"
else
    echo "Note: no Proton prefix yet ($PFX)."
    echo "      Launch the game once, then run ./install.sh again."
fi

cat <<'EOF'

Done. In Steam: Minecraft Dungeons II > Properties > General > Launch options:

  WINEDLLOVERRIDES="xgameruntime=n" %command%

On first launch a window shows a code: enter it at https://www.microsoft.com/link
EOF
