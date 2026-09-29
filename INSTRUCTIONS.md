# Minecraft Dungeons II on Linux (Proton)

*[Versión en español](INSTRUCCIONES.md)*

Minecraft Dungeons II (Steam, app `1912410`) does not start under Proton because
it needs **Microsoft Gaming Services** (`xgameruntime.dll`), which only exists on
Windows. This repo ships its own replacement for that DLL, written from scratch
in C (`src/xgameruntime.c`). **It contains no Microsoft code and does not modify
any game file.** It only adds a DLL next to the game.

This is a fork of [Alextibtab/Dungeons2_linux_fix](https://github.com/Alextibtab/Dungeons2_linux_fix)
(itself a fork of [Kubas556/Dungeons2_linux_fix](https://github.com/Kubas556/Dungeons2_linux_fix)).
It fixes a crash with the current game build (1.1.1.0) and makes installation
work on any setup. Details are in [Changes from the original](#changes-from-the-original).

---

## Install

**Requirements:** Steam with Proton (any recent version: Proton 9/10, GE,
CachyOS…) and Python 3 with `venv`.

| Distro        | If `venv` is missing               |
|---------------|------------------------------------|
| Debian/Ubuntu | `sudo apt install python3-venv`    |
| Fedora        | included with `python3`            |
| Arch          | included with `python`             |

1. **Launch the game once** from Steam with Proton (even if it crashes), so Steam
   creates the game's Proton prefix. Then quit it completely.
2. Clone and install (the repo can live in any folder):
   ```sh
   git clone https://github.com/AdrianMontes0512/Dungeons2_linux_fix.git
   cd Dungeons2_linux_fix
   ./install.sh
   ```
   The script finds the game in all your Steam libraries, including ones on
   other drives, paths with spaces, and Flatpak or Snap Steam. If it cannot
   find it, pass the folder yourself:
   ```sh
   ./install.sh --game-dir "/path/SteamLibrary/steamapps/common/Minecraft Dungeons II"
   ```
3. In Steam, go to **Minecraft Dungeons II → Properties → General → Launch
   options** and paste:
   ```
   WINEDLLOVERRIDES="xgameruntime=n" %command%
   ```
4. Launch the game. The first time, a window shows a **code** and
   <https://www.microsoft.com/link> opens. Enter the code and sign in with
   **your** Microsoft/Xbox account. Do not change the URL.

After that the game starts normally. The session refreshes on its own and, if
it expires, asks you for a code again.

### If Steam updates the game

An update can remove or replace the DLL. Run `./install.sh` again. The same
applies if you switch Proton versions.

### Uninstall

```sh
./uninstall.sh            # remove the DLL from the game
./uninstall.sh --purge    # also delete ~/.local/share/dungeons2-compat (tokens included)
```
Then remove the launch option in Steam.

---

## What each file does, exactly

The point is that you can review everything before installing it. Four files
matter:

### `install.sh`: what it touches on your system

It does not use `sudo` and only does this:

1. Creates `~/.local/share/dungeons2-compat/` and copies `xauth.py` there. The
   folder is fixed because the DLL looks for the sign-in script there.
2. Creates a Python virtual environment (`.venv`) in that folder and installs
   **one** package from PyPI: [`cryptography`](https://pypi.org/project/cryptography/).
   It does not touch system Python.
3. Finds the game by reading Steam's `libraryfolders.vdf`.
4. Copies `src/xgameruntime.dll` to 3 places:
   - `…/Minecraft Dungeons II/` (next to `Dungeons.exe`)
   - `…/Minecraft Dungeons II/Dungeons/Binaries/Win64/` (next to `Dungeons-Win64-Shipping.exe`)
   - `…/compatdata/1912410/pfx/drive_c/windows/system32/` (the game's Proton prefix)

If the game is running, the installer refuses to continue.

### `src/xgameruntime.dll` / `src/xgameruntime.c`: the Gaming Services replacement

The game calls Gaming Services functions to sign in, connect and store data.
The DLL answers those calls:

- **Task queues and async operations** (`XTaskQueue`, `XAsync`): the plumbing
  the game uses for everything else.
- **Xbox user** (`XUser*`): tells the game a user is signed in with **your real
  XUID and gamertag**, read from your session tokens. Achievement and privilege
  checks always answer "allowed".
- **Tokens:** when the game asks for a token for a server, the DLL hands over
  the matching one, and only at that moment:
  - `api.minecraftservices.com` → Minecraft token
  - `playfabapi.com` → PlayFab token
  - everything else (`*.xboxlive.com`) → general Xbox token
- **Game data:** title ID, `RETAIL` sandbox, and local storage in
  `C:\users\steamuser\AppData\Local\Dungeons2\PLS` inside the Proton prefix.
- **The game's HTTPS connections (XCurl):** hooks 7 WinHTTP functions used by
  `XCurl.dll` to:
  - ignore an option (`IPV6_FAST_FALLBACK`) that Wine does not support and that
    would stop XCurl from ever connecting;
  - force TLS 1.2/1.3 if the game asks for an older protocol;
  - log which server it connects to, which headers each request carries (only
    whether they exist, not their values) and the HTTP status code;
  - if the server answers with an error (status 400 or higher), log the first
    ~180 characters of that error, unless it looks like a token.

  **It does not change the content of connections.** Wine still validates the
  TLS certificate normally. The only thing skipped is Gaming Services' extra
  verification step, which always answers "OK".
- **Sign-in:** if there are no valid tokens, it runs
  `~/.local/share/dungeons2-compat/.venv/bin/python3 xauth.py` on the Linux side
  (through `start.exe /unix`) and shows the sign-in code in a window.

**What it writes to disk:**

| File | Contents |
|------|----------|
| `<game's Proton prefix>/drive_c/xgr.log` | Diagnostic log: calls, servers, HTTP status codes, your XUID and the one-time sign-in code. **No tokens.** |
| `…/AppData/Local/Dungeons2/PLS/` | Local data the game saves. |
| `drive_c/xgr-sensitive.log`, `xgr-body-*.bin`, `xgr-response-*.bin` | **Only** if you set `XGR_TRACE_SENSITIVE=1` (for debugging). They contain tokens and HTTP bodies. **Never enable it if you are going to share logs.** |

### `xauth.py`: Microsoft sign-in

It only uses the Python standard library plus `cryptography`. It connects
**only** to Microsoft servers:

| Server | Purpose |
|--------|---------|
| `login.live.com` | Device-code sign-in with this game's app ID, and token refresh. |
| `user.auth.xboxlive.com` | Turns the Microsoft sign-in into an Xbox user token. |
| `device.auth.xboxlive.com` | Creates a "device" token signed with a fresh random key. PlayFab requires it. |
| `xsts.auth.xboxlive.com` | Requests the 3 final tokens: Xbox, Minecraft and PlayFab. |

- Stores everything in `~/.local/share/dungeons2-compat/tokens.txt` with mode
  `0600` (only your user can read it): the tokens, your XUID, your gamertag and
  the Microsoft *refresh token*. **Never share that file**, because it gives
  access to your Xbox account.
- Never prints the tokens.
- To show the code it uses `xdg-open` (opens the browser) and, if installed,
  `zenity` (the small window).
- **It sends nothing to third parties.** You can check with
  `grep -n "https://" xauth.py`.

### `build.sh`: build it yourself

`src/xgameruntime.dll` comes prebuilt so you only have to install. If you would
rather not trust a binary, build it from source before installing:

```sh
./build.sh      # uses MinGW-w64 if you have it, otherwise zig
./install.sh
```

Possible compilers: `sudo pacman -S mingw-w64-gcc` (Arch),
`sudo apt install gcc-mingw-w64-x86-64` (Debian/Ubuntu),
`sudo dnf install mingw64-gcc` (Fedora), or
[zig](https://ziglang.org/download/) without installing anything as root.

---

## Troubleshooting

| Symptom | What to do |
|---------|------------|
| Unreal crash ("Spicewood Crash Reporter") ~1 min after launch | You probably have the original upstream DLL. Install this fork's. |
| The sign-in code never shows up | Check `~/.local/share/dungeons2-compat/login-code.txt` and `login-error.txt`. |
| `install.sh` says the Proton prefix is missing | Launch the game once, quit it and install again. |
| It stopped working after an update | Run `./install.sh` again. |
| You want to see what happened | `drive_c/xgr.log` inside `steamapps/compatdata/1912410/pfx/`. |

---

## Changes from the original

- **XCurl crash fixed.** The original hooked WinHTTP by writing to fixed memory
  offsets (`0x19400`–`0x19470`) in `XCurl.dll`. In the current game build those
  offsets land in the middle of code, corrupt it, and the game crashes with
  `EXCEPTION_ACCESS_VIOLATION` in XCurl on its first connection attempt. The
  DLL now walks XCurl's import table and finds each function by **name**, so
  it works with any XCurl version. If it cannot find a function, it skips that
  hook instead of corrupting memory.
- **Universal `install.sh`:** works from any clone location, detects native,
  Flatpak and Snap Steam, supports libraries with spaces in the path (the
  original broke there), accepts `--game-dir`, does not fail when the Proton
  prefix does not exist yet, and refuses to install while the game is running.
- New `uninstall.sh` and `build.sh`.
