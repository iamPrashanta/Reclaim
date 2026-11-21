# Changelog

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
