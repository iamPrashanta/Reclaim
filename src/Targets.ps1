# Target catalog: loading, presets, measuring and cleaning.

$script:Groups = @('Windows', 'Browsers', 'Developer', 'Apps', 'GPU and drivers', 'Android and phones', 'System (admin)', 'Custom')

function Import-ReclaimTargets {
    $files = @(Join-Path $script:Root 'config\targets.psd1')
    $custom = Join-Path $script:Root 'config\custom-targets.psd1'
    if (Test-Path -LiteralPath $custom) { $files += $custom }
    $all = New-Object System.Collections.Generic.List[object]
    $ids = @{}
    foreach ($f in $files) {
        $data = Import-PowerShellDataFile -LiteralPath $f
        foreach ($t in $data.Targets) {
            if (-not $t.Id -or -not $t.Name) { throw "A target in $f has no Id or Name" }
            if ($ids.ContainsKey($t.Id)) { throw "Duplicate target id '$($t.Id)' in $f" }
            $ids[$t.Id] = $true
            if (@($script:Cfg.ExcludeTargets) -contains $t.Id) { continue }
            $o = [pscustomobject]@{
                Id            = [string]$t.Id
                Group         = $(if ($t.Group) { [string]$t.Group } else { 'Custom' })
                Name          = [string]$t.Name
                Risk          = $(if ($t.Risk) { [string]$t.Risk } else { 'Safe' })
                Admin         = [bool]$t.Admin
                Paths         = @($t.Paths | Where-Object { $_ })
                Mode          = $(if ($t.Mode) { [string]$t.Mode } else { 'Contents' })
                OlderThanDays = $(if ($t.OlderThanDays) { [int]$t.OlderThanDays } else { 0 })
                Processes     = @($t.Processes | Where-Object { $_ })
                Handler       = [string]$t.Handler
                Presets       = @($t.Presets | Where-Object { $_ })
                Recycle       = [bool]$t.Recycle
                MinDepth      = $(if ($t.MinDepth) { [int]$t.MinDepth } else { 3 })
                After         = [string]$t.After
            }
            if ($o.Risk -notin @('Safe', 'Moderate', 'Careful')) { throw "Target $($o.Id): Risk must be Safe, Moderate or Careful" }
            if ($o.Mode -notin @('Contents', 'Folder')) { throw "Target $($o.Id): Mode must be Contents or Folder" }
            if (-not $o.Handler -and $o.Paths.Count -eq 0) { throw "Target $($o.Id): needs Paths or a Handler" }
            if ($o.Handler -and -not $script:Handlers.ContainsKey($o.Handler)) { throw "Target $($o.Id): unknown handler '$($o.Handler)'" }
            $all.Add($o)
        }
    }
    return $all
}

function Test-InPreset($t, [string]$preset) {
    if ($t.Risk -eq 'Careful') { return $false }
    if ($t.Presets.Count -gt 0) { return ($t.Presets -contains $preset) }
    switch ($preset) {
        'Quick' { return ($t.Risk -eq 'Safe' -and -not $t.Admin) }
        'Dev'   { return (-not $t.Admin) }
        'Deep'  { return $true }
    }
    return $false
}

function Get-PresetTargets([string]$preset) {
    return @($script:Catalog | Where-Object { Test-InPreset $_ $preset })
}

function Get-TargetsById([string[]]$ids) {
    $out = @()
    foreach ($id in $ids) {
        $t = $script:Catalog | Where-Object { $_.Id -eq $id }
        if (-not $t) { throw "Unknown target id '$id'. Run: reclaim -List" }
        $out += $t
    }
    return $out
}

# Resolves the concrete paths of a target (wildcards expanded, guard applied).
function Resolve-TargetPaths($t) {
    $paths = @()
    foreach ($p in $t.Paths) {
        foreach ($x in (Expand-ReclaimPath $p)) {
            if (-not $x) { continue }
            if (Test-ProtectedPath $x) { Write-Log "Target $($t.Id): protected path skipped $x" 'WARN'; continue }
            $paths += $x
        }
    }
    return @($paths | Select-Object -Unique)
}

# Returns a row object: target + paths + size. Never deletes anything.
function Measure-Target($t) {
    $row = [pscustomobject]@{
        Target = $t; Id = $t.Id; Group = $t.Group; Name = $t.Name; Risk = $t.Risk; Admin = $t.Admin
        Paths = @(); Bytes = [int64]0; Files = [int64]0; Status = 'ready'; Note = ''; Selected = $false
        Freed = [int64]0; InUse = 0; Errors = 0; Result = ''
    }
    try {
        if ($t.Handler) {
            $m = & $script:Handlers[$t.Handler].Measure $t
            $row.Paths = @($m.Paths); $row.Bytes = [int64]$m.Bytes; $row.Note = [string]$m.Note
            if ($m.Status) { $row.Status = $m.Status }
        } else {
            $row.Paths = @(Resolve-TargetPaths $t)
            if ($row.Paths.Count -eq 0 -and $t.Admin -and -not $script:IsAdmin) { $row.Status = 'needs admin'; $row.Bytes = -1; $row.Note = 'size shown after restarting as administrator' }
            elseif ($row.Paths.Count -eq 0) { $row.Status = 'not found' }
            else {
                $s = Measure-ReclaimPath $row.Paths $t.OlderThanDays ("Measuring " + $t.Name)
                $row.Bytes = $s.Bytes; $row.Files = $s.Files
                if ($s.Errors -gt 0 -and $t.Admin -and -not $script:IsAdmin) { $row.Note = 'run as admin to see everything' }
            }
        }
        if ($row.Status -eq 'ready' -and $row.Bytes -eq 0 -and -not $t.Handler) { $row.Status = 'empty' }
        if ($t.Admin -and -not $script:IsAdmin -and $row.Status -eq 'ready') { $row.Status = 'needs admin' }
    } catch {
        $row.Status = 'error'; $row.Note = $_.Exception.Message
        Write-Log "Measure $($t.Id) failed: $($_.Exception.Message)" 'ERROR'
    }
    return $row
}

function Measure-Targets($targets) {
    $rows = New-Object System.Collections.Generic.List[object]
    $i = 0
    foreach ($t in $targets) {
        $i++
        if (-not $script:Quiet) {
            Write-Progress -Id 1 -Activity 'Scanning' -Status ("{0}/{1}  {2}" -f $i, $targets.Count, $t.Name) -PercentComplete ([int](100 * $i / [Math]::Max(1, $targets.Count)))
        }
        $rows.Add((Measure-Target $t))
    }
    if (-not $script:Quiet) { Write-Progress -Id 1 -Activity 'Scanning' -Completed }
    return $rows
}

# Asks what to do when a target's program is running. Returns $true to go ahead.
function Confirm-ProcessesClosed($t) {
    $running = Get-RunningProcess $t.Processes
    if ($running.Count -eq 0) { return $true }
    $names = $running -join ', '
    if ($script:NonInteractive) {
        if ($script:Force) { Write-Log "$($t.Id): $names running, cleaning anyway (-Force)"; return $true }
        Write-Log "$($t.Id): skipped because $names is running" 'WARN'
        return $false
    }
    while ($true) {
        Out-Line ("  {0} is running. Close it for the best result." -f $names) 'Yellow'
        $a = Read-Text 'Enter = I closed it, K = clean anyway (files in use are skipped), S = skip' ''
        if ($a -match '^[sS]') { return $false }
        if ($a -match '^[kK]') { return $true }
        $running = Get-RunningProcess $t.Processes
        if ($running.Count -eq 0) { return $true }
        $names = $running -join ', '
    }
}

# Cleans one measured row in place (fills Freed / InUse / Errors / Result).
function Invoke-TargetClean($row) {
    $t = $row.Target
    if ($t.Admin -and -not $script:IsAdmin) { $row.Result = 'skipped: needs admin'; return }
    if ($row.Status -in @('not found', 'empty', 'error', 'unavailable')) { $row.Result = 'nothing to do'; return }
    if (-not (Confirm-ProcessesClosed $t)) { $row.Result = 'skipped: program running'; return }
    $drive = $env:SystemDrive
    $first = @($row.Paths | Where-Object { $_ }) | Select-Object -First 1
    if ($first) { $drive = [IO.Path]::GetPathRoot([string]$first) }
    $freeBefore = Get-FreeBytes $drive
    try {
        if ($t.Handler) {
            $r = & $script:Handlers[$t.Handler].Clean $t $row
            $row.Freed = [int64]$r.Freed; $row.InUse = [int]$r.InUse; $row.Errors = [int]$r.Errors
            $row.Result = $(if ($r.Note) { [string]$r.Note } else { 'done' })
        } elseif ($t.Recycle) {
            $s = Send-ToRecycleBin $row.Paths
            $row.Freed = 0; $row.Errors = [int]$s.Errors
            $row.Result = '{0} sent to Recycle Bin ({1})' -f $s.DeletedFiles, (Format-Size $s.Bytes)
        } else {
            $s = Remove-ReclaimPath $row.Paths $t.Mode $t.OlderThanDays $t.MinDepth ('Cleaning ' + $t.Name)
            $row.Freed = [int64]$s.Bytes; $row.InUse = [int]$s.InUse; $row.Errors = [int]$s.Errors
            $row.Result = 'done'
            if ($s.InUse -gt 0) { $row.Result = 'done, {0} files in use were skipped' -f $s.InUse }
        }
        # handlers that run external tools (DISM, docker) report through the drive's free space
        if ($t.Handler -and $row.Freed -le 0 -and -not $script:DryRun) {
            $delta = (Get-FreeBytes $drive) - $freeBefore
            if ($delta -gt 0) { $row.Freed = $delta }
        }
    } catch {
        $row.Result = 'error: ' + $_.Exception.Message
        $row.Errors++
        Write-Log "Clean $($t.Id) failed: $($_.Exception.Message)" 'ERROR'
    }
    Write-Log ("Cleaned {0}: {1} ({2})" -f $t.Id, (Format-Size $row.Freed), $row.Result)
}
