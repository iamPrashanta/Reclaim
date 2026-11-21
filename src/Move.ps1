# Moving things off the system drive, finding out what grew, and labelling big folders Reclaim cannot clean.

# ------------------------------------------------------------------ labels for big folders
# Big folders that are not caches: what they are and what Reclaim can do about them.
$script:PathLabels = @(
    @{ Match = '\.local\share\containers';                     Label = 'Podman Linux disk (containers, images, volumes)'; Hint = 'compact: menu 8; prune: podman system prune' }
    @{ Match = '\AppData\Local\wsl\';                          Label = 'WSL Linux disk';                                  Hint = 'compact: menu 8; move: menu M > 3' }
    @{ Match = '\AppData\Local\Packages\CanonicalGroupLimited'; Label = 'WSL Linux disk (Store install)';                  Hint = 'compact: menu 8; move: menu M > 3' }
    @{ Match = '\AppData\Local\Docker\wsl';                    Label = 'Docker Desktop disk';                             Hint = 'compact: menu 8; move: Docker Settings > Resources' }
    @{ Match = '\AppData\Roaming\Claude\vm_bundles';           Label = 'Claude desktop app virtual machine';              Hint = 'managed by the Claude app; leave it' }
    @{ Match = '\.android\avd';                                Label = 'Android emulators';                               Hint = 'move: menu M > 2' }
    @{ Match = '\AppData\Local\Android\Sdk';                   Label = 'Android SDK';                                     Hint = 'move: Android Studio > Settings > Android SDK location' }
    @{ Match = '\.ollama\models';                              Label = 'Ollama models';                                   Hint = 'move: menu M > 2' }
    @{ Match = '\.lmstudio';                                   Label = 'LM Studio models';                                Hint = 'move: LM Studio > My Models > models folder' }
    @{ Match = '\.cache\huggingface';                          Label = 'Hugging Face models';                             Hint = 'move: menu M > 2' }
    @{ Match = '\.rustup';                                     Label = 'Rust toolchains';                                 Hint = 'move: menu M > 2' }
    @{ Match = '\.cargo';                                      Label = 'Rust Cargo home';                                 Hint = 'move: menu M > 2' }
    @{ Match = '\Pub\Cache';                                   Label = 'Flutter / Dart pub cache';                        Hint = 'move: menu M > 2' }
    @{ Match = '\steamapps';                                   Label = 'Steam games';                                     Hint = 'move: Steam > Settings > Storage' }
    @{ Match = '\Epic Games';                                  Label = 'Epic Games';                                      Hint = 'reinstall the games on D:' }
)

function Get-PathLabel([string]$path) {
    foreach ($l in $script:PathLabels) {
        if ($path.IndexOf($l.Match, [StringComparison]::OrdinalIgnoreCase) -ge 0) { return $l }
    }
    return $null
}

# ------------------------------------------------------------------ what grew
function Get-SnapshotDir {
    $d = Join-Path $script:Cfg.DataDir 'snapshots'
    if (-not (Test-Path -LiteralPath $d)) { New-Item -ItemType Directory -Path $d -Force | Out-Null }
    return $d
}

function Get-RootKey([string]$root) { return (($root.TrimEnd('\') -replace '[:\\ ]+', '_').Trim('_')).ToLowerInvariant() }

function Save-SizeSnapshot($scan) {
    $folders = @{}
    foreach ($f in $scan.Folders) { $folders[$f.Path] = $f.Bytes }
    $o = [pscustomobject]@{ Root = $scan.Root; Date = (Get-Date).ToString('o'); Total = $scan.Total; Free = (Get-FreeBytes $scan.Root.Substring(0, 2)); Folders = $folders }
    $f = Join-Path (Get-SnapshotDir) ('{0}-{1}.json' -f (Get-RootKey $scan.Root), (Get-Date -Format 'yyyyMMdd-HHmmss'))
    ($o | ConvertTo-Json -Depth 4) | Set-Content -LiteralPath $f -Encoding UTF8
    return $f
}

function Get-PreviousSnapshot([string]$root, [string]$except) {
    $key = Get-RootKey $root
    $files = @(Get-ChildItem -LiteralPath (Get-SnapshotDir) -Filter "$key-*.json" -ErrorAction SilentlyContinue | Where-Object { $_.FullName -ne $except } | Sort-Object Name -Descending)
    if (-not $files.Count) { return $null }
    try {
        $o = Get-Content -LiteralPath $files[0].FullName -Raw -Encoding UTF8 | ConvertFrom-Json
        $h = @{}
        foreach ($p in $o.Folders.PSObject.Properties) { $h[$p.Name] = [int64]$p.Value }
        return [pscustomobject]@{ Date = [datetime]$o.Date; Total = [int64]$o.Total; Free = [int64]$o.Free; Folders = $h }
    } catch { return $null }
}

# Folders that grew the most since the previous snapshot. A parent is dropped when one child explains most of it.
function Compare-SizeSnapshot($scan, $old) {
    $rows = New-Object System.Collections.Generic.List[object]
    foreach ($f in $scan.Folders) {
        $before = if ($old.Folders.ContainsKey($f.Path)) { $old.Folders[$f.Path] } else { [int64]0 }
        $delta = [int64]$f.Bytes - $before
        if ($delta -ge 200MB) { $rows.Add([pscustomobject]@{ Path = $f.Path; Relative = $f.Relative; Before = $before; After = [int64]$f.Bytes; Delta = $delta }) }
    }
    $keep = @()
    foreach ($r in $rows) {
        $child = $rows | Where-Object { $_.Path -ne $r.Path -and $_.Path.StartsWith($r.Path + '\', [StringComparison]::OrdinalIgnoreCase) -and $_.Delta -ge 0.8 * $r.Delta }
        if (-not $child) { $keep += $r }
    }
    return @($keep | Sort-Object Delta -Descending | Select-Object -First 15)
}

function Show-RecentBigFiles($scan, [int]$days = 7) {
    $cut = (Get-Date).AddDays(-$days)
    $recent = @($scan.TopFiles | Where-Object { $_.LastWrite -gt $cut -and $_.Bytes -ge 500MB })
    if (-not $recent.Count) { return }
    Out-Line ''
    Out-Line ('  Big files changed in the last {0} days (virtual disks that keep growing show up here)' -f $days) 'Cyan'
    foreach ($f in $recent) {
        $l = Get-PathLabel $f.Path
        Out-Part ('  {0,10}  {1:yyyy-MM-dd HH:mm}  ' -f (Format-Size $f.Bytes), $f.LastWrite) 'Gray'
        Out-Part (Limit-Text $f.Path ((Get-ConsoleWidth) - 40)) 'White'
        if ($l) { Out-Line ('  [{0}]' -f $l.Label) 'Yellow' } else { Out-Line '' }
    }
}

function Invoke-GrowthMenu([string]$root, [switch]$NoWait) {
    if (-not $root) { $root = Read-Text 'Folder or drive to check' $env:USERPROFILE }
    if (-not (Test-Path -LiteralPath $root -PathType Container)) { Out-Line '  Not found.' 'Yellow'; return }
    Out-Line '  Scanning (about a minute for a user folder)...' 'DarkGray'
    $scan = Invoke-SpaceScan $root
    $snap = Save-SizeSnapshot $scan
    $old = Get-PreviousSnapshot $scan.Root $snap
    Out-Line ''
    Out-Line ('  {0}: {1} now' -f $scan.Root, (Format-Size $scan.Total)) 'White'
    if (-not $old) {
        Out-Line '  First check of this folder: a baseline is saved. Run "What grew" again later to see the changes.' 'DarkGray'
    } else {
        $d = $scan.Total - $old.Total
        Out-Line ('  Since {0:yyyy-MM-dd HH:mm}: {1}{2}' -f $old.Date, $(if ($d -ge 0) { '+' } else { '-' }), (Format-Size ([math]::Abs($d)))) $(if ($d -gt 1GB) { 'Yellow' } else { 'Green' })
        $rows = Compare-SizeSnapshot $scan $old
        if (-not $rows.Count) { Out-Line '  No folder grew by more than 200 MB.' 'Green' }
        foreach ($r in $rows) {
            $l = Get-PathLabel $r.Path
            $k = Find-KnownTarget $r.Path
            Out-Part ('  +{0,9}  ' -f (Format-Size $r.Delta)) 'Yellow'
            Out-Part ('{0,10} -> {1,-10} ' -f (Format-Size $r.Before), (Format-Size $r.After)) 'DarkGray'
            Out-Line (Limit-Text $r.Relative ((Get-ConsoleWidth) - 50)) 'White'
            if ($l) { Out-Line ('              {0}: {1}' -f $l.Label, $l.Hint) 'Gray' }
            elseif ($k) { Out-Line ('              cleanable: {0} ({1})' -f $k.Name, $k.Id) 'Gray' }
        }
    }
    Show-RecentBigFiles $scan 7
    if (-not $NoWait) { Wait-AnyKey }
}

# ------------------------------------------------------------------ moving folders
# robocopy /MOVE: copies everything, then removes the source; junctions are not followed (/XJ).
function Move-FolderTree([string]$src, [string]$dst) {
    if (Test-ProtectedPath $src) { throw "Refusing to move a protected folder: $src" }
    if ($script:DryRun) { return $true }
    New-Item -ItemType Directory -Path $dst -Force | Out-Null
    & robocopy.exe $src $dst /E /MOVE /XJ /COPY:DAT /DCOPY:DAT /R:1 /W:1 /NFL /NDL /NJH /NJS /NP | Out-Null
    $code = $LASTEXITCODE
    Write-Log "robocopy move $src -> $dst exit $code"
    return ($code -lt 8)
}

function Update-UserPath([string]$oldPart, [string]$newPart) {
    $p = [Environment]::GetEnvironmentVariable('Path', 'User')
    if (-not $p) { return $false }
    $parts = $p -split ';'
    $changed = $false
    for ($i = 0; $i -lt $parts.Count; $i++) {
        if ([Environment]::ExpandEnvironmentVariables($parts[$i]).TrimEnd('\') -ieq $oldPart.TrimEnd('\')) { $parts[$i] = $newPart; $changed = $true }
    }
    if ($changed -and -not $script:DryRun) { [Environment]::SetEnvironmentVariable('Path', ($parts -join ';'), 'User') }
    return $changed
}

# Tool folders that have an official setting (an environment variable) for their location.
$script:ToolMoves = @(
    @{ Name = 'Android emulators';  Vars = @(@{ Var = 'ANDROID_AVD_HOME'; Default = '%USERPROFILE%\.android\avd'; Folder = 'android-avd' })
       Processes = @('qemu-system-x86_64', 'emulator', 'studio64'); Fix = 'avd-ini'
       Note = 'Android Studio and the emulator read ANDROID_AVD_HOME; the .ini files are updated to the new place.' }
    @{ Name = 'Flutter / Dart pub cache'; Vars = @(@{ Var = 'PUB_CACHE'; Default = '%LOCALAPPDATA%\Pub\Cache'; Folder = 'pub-cache'; PathBin = 'bin' })
       Processes = @('dart', 'flutter', 'studio64', 'Code'); Note = 'Global Dart tools keep working: their bin folder is updated in your PATH.' }
    @{ Name = 'Rust (rustup + cargo)'; Vars = @(@{ Var = 'RUSTUP_HOME'; Default = '%USERPROFILE%\.rustup'; Folder = 'rustup' }, @{ Var = 'CARGO_HOME'; Default = '%USERPROFILE%\.cargo'; Folder = 'cargo'; PathBin = 'bin' })
       Processes = @('cargo', 'rustc', 'rust-analyzer', 'rustrover64'); Note = 'RUSTUP_HOME and CARGO_HOME are set and cargo\bin in your PATH is updated.' }
    @{ Name = 'Ollama models'; Vars = @(@{ Var = 'OLLAMA_MODELS'; Default = '%USERPROFILE%\.ollama\models'; Folder = 'ollama-models' })
       Processes = @('ollama', 'ollama app'); Note = 'Quit Ollama first; it reads OLLAMA_MODELS when it starts again.' }
    @{ Name = 'Hugging Face models'; Vars = @(@{ Var = 'HF_HOME'; Default = '%USERPROFILE%\.cache\huggingface'; Folder = 'huggingface' })
       Processes = @('python'); Note = 'Python libraries read HF_HOME; models are moved, not downloaded again.' }
)

function Get-ToolMoveRows([string]$base) {
    foreach ($t in $script:ToolMoves) {
        $bytes = [int64]0; $paths = @(); $already = $true
        foreach ($v in $t.Vars) {
            $cur = [Environment]::GetEnvironmentVariable($v.Var, 'User')
            $src = if ($cur) { $cur } else { Expand-EnvPath $v.Default }
            if (-not $cur -or $src.StartsWith($env:SystemDrive, [StringComparison]::OrdinalIgnoreCase)) { $already = $false }
            if (Test-Exists $src) { $bytes += (Measure-ReclaimPath @($src) 0 ('Measuring ' + $t.Name)).Bytes }
            $paths += [pscustomobject]@{ Var = $v.Var; Src = $src; Dst = (Join-Path $base $v.Folder); PathBin = $v.PathBin }
        }
        [pscustomobject]@{ Name = $t.Name; Tool = $t; Paths = $paths; Bytes = $bytes; Selected = ($bytes -gt 100MB -and -not $already); Already = $already }
    }
}

function Repair-AvdIni([string]$newDir) {
    foreach ($ini in (Get-ChildItem -LiteralPath $newDir -Filter '*.ini' -File -ErrorAction SilentlyContinue)) {
        $txt = Get-Content -LiteralPath $ini.FullName
        $out = foreach ($line in $txt) {
            if ($line -match '^path=(.*)$') { 'path=' + (Join-Path $newDir (Split-Path $Matches[1] -Leaf)) } else { $line }
        }
        if (-not $script:DryRun) { Set-Content -LiteralPath $ini.FullName -Value $out -Encoding ASCII }
    }
}

function Invoke-ToolMoveMenu {
    $drives = @(Get-FixedDrives | Where-Object { $_.Name -ne $env:SystemDrive })
    if (-not $drives.Count) { Out-Line '  There is no other fixed drive.' 'Yellow'; Wait-AnyKey; return }
    $base = Read-Text 'New base folder' ('{0}\DevData' -f $drives[0].Name)
    if ($base -notmatch '^[a-zA-Z]:\\' -or $base.StartsWith($env:SystemDrive, [StringComparison]::OrdinalIgnoreCase)) { Out-Line '  Use a folder on another drive, like D:\DevData' 'Yellow'; return }
    $items = @(Get-ToolMoveRows $base)
    $line = { param($i) '{0,10}  {1,-26} {2}' -f (Format-Size $i.Bytes), $i.Name, $(if ($i.Already) { '(already off C:)' } else { (($i.Paths | ForEach-Object { $_.Var + ' -> ' + $_.Dst }) -join ', ') }) }
    $info = { param($i) Out-Line ''; Out-Line ('  ' + $i.Tool.Note) 'Gray'; foreach ($p in $i.Paths) { Out-Line ('  {0}: {1} -> {2}' -f $p.Var, $p.Src, $p.Dst) 'DarkGray' } }
    if (-not (Invoke-Picker $items 'Tool folders to move (moved, not deleted)' $line $null $info '      Size  Tool                       Setting -> new folder')) { return }
    $sel = @($items | Where-Object { $_.Selected -and -not $_.Already })
    if (-not $sel.Count) { return }
    foreach ($i in $sel) { $run = Get-RunningProcess $i.Tool.Processes; if ($run) { Out-Line ('  Close {0} first ({1}).' -f $i.Name, ($run -join ', ')) 'Yellow'; Wait-AnyKey; return } }
    if (-not (Read-YesNo ('Move {0} folder group(s) to {1}?' -f $sel.Count, $base) $true)) { return }
    foreach ($i in $sel) {
        $failed = $false
        foreach ($p in $i.Paths) {
            $ok = $true
            if (Test-Exists $p.Src) { $ok = Move-FolderTree $p.Src $p.Dst }
            if (-not $ok) { Out-Line ('  {0}: copy failed, its setting was not changed (see the log).' -f $i.Name) 'Red'; $failed = $true; continue }
            if (-not $script:DryRun) {
                New-Item -ItemType Directory -Path $p.Dst -Force | Out-Null
                [Environment]::SetEnvironmentVariable($p.Var, $p.Dst, 'User')
            }
            if ($p.PathBin) { [void](Update-UserPath (Join-Path $p.Src $p.PathBin) (Join-Path $p.Dst $p.PathBin)) }
            if ($i.Tool.Fix -eq 'avd-ini') { Repair-AvdIni $p.Dst }
            Write-Log ("Moved {0}: {1}={2}{3}" -f $i.Name, $p.Var, $p.Dst, $(if ($script:DryRun) { ' (dry run)' } else { '' }))
        }
        if (-not $failed) { Out-Line ('  {0}: {1} {2} to {3}' -f $i.Name, $(if ($script:DryRun) { 'would move' } else { 'moved' }), (Format-Size $i.Bytes), $base) 'Green' }
    }
    Out-Line '  Sign out and in again (or restart the apps and terminals) so they see the new locations.' 'Cyan'
    Wait-AnyKey
}

# ------------------------------------------------------------------ WSL distros
function Test-WslMoveSupported { return ((Invoke-WslCommand @('--help')) -join ' ') -match '--move' }

function Invoke-WslMoveMenu {
    $disks = @(Get-VirtualDisks | Where-Object { $_.Kind -eq 'WSL' })
    if (-not $disks.Count) { Out-Line '  No WSL distros found.' 'Green'; Wait-AnyKey; return }
    $drives = @(Get-FixedDrives | Where-Object { $_.Name -ne $env:SystemDrive })
    if (-not $drives.Count) { Out-Line '  There is no other fixed drive.' 'Yellow'; Wait-AnyKey; return }
    $items = @($disks | ForEach-Object {
        $managed = $_.Distro -match '^(docker-desktop|podman-)'
        $onC = $_.Path.StartsWith($env:SystemDrive, [StringComparison]::OrdinalIgnoreCase)
        $_ | Add-Member -NotePropertyName Selected -NotePropertyValue $false -PassThru -Force |
            Add-Member -NotePropertyName Managed -NotePropertyValue $managed -PassThru -Force |
            Add-Member -NotePropertyName OnC -NotePropertyValue $onC -PassThru -Force })
    $line = { param($d) '{0,10}  {1,-26} {2}' -f (Format-Size $d.Bytes), (Limit-Text $d.Distro 26), $(if ($d.Managed) { '(managed by Docker/Podman: move it from that app)' } elseif (-not $d.OnC) { '(already off C:)' } else { $d.Path }) }
    Out-Line ''
    Out-Line '  Moves a WSL distro (its whole Linux disk) to another drive with "wsl --manage <distro> --move".' 'Gray'
    Out-Line '  Docker and Podman machines are listed but not moved here: their own apps keep track of them.' 'Gray'
    if (-not (Invoke-Picker $items 'WSL distros' $line $null $null '      Size  Distro                     Disk')) { return }
    $sel = @($items | Where-Object { $_.Selected -and -not $_.Managed -and $_.OnC })
    if (-not $sel.Count) { return }
    if (-not (Test-WslMoveSupported)) {
        Out-Line '  This WSL version has no --move. Update WSL (wsl --update) or move it by hand:' 'Yellow'
        Out-Line '    wsl --export <distro> D:\WSL\<distro>.tar ; wsl --unregister <distro> ; wsl --import <distro> D:\WSL\<distro> D:\WSL\<distro>.tar' 'DarkGray'
        Wait-AnyKey; return
    }
    $base = Read-Text 'Folder for the distros' ('{0}\WSL' -f $drives[0].Name)
    Out-Line '  The distro is stopped for the move; its Linux programs stop.' 'Yellow'
    if (-not (Read-YesNo ('Move {0} distro(s) to {1}?' -f $sel.Count, $base) $false)) { return }
    foreach ($d in $sel) {
        $dst = Join-Path $base $d.Distro
        if ($script:DryRun) { Out-Line ('  Dry run: wsl --manage {0} --move {1}' -f $d.Distro, $dst) 'Magenta'; continue }
        New-Item -ItemType Directory -Path $dst -Force | Out-Null
        Invoke-WslCommand @('--terminate', $d.Distro) | Out-Null
        $out = Invoke-WslCommand @('--manage', $d.Distro, '--move', $dst)
        Write-Log ("wsl move {0} -> {1}: {2}" -f $d.Distro, $dst, ($out -join ' '))
        $now = @(Get-VirtualDisks | Where-Object { $_.Distro -eq $d.Distro } | Select-Object -First 1)
        if ($now.Count -and $now[0].Path.StartsWith($base, [StringComparison]::OrdinalIgnoreCase)) { Out-Line ('  {0}: moved to {1}' -f $d.Distro, $now[0].Path) 'Green' }
        else { Out-Line ('  {0}: not moved: {1}' -f $d.Distro, ($out -join ' ')) 'Red' }
    }
    Wait-AnyKey
}

# ------------------------------------------------------------------ installed programs
$script:InstallAdvice = @(
    @{ Match = 'Steam';            Advice = 'Steam > Settings > Storage: add a library on D: and move games there' }
    @{ Match = 'Epic Games';       Advice = 'Epic: uninstall a game and install it again on D:' }
    @{ Match = 'Android Studio';   Advice = 'keep the IDE; move the SDK (Settings > Android SDK) and emulators (menu M > 2)' }
    @{ Match = 'JetBrains|PyCharm|IntelliJ|WebStorm|Rider|RustRover|CLion|GoLand|DataGrip'; Advice = 'JetBrains Toolbox > Settings > Tools install location: set a folder on D:' }
    @{ Match = 'Visual Studio (Community|Professional|Enterprise|Build Tools)'; Advice = 'cannot be moved; Visual Studio Installer > Modify can remove unused workloads' }
    @{ Match = 'Docker Desktop';   Advice = 'Docker Settings > Resources > Advanced > Disk image location' }
    @{ Match = 'Podman';           Advice = 'the program is small; its Linux disk is in your profile (see What grew)' }
    @{ Match = 'DaVinci Resolve';  Advice = 'set the cache and gallery folders to D: in Project Settings; Extras can be removed in the installer' }
    @{ Match = 'Ollama';           Advice = 'move the models with menu M > 2 (OLLAMA_MODELS)' }
    @{ Match = 'LM Studio';        Advice = 'LM Studio > My Models: change the models folder to D:' }
    @{ Match = 'Unity Hub|Unity '; Advice = 'Unity Hub > Preferences > Installs location: set a folder on D:' }
    @{ Match = 'NVIDIA';           Advice = 'drivers stay on C:; old driver downloads are cleaned by Reclaim (Deep clean)' }
)

function Get-InstalledPrograms {
    $keys = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*', 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*', 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
    $seen = @{}
    foreach ($e in (Get-ItemProperty $keys -ErrorAction SilentlyContinue)) {
        if (-not $e.DisplayName -or $e.SystemComponent -eq 1 -or $e.ParentKeyName) { continue }
        $loc = ([string]$e.InstallLocation).Trim('"').TrimEnd('\')
        $name = [string]$e.DisplayName
        if ($seen.ContainsKey($name)) { continue }
        $seen[$name] = $true
        [pscustomobject]@{ Name = $name; Location = $loc; Bytes = ([int64]$e.EstimatedSize) * 1KB; OnC = ($loc -and $loc.StartsWith($env:SystemDrive, [StringComparison]::OrdinalIgnoreCase)) }
    }
}

function Invoke-ProgramsReport {
    Out-Line '  Reading installed programs...' 'DarkGray'
    $all = @(Get-InstalledPrograms | Where-Object { $_.OnC -or -not $_.Location })
    # measure the real folder size of the biggest candidates (the registry size is often missing or old)
    $cands = @($all | Where-Object { $_.Location -and (Test-Exists $_.Location) -and [Reclaim.Engine]::Depth($_.Location) -ge 3 } | Sort-Object Bytes -Descending | Select-Object -First 40)
    foreach ($c in $cands) { $c.Bytes = [int64](Measure-ReclaimPath @($c.Location) 0 ('Measuring ' + $c.Name)).Bytes }
    $top = @($all | Sort-Object Bytes -Descending | Select-Object -First 20)
    Out-Line ''
    Out-Line '  Biggest installed programs on C:' 'White'
    Out-Line '  Installed programs cannot be moved safely by copying their folder (Windows and their updaters still point to C:).' 'Gray'
    Out-Line '  Use the program''s own setting where there is one, otherwise uninstall it and install it again on D:.' 'Gray'
    Out-Line ''
    foreach ($p in $top) {
        $adv = $null
        foreach ($a in $script:InstallAdvice) { if ($p.Name -match $a.Match) { $adv = $a.Advice; break } }
        if (-not $adv) { $adv = 'if it is big and you use it rarely: uninstall, then install again choosing a folder on D:' }
        Out-Part ('  {0,10}  ' -f (Format-Size $p.Bytes)) 'Gray'
        Out-Line (Limit-Text $p.Name 60) 'White'
        Out-Line ('              ' + $adv) 'DarkGray'
    }
    Wait-AnyKey
}

# ------------------------------------------------------------------ the Move menu
function Invoke-MoveMenu {
    while ($true) {
        Out-Line ''
        Out-Line '  Move things off C:' 'White'
        Show-MenuItem '1' 'Developer caches' 'npm, Yarn, pip, uv, NuGet, Gradle, Puppeteer, Playwright (old copy removed)'
        Show-MenuItem '2' 'Tool folders' 'Android emulators, pub cache, Rust, Ollama, Hugging Face (moved, not deleted)'
        Show-MenuItem '3' 'WSL Linux distros' 'move a whole distro disk with wsl --manage --move'
        Show-MenuItem '4' 'Installed programs' 'the biggest programs on C: and how to get each one onto D:'
        Out-Line '     Enter = back' 'DarkGray'
        $a = (Read-Host '  Select').Trim()
        switch ($a) {
            '' { return }
            '1' { Invoke-RelocateMenu }
            '2' { Invoke-ToolMoveMenu }
            '3' { Invoke-WslMoveMenu }
            '4' { Invoke-ProgramsReport }
        }
    }
}
