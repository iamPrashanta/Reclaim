# Reclaim

![Reclaim main menu](docs/images/reclaim-menu.jpg)

**Free up disk space on Windows, safely.**

Reclaim is a menu-driven cleaner for Windows 10 and 11. It knows where Windows, browsers and developer tools
(npm, Gradle, NuGet, pip, Android Studio, JetBrains, VS Code, Docker, WSL...) leave their gigabytes, shows you
exactly how much each item takes, tells you what happens after cleaning it, and only then deletes. Every run can
be a dry run first, and every run leaves a report.

![Platform: Windows 10/11](https://img.shields.io/badge/platform-Windows%2010%20%7C%2011-2C6EF7)
![PowerShell 5.1 and 7](https://img.shields.io/badge/PowerShell-5.1%20%7C%207-2C6EF7)
![No install](https://img.shields.io/badge/install-none-3DD68C)
![License: MIT](https://img.shields.io/badge/license-MIT-FF7A1A)

| Pick and clean | Reports and self test |
| --- | --- |
| ![Quick clean picker and dry-run results](docs/images/reclaim-quick-clean.jpg) | ![HTML report and self test](docs/images/reclaim-report.jpg) |

## Contents

- [Why Reclaim](#why-reclaim)
- [Features](#features)
- [Requirements](#requirements)
- [Install](#install)
- [Your first clean, step by step](#your-first-clean-step-by-step)
- [The menu](#the-menu)
- [Risk levels and presets](#risk-levels-and-presets)
- [What gets cleaned](#what-gets-cleaned)
- [Command line](#command-line)
- [Everyday recipes](#everyday-recipes)
- [Reports, logs and where Reclaim keeps its data](#reports-logs-and-where-reclaim-keeps-its-data)
- [Safety design](#safety-design)
- [Privacy](#privacy)
- [Configuration](#configuration)
- [Troubleshooting and FAQ](#troubleshooting-and-faq)
- [Uninstall](#uninstall)
- [How it works](#how-it-works)
- [Development and contributing](#development-and-contributing)
- [License](#license)

## Why Reclaim

Developer laptops fill up in the same places: package-manager caches, IDE indexes, emulator images, browser
caches and on-device AI models, Windows Update leftovers, and WSL or Docker disks that grow but never shrink.
Windows' own Disk Cleanup does not know about most of them, and deleting them by hand means remembering dozens of
paths and guessing what is safe.

Reclaim turns that into a list you can read: size, risk, and a sentence on what you will notice afterwards
("the next Gradle build downloads dependencies again"). You choose; it cleans; it writes down what it did.

## Features

| Feature | What you get |
| --- | --- |
| **55 cleaning targets** | Windows temp and crash dumps, every Chromium browser and Firefox (all profiles), npm / Yarn / pnpm / Bun, pip / uv / Poetry / Conda, NuGet, Gradle, Maven, Cargo, Go, Composer, Flutter pub, JetBrains and Android Studio (including caches of old IDE versions), VS Code / Cursor / Windsurf / Antigravity, Docker, Teams / Slack / Discord, GPU shader caches, NVIDIA driver downloads, Android emulator snapshots, Windows Update, Delivery Optimization, the DISM component store, Windows.old. Full list: [docs/TARGETS.md](docs/TARGETS.md). |
| **Risk levels** | Every target is **Safe**, **Moderate** or **Careful**, with a note on what happens after cleaning. Careful items are never in a preset and need you to type `YES`. |
| **Presets** | Quick (safe, no admin), Developer (adds caches that are rebuilt), Deep (adds system items, admin). Or pick items one by one. |
| **Dry run** | Exact sizes, the full report, and nothing deleted. |
| **Space hogs** | Scans a whole drive or folder in a background thread, shows the biggest folders and files, file types and data untouched for a year, and marks folders Reclaim can clean. Drill into a folder, open it in Explorer, or send files to the Recycle Bin. |
| **Old project folders** | Finds `node_modules`, `.next`, `.nuxt`, `.turbo`, `target`, `build`, `.gradle`, `.dart_tool`, `bin/obj`, `__pycache__`, `.venv`, `vendor`, `Pods`, `.terraform` in your code folders, only when the project file next to them exists, and preselects projects untouched for 30 days. |
| **Duplicate files** | Same size, then a quick hash of the first and last 64 KB, then full SHA-256. Hard links are never reported as duplicates. Keep the oldest, newest or shortest-path copy; the others go to the Recycle Bin. |
| **WSL / Docker disks** | Finds every WSL distro and Docker Desktop disk, runs `fstrim` inside the distros, shuts WSL down and compacts the `.vhdx` files. Optionally switches WSL to sparse mode so the disks shrink by themselves. |
| **What grew** | Saves a size snapshot of a drive or folder each time you scan it and shows which folders grew since the last check, plus big files that changed in the last week (Podman, WSL and Docker disks that keep growing show up here) with what each one is and what to do about it. |
| **Move off C:** | Developer caches (npm, Yarn, pip, uv, NuGet, Gradle, Puppeteer, Playwright) pointed to another drive; tool folders moved with their official setting (Android emulators, Flutter pub cache, Rust, Ollama models, Hugging Face models); whole WSL distros moved with `wsl --manage --move`; and a report of the biggest installed programs with the right way to get each one onto D:. |
| **System options** | Shrink or turn off the hibernation file, page file and restore point information, Compact OS, DISM analysis, Storage Sense, Disk Cleanup. |
| **Reports** | A self-contained HTML page (light and dark) and JSON for every clean and scan, plus a history of the space freed over time. |
| **Schedule** | A weekly hidden Quick clean, and a daily notification when a drive drops under 20 GB free. |
| **Command line** | Everything also works without the menu, with JSON output and exit codes. |

## Requirements

- Windows 10 or Windows 11 (64-bit).
- Windows PowerShell 5.1, which is built into every Windows 10 and 11 PC. PowerShell 7 works too.
- Nothing to install. The first start compiles a small C# engine with the .NET Framework that Windows already has
  (a few seconds, once).
- Administrator rights only for the system items (Windows Update cache, DISM, all users' Recycle Bins, WSL disk
  compaction, hibernation). Everything else runs as a normal user.

## Install

**Option 1: download the ZIP**

1. On GitHub, click **Code > Download ZIP**.
2. Extract it anywhere you like, for example `D:\Tools\Reclaim`. Keep the folder structure as it is.
3. Windows marks downloaded files as coming from the internet. Unblock them once, in PowerShell:
   ```powershell
   Get-ChildItem -Path 'D:\Tools\Reclaim' -Recurse | Unblock-File
   ```
   (Or right-click the ZIP before extracting > Properties > tick **Unblock** > OK.)

**Option 2: git**

```powershell
git clone https://github.com/iamPrashanta/Reclaim.git D:\Tools\Reclaim
```

**Optional: run it from anywhere.** Add the folder to your user `PATH` (Settings > System > About > Advanced
system settings > Environment Variables), then type `reclaim` in any terminal.

## Your first clean, step by step

1. Double-click **`reclaim.cmd`**. The menu shows your drives and how full they are.
2. Press **D** and Enter: the header now says *DRY RUN*. Nothing will be deleted until you turn it off.
3. Press **1** (Quick clean). Reclaim measures every safe target; this takes a few seconds.
4. You get a list grouped by area, with the size and risk of each item. Everything in Quick is Safe and preselected.
   - Type numbers to tick or untick items: `4`, `1,3`, `5-8`.
   - Type `i 4` to see exactly which folders item 4 covers and what happens after cleaning it.
5. Press **Enter**, then confirm. In a dry run you see *would free* for each item and the total.
6. The last line shows where the HTML report was saved. Open it from the menu with **R**.
7. Happy with it? Press **D** again to turn the dry run off and repeat step 3 for real.

If a program that uses an item is running (Chrome for the Chrome cache, for example), Reclaim asks you to close it,
skip the item, or clean anyway; files that are locked are skipped, never forced.

## The menu

| Key | Item | What it does | Admin |
| --- | --- | --- | --- |
| 1 | Quick clean | Safe caches and temp files. Nothing you would miss. | no |
| 2 | Developer clean | Quick + caches that are rebuilt or downloaded again (npm, Gradle, NuGet, IDE indexes, emulator snapshots...). | no |
| 3 | Deep clean | Developer + system items: Windows Update cache, DISM, Recycle Bin, driver leftovers. | yes, for the system items |
| 4 | Choose items | Measures every target and lets you pick exactly what to clean. Safe ones are preselected. | for system items |
| 5 | Space hogs | Biggest folders, files and file types on a drive or folder, with an HTML report. | no (admin sees more) |
| 6 | Old project folders | Build folders in your code folders, with the age of each project. | no |
| 7 | Duplicate files | Identical files by SHA-256; extra copies go to the Recycle Bin. | no |
| 8 | WSL / Docker disks | Compacts the virtual disks of WSL distros and Docker Desktop. | yes |
| 9 | System options | Hibernation file, page file, restore points, Compact OS, DISM analysis, Storage Sense, Disk Cleanup. | some |
| G | What grew | Which folders grew since the last check, and big files that changed in the last 7 days, labelled (Podman disk, WSL disk, Android SDK...). | no |
| M | Move off C: | 1 developer caches, 2 tool folders (moved, not deleted), 3 WSL distros, 4 installed programs report. | no |
| S | Schedule | Weekly Quick clean and a low-space notification. | no |
| R | Reports | History, total space freed, open the last report. | no |
| T | Tips | How to keep C: from filling up again ([docs/RECOMMENDATIONS.md](docs/RECOMMENDATIONS.md)). | no |
| D | Dry run | Turns simulation on or off. | no |
| A | Run as administrator | Restarts Reclaim elevated (one Windows prompt). | |

**In every list** (cleaning targets, build folders, duplicates, disks):

| Type | Does |
| --- | --- |
| `3`, `1,3`, `5-8` | Tick or untick those numbers |
| `a` / `n` | Select all / none |
| `s` / `m` | Safe only / Safe + Moderate (cleaning lists) |
| `i 3` | Details of item 3: folders, programs to close, what happens afterwards |
| `+` / `-` | Next / previous page |
| Enter | Continue with the selection |
| `b` | Back |

Long scans and cleans show live progress; **Esc** stops them.

## Risk levels and presets

| Risk | Meaning | Example |
| --- | --- | --- |
| **Safe** | You will not notice anything. | Temp files, browser caches, npm cache |
| **Moderate** | Something is rebuilt or downloaded again, so it is slower once. | Gradle caches, IDE indexes, Docker build cache |
| **Careful** | Removes things you may want back. Never in a preset; you must type `YES`. | Android emulators, downloaded AI models, Windows.old |

| Preset | Contains | Admin |
| --- | --- | --- |
| Quick | Safe items that need no admin | no |
| Developer | Safe + Moderate items that need no admin | no |
| Deep | Safe + Moderate items, including system items | yes |

## What gets cleaned

| Group | Examples |
| --- | --- |
| Windows | Your temp folder (files older than a day), crash dumps, error reports, DirectX shader cache, Recycle Bin, old installers in Downloads (to the Recycle Bin) |
| Browsers | Chrome, Edge, Brave, Vivaldi, Opera and Firefox caches in every profile; Chrome's on-device AI model. Logins, history, passwords and bookmarks are never touched |
| Developer | npm, Yarn, Bun, pnpm (prune only), pip, uv, Poetry, Conda, NuGet, Gradle, Maven, Cargo, Go, Composer, Flutter pub, Puppeteer / Playwright / Cypress browsers, JetBrains and Android Studio caches and old versions, VS Code-family caches, Visual Studio, Docker prune, Unity |
| Apps | Teams, Slack, Discord, Notion, Postman, Steam and Spotify caches |
| GPU and drivers | NVIDIA / AMD / Intel shader caches, NVIDIA App downloaded updates, extracted driver installers |
| Android and phones | Emulator snapshots, emulators, SDK system images, iPhone backups (to the Recycle Bin) |
| System (admin) | Windows temp, Windows Update cache, Delivery Optimization, system crash dumps, MEMORY.DMP, old setup logs, DISM component cleanup, Windows.old |

Every item, its risk and what happens afterwards: [docs/TARGETS.md](docs/TARGETS.md).

## Command line

`reclaim.cmd` passes everything to `Reclaim.ps1`. Lists can be comma-separated: `-Targets a,b`.

```bat
reclaim                                     :: interactive menu
reclaim -List                               :: all targets with id, risk, presets
reclaim -Scan                               :: measure everything, delete nothing
reclaim -Scan -Preset Dev -Json             :: measure one preset, as JSON
reclaim -Clean -Preset Quick                :: clean a preset (asks once)
reclaim -Clean -Preset Quick -Yes -Quiet    :: no questions, no output (for Task Scheduler)
reclaim -Clean -Targets npm-cache,gradle-caches -DryRun
reclaim -Clean -Targets android-avds -Force :: Careful items need -Targets and -Force
reclaim -Clean -Preset Dev -Skip chrome-ai-model
reclaim -Analyze C:\                        :: space hogs, saves an HTML report
reclaim -Growth C:\Users\me                :: what grew since the last check of this folder
reclaim -DevFolders D:\Code                 :: list build folders, mark stale ones
reclaim -DevFolders D:\Code -StaleDays 60 -Clean
reclaim -Duplicates D:\Photos -MinMB 5      :: list duplicate groups
reclaim -Schedule weekly -At 13:00          :: weekly Quick clean   (also: daily, monthly)
reclaim -Schedule alert                     :: low disk space notification
reclaim -Schedule status                    :: show the scheduled tasks
reclaim -Schedule remove                    :: remove them
reclaim -CheckSpace                         :: exit code 1 and a notification if a drive is low
reclaim -SelfTest                           :: safety and engine tests
reclaim -Version
```

| Parameter | Meaning |
| --- | --- |
| `-List` | Print the catalog. Add `-Json` for JSON. |
| `-Scan` | Measure targets (all, a `-Preset`, or `-Targets`). Deletes nothing. |
| `-Clean` | Clean a `-Preset` or `-Targets`. Asks once unless `-Yes`. |
| `-Preset Quick\|Dev\|Deep` | Choose a preset. |
| `-Targets id,id` | Choose targets by id (see `-List`). |
| `-Skip id,id` | Leave these out. |
| `-DryRun` | Simulate: sizes and report, nothing deleted. |
| `-Yes` | Do not ask. Targets whose program is running are skipped. |
| `-Force` | With `-Yes`: clean even if the program is running. With `-Targets`: allow Careful items. |
| `-Quiet` | No console output (the report and log are still written). |
| `-NoReport` | Do not write HTML/JSON reports. |
| `-Json` | JSON output for `-List`, `-Scan`, `-Analyze`, `-DevFolders`, `-Duplicates`. |
| `-Analyze path` | Space hogs for a drive or folder. |
| `-Growth path` | What grew since the last check of that folder (a snapshot is saved each time). |
| `-DevFolders path;path` | Old project build folders; add `-Clean` to delete the stale ones, `-StaleDays n` to change the age. |
| `-Duplicates path;path` | Duplicate groups; `-MinMB n` ignores smaller files. |
| `-Schedule weekly\|daily\|monthly\|alert\|status\|remove` | Manage the scheduled tasks; `-At HH:mm` sets the time. |
| `-CheckSpace` | Notify (and exit 1) when a drive is under the low-space limit. |
| `-Menu disks\|system\|dev\|space\|duplicates\|relocate` | Open one menu directly. |
| `-Pause` | Wait for Enter at the end (useful in a new window). |
| `-SelfTest` | Run the safety tests. |

Exit codes: `0` done, `1` error, `2` finished but some items failed.
Set `RECLAIM_PWSH=1` to make `reclaim.cmd` use PowerShell 7 when it is installed.

## Everyday recipes

| I want to... | Do this |
| --- | --- |
| Free space quickly, safely | Menu **1**, or `reclaim -Clean -Preset Quick` |
| See what is possible first | `reclaim -Scan` (everything) or press **D** then **3** |
| Clean like a developer once a month | Menu **2** |
| Find what is really eating my drive | Menu **5**, or `reclaim -Analyze C:\` |
| Remove old `node_modules` and build folders | Menu **6**, or `reclaim -DevFolders D:\Code` |
| Shrink a WSL or Docker disk | Menu **A** (admin), then **8** |
| Find out why C: suddenly lost 20 GB | Menu **G** (run it once now and again later), or menu **5** and look at "Big files changed in the last 7 days" |
| Stop caches filling C: | Menu **M** > 1, pick the caches, choose a folder on D: |
| Move Android emulators, Rust, Ollama or Hugging Face models to D: | Menu **M** > 2 |
| Move a WSL distro (Ubuntu) to D: | Menu **M** > 3 |
| Get a big program onto D: | Menu **M** > 4 shows the right way for each one |
| Keep it clean without thinking | `reclaim -Schedule weekly` and `reclaim -Schedule alert` |
| Use it in a script | `reclaim -Scan -Preset Dev -Json > scan.json` |

## Reports, logs and where Reclaim keeps its data

Everything Reclaim writes is in `%LOCALAPPDATA%\Reclaim` (for example `C:\Users\you\AppData\Local\Reclaim`):

| Folder or file | What |
| --- | --- |
| `reports\clean-<date>.html` / `.json` | One per clean (or dry run): drives before and after, every item, found, freed, result |
| `reports\space-<date>.html` / `.json` | One per space scan |
| `reports\history.csv` | Date, preset, bytes freed, items, report path of every real clean |
| `logs\reclaim-<date>.log` | Every action and every path that was refused or skipped |
| `engine\Reclaim.Engine-*.dll` | The compiled engine (rebuilt automatically when `src\Engine.cs` changes) |
| `snapshots\<folder>-<date>.json` | Folder sizes saved by space scans and "What grew" |
| `state.json` | Remembered choices: your code folders, duplicate folders, last report |

The Reclaim folder itself is never written to and never cleaned.

## Safety design

Deleting files is the one thing a cleaner must never get wrong, so Reclaim is built around it:

- **Junctions and symbolic links are never followed.** A link inside a cache is removed as a link; the folder it
  points to is never touched. A junction inside `node_modules` or a tool's cache can point anywhere, so this matters.
- **Two independent guards.** The PowerShell layer refuses protected folders (drive roots, Windows, System32,
  WinSxS, Program Files, ProgramData, Package Cache, Windows\Installer, your profile, Documents, Desktop, Downloads,
  Pictures, OneDrive, `.ssh`, and Reclaim's own folder) plus anything you list in `ExcludePaths`. The C# engine then
  refuses wildcards, relative paths and anything less than three levels deep (`C:\a\b`), with a few explicit
  exceptions such as `C:\Windows.old`.
- **Programs in use.** Reclaim asks you to close them, skip, or clean anyway; locked files are skipped and counted.
- **Dry run everywhere** gives the exact sizes without deleting anything.
- **Your data goes to the Recycle Bin.** Duplicates, big files, old installers and phone backups are recycled, not
  deleted. Caches, which programs rebuild by themselves, are deleted permanently.
- **Long paths** (over 260 characters, common in `node_modules`) and read-only files are handled.
- **Logged.** Every action is written to the log.
- **Tested.** `reclaim -SelfTest` builds a throw-away folder tree in `%TEMP%` (with a junction to a "precious"
  folder, locked, read-only, old and very long paths, duplicates and hard links) and checks 30 rules, including that
  the junction target survives.

What Reclaim will **not** do: touch `WinSxS`, `Windows\Installer` or `Package Cache` by hand (it uses DISM instead),
delete restore points, "clean" the registry, or delete anything in Documents, Desktop or Pictures except files you
pick yourself.

## Privacy

Reclaim works entirely on your PC. It makes no network requests, collects nothing and sends nothing. The only
programs it starts are Windows tools (`dism`, `powercfg`, `diskpart`, `compact`, `wsl`, `takeown`, `icacls`) and,
only when you select those items, `docker`, `pnpm` and `conda`.

## Configuration

Defaults are in [`config/settings.psd1`](config/settings.psd1). Put your own values in
`config/settings.local.psd1` (ignored by git), for example:

```powershell
@{
    DevRoots       = @('D:\Code', 'C:\Users\me\source\repos')
    StaleDays      = 45
    LowSpaceGB     = 30
    ExcludeTargets = @('spotify-cache')
    ExcludePaths   = @('D:\Code\keep-this-build')
}
```

| Setting | Default | Meaning |
| --- | --- | --- |
| `DevRoots` | none | Code folders for "Old project folders" |
| `StaleDays` | 30 | A project untouched this long counts as stale |
| `ScanDepth`, `TopCount`, `LargeFileMinMB`, `OldFileDays` | 3, 30, 100, 365 | Space hogs |
| `DuplicateMinMB`, `DuplicateSkipDirs` | 10, system and build folders | Duplicate finder |
| `LowSpaceGB` | 20 | Low-space alert limit |
| `ExcludeTargets` | none | Target ids to hide |
| `ExcludePaths` | none | Paths Reclaim must never touch |
| `DataDir`, `ReportsDir` | `%LOCALAPPDATA%\Reclaim` | Where reports, logs and state go |

**Your own targets:** copy [`config/custom-targets.example.psd1`](config/custom-targets.example.psd1) to
`config/custom-targets.psd1` and add folders. Each target is a few lines of data: id, name, risk, paths (with
`%VARIABLES%` and `*` wildcards) and what happens after cleaning. See [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md).

## Troubleshooting and FAQ

**"Running scripts is disabled on this system".** Start Reclaim with `reclaim.cmd`, which runs it with
`-ExecutionPolicy Bypass` for that run only. If you start `Reclaim.ps1` yourself, use
`powershell -ExecutionPolicy Bypass -File .\Reclaim.ps1`.

**"The file is not digitally signed" or a security warning.** The files are still marked as downloaded. Run the
`Unblock-File` command from [Install](#install).

**My antivirus complains on the first start.** The first start compiles `src\Engine.cs` into a small DLL in
`%LOCALAPPDATA%\Reclaim\engine`. Some antivirus products look closely at programs that compile code. The source is
in this repository; you can allow that folder, or read the engine first.

**An item says "skipped: program running".** Close the program (Chrome, an IDE, the emulator) and run it again,
or choose "clean anyway" (locked files are skipped).

**I emptied the Recycle Bin from Reclaim but my space did not change much.** As a normal user Reclaim empties only
your own bin; run as administrator (**A**) to empty every account's bin.

**Duplicates or big files went to the Recycle Bin but C: did not get bigger.** Recycled files still take space
until the bin is emptied. That is on purpose, so you can restore them.

**Chrome's AI model came back.** Chrome downloads it again while its on-device AI is on. Turn it off in
`chrome://settings/ai` (or set the policy `GenAILocalFoundationalModelSettings` to `1`).

**C: lost a lot of space and I don't know why.** Menu **G** (or **5**) lists big files that changed in the last week. Virtual disks are the usual cause: Podman (`.local\share\containers`), WSL (`AppData\Local\wsl`) and Docker grow as you use containers and never shrink by themselves. Compact them with **8**, prune unused images and volumes in Podman or Docker, or move a WSL distro with **M** > 3.

**Can Reclaim move my installed programs to D:?** Not by copying their folders: Windows, their updaters and their uninstallers still point to C:, and that breaks them. **M** > 4 lists the biggest ones with the safe way for each (the program's own location setting, or uninstall and install again on D:). Data folders with an official location setting are moved for you by **M** > 2.

**WSL compaction freed little.** Answer yes to *fstrim* first, and make sure Docker Desktop is quit. Then consider
sparse mode (offered after compacting).

**Does it work on non-English Windows?** Yes. Sizes are measured by the engine itself, not by parsing the output of
Windows tools.

**Is it safe to run the weekly schedule?** The scheduled task runs only the Quick preset (Safe items, no admin) and
skips any item whose program is running.

**Something went wrong.** Look at the newest file in `%LOCALAPPDATA%\Reclaim\logs`, and run `reclaim -SelfTest`.

## Uninstall

1. `reclaim -Schedule remove` (if you created scheduled tasks).
2. If you used "Move caches off C:", remove the user environment variables it set (`npm_config_cache`,
   `GRADLE_USER_HOME`, ...) in Environment Variables, or leave them: they keep working.
3. Delete the Reclaim folder and `%LOCALAPPDATA%\Reclaim`.

Reclaim installs nothing else and changes no registry keys of its own.

## How it works

```
reclaim.cmd -> Reclaim.ps1 -+- src/Core.ps1      settings, guard, path expansion, engine loader, prompts
                            +- src/Targets.ps1   catalog, presets, measure and clean a target
                            +- src/System.ps1    special cleaners (DISM, Windows Update, Docker, pnpm,
                            |                    conda, Windows.old...), WSL disks, hibernation, schedule
                            +- src/Analyze.ps1   space hogs, old project folders, duplicates
                            +- src/Report.ps1    HTML / JSON reports and history
                            +- src/UI.ps1        menus and the item picker
                            +- src/Engine.cs     C# engine, compiled once with Add-Type and cached
```

The heavy work (walking hundreds of thousands of files, deleting, hashing) is done by `Engine.cs`, a small C# library
that PowerShell compiles on first start. It runs on a background thread, so the console shows live progress and
**Esc** stops any scan. It reads file sizes from the directory listing (no extra disk access per file), uses `\\?\`
paths for long names, measures the real size on disk of sparse `.vhdx` files, and identifies hard links by volume
and file index.

The cleaning targets are data, not code: `config/targets.psd1` is the whole catalog, and
[docs/TARGETS.md](docs/TARGETS.md) is generated from it.

## Development and contributing

```powershell
powershell -ExecutionPolicy Bypass -File tools\check.ps1          # parse, ASCII check, compile engine, self test
powershell -ExecutionPolicy Bypass -File tools\gen-targets-doc.ps1 # regenerate docs/TARGETS.md
```

- New cleaning target: add a few lines to `config/targets.psd1`, run both commands above, open a pull request.
- Scripts stay ASCII-only and avoid PowerShell 7-only syntax, so Windows PowerShell 5.1 runs them unchanged.
- Every deletion goes through the guard and the engine; never `Remove-Item -Recurse` on a computed path.

Details: [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md). Changes: [CHANGELOG.md](CHANGELOG.md).
Found a way Reclaim could delete something it should not? Please open an issue marked **safety** before anything else.

## License

MIT, see [LICENSE](LICENSE). Use at your own risk: Reclaim tells you what it will delete, but you decide.
