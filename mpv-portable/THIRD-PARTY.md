# Сторонние компоненты и исходники

mpv Neon — сборка нескольких проектов, а не новый автор всего плеера. Все исходные copyright notices и отдельные лицензии сохраняются. Новая единая лицензия на весь набор не назначается. Собственные изменения и оригинальные сторонние компоненты необходимо различать; публичный доступ сам по себе не отменяет условия их лицензий.

Точные версии/ревизии и первичные ссылки: `mpv-portable/docs/SOURCES.json`. Прилагаемые тексты: `mpv-portable/docs/licenses/`, Python LICENSE.txt в готовой сборке.

- mpv: https://github.com/mpv-player/mpv/tree/6a262d11f6 ; бинарная сборка https://github.com/shinchiro/mpv-winbuild-cmake/releases/tag/20261019 ; GPL и условия конкретных компонентов сборки.
- uosc 5.13.0: https://github.com/tomasklaen/uosc/tree/5.13.0 ; LGPL, локально изменены темы/меню/громкость. Исходники изменений включены.
- thumbfast, memo, quality-menu, mpv-sub-select, mpv_sponsorblock: отдельные лицензии и commit hashes в manifest.
- FSRCNNX, KrigBilateral, SSimSuperRes, Anime4K, mpv-prescalers: исходники шейдеров и тексты лицензий сохранены.
- yt-dlp: https://github.com/yt-dlp/yt-dlp/releases/tag/2026.08.19 ; Deno: https://github.com/denoland/deno/releases/tag/v2.9.7 ; Python: https://www.python.org/downloads/release/python-31316/ . Их исходники, зависимости и условия распространения принадлежат соответствующим проектам.
- TorrServer MatriX.147: https://github.com/YouROK/TorrServer/tree/MatriX.147 ; GPL-3.0, исходный проект и LICENSE прилагаются ссылкой/текстом.
- ABI reference для необязательного LSFG-модуля: https://github.com/Jossec101/openls/tree/a382695fe853500479d8eba393653744b36f6ac2 ; reference MIT-текст приложен. Это не официальный стабильный SDK.

**Lossless.dll не распространяется.** Наличие купленного пользователем Lossless Scaling в личной установке не превращает эту DLL в часть публичного пакета. Она не включена в установщик, portable-папку и Git.
