# Сборка установщика v12

Локальное обновление исходников GitHub v11.4. build.ps1 компилирует как launcher, так и изменённый PlaylistWindow.cs. Новый релиз в GitHub не публикуется этим скриптом.

Требуются Windows x64, .NET Framework C# compiler и Inno Setup с x64compatible. Исходники: Launcher.cs, Setup.iss, Associations.iss, StopBundledTorrServer.ps1. Launcher.cs заменяет старый C launcher; native/lsfg-native.c остаётся отдельным необязательным модулем.

Из корня репозитория:

```powershell
.\prepare-public.ps1 -InputPlayerRoot 'D:/full-player-v12' -OutputPlayerRoot 'D:/build/mpv-v12-public'
.\installer-source\build.ps1 -PlayerRoot 'D:/build/mpv-v12-public' -OutputRoot 'D:/build/release' -Compiler 'C:/Program Files (x86)/Inno Setup 6/ISCC.exe'
```

Подготовка создаёт новую папку, исключает Lossless.dll и личные данные, восстанавливает лицензии, сбрасывает TorrServer на loopback, пересчитывает defaults.sha256. Сборка проверяет публичный payload, компилирует launcher из исходников и затем установщик. Крупные зависимости не входят в Git: сверяйте docs/SOURCES.json. ZIP embedded Python — часть runtime, не пользовательский архив.

Входная полная папка должна уже содержать обновлённые Lua-скрипты и defaults v12.
Одна смена номера в манифесте не обновляет код старого плеера. При публикации
использован готовый публичный установщик автора, повторно проверенный в изолированном
Portable-режиме; новый установщик ради изменения документации не пересобирался.

Для отдельной тестовой идентичности используйте -TestBuild. Настоящий выпуск сохраняет AppId mpvNeon.Personal для обновления v6. Установка для всех пользователей запрашивает UAC. Ветка runas и реальные GPU требуют ручной проверки; локальные тесты не подтверждают их автоматически.

VALIDATION.txt содержит результаты прежних личных проверок. Проверки именно публичной сборки записаны в корневом PUBLIC-VALIDATION.md.
