# Minecraft Dungeons II en Linux (Proton)

Minecraft Dungeons II (Steam, app `1912410`) no arranca en Proton porque necesita
**Microsoft Gaming Services** (`xgameruntime.dll`), que solo existe en Windows.
Este repo trae un reemplazo propio de ese DLL, escrito desde cero en C
(`src/xgameruntime.c`). **No incluye código de Microsoft y no modifica ningún
archivo del juego.** Solo agrega un DLL junto al juego.

Es un fork de [Alextibtab/Dungeons2_linux_fix](https://github.com/Alextibtab/Dungeons2_linux_fix)
que corrige un crash con la versión actual del juego (1.1.1.0) y hace la
instalación universal. Los detalles están en [Cambios respecto al original](#cambios-respecto-al-original).

---

## Instalación

**Requisitos:** Steam con Proton (cualquier versión reciente: Proton 9/10,
GE, CachyOS…) y Python 3 con `venv`.

| Distro        | Si falta `venv`                    |
|---------------|------------------------------------|
| Debian/Ubuntu | `sudo apt install python3-venv`    |
| Fedora        | ya viene con `python3`             |
| Arch          | ya viene con `python`              |

1. **Abre el juego una vez** desde Steam con Proton (aunque crashee), para que
   Steam cree la carpeta de Proton del juego. Luego ciérralo por completo.
2. Clona e instala (el repo puede quedar en cualquier carpeta):
   ```sh
   git clone https://github.com/AdrianMontes0512/Dungeons2_linux_fix.git
   cd Dungeons2_linux_fix
   ./install.sh
   ```
   El script encuentra el juego en todas tus bibliotecas de Steam, incluidas
   las que están en otros discos, las rutas con espacios y Steam Flatpak o Snap.
   Si no lo encuentra, indícale la carpeta:
   ```sh
   ./install.sh --game-dir "/ruta/SteamLibrary/steamapps/common/Minecraft Dungeons II"
   ```
3. En Steam, entra a **Minecraft Dungeons II → Propiedades → General → Opciones
   de lanzamiento** y pega:
   ```
   WINEDLLOVERRIDES="xgameruntime=n" %command%
   ```
4. Abre el juego. La primera vez aparece una ventana con un **código** y se abre
   <https://www.microsoft.com/link>. Escribe el código e inicia sesión con **tu**
   cuenta de Microsoft/Xbox. No cambies la URL.

Después de esto, el juego arranca normal. La sesión se renueva sola y, si
caduca, vuelve a pedirte el código.

### Si Steam actualiza el juego

Una actualización puede borrar o reemplazar el DLL. Vuelve a correr `./install.sh`.
Pasa lo mismo si cambias de versión de Proton.

### Desinstalar

```sh
./uninstall.sh            # quita el DLL del juego
./uninstall.sh --purge    # además borra ~/.local/share/dungeons2-compat (tokens incluidos)
```
Luego quita la opción de lanzamiento en Steam.

---

## Qué hace exactamente cada archivo

La idea es que puedas revisar todo antes de instalarlo. Son 4 archivos que
importan:

### `install.sh`: qué toca en tu sistema

No usa `sudo` y solo hace esto:

1. Crea `~/.local/share/dungeons2-compat/` y copia ahí `xauth.py`. La carpeta
   está fija porque el DLL busca ahí el script de login.
2. Crea un entorno virtual de Python (`.venv`) en esa carpeta e instala **un**
   paquete desde PyPI: [`cryptography`](https://pypi.org/project/cryptography/).
   No toca el Python del sistema.
3. Busca el juego leyendo `libraryfolders.vdf` de Steam.
4. Copia `src/xgameruntime.dll` a 3 lugares:
   - `…/Minecraft Dungeons II/` (junto a `Dungeons.exe`)
   - `…/Minecraft Dungeons II/Dungeons/Binaries/Win64/` (junto a `Dungeons-Win64-Shipping.exe`)
   - `…/compatdata/1912410/pfx/drive_c/windows/system32/` (la carpeta de Proton del juego)

Si el juego está abierto, el instalador se niega a continuar.

### `src/xgameruntime.dll` / `src/xgameruntime.c`: el reemplazo de Gaming Services

El juego llama a funciones de Gaming Services para iniciar sesión, conectarse y
guardar datos. El DLL responde a esas llamadas:

- **Colas de tareas y operaciones asíncronas** (`XTaskQueue`, `XAsync`): la
  infraestructura que usa el juego para todo lo demás.
- **Usuario de Xbox** (`XUser*`): le dice al juego que hay un usuario conectado
  con **tu XUID y gamertag reales**, sacados de los tokens de tu sesión. Los
  logros y privilegios siempre responden "permitido".
- **Tokens:** cuando el juego pide un token para un servidor, el DLL le da el
  que corresponde, y solo en ese momento:
  - `api.minecraftservices.com` → token de Minecraft
  - `playfabapi.com` → token de PlayFab
  - todo lo demás (`*.xboxlive.com`) → token general de Xbox
- **Datos del juego:** ID del título, sandbox `RETAIL` y almacenamiento local en
  `C:\users\steamuser\AppData\Local\Dungeons2\PLS`, dentro de la carpeta de Proton.
- **Conexiones HTTPS del juego (XCurl):** intercepta 7 funciones de WinHTTP que
  usa `XCurl.dll` para:
  - ignorar una opción (`IPV6_FAST_FALLBACK`) que Wine no soporta y que haría
    que XCurl nunca se conecte;
  - forzar TLS 1.2/1.3 si el juego pide un protocolo más viejo;
  - anotar en el log a qué servidor se conecta, qué cabeceras lleva cada
    petición (solo si existen, sin sus valores) y el código HTTP de respuesta;
  - si el servidor responde con un error (código 400 o mayor), anotar en el log
    los primeros ~180 caracteres de ese error, salvo que parezcan un token.

  **No cambia el contenido de las conexiones.** Wine sigue validando el
  certificado TLS normalmente. Lo único que se omite es la verificación extra
  de Gaming Services, que siempre responde "OK".
- **Login:** si no hay tokens válidos, ejecuta en Linux
  `~/.local/share/dungeons2-compat/.venv/bin/python3 xauth.py` (a través de
  `start.exe /unix`) y muestra el código de inicio de sesión en una ventana.

**Qué escribe en disco:**

| Archivo | Contenido |
|---------|-----------|
| `<carpeta de Proton del juego>/drive_c/xgr.log` | Log de diagnóstico: llamadas, servidores, códigos HTTP, tu XUID y el código de login de un solo uso. **No contiene tokens.** |
| `…/AppData/Local/Dungeons2/PLS/` | Datos locales que el juego guarda. |
| `drive_c/xgr-sensitive.log`, `xgr-body-*.bin`, `xgr-response-*.bin` | **Solo** si defines `XGR_TRACE_SENSITIVE=1` (para depurar). Contienen tokens y cuerpos HTTP. **Nunca lo actives si vas a compartir logs.** |

### `xauth.py`: el login con Microsoft

Solo usa la biblioteca estándar de Python más `cryptography`. Se conecta
**únicamente** a servidores de Microsoft:

| Servidor | Para qué |
|----------|----------|
| `login.live.com` | Login por código (*device code*) con el ID de app de este juego, y renovación del token. |
| `user.auth.xboxlive.com` | Convierte el login de Microsoft en un token de usuario de Xbox. |
| `device.auth.xboxlive.com` | Crea un token de "dispositivo" firmado con una clave nueva al azar. PlayFab lo exige. |
| `xsts.auth.xboxlive.com` | Pide los 3 tokens finales: Xbox, Minecraft y PlayFab. |

- Guarda todo en `~/.local/share/dungeons2-compat/tokens.txt` con permisos `0600`
  (solo tu usuario puede leerlo): los tokens, tu XUID, tu gamertag y el
  *refresh token* de Microsoft. **Nunca compartas ese archivo**, porque da
  acceso a tu cuenta de Xbox.
- Nunca imprime los tokens.
- Para mostrar el código usa `xdg-open` (abre el navegador) y, si está
  instalado, `zenity` (la ventanita).
- **No manda nada a terceros.** Puedes comprobarlo con
  `grep -n "https://" xauth.py`.

### `build.sh`: compilar tú mismo

`src/xgameruntime.dll` ya viene compilado para que solo tengas que instalar. Si
prefieres no confiar en un binario, compílalo desde el código fuente antes de
instalar:

```sh
./build.sh      # usa MinGW-w64 si lo tienes; si no, zig
./install.sh
```

Compiladores posibles: `sudo pacman -S mingw-w64-gcc` (Arch),
`sudo apt install gcc-mingw-w64-x86-64` (Debian/Ubuntu),
`sudo dnf install mingw64-gcc` (Fedora), o
[zig](https://ziglang.org/download/) sin instalar nada como root.

---

## Problemas comunes

| Síntoma | Qué hacer |
|---------|-----------|
| Crash de Unreal ("Spicewood Crash Reporter") ~1 min después de abrir | Probablemente tienes el DLL original de upstream. Instala el de este fork. |
| No aparece el código de login | Revisa `~/.local/share/dungeons2-compat/login-code.txt` y `login-error.txt`. |
| `install.sh` dice que no encuentra la carpeta de Proton | Abre el juego una vez, ciérralo y vuelve a instalar. |
| Dejó de funcionar tras una actualización | `./install.sh` otra vez. |
| Quieres ver qué pasó | `drive_c/xgr.log` dentro de `steamapps/compatdata/1912410/pfx/`. |

---

## Cambios respecto al original

- **Crash con XCurl corregido.** El original enganchaba WinHTTP escribiendo en
  posiciones fijas de memoria (`0x19400`–`0x19470`) de `XCurl.dll`. En la versión
  actual del juego esas posiciones caen en medio del código, lo corrompen y el
  juego crashea con `EXCEPTION_ACCESS_VIOLATION` en XCurl al primer intento de
  conexión. Ahora el DLL recorre la tabla de importaciones de XCurl y busca
  cada función por **nombre**, así que funciona con cualquier versión de
  XCurl. Si no encuentra una función, no la engancha, en vez de corromper memoria.
- **`install.sh` universal:** funciona desde cualquier carpeta donde clones el
  repo, detecta Steam nativo, Flatpak y Snap, soporta bibliotecas con espacios
  en la ruta (el original fallaba ahí), acepta `--game-dir`, no se rompe si
  todavía no existe la carpeta de Proton y se niega a instalar con el juego abierto.
- Nuevos `uninstall.sh` y `build.sh`.
