#!/bin/sh
# Remove the stand-in DLL from the game and, with --purge, the helper folder
# ~/.local/share/dungeons2-compat (venv and cached Xbox tokens included).
#
#   ./uninstall.sh [--game-dir DIR] [--purge]
set -eu

APPID=1912410
GAME_NAME="Minecraft Dungeons II"
DEST="$HOME/.local/share/dungeons2-compat"
GAME_DIR=${GAME_DIR:-}
PURGE=0

die() { echo "Error: $*" >&2; exit 1; }

while [ $# -gt 0 ]; do
    case "$1" in
        --game-dir) [ $# -ge 2 ] || die "--game-dir needs a path"; GAME_DIR=$2; shift 2 ;;
        --game-dir=*) GAME_DIR=${1#--game-dir=}; shift ;;
        --purge) PURGE=1; shift ;;
        -h|--help) sed -n '2,5p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) die "unknown option $1 (see --help)" ;;
    esac
done

if pgrep -f "Dungeons-Win64-Shipping.exe" >/dev/null 2>&1; then
    die "the game is running. Quit it first."
fi

vdf_paths() {
    sed -n 's/^[[:space:]]*"path"[[:space:]]*"\(.*\)"[[:space:]]*$/\1/p' "$1" | sed 's/\\\\/\\/g'
}

LIB=
if [ -n "$GAME_DIR" ]; then
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
    [ -n "$LIB" ] && GAME_DIR="$LIB/steamapps/common/$GAME_NAME"
fi

if [ -n "$GAME_DIR" ]; then
    for f in "$GAME_DIR/xgameruntime.dll" \
             "$GAME_DIR/Dungeons/Binaries/Win64/xgameruntime.dll" \
             "$LIB/steamapps/compatdata/$APPID/pfx/drive_c/windows/system32/xgameruntime.dll"; do
        if [ -f "$f" ]; then rm -f "$f"; echo "Removed $f"; fi
    done
else
    echo "Game not found; pass --game-dir to remove the DLLs."
fi

if [ "$PURGE" = 1 ] && [ -d "$DEST" ]; then
    rm -rf "$DEST"
    echo "Removed $DEST (venv and cached tokens)"
fi

echo
echo "Also remove the launch option WINEDLLOVERRIDES=\"xgameruntime=n\" in Steam."
echo "If the game will not start without it, use Steam's \"Verify integrity of game files\"."
