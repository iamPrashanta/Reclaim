# Development

## Layout

| Path | What |
| --- | --- |
| `reclaim.cmd` | Launcher: starts Windows PowerShell with `-ExecutionPolicy Bypass` (PowerShell 7 with `RECLAIM_PWSH=1`). |
| `Reclaim.ps1` | Parameters, command-line modes, start of the menu. |
| `src/Core.ps1` | Settings, state, logging, sizes, protected paths, path expansion, engine loading, delete / measure / recycle wrappers, prompts. |
| `src/Targets.ps1` | Loads and validates the catalog, presets, measures and cleans a target, process checks. |
| `src/System.ps1` | Handlers (special cleaners), WSL / Docker disks, hibernation, page file, schedule, notifications. |
| `src/Analyze.ps1` | Space scan, old project folders, duplicates. |
| `src/Report.ps1` | HTML / JSON reports and `history.csv`. |
| `src/Move.ps1` | What grew (size snapshots), labels for big folders, moving caches, tool folders and WSL distros off C:, installed-programs report. |
| `src/UI.ps1` | Menus and the generic item picker. |
| `src/Engine.cs` | C# engine (measure, delete, scan, find folders, duplicates, size on disk, newest change). |
| `config/targets.psd1` | The catalog of cleaning targets. |
| `config/settings.psd1` | Defaults; `settings.local.psd1` overrides them. |
| `tests/SelfTest.ps1` | Sandbox tests for the guard and the engine. |
| `tools/check.ps1` | Parse check, ASCII check, engine compile, self test. |
| `tools/gen-targets-doc.ps1` | Regenerates `docs/TARGETS.md`. |

## Rules

- Windows PowerShell 5.1 must work: no `??`, `?:`, `&&`, `-Parallel`, `ConvertFrom-Json -AsHashtable`.
- `.ps1` and `.psd1` files are ASCII only (5.1 reads BOM-less files as the ANSI code page).
- `Engine.cs` is C# 5: no string interpolation, no `?.`, no expression-bodied members.
- Never name a script-scope variable like a parameter of `Reclaim.ps1` (`$Scan`, `$Targets`, `$Version`...):
  dot-sourced files share that scope and the parameter's type would be forced on it.
- Every deletion goes through `Remove-ReclaimPath` (guard + engine) or `Send-ToRecycleBin`. Never call
  `Remove-Item -Recurse` on a computed path.
- Use `Test-Exists` instead of `Test-Path` for paths that may be unreadable: with `-ErrorAction Stop`,
  `Test-Path` throws on access denied.

## Adding a target

Add a hashtable to `config/targets.psd1` (or to your own `config/custom-targets.psd1`):

```powershell
@{ Id = 'my-tool-cache'; Group = 'Developer'; Name = 'My tool cache'; Risk = 'Safe'
   Paths = @('%LOCALAPPDATA%\MyTool\Cache', '%APPDATA%\MyTool\*\GPUCache')
   Processes = @('mytool')
   After = 'My tool downloads what it needs again.' }
```

Then run `tools\check.ps1` (the self test checks that no target resolves to a protected folder) and
`tools\gen-targets-doc.ps1`.

Optional fields: `Admin`, `Mode = 'Folder'` (delete the folder or file itself), `OlderThanDays`, `Presets`,
`Recycle`, `MinDepth`, `Handler`.

## Adding a handler

When plain deletion is not right (a tool must run, services must stop), add an entry to `$script:Handlers`
in `src/System.ps1` with two script blocks:

- `Measure = { param($t) @{ Paths = @(...); Bytes = 123; Status = 'ready'; Note = '...' } }`
- `Clean = { param($t, $row) @{ Freed = 123; InUse = 0; Errors = 0; Note = '...' } }`

Respect `$script:DryRun` in `Clean`. If the handler cannot know the freed size, return `Freed = 0`: the
caller then uses the change in the drive's free space.

## Testing

```powershell
powershell -ExecutionPolicy Bypass -File tools\check.ps1
reclaim -Scan
reclaim -Clean -Preset Deep -DryRun -Yes
```

The self test works only inside a new folder in `%TEMP%` and removes it at the end.
