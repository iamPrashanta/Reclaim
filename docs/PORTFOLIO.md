# Portfolio entry

Copy-ready text for a portfolio or project page.

**Title:** Reclaim: a safe disk cleaner for Windows developers

**One line:** A menu-driven PowerShell + C# tool that frees up disk space on Windows without ever
following a junction or deleting something you did not see first.

**Short description (about 60 words):**
Reclaim finds the gigabytes that developer tools leave on C: (npm, Gradle, NuGet, pip, Android Studio,
JetBrains, Docker, WSL and every browser) and cleans them with clear risk levels and a note on what happens
afterwards. It also finds space hogs, stale `node_modules` and build folders, duplicate files, and compacts
WSL and Docker disks. Every run produces an HTML report.

**Longer description:**
I built Reclaim after cleaning my own laptop by hand. The same folders kept coming back: package-manager
caches, IDE indexes, emulator images, browser AI models, Windows Update leftovers, WSL disks that never
shrink. Reclaim turns that knowledge into a catalog of cleaning targets, each described as data with a risk
level (Safe, Moderate, Careful), the programs that must be closed first, and what you will notice afterwards.

The deletion engine is a small C# library compiled at run time from PowerShell. It walks folders on a
background thread with live progress, handles paths over 260 characters, never follows junctions or
symbolic links, and sits behind two independent guards that refuse system and personal folders. A dry run
shows exact sizes before anything is deleted, and personal files always go to the Recycle Bin.

**Highlights:**
- Catalog-driven design: cleaning targets are a data file, documentation is generated from it.
- C# engine via `Add-Type`, cached as a DLL: fast scans, cancellable with Esc, long-path and hard-link aware.
- Duplicate finder: size, then partial hash, then SHA-256; hard links detected by file index.
- Finds stale build folders only when the matching project file exists (`package.json`, `Cargo.toml`,
  `*.csproj`...), and dates each project by its newest change and git activity.
- WSL / Docker `.vhdx` compaction with `fstrim` and `diskpart`; optional sparse mode.
- Self-contained HTML reports (light and dark), JSON output, Task Scheduler integration, Windows toast alerts.
- Self test that builds a sandbox with junctions, locked, read-only and long paths and checks 28 safety rules.

**Stack:** PowerShell 5.1 / 7, C# (.NET Framework 4.x and .NET 6+), Windows Task Scheduler, WinRT notifications.

**Links:** GitHub repository (add the URL after pushing).
