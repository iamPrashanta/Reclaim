# Changelog

## 1.1.0 (2026-11-21)

- **What grew** (menu G, `-Growth path`): size snapshots of a drive or folder and the folders that grew since the last check; big files changed in the last 7 days; labels for big folders Reclaim does not clean (Podman, WSL and Docker disks, Claude VM, Android SDK, models) with what to do about each.
- **Move off C:** (menu M) is now a submenu: developer caches; tool folders moved with their official setting (Android emulators with their .ini paths fixed, Flutter pub cache, Rust with PATH updated, Ollama and Hugging Face models; moved with robocopy, never deleted); WSL distros with `wsl --manage --move`; an installed-programs report with the safe way to get each one onto D:.
- Space hogs saves a snapshot every time and shows growing big files and labels.
- Hugging Face models are moved instead of deleted when relocated.
- Self test: 30 checks.

## 1.0.0 (2026-11-21)

First release.

- Interactive menu and full command line (`-Scan`, `-Clean`, `-Preset`, `-Targets`, `-DryRun`, `-Json`...).
- Catalog of cleaning targets across Windows, browsers, developer tools, apps, GPU drivers, Android and
  system areas, each with a risk level and an "after cleaning" note.
- C# engine: junction-safe, long-path aware deletion and measuring on a background thread with live
  progress and Esc to stop.
- Space hogs scan with HTML report, old project build folder finder, SHA-256 duplicate finder with hard-link
  detection, WSL / Docker disk compaction, cache relocation to another drive, hibernation and Compact OS
  options.
- HTML + JSON reports, history of space freed, weekly scheduled clean, low disk space notification.
- Self test with 28 checks.
