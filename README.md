<p align="center"><img src="docs/header.png" alt="Vigilia"></p>

<p align="center"><b>English</b> · <a href="README.ru.md">Русский</a></p>

A small Windows app that keeps your computer awake. The main button is an eye: closed means normal sleep, open means the computer stays awake. The interface is in English and Russian.

![Vigilia: timer, Mode with download, Schedule, System with the update button](docs/screenshot.png)

## Features

- **On/off** by clicking the eye, pressing Space, or a global hotkey (**Ctrl+Alt+V** by default, can be changed; works even when the window is hidden). Uses the Windows Power Request API with the reason "Vigilia: режим «не спать» включён" ("stay-awake mode is on", shown by `powercfg /requests`, which needs admin rights). If the process exits, Windows drops the request by itself.
- **Settings are tucked away** behind the Settings button at the bottom of the window: pressing it grows a panel with Mode, Schedule, General and System tabs.
- **Display:** "May turn off" (only the system stays awake) or "Stays on" (system and display).
- **Until:**
  - **always** — until you turn it off;
  - **timer** — 30 minutes, 1, 2 or 4 hours, with a progress ring around the button;
  - **process** — while at least one of the selected programs is running (up to 10: a game, a render, an install). Programs are picked from a searchable list of running ones and matched by exe path, so same-named programs from different folders don't get mixed up;
  - **download** — until the speed stays below a threshold (50 KB/s – 1 MB/s) for 2 minutes straight. Counts all physical adapters or a single selected one (for example, a VPN).
- **Schedule:** weekdays and a "from — to" range in 30-minute steps, overnight ranges included. If you turn the mode off by hand during a range, the current range is skipped and the next one starts as usual. While the mode is off, the time of the next range is shown under the eye.
- **Windows notifications** when the mode turned off by itself (timer, process, download, end of schedule) or was toggled by the hotkey while the window was hidden.
- **Tray:** × and Esc hide the window, the mode keeps working. The tray icon matches the interface color. Left click on the icon shows or hides the window, right click opens a menu: Turn on/Turn off · Show window · Quit.
- **General:** interface color (6 options, dark layers are tinted to match the accent), language EN/RU (system language by default), sounds.
- **System:** global hotkey (click the keys to record a new combination), start with Windows, updates.
- **Updates:** checks GitHub Releases at startup and every 12 hours (can be turned off). To update, hold the button: Vigilia downloads the installer, verifies its size and SHA-256, closes, and the installer puts the new version in place and starts it. A portable copy opens the release page instead.
- Remembers settings. The "always" mode is restored after a restart. If the app is moved or reinstalled, the autostart path updates itself.
- Only one copy runs: launching it again shows the window that is already open.
- Respects the Windows "Animation effects" setting: when it is off, only color changes, fades and the flash remain.
- **Keyboard control:**
  - Tab — one stop per switch;
  - ←/→ and Home/End change the value inside a switch;
  - Space and Enter press;
  - the update button can be held with Space or Enter;
  - Esc closes, in order, the process or adapter list, then the panel, then hides the window.

Design: Catppuccin Mocha tinted by the accent, a monospace font, a "triple response" on click, a "caterpillar" switch, OutBack springs. Sounds are synthesized inside the app.

## Install

Download `Vigilia-<version>-setup.exe` from the [Releases](https://github.com/alexskvo10/vigilia/releases) page. The installer:
- installs the app for the current user, no admin rights needed;
- adds a Start menu shortcut;
- optionally enables start with Windows;
- removes autostart on uninstall.

The files are not signed, so on first launch Windows SmartScreen may show a warning: "More info" → "Run anyway".

## Build

You need Flutter (tested on 3.41.7) and Visual Studio with "Desktop development with C++".

```bash
flutter pub get
flutter test
flutter build windows --release
```

Output: `build/windows/x64/runner/Release/` (run `vigilia.exe` together with the whole folder).

Native tests (tray, hotkey) are built after the Release build with CMake from Visual Studio:

```bash
cmake -S windows/runner/test -B build/native_test
```
```bash
cmake --build build/native_test --config Release
```
```bash
ctest --test-dir build/native_test -C Release --output-on-failure
```

The installer is built with [Inno Setup 6](https://jrsoftware.org/isinfo.php) after the Release build:

```bash
iscc installer/vigilia.iss
```

Output: `build/installer/Vigilia-<version>-setup.exe`. In GitHub Actions ([build.yml](.github/workflows/build.yml)) analysis, Dart and C++ tests and the build run on every push to `main`. The installer is built on a manual workflow run, and on `v*` tags it is also attached to the release.

Tray icons for all colors are generated by a script (needs Pillow); with `--app` it also generates the app icon:

```bash
python tool/make_icons.py
```

## Project layout

| File | What it does |
|---|---|
| `lib/main.dart` | startup: window, controller, tray |
| `lib/controller.dart` | state and logic: on/off, display, "until", schedule, settings |
| `lib/schedule.dart` | schedule ranges |
| `lib/probes.dart` | which programs are running, adapters and download speed |
| `lib/win32.dart` | WinAPI via `dart:ffi`: power request, sound, processes and their paths, adapter counters (`GetIfTable2`), "animation effects" |
| `lib/hotkey.dart` | global hotkey combination |
| `lib/updater.dart` | checking for and installing updates |
| `lib/native.dart` | channel to the native side: tray, notifications, hotkey |
| `lib/strings.dart` | EN/RU texts |
| `lib/sounds.dart` | sound synthesis to WAV |
| `lib/settings.dart` | `%APPDATA%\Vigilia\settings.json`, autostart (`HKCU\...\Run`) |
| `lib/shell.dart` | tray, window, notifications |
| `lib/theme.dart` | palette from the accent, durations, curves, `lighter`/`darker` |
| `lib/ui/` | screen and components: orb, settings panel and tabs, switches, toggle, hotkey recorder, hold button, text animations |
| `windows/runner/native_shell.cpp` | tray, menu, notifications, `RegisterHotKey` |
| `windows/runner/main.cpp` | single app instance |
| `windows/runner/test/` | native tests |
| `installer/vigilia.iss` | installer |

## Limitations

- The mode only prevents sleep caused by inactivity. Closing the laptop lid, the power button and Start → Sleep work as usual: that is how the Power Request API works.
- The download mode sees all incoming traffic on the adapter, not a single download: background updates also keep the mode going.
- If the combination is already taken by another program, the hotkey switch says so and stays off.
- The global hotkey accepts letters, digits, F1–F24, arrows, Home/End, PgUp/PgDn, Ins/Del, Space and Pause together with Ctrl, Alt or Win.
- The files are not signed: auto-update verifies the size and SHA-256 from GitHub, but not a signature.

## License

[MIT](LICENSE)
