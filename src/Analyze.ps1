# Analyzers: space hogs, old project build folders, duplicate files. They only read; deleting is done by the UI.

# Map of resolved target paths -> target, to label folders the cleaner already knows.
function Get-KnownTargetPaths {
    if ($script:KnownPaths) { return $script:KnownPaths }
    $list = New-Object System.Collections.Generic.List[object]
    foreach ($t in $script:Catalog) {
        foreach ($p in $t.Paths) {
            foreach ($x in (Expand-ReclaimPath $p)) { if ($x) { $list.Add([pscustomobject]@{ Path = $x.TrimEnd('\'); Target = $t }) } }
        }
    }
    $script:KnownPaths = $list
    return $list
}

function Find-KnownTarget([string]$path) {
    $p = $path.TrimEnd('\')
    foreach ($k in (Get-KnownTargetPaths)) {
        if ($p -ieq $k.Path -or $p.StartsWith($k.Path + '\', [StringComparison]::OrdinalIgnoreCase)) { return $k.Target }
    }
    return $null
}

function Invoke-SpaceScan([string]$root) {
    $root = [IO.Path]::GetFullPath($root)
    $job = [Reclaim.Engine]::StartScan($root, [int]$script:Cfg.ScanDepth, [int]$script:Cfg.TopCount,
        [int64]($script:Cfg.LargeFileMinMB * 1MB), [int]$script:Cfg.OldFileDays)
    $r = Wait-EngineJob $job "Scanning $root"
    $total = [Math]::Max([double]1, [double]$r.Stats.Bytes)
    $rootTrim = $root.TrimEnd('\')
    $folders = foreach ($kv in $r.DirBytes.GetEnumerator()) {
        if ($kv.Value -lt [Math]::Max([double]100MB, $total * 0.005)) { continue }
        $rel = $kv.Key.Substring([Math]::Min($kv.Key.Length, $rootTrim.Length)).TrimStart('\')
        $known = Find-KnownTarget $kv.Key
        [pscustomobject]@{ Path = $kv.Key; Relative = $rel; Depth = ($rel.Split('\').Count); Bytes = [int64]$kv.Value
            Percent = [math]::Round(100 * $kv.Value / $total, 1); Known = $(if ($known) { $known.Id } else { '' }) }
    }
    $exts = foreach ($kv in $r.ExtBytes.GetEnumerator()) {
        [pscustomobject]@{ Ext = $kv.Key; Bytes = [int64]$kv.Value; Files = [int64]$r.ExtFiles[$kv.Key] }
    }
    [pscustomobject]@{
        Root = $root; Total = [int64]$r.Stats.Bytes; Files = $r.Stats.Files; Dirs = $r.Stats.Dirs; Errors = $r.Stats.Errors
        OldBytes = [int64]$r.OldBytes; OldDays = $r.OldDays
        Folders = @($folders | Sort-Object Bytes -Descending)
        TopFiles = @($r.TopFiles | ForEach-Object { [pscustomobject]@{ Path = $_.Path; Bytes = [int64]$_.Bytes; LastWrite = $_.LastWrite } })
        Extensions = @($exts | Sort-Object Bytes -Descending | Select-Object -First 15)
    }
}

function Get-ProjectLastActive([string]$dir, [string[]]$skip) {
    $newest = [Reclaim.Engine]::NewestWrite($dir, 4, $skip, 30000)
    foreach ($g in @('.git\index', '.git\HEAD', '.git\FETCH_HEAD', '.git\logs\HEAD')) {
        $f = Join-Path $dir $g
        if (Test-Path -LiteralPath $f) { $t = (Get-Item -LiteralPath $f -Force).LastWriteTime; if ($t -gt $newest) { $newest = $t } }
    }
    return $newest
}

$script:ProjectMarkers = @('.git', 'package.json', 'pyproject.toml', 'requirements.txt', 'setup.py', 'Cargo.toml', 'go.mod', 'pom.xml',
    'build.gradle', 'build.gradle.kts', 'settings.gradle', 'settings.gradle.kts', 'pubspec.yaml', 'composer.json', '*.sln', '*.csproj')

# The project a build folder belongs to: the nearest folder above it with a project file, within the search roots.
function Find-ProjectRoot([string]$dir, [string[]]$roots) {
    $cur = $dir
    while ($cur) {
        foreach ($m in $script:ProjectMarkers) { if (Test-Path -Path (Join-Path $cur $m)) { return $cur } }
        $inRoot = $false
        foreach ($r in $roots) { if ($cur.TrimEnd('\') -ieq $r.TrimEnd('\')) { $inRoot = $true } }
        if ($inRoot) { break }
        $up = Split-Path $cur -Parent
        if (-not $up -or $up -eq $cur) { break }
        $cur = $up
    }
    return $dir
}

function Find-DevArtifacts([string[]]$roots) {
    $rules = @{}
    foreach ($a in $script:Cfg.DevArtifacts) { $rules[$a.Name.ToLowerInvariant()] = $a }
    $names = @($script:Cfg.DevArtifacts | ForEach-Object { $_.Name })
    $skipWalk = @($script:Cfg.DevSkipDirs)
    $job = [Reclaim.Engine]::StartFindDirs([string[]]$roots, [string[]]$names, [string[]]$skipWalk)
    $found = Wait-EngineJob $job 'Looking for build folders'
    $skipActivity = @($names + @('.git', '.idea', '.vs', '.vscode'))
    $activity = @{}
    $out = New-Object System.Collections.Generic.List[object]
    $i = 0
    foreach ($p in $found) {
        $i++
        $name = Split-Path $p -Leaf
        $rule = $rules[$name.ToLowerInvariant()]
        if (-not $rule) { continue }
        $parent = Split-Path $p -Parent
        $ok = $false
        foreach ($m in $rule.Markers) {
            if ($m -eq '*') { $ok = $true; break }
            if (Test-Path -Path (Join-Path $parent $m)) { $ok = $true; break }
        }
        if (-not $ok) { continue }
        if (Test-ProtectedPath $p) { continue }
        if (-not $script:Quiet) {
            Write-Progress -Activity 'Measuring build folders' -Status ("{0}/{1}  {2}" -f $i, $found.Count, (Limit-Text $p 80)) -PercentComplete ([int](100 * $i / [Math]::Max(1, $found.Count)))
        }
        $project = Find-ProjectRoot $parent $roots
        if (-not $activity.ContainsKey($project)) { $activity[$project] = Get-ProjectLastActive $project $skipActivity }
        $last = $activity[$project]
        $s = [Reclaim.Engine]::Measure($p, 0, $null)
        $age = if ($last -gt [datetime]::MinValue) { [int]((Get-Date) - $last).TotalDays } else { 9999 }
        $out.Add([pscustomobject]@{
            Path = $p; Name = $name; Kind = $rule.Kind; Risk = $rule.Risk; Restore = $rule.Restore
            Project = $project; LastActive = $last; AgeDays = $age; Bytes = [int64]$s.Bytes; Files = $s.Files
            Selected = ($age -ge $script:Cfg.StaleDays -and $rule.Risk -ne 'Careful')
        })
    }
    if (-not $script:Quiet) { Write-Progress -Activity 'Measuring build folders' -Completed }
    return @($out | Where-Object { $_.Bytes -gt 0 } | Sort-Object Bytes -Descending)
}

function Find-DuplicateFiles([string[]]$roots, [int]$minMB) {
    $job = [Reclaim.Engine]::StartDuplicates([string[]]$roots, [int64]($minMB * 1MB), [string[]]@($script:Cfg.DuplicateSkipDirs))
    $groups = Wait-EngineJob $job 'Finding duplicate files'
    return @($groups)
}

# Chooses which file of a duplicate group to keep. Strategy: oldest | newest | shortest
function Select-DuplicateKeeper($group, [string]$strategy) {
    $files = @($group.Files)
    switch ($strategy) {
        'newest'   { return ($files | Sort-Object LastWrite -Descending | Select-Object -First 1) }
        'shortest' { return ($files | Sort-Object { $_.Path.Length }, Path | Select-Object -First 1) }
        default    { return ($files | Sort-Object LastWrite, Path | Select-Object -First 1) }
    }
}
