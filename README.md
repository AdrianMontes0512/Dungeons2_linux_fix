# Minecraft Dungeons II on Linux

A local stand-in for Microsoft Gaming Services so Minecraft Dungeons II (Steam app `1912410`) can start under Proton. The game looks for `xgameruntime.dll`. This repository builds that DLL. It does not modify the game and it does not include Microsoft's library.

On first launch it signs you in with your own Microsoft account through the normal device-code page at <https://www.microsoft.com/link>, then caches the Xbox tokens next to the helper. Later launches reuse that cache until it expires.

> **Fork note.** This fork fixes a crash with the current game build (1.1.1.0): the
> original hooked `XCurl.dll` at hardcoded IAT offsets that now land inside code.
> The hook now resolves WinHTTP imports by name. It also makes the installer work
> from any clone location. Full guide in Spanish, including exactly what every file
> does: [INSTRUCCIONES.md](INSTRUCCIONES.md).

## Install

Proton and Python 3 (with `venv`) are required. Launch the game once so Steam
creates its Proton prefix, quit it, then:

```sh
git clone https://github.com/AdrianMontes0512/Dungeons2_linux_fix.git
cd Dungeons2_linux_fix
./install.sh                       # or: ./install.sh --game-dir "/path/to/Minecraft Dungeons II"
```

`install.sh` copies `xauth.py` to `~/.local/share/dungeons2-compat` (the DLL looks
there), creates a venv there with the [`cryptography`](https://pypi.org/project/cryptography/)
package, finds the game in any Steam library (native, Flatpak or Snap; paths with
spaces are fine) and copies `src/xgameruntime.dll`:

- next to `Dungeons.exe`
- next to `Dungeons-Win64-Shipping.exe`
- into the Proton prefix `drive_c/windows/system32`

In Steam, open the game's properties and set the launch option:

```text
WINEDLLOVERRIDES="xgameruntime=n" %command%
```

Quit the game completely before installing. A running process keeps the old DLL.
`./uninstall.sh [--purge]` removes it again.

## First sign-in

Start the game from Steam. A window shows a code and opens <https://www.microsoft.com/link>. Enter the code, then sign in with the Microsoft account that should own the Xbox profile. Leave that page as `https://www.microsoft.com/link` with no extra query string.

The token file is `~/.local/share/dungeons2-compat/tokens.txt` (mode `0600`). Do not share it. When it expires, the next launch refreshes it or asks you to sign in again.

The cache holds three Xbox tokens, one per relying party: `http://xboxlive.com` for the general Xbox services, `rp://api.minecraftservices.com/` for Minecraft, and `http://playfab.xboxlive.com/` for PlayFab. The PlayFab token is minted with a proof-of-possession device token, which PlayFab requires; without it the account-link step fails.

## Rebuild

The DLL already in `src/` is ready to install. To build it yourself, run `./build.sh`
(MinGW-w64 if installed, otherwise `zig cc`), then `./install.sh`.

## What the game gets

The DLL answers the Gaming Services calls this title makes: task queues, a signed-in Xbox user (your real XUID and gamertag from the cache), title id, retail sandbox, persistent local storage, and the HTTPS security settings XCurl asks for before it connects. PlayFab login still uses the Steam session. The Microsoft token is returned only when the game asks for one, and the DLL picks the token that matches the requested service: the Minecraft token for `api.minecraftservices.com`, the PlayFab token for `playfabapi.com`, and the general Xbox token for everything else such as `*.xboxlive.com`.
