#!/bin/sh
# Copy xgameruntime.dll next to both game executables and into the Proton prefix.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
DLL="$ROOT/src/xgameruntime.dll"
APPID=1912410
if [ ! -f "$DLL" ]; then
    echo "Missing $DLL. Build it first; see README.md." >&2
    exit 1
fi

# xauth.py runs under a self-contained virtual environment so the device-token
# step gets the third-party cryptography package without touching system Python.
PY=${PYTHON:-/usr/bin/python3}
[ -x "$PY" ] || PY=python3
if ! command -v "$PY" >/dev/null 2>&1; then
    echo "Python 3 is required (xauth.py runs under it)." >&2
    exit 1
fi

VENV="$ROOT/.venv"
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
Could not set up the virtual environment. Install Python's venv support, then
re-run install.sh:

  Debian/Ubuntu  sudo apt install python3-venv
  Fedora         sudo dnf install python3
  Arch           sudo pacman -S python
EOF
    exit 1
fi

STEAM_ROOT=${STEAM_ROOT:-$HOME/.local/share/Steam}
if [ ! -f "$STEAM_ROOT/steamapps/libraryfolders.vdf" ] && [ -f "$HOME/.steam/steam/steamapps/libraryfolders.vdf" ]; then
    STEAM_ROOT=$HOME/.steam/steam
fi
VDF="$STEAM_ROOT/steamapps/libraryfolders.vdf"
if [ ! -f "$VDF" ]; then
    echo "Could not find libraryfolders.vdf. Set STEAM_ROOT." >&2
    exit 1
fi

LIB=$(awk '
    /"path"/ {
        gsub(/"/, "", $2)
        path = $2
        manifest = path "/steamapps/appmanifest_'"$APPID"'.acf"
        if (system("test -f \"" manifest "\"") == 0) { print path; exit }
    }
' "$VDF")
if [ -z "$LIB" ]; then
    echo "Steam app $APPID is not in any library folder." >&2
    exit 1
fi

GAME="$LIB/steamapps/common/Minecraft Dungeons II"
PFX="$LIB/steamapps/compatdata/$APPID/pfx/drive_c/windows/system32"
SHIP="$GAME/Dungeons/Binaries/Win64"
for dir in "$GAME" "$SHIP" "$PFX"; do
    if [ ! -d "$dir" ]; then
        echo "Missing $dir" >&2
        exit 1
    fi
    cp -f "$DLL" "$dir/xgameruntime.dll"
    echo "Installed $dir/xgameruntime.dll"
done
echo
echo "In Steam, set this launch option for Minecraft Dungeons II:"
echo '  WINEDLLOVERRIDES="xgameruntime=n" %command%'
