# Сборка native-модуля и launcher

Текущий launcher v11.4 — installer-source/Launcher.cs в корне репозитория. Он компилируется installer-source/build.ps1 системным csc.exe (.NET Framework 4) и поддерживает пользовательские профили и обновление defaults. Прежний C launcher ниже оставлен как исторический исходник; для текущего выпуска его не собирать.

**Lossless.dll не включается в публичный пакет.** Она не является зависимостью обычного воспроизведения; LSFG без неё сообщает об отсутствии библиотеки.

# Исторический launcher и сборка lsfg-native.dll

The plugin also sets the mpv window icon from `assets/player-neon-07.ico` without loading the LS engine. The separate GUI launcher is built from this directory with:

```text
zig cc -O2 -municode -Wl,--subsystem,windows player-launcher.c player-launcher.rc -o ../Player.exe -luser32
```

In PowerShell, quote `'-Wl,--subsystem,windows'` as one argument. The launcher embeds the selected icon and starts the original mpv.exe, preserving argument text and caller working directory.

Compiler used: Zig 0.15.2 x86_64 Windows; SHA-256 of the official ZIP:
`3a0ed1e8799a2f8ce2a6e6290a9ff22e6906f8227865911fb7ddedc3cc14cb0c`.

The included `include/mpv/client.h` is from mpv commit `6a262d11f6`. Run from this directory:

```text
zig cc -shared -O2 -fms-extensions -Iinclude lsfg-native.c -o lsfg-native.dll -lole32 -luser32
```

Only copy the resulting `.dll` to `portable_config/scripts`. Keep the compiler's `.lib` and `.pdb` outside that folder, otherwise mpv will attempt to load them as scripts.

The plugin loads `runtime/lsfg/Lossless.dll` on demand. This is a local copy from the user's purchased Lossless Scaling 3.2.2 installation. It is not part of the plugin's source code. The Steam installation is not patched or replaced.

The private native ABI was cross-checked against the declarations in [Jossec101/openls](https://github.com/Jossec101/openls). Reference license is included in `docs/licenses/openls-reference.txt`. It is not an official supported SDK and can change between Lossless Scaling versions.

The plugin initializes OLE and pumps Windows messages on its own mpv client thread. Native callbacks only update atomic status fields. Requests are received as `script-message lsfg-native-set 0|60|120`. GPU and capture settings are applied without calling driver or Windows settings mutation exports. The original Lossless Scaling UI need not run, and a second active instance may prevent initialization.

This is in-process DLL control, but the original core still performs window capture and presentation. It does not insert generated decoded frames into mpv's own video filter graph. Its status `active` confirms active capture, not a measurement of stable generated FPS. FPS should be checked using the core's on-screen counter and a real film.
