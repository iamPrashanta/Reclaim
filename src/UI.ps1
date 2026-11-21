# Interactive console UI.

function Show-Banner {
    Out-Line ''
    Out-Part '  RECLAIM ' 'Green'; Out-Part $script:ReclaimVersion 'DarkGray'; Out-Line '   free up disk space on Windows, safely' 'Gray'
    $who = if ($script:IsAdmin) { 'administrator' } else { 'standard user (A = restart as administrator)' }
    Out-Part '  Running as: ' 'DarkGray'; Out-Part $who 'Gray'
    if ($script:DryRun) { Out-Part '   DRY RUN: nothing is deleted' 'Magenta' }
    Out-Line ''
    Out-Line ''
}

function Show-Drives {
    foreach ($d in (Get-FixedDrives)) {
        $usedPct = if ($d.Total -gt 0) { $d.Used / $d.Total } else { 0 }
        $width = 24
        $fill = [int][Math]::Round($usedPct * $width)
        $freePct = 1 - $usedPct
        $color = if ($freePct -lt 0.10) { 'Red' } elseif ($freePct -lt 0.20) { 'Yellow' } else { 'Green' }
        Out-Part ('  {0,-3} ' -f $d.Name) 'White'
        Out-Part '[' 'DarkGray'; Out-Part ('#' * $fill) $color; Out-Part ('-' * ($width - $fill)) 'DarkGray'; Out-Part '] ' 'DarkGray'
        Out-Part ('{0,10} free' -f (Format-Size $d.Free)) $color
        Out-Line ('  of {0}{1}' -f (Format-Size $d.Total), $(if ($d.Label) { "  ($($d.Label))" } else { '' })) 'DarkGray'
    }
    Out-Line ''
}

function Show-MenuItem([string]$key, [string]$title, [string]$hint) {
    Out-Part ('  {0,2}  ' -f $key) 'Cyan'; Out-Part ('{0,-24}' -f $title) 'White'; Out-Line $hint 'DarkGray'
}

# ------------------------------------------------------------------ generic picker
# items need .Selected and .Bytes. $line renders one row (string). $shortcuts: key -> @{ Label; Filter }
function Invoke-Picker($items, [string]$title, [scriptblock]$line, $shortcuts, [scriptblock]$info, [string]$header) {
    $page = 0; $size = 35
    while ($true) {
        $count = @($items).Count
        $pages = [Math]::Max(1, [Math]::Ceiling($count / $size))
        if ($page -ge $pages) { $page = $pages - 1 }
        Out-Line ''
        Out-Line ("  {0}" -f $title) 'White'
        if ($header) { Out-Line ('            ' + $header) 'DarkGray' }
        $from = $page * $size; $to = [Math]::Min($count, $from + $size) - 1
        $lastGroup = $null
        for ($i = $from; $i -le $to; $i++) {
            $it = $items[$i]
            if ($it.PSObject.Properties['Group'] -and $it.Group -ne $lastGroup) { Out-Line ("  -- {0}" -f $it.Group) 'DarkCyan'; $lastGroup = $it.Group }
            $mark = if ($it.Selected) { '[x]' } else { '[ ]' }
            Out-Part ('  {0,4} ' -f ($i + 1)) 'Cyan'
            Out-Part ($mark + ' ') $(if ($it.Selected) { 'Green' } else { 'DarkGray' })
            $text = & $line $it
            $rc = 'Gray'
            if ($it.PSObject.Properties['Risk']) { $rc = Get-RiskColor $it.Risk }
            if ($it.PSObject.Properties['Status'] -and $it.Status -notin @('ready')) { $rc = 'DarkGray' }
            Out-Line $text $rc
        }
        if ($pages -gt 1) { Out-Line ("  page {0}/{1}  (+ next, - previous)" -f ($page + 1), $pages) 'DarkGray' }
        $sel = @($items | Where-Object { $_.Selected })
        $bytes = [int64]0; foreach ($s in $sel) { if ($s.Bytes -gt 0) { $bytes += $s.Bytes } }
        Out-Line ''
        Out-Part '  Selected: ' 'Gray'; Out-Line ('{0} items, {1}' -f $sel.Count, (Format-Size $bytes)) 'Green'
        $keys = '1,3,5-8 toggle | a all | n none'
        if ($shortcuts) { foreach ($k in $shortcuts.Keys) { $keys += ' | {0} {1}' -f $k, $shortcuts[$k].Label } }
        if ($info) { $keys += ' | i 3 details' }
        Out-Line ("  $keys") 'DarkGray'
        Out-Line '  Enter = continue with the selection, b = back' 'DarkGray'
        $a = (Read-Host '  >').Trim()
        if ($a -eq '') { return $true }
        if ($a -match '^(b|q|back)$') { return $false }
        if ($a -eq '+') { $page++; continue }
        if ($a -eq '-') { if ($page -gt 0) { $page-- }; continue }
        if ($a -eq 'a') { foreach ($it in $items) { if (-not $it.PSObject.Properties['Status'] -or $it.Status -in @('ready', 'needs admin')) { $it.Selected = $true } }; continue }
        if ($a -eq 'n') { foreach ($it in $items) { $it.Selected = $false }; continue }
        if ($shortcuts -and $shortcuts.Contains($a)) {
            foreach ($it in $items) { $it.Selected = [bool](& $shortcuts[$a].Filter $it) }
            continue
        }
        if ($info -and $a -match '^i\s*(\d+)$') {
            $n = [int]$Matches[1]
            if ($n -ge 1 -and $n -le $count) { & $info $items[$n - 1]; Wait-AnyKey }
            continue
        }
        foreach ($n in (ConvertFrom-NumberList $a $count)) {
            $it = $items[$n - 1]
            if ($it.PSObject.Properties['Status'] -and $it.Status -notin @('ready', 'needs admin')) {
                Out-Line ("  #{0} cannot be selected: {1}" -f $n, $it.Status) 'Yellow'; continue
            }
            $it.Selected = -not $it.Selected
        }
    }
}

# ------------------------------------------------------------------ cleaning flow
function Format-TargetLine($r) {
    $size = if ($r.Bytes -lt 0) { '      ?' } else { Format-Size $r.Bytes }
    $flags = @()
    if ($r.Admin) { $flags += 'admin' }
    if ($r.Status -ne 'ready') { $flags += $r.Status }
    if ($r.Note) { $flags += $r.Note }
    $w = [Math]::Max(30, (Get-ConsoleWidth) - 50)
    return ('{0,10}  {1,-8}  {2}{3}' -f $size, $r.Risk, (Limit-Text $r.Name $w), $(if ($flags) { '  (' + ($flags -join ', ') + ')' } else { '' }))
}

function Show-TargetInfo($r) {
    $t = $r.Target
    Out-Line ''
    Out-Line ("  {0}  [{1}]" -f $t.Name, $t.Id) 'White'
    Out-Line ("  Risk: {0}   Needs admin: {1}   Mode: {2}{3}" -f $t.Risk, $(if ($t.Admin) { 'yes' } else { 'no' }), $t.Mode,
        $(if ($t.OlderThanDays) { "   Only files older than $($t.OlderThanDays) days" } else { '' })) (Get-RiskColor $t.Risk)
    if ($t.Processes.Count) { Out-Line ("  Close first: {0}" -f ($t.Processes -join ', ')) 'Gray' }
    Out-Line ("  After cleaning: {0}" -f $t.After) 'Gray'
    if ($t.Recycle) { Out-Line '  Goes to the Recycle Bin (can be restored).' 'Gray' }
    Out-Line '  Paths:' 'Gray'
    foreach ($p in $r.Paths) { Out-Line ("    {0}" -f $p) 'DarkGray' }
    if (-not $r.Paths.Count) { Out-Line '    (none found on this PC)' 'DarkGray' }
}

function Restart-Elevated([string]$arguments) {
    $ps = (Get-Process -Id $PID).Path
    $file = Join-Path $script:Root 'Reclaim.ps1'
    $argLine = '-NoProfile -ExecutionPolicy Bypass -File "{0}" {1}' -f $file, $arguments
    try {
        Start-Process -FilePath $ps -Verb RunAs -ArgumentList $argLine | Out-Null
        return $true
    } catch {
        Out-Line '  Administrator start was cancelled.' 'Yellow'
        return $false
    }
}

function Invoke-CleanRows($rows, [string]$preset) {
    $sel = @($rows | Where-Object { $_.Selected })
    if ($sel.Count -eq 0) { Out-Line '  Nothing selected.' 'Yellow'; return $null }
    $run = [pscustomobject]@{ Started = Get-Date; Finished = $null; Preset = $preset; DryRun = [bool]$script:DryRun; Admin = $script:IsAdmin
        DrivesBefore = Get-DriveSnapshot; DrivesAfter = $null; Items = $sel; Freed = [int64]0 }
    Out-Line ''
    $n = 0
    foreach ($r in $sel) {
        $n++
        Out-Part ('  [{0}/{1}] ' -f $n, $sel.Count) 'DarkGray'; Out-Line $r.Name 'White'
        Invoke-TargetClean $r
        $c = if ($r.Result -match '^(skipped|error)') { 'Yellow' } else { 'Green' }
        Out-Line ('          {0}{1}   {2}' -f $(if ($script:DryRun) { 'would free ' } else { 'freed ' }), (Format-Size $r.Freed), $r.Result) $c
        $run.Freed += [int64]$r.Freed
    }
    $run.Finished = Get-Date
    $run.DrivesAfter = Get-DriveSnapshot
    Out-Line ''
    Out-Part '  Total ' 'White'; Out-Part $(if ($script:DryRun) { 'that would be freed: ' } else { 'freed: ' }) 'White'
    Out-Line (Format-Size $run.Freed) 'Green'
    foreach ($b in $run.DrivesBefore) {
        $a = $run.DrivesAfter | Where-Object { $_.Drive -eq $b.Drive }
        if ($a -and $a.Free -ne $b.Free) { Out-Line ('  {0} free space: {1} -> {2}' -f $b.Drive, (Format-Size $b.Free), (Format-Size $a.Free)) 'Gray' }
    }
    if (-not $script:NoReport) {
        $path = Save-CleanReport $run
        Out-Line ("  Report: {0}" -f $path) 'DarkGray'
        $script:LastReport = $path
    }
    return $run
}

# Splits admin rows when not elevated. Returns 'go', 'back' or 'elevated'.
function Resolve-AdminRows($rows) {
    $need = @($rows | Where-Object { $_.Selected -and $_.Admin })
    if ($need.Count -eq 0 -or $script:IsAdmin) { return 'go' }
    Out-Line ''
    Out-Line ("  {0} selected item(s) need administrator rights: {1}" -f $need.Count, (($need | ForEach-Object { $_.Name }) -join ', ')) 'Yellow'
    $a = Read-Text 'E = restart as administrator and clean everything selected, S = skip those, B = back' 'E'
    if ($a -match '^[bB]') { return 'back' }
    if ($a -match '^[sS]') { foreach ($r in $need) { $r.Selected = $false }; return 'go' }
    $ids = (@($rows | Where-Object { $_.Selected }) | ForEach-Object { $_.Id }) -join ','
    $extra = "-Clean -Targets $ids -Yes -Pause"
    if ($script:DryRun) { $extra += ' -DryRun' }
    if (Restart-Elevated $extra) { Out-Line '  Cleaning continues in the administrator window.' 'Cyan'; return 'elevated' }
    return 'back'
}

function Confirm-Selection($rows) {
    $sel = @($rows | Where-Object { $_.Selected })
    if ($sel.Count -eq 0) { return $false }
    $bytes = [int64]0; foreach ($s in $sel) { if ($s.Bytes -gt 0) { $bytes += $s.Bytes } }
    $careful = @($sel | Where-Object { $_.Risk -eq 'Careful' })
    $moderate = @($sel | Where-Object { $_.Risk -eq 'Moderate' })
    Out-Line ''
    Out-Line ("  Ready to clean {0} items, about {1}{2}." -f $sel.Count, (Format-Size $bytes), $(if ($script:DryRun) { ' (dry run, nothing is deleted)' } else { '' })) 'White'
    foreach ($m in $moderate) { Out-Line ("   ~ {0}: {1}" -f $m.Name, $m.Target.After) 'Yellow' }
    foreach ($c in $careful) { Out-Line ("   ! {0}: {1}" -f $c.Name, $c.Target.After) 'Red' }
    if ($careful.Count -gt 0 -and -not $script:DryRun) { return (Read-TypedConfirm 'YES') }
    return (Read-YesNo 'Clean now?' ($moderate.Count -eq 0))
}

function Invoke-InteractiveClean($targets, [string]$title, [string]$preset, [switch]$PreselectAll) {
    $rows = Measure-Targets $targets
    foreach ($r in $rows) {
        $r.Selected = ($r.Status -in @('ready', 'needs admin')) -and ($r.Bytes -ne 0) -and ($PreselectAll -or (Test-InPreset $r.Target 'Quick'))
    }
    $rows = @($rows | Sort-Object @{ e = { [array]::IndexOf($script:Groups, $_.Group) } }, @{ e = { $_.Bytes }; Descending = $true })
    $visible = @($rows | Where-Object { $_.Status -notin @('not found', 'empty') })
    $hidden = $rows.Count - $visible.Count
    if ($visible.Count -eq 0) { Out-Line '  Nothing to clean here. Everything is already clean.' 'Green'; Wait-AnyKey; return }
    $shortcuts = [ordered]@{
        's' = @{ Label = 'Safe only'; Filter = { param($r) $r.Risk -eq 'Safe' -and $r.Status -in @('ready', 'needs admin') } }
        'm' = @{ Label = 'Safe + Moderate'; Filter = { param($r) $r.Risk -ne 'Careful' -and $r.Status -in @('ready', 'needs admin') } }
    }
    $header = '     Size  Risk      Item'
    $t = '{0}  ({1} more not present on this PC)' -f $title, $hidden
    while ($true) {
        $go = Invoke-Picker $visible $t ${function:Format-TargetLine} $shortcuts ${function:Show-TargetInfo} $header
        if (-not $go) { return }
        $adm = Resolve-AdminRows $visible
        if ($adm -eq 'back') { continue }
        if ($adm -eq 'elevated') { Wait-AnyKey; return }
        if (-not (Confirm-Selection $visible)) { Out-Line '  Cancelled.' 'Yellow'; continue }
        Invoke-CleanRows $visible $preset | Out-Null
        Wait-AnyKey
        return
    }
}

# ------------------------------------------------------------------ space hogs
function Read-ScanRoot {
    $drives = @(Get-FixedDrives)
    Out-Line ''
    for ($i = 0; $i -lt $drives.Count; $i++) { Out-Line ('  {0}  {1}  {2} used, {3} free' -f ($i + 1), $drives[$i].Name, (Format-Size $drives[$i].Used), (Format-Size $drives[$i].Free)) 'Gray' }
    $a = Read-Text 'Drive number, or a folder path (for example C:\Users)' '1'
    if ($a -match '^\d+$' -and [int]$a -ge 1 -and [int]$a -le $drives.Count) { return ($drives[[int]$a - 1].Name + '\') }
    if ($a -match '^[a-zA-Z]:?$') { return ($a.Substring(0, 1).ToUpper() + ':\') }
    if (Test-Path -LiteralPath $a -PathType Container) { return $a }
    Out-Line '  Not found.' 'Yellow'
    return $null
}

function Invoke-SpaceHogsMenu([string]$root) {
    if (-not $root) { $root = Read-ScanRoot }
    if (-not $root) { return }
    if (-not $script:IsAdmin -and $root.Length -le 3) { Out-Line '  Tip: run as administrator to see inside system folders too.' 'DarkGray' }
    $scan = Invoke-SpaceScan $root
    $report = if (-not $script:NoReport) { Save-ScanReport $scan } else { $null }
    while ($true) {
        $w = Get-ConsoleWidth
        Out-Line ''
        Out-Line ('  {0}: {1} in {2:N0} files ({3:N0} folders could not be read)' -f $scan.Root, (Format-Size $scan.Total), $scan.Files, $scan.Errors) 'White'
        Out-Line ('  Not changed for {0}+ days: {1}' -f $scan.OldDays, (Format-Size $scan.OldBytes)) 'DarkGray'
        Out-Line ''
        Out-Line '  Biggest folders' 'Cyan'
        $folders = @($scan.Folders | Select-Object -First 25)
        $max = if ($folders.Count) { [double]$folders[0].Bytes } else { 1 }
        for ($i = 0; $i -lt $folders.Count; $i++) {
            $f = $folders[$i]
            $bar = '#' * [int][Math]::Max(1, [Math]::Round(12 * $f.Bytes / [Math]::Max([double]1, [double]$max)))
            Out-Part ('  d{0,-3}' -f ($i + 1)) 'Cyan'
            Out-Part ('{0,10} {1,-12} ' -f (Format-Size $f.Bytes), $bar) 'Gray'
            Out-Part (Limit-Text $f.Relative ($w - 45)) 'White'
            if ($f.Known) { Out-Line ('  [clean: {0}]' -f $f.Known) 'Green' } else { Out-Line '' }
        }
        Out-Line ''
        Out-Line ('  Biggest files (over {0} MB)' -f $script:Cfg.LargeFileMinMB) 'Cyan'
        $files = @($scan.TopFiles)
        for ($i = 0; $i -lt [Math]::Min(20, $files.Count); $i++) {
            $f = $files[$i]
            Out-Part ('  {0,-4}' -f ($i + 1)) 'Cyan'
            Out-Line ('{0,10}  {1:yyyy-MM-dd}  {2}' -f (Format-Size $f.Bytes), $f.LastWrite, (Limit-Text $f.Path ($w - 34))) 'Gray'
        }
        Out-Line ''
        Out-Line ('  By type: ' + (($scan.Extensions | Select-Object -First 8 | ForEach-Object { '{0} {1}' -f $_.Ext, (Format-Size $_.Bytes) }) -join ' | ')) 'DarkGray'
        if ($report) { Out-Line ("  Full report: {0}" -f $report) 'DarkGray' }
        Out-Line ''
        Out-Line '  s d3 = scan folder d3 | o 2 / o d3 = open in Explorer | r 1,4 = send files to Recycle Bin | h = open report | Enter = back' 'DarkGray'
        $a = (Read-Host '  >').Trim()
        if ($a -eq '') { return }
        if ($a -eq 'h' -and $report) { Start-Process $report; continue }
        if ($a -match '^s\s*d(\d+)$') { $n = [int]$Matches[1]; if ($n -le $folders.Count) { Invoke-SpaceHogsMenu $folders[$n - 1].Path }; continue }
        if ($a -match '^o\s*d(\d+)$') { $n = [int]$Matches[1]; if ($n -le $folders.Count) { Start-Process explorer.exe $folders[$n - 1].Path }; continue }
        if ($a -match '^o\s*(\d+)$') { $n = [int]$Matches[1]; if ($n -le $files.Count) { Start-Process explorer.exe ('/select,"{0}"' -f $files[$n - 1].Path) }; continue }
        if ($a -match '^r\s*(.+)$') {
            $nums = ConvertFrom-NumberList $Matches[1] ([Math]::Min(20, $files.Count))
            if (-not $nums) { continue }
            $pick = @($nums | ForEach-Object { $files[$_ - 1] })
            foreach ($p in $pick) { Out-Line ('   {0}  {1}' -f (Format-Size $p.Bytes), $p.Path) 'Yellow' }
            if (Read-YesNo ('Send these {0} files to the Recycle Bin?' -f $pick.Count) $false) {
                $s = Send-ToRecycleBin @($pick | ForEach-Object { $_.Path })
                Out-Line ('  {0} files moved to the Recycle Bin ({1}). Empty the bin to get the space back.' -f $s.DeletedFiles, (Format-Size $s.Bytes)) 'Green'
                $scan.TopFiles = @($scan.TopFiles | Where-Object { Test-Path -LiteralPath $_.Path })
            }
        }
    }
}

# ------------------------------------------------------------------ old project folders
function Read-DevRoots {
    $state = Get-State
    $def = @()
    if ($state['DevRoots']) { $def = @($state['DevRoots']) } elseif ($script:Cfg.DevRoots) { $def = @($script:Cfg.DevRoots) }
    $a = Read-Text 'Code folders to search, separated by ;' ($def -join ';')
    $roots = @($a -split ';' | ForEach-Object { $_.Trim().Trim('"') } | Where-Object { $_ -and (Test-Path -LiteralPath $_ -PathType Container) })
    if ($roots.Count) { Set-StateValue 'DevRoots' $roots }
    return $roots
}

function Invoke-DevFoldersMenu([string[]]$roots) {
    if (-not $roots) { $roots = Read-DevRoots }
    if (-not $roots) { Out-Line '  No existing folder given.' 'Yellow'; Wait-AnyKey; return }
    $all = Find-DevArtifacts $roots
    $items = @($all | Where-Object { $_.Bytes -ge 1MB })
    if ($all.Count -gt $items.Count) { Out-Line ('  {0} build folders under 1 MB are not listed.' -f ($all.Count - $items.Count)) 'DarkGray' }
    if (-not $items.Count) { Out-Line '  No build folders found.' 'Green'; Wait-AnyKey; return }
    $total = [int64]0; $stale = [int64]0
    foreach ($i in $items) { $total += $i.Bytes; if ($i.Selected) { $stale += $i.Bytes } }
    Out-Line ''
    Out-Line ('  Found {0} build folders, {1} in total. {2} belong to projects untouched for {3}+ days (preselected).' -f $items.Count, (Format-Size $total), (Format-Size $stale), $script:Cfg.StaleDays) 'White'
    $line = {
        param($i)
        $w = [Math]::Max(30, (Get-ConsoleWidth) - 58)
        '{0,10}  {1,5}d  {2,-8}  {3,-20} {4}' -f (Format-Size $i.Bytes), $(if ($i.AgeDays -ge 9999) { '?' } else { $i.AgeDays }), $i.Risk, (Limit-Text $i.Kind 20), (Limit-Text $i.Path $w)
    }
    $shortcuts = [ordered]@{
        's' = @{ Label = ('stale (' + $script:Cfg.StaleDays + '+ days)'); Filter = { param($i) $i.AgeDays -ge $script:Cfg.StaleDays -and $i.Risk -ne 'Careful' } }
        'nm' = @{ Label = 'node_modules only'; Filter = { param($i) $i.Name -eq 'node_modules' } }
    }
    $info = { param($i) Out-Line ''; Out-Line ('  {0}' -f $i.Path) 'White'; Out-Line ('  Project: {0}' -f $i.Project) 'Gray'
        Out-Line ('  Last change in project: {0}' -f $i.LastActive) 'Gray'; Out-Line ('  Restore with: {0}' -f $i.Restore) 'Gray' }
    $go = Invoke-Picker $items 'Build folders (age = days since the project last changed)' $line $shortcuts $info '      Size    Age  Risk      Kind                 Path'
    if (-not $go) { return }
    $sel = @($items | Where-Object { $_.Selected })
    if (-not $sel.Count) { return }
    $bytes = [int64]0; foreach ($s in $sel) { $bytes += $s.Bytes }
    Out-Line ('  Delete {0} build folders ({1})? They are rebuilt by the commands shown with i <number>.' -f $sel.Count, (Format-Size $bytes)) 'White'
    $careful = @($sel | Where-Object { $_.Risk -eq 'Careful' })
    $ok = if ($careful.Count -and -not $script:DryRun) { Out-Line ('  Includes {0} Python virtualenvs.' -f $careful.Count) 'Red'; Read-TypedConfirm 'YES' } else { Read-YesNo 'Delete now?' $true }
    if (-not $ok) { return }
    $freed = [int64]0; $n = 0
    $before = Get-DriveSnapshot
    $started = Get-Date
    foreach ($s in $sel) {
        $n++
        $r = Remove-ReclaimPath @($s.Path) 'Folder' 0 3 ('[{0}/{1}] {2}' -f $n, $sel.Count, $s.Path)
        $freed += $r.Bytes
    }
    Out-Line ('  {0} {1}' -f $(if ($script:DryRun) { 'Would free' } else { 'Freed' }), (Format-Size $freed)) 'Green'
    if (-not $script:NoReport) {
        $rows = @($sel | ForEach-Object { [pscustomobject]@{ Id = $_.Name; Name = ('{0} ({1})' -f $_.Path, $_.Kind); Group = 'Old project folders'
            Risk = $_.Risk; Bytes = $_.Bytes; Freed = $_.Bytes; InUse = 0; Errors = 0; Result = ('restore: ' + $_.Restore); Paths = @($_.Path) } })
        $run = [pscustomobject]@{ Started = $started; Finished = Get-Date; Preset = 'Old project folders'; DryRun = [bool]$script:DryRun
            Admin = $script:IsAdmin; DrivesBefore = $before; DrivesAfter = Get-DriveSnapshot; Items = $rows; Freed = $freed }
        $p = Save-CleanReport $run
        Out-Line ("  Report: {0}" -f $p) 'DarkGray'
    }
    Wait-AnyKey
}

# ------------------------------------------------------------------ duplicates
function Invoke-DuplicatesMenu([string[]]$roots) {
    if (-not $roots) {
        $def = @("$env:USERPROFILE\Downloads", "$env:USERPROFILE\Documents", "$env:USERPROFILE\Pictures", "$env:USERPROFILE\Videos", "$env:USERPROFILE\Desktop") | Where-Object { Test-Path -LiteralPath $_ }
        $state = Get-State
        if ($state['DupRoots']) { $def = @($state['DupRoots']) }
        $a = Read-Text 'Folders to compare, separated by ;' ($def -join ';')
        $roots = @($a -split ';' | ForEach-Object { $_.Trim().Trim('"') } | Where-Object { $_ -and (Test-Path -LiteralPath $_ -PathType Container) })
        if (-not $roots) { return }
        Set-StateValue 'DupRoots' $roots
    }
    $min = [int](Read-Text 'Ignore files smaller than (MB)' ([string]$script:Cfg.DuplicateMinMB))
    $groups = Find-DuplicateFiles $roots $min
    if (-not $groups.Count) { Out-Line '  No duplicate files found.' 'Green'; Wait-AnyKey; return }
    $strategy = 'oldest'
    $items = foreach ($g in $groups) { [pscustomobject]@{ Group_ = $g; Bytes = [int64]$g.Wasted; Selected = $true; Keep = $null } }
    $items = @($items)
    $setKeep = { foreach ($i in $items) { $i.Keep = Select-DuplicateKeeper $i.Group_ $strategy } }
    & $setKeep
    $wasted = [int64]0; foreach ($i in $items) { $wasted += $i.Bytes }
    Out-Line ''
    Out-Line ('  {0} groups of identical files (SHA-256), {1} could be freed.' -f $items.Count, (Format-Size $wasted)) 'White'
    $line = { param($i) $w = [Math]::Max(30, (Get-ConsoleWidth) - 40); '{0,10}  x{1}  {2}' -f (Format-Size $i.Bytes), $i.Group_.Files.Count, (Limit-Text $i.Keep.Path $w) }
    $info = { param($i)
        Out-Line ''
        foreach ($f in $i.Group_.Files) {
            $k = if ($f.Path -eq $i.Keep.Path) { 'KEEP  ' } else { 'remove' }
            Out-Line ('  {0}  {1:yyyy-MM-dd}  {2}' -f $k, $f.LastWrite, $f.Path) $(if ($k -eq 'KEEP  ') { 'Green' } else { 'Yellow' })
        } }
    while ($true) {
        $go = Invoke-Picker $items ('Duplicate groups (keeping the {0} copy; i 3 shows all copies)' -f $strategy) $line $null $info '      Free   Copies  Kept file'
        if (-not $go) { return }
        $k = Read-Text 'Keep which copy: o = oldest, n = newest, s = shortest path, Enter = keep current choice' ''
        if ($k -eq 'o') { $strategy = 'oldest'; & $setKeep; continue }
        if ($k -eq 'n') { $strategy = 'newest'; & $setKeep; continue }
        if ($k -eq 's') { $strategy = 'shortest'; & $setKeep; continue }
        break
    }
    $remove = @()
    foreach ($i in ($items | Where-Object { $_.Selected })) { foreach ($f in $i.Group_.Files) { if ($f.Path -ne $i.Keep.Path) { $remove += $f.Path } } }
    if (-not $remove.Count) { return }
    $how = Read-Text ('{0} files. R = send to Recycle Bin (default), D = delete permanently' -f $remove.Count) 'R'
    if ($how -match '^[dD]') {
        if (-not (Read-TypedConfirm 'DELETE')) { return }
        $freed = [int64]0
        foreach ($p in $remove) { $freed += (Remove-ReclaimPath @($p) 'Folder' 0 3 'Deleting duplicates').Bytes }
        Out-Line ('  Deleted, freed {0}.' -f (Format-Size $freed)) 'Green'
    } else {
        $s = Send-ToRecycleBin $remove
        Out-Line ('  {0} files moved to the Recycle Bin ({1}). Empty the bin to get the space back.' -f $s.DeletedFiles, (Format-Size $s.Bytes)) 'Green'
    }
    Wait-AnyKey
}

# ------------------------------------------------------------------ virtual disks
function Invoke-VirtualDisksMenu {
    $disks = @(Get-VirtualDisks)
    Out-Line ''
    if (-not $disks.Count) { Out-Line '  No WSL or Docker virtual disks found.' 'Green'; Wait-AnyKey; return }
    Out-Line '  WSL and Docker store Linux files in .vhdx disks that grow but never shrink by themselves.' 'Gray'
    Out-Line '  Compacting gives the free space inside them back to Windows. WSL and Docker are stopped first.' 'Gray'
    $items = @($disks | ForEach-Object { $_ | Add-Member -NotePropertyName Selected -NotePropertyValue $true -PassThru -Force })
    $line = { param($d) '{0,10}  {1,-7} {2,-28} {3}' -f (Format-Size $d.Bytes), $d.Kind, (Limit-Text $d.Name 28), (Limit-Text $d.Path 60) }
    $go = Invoke-Picker $items 'Virtual disks' $line $null $null '      Size  Kind    Name                         File'
    if (-not $go) { return }
    $sel = @($items | Where-Object { $_.Selected })
    if (-not $sel.Count) { return }
    if (-not $script:IsAdmin) {
        Out-Line '  Compacting needs administrator rights.' 'Yellow'
        if (Read-YesNo 'Restart as administrator and open this menu?' $true) { if (Restart-Elevated '-Menu disks -Pause') { exit 0 } }
        return
    }
    if (Get-RunningProcess @('Docker Desktop')) { Out-Line '  Docker Desktop is running: quit it from the tray icon first.' 'Yellow'; if (-not (Read-YesNo 'Continue anyway?' $false)) { return } }
    $trim = Read-YesNo 'Run fstrim inside each WSL distro first (recommended, frees more)?' $true
    if (-not (Read-YesNo ('WSL will be shut down now (running Linux programs stop). Compact {0} disk(s)?' -f $sel.Count) $true)) { return }
    $res = Compress-VirtualDisks $sel -Trim:$trim
    $freed = [int64]0
    foreach ($r in $res) {
        $d = $r.Before - $r.After; if ($d -gt 0) { $freed += $d }
        Out-Line ('  {0,-28} {1} -> {2}  ({3})' -f (Limit-Text $r.Disk.Name 28), (Format-Size $r.Before), (Format-Size $r.After), $r.Result) 'Green'
    }
    Out-Line ('  Freed {0}.' -f (Format-Size $freed)) 'Green'
    $distros = @($sel | Where-Object { $_.Distro })
    if ($distros.Count -and (Read-YesNo 'Make WSL disks shrink automatically from now on (sparse mode, WSL 2.0+)?' $false)) {
        foreach ($d in $distros) { Invoke-WslCommand @('--manage', $d.Distro, '--set-sparse', 'true') | ForEach-Object { Out-Line ('  ' + $_) 'Gray' } }
    }
    Wait-AnyKey
}

# ------------------------------------------------------------------ system options
function Invoke-SystemMenu {
    while ($true) {
        Out-Line ''
        Out-Line '  System options' 'White'
        $big = Get-BigSystemFiles
        foreach ($b in $big) { Out-Line ('     {0,-14} {1,10}' -f $b.Name, (Format-Size $b.Bytes)) 'DarkGray' }
        Out-Line ''
        Show-MenuItem '1' 'Hibernation file' 'shrink it (keeps Fast Startup) or turn hibernation off'
        Show-MenuItem '2' 'Page file' 'see how big it is and what is safe'
        Show-MenuItem '3' 'Restore points' 'space used by System Restore'
        Show-MenuItem '4' 'Compact OS' 'compress Windows files (saves 2-4 GB, admin)'
        Show-MenuItem '5' 'Component store' 'analyse WinSxS with DISM (admin)'
        Show-MenuItem '6' 'Storage Sense' 'open Windows automatic cleanup settings'
        Show-MenuItem '7' 'Disk Cleanup' 'open the classic Windows Disk Cleanup'
        Out-Line '     Enter = back' 'DarkGray'
        $a = (Read-Host '  >').Trim()
        switch ($a) {
            '' { return }
            '1' {
                $h = Get-HibernationInfo
                Out-Line ('  Hibernation: {0}, type {1}, hiberfil.sys {2}' -f $(if ($h.Enabled) { 'on' } else { 'off' }), $h.Type, (Format-Size $h.Bytes)) 'Gray'
                Out-Line '  r = reduced (about half the size, keeps Fast Startup, no Hibernate in the power menu)' 'DarkGray'
                Out-Line '  o = off (removes the file, also turns off Fast Startup)   f = full (default Windows setting)' 'DarkGray'
                $c = Read-Text 'Choice (Enter = no change)' ''
                $map = @{ 'r' = 'reduced'; 'o' = 'off'; 'f' = 'full' }
                if ($map.ContainsKey($c)) {
                    if (-not $script:IsAdmin) { Out-Line '  Needs administrator: use A in the main menu.' 'Yellow' }
                    else { Set-Hibernation $map[$c]; $h = Get-HibernationInfo; Out-Line ('  hiberfil.sys is now {0}' -f (Format-Size $h.Bytes)) 'Green' }
                }
                Wait-AnyKey
            }
            '2' {
                foreach ($p in (Get-PageFileInfo)) {
                    Out-Line ('  {0}: {1} MB allocated, {2} MB in use, peak {3} MB. RAM {4} GB. Managed by Windows: {5}' -f $p.Path, $p.AllocatedMB, $p.CurrentMB, $p.PeakMB, $p.RamGB, $p.Automatic) 'Gray'
                }
                Out-Line '  Keep the page file on and managed by Windows. If C: is small, add a page file on another' 'DarkGray'
                Out-Line '  drive in System > About > Advanced system settings > Performance > Advanced > Virtual memory.' 'DarkGray'
                Wait-AnyKey
            }
            '3' {
                if ($script:IsAdmin) { & vssadmin.exe list shadowstorage | Out-Host } else { Out-Line '  Run as administrator to see restore point storage.' 'Yellow' }
                if (Read-YesNo 'Open System Protection settings?' $false) { Start-Process SystemPropertiesProtection.exe }
            }
            '4' {
                $q = (& compact.exe /compactos:query 2>&1 | Out-String).Trim()
                Out-Line ('  ' + ($q -replace "`r?`n", "`n  ")) 'Gray'
                if ($script:IsAdmin -and (Read-YesNo 'Turn Compact OS on now (takes 10-20 minutes, safe, reversible)?' $false)) {
                    if ($script:DryRun) { Out-Line '  Dry run: not started.' 'Magenta' } else { & compact.exe /compactos:always | Out-Host }
                }
                Wait-AnyKey
            }
            '5' {
                if ($script:IsAdmin) { & dism.exe /Online /Cleanup-Image /AnalyzeComponentStore | Out-Host } else { Out-Line '  Needs administrator.' 'Yellow' }
                Wait-AnyKey
            }
            '6' { Start-Process 'ms-settings:storagesense' }
            '7' { Start-Process cleanmgr.exe }
        }
    }
}

# ------------------------------------------------------------------ move caches off C:
$script:Relocations = @(
    @{ Name = 'npm cache';            Var = 'npm_config_cache';         Default = '%LOCALAPPDATA%\npm-cache';        Folder = 'npm-cache' }
    @{ Name = 'Yarn cache';           Var = 'YARN_CACHE_FOLDER';        Default = '%LOCALAPPDATA%\Yarn\Cache';       Folder = 'yarn-cache' }
    @{ Name = 'pip cache';            Var = 'PIP_CACHE_DIR';            Default = '%LOCALAPPDATA%\pip\Cache';        Folder = 'pip-cache' }
    @{ Name = 'uv cache';             Var = 'UV_CACHE_DIR';             Default = '%LOCALAPPDATA%\uv\cache';         Folder = 'uv-cache' }
    @{ Name = 'NuGet packages';       Var = 'NUGET_PACKAGES';           Default = '%USERPROFILE%\.nuget\packages';   Folder = 'nuget-packages' }
    @{ Name = 'Gradle home';          Var = 'GRADLE_USER_HOME';         Default = '%USERPROFILE%\.gradle';           Folder = 'gradle'; Keep = @('gradle.properties', 'init.d') }
    @{ Name = 'Puppeteer browsers';   Var = 'PUPPETEER_CACHE_DIR';      Default = '%USERPROFILE%\.cache\puppeteer';  Folder = 'puppeteer' }
    @{ Name = 'Playwright browsers';  Var = 'PLAYWRIGHT_BROWSERS_PATH'; Default = '%LOCALAPPDATA%\ms-playwright';    Folder = 'ms-playwright' }
    @{ Name = 'Hugging Face models';  Var = 'HF_HOME';                  Default = '%USERPROFILE%\.cache\huggingface'; Folder = 'huggingface' }
)

function Invoke-RelocateMenu {
    $drives = @(Get-FixedDrives | Where-Object { $_.Name -ne $env:SystemDrive })
    Out-Line ''
    Out-Line '  Point developer caches to another drive, so they stop filling C:. This sets a user environment' 'Gray'
    Out-Line '  variable for each one; programs started afterwards use the new place. The old cache is deleted.' 'Gray'
    if (-not $drives.Count) { Out-Line '  There is no other fixed drive.' 'Yellow'; Wait-AnyKey; return }
    $target = Read-Text 'New base folder' ('{0}\DevCache' -f $drives[0].Name)
    if ($target -notmatch '^[a-zA-Z]:\\') { Out-Line '  Use a full path like D:\DevCache' 'Yellow'; return }
    $items = foreach ($r in $script:Relocations) {
        $cur = [Environment]::GetEnvironmentVariable($r.Var, 'User')
        $old = if ($cur) { $cur } else { Expand-EnvPath $r.Default }
        $size = if (Test-Path -LiteralPath $old) { (Measure-ReclaimPath @($old) 0 ('Measuring ' + $r.Name)).Bytes } else { 0 }
        [pscustomobject]@{ Name = $r.Name; Var = $r.Var; Current = $old; New = (Join-Path $target $r.Folder); Bytes = [int64]$size
            Selected = (-not $cur) -and $old.StartsWith($env:SystemDrive, [StringComparison]::OrdinalIgnoreCase); Keep = $r.Keep; IsSet = [bool]$cur }
    }
    $items = @($items)
    $line = { param($i) '{0,10}  {1,-20} {2,-26} -> {3}{4}' -f (Format-Size $i.Bytes), $i.Name, $i.Var, $i.New, $(if ($i.IsSet) { '  (already set: ' + $i.Current + ')' } else { '' }) }
    if (-not (Invoke-Picker $items 'Caches to move' $line $null $null '      Size  Cache                Variable                      New folder')) { return }
    $sel = @($items | Where-Object { $_.Selected })
    if (-not $sel.Count -or -not (Read-YesNo ('Move {0} caches to {1}?' -f $sel.Count, $target) $true)) { return }
    foreach ($i in $sel) {
        if ($script:DryRun) { Out-Line ('  Dry run: would set {0}={1}' -f $i.Var, $i.New) 'Magenta'; continue }
        New-Item -ItemType Directory -Path $i.New -Force | Out-Null
        foreach ($k in @($i.Keep)) {
            if (-not $k) { continue }
            $src = Join-Path $i.Current $k
            if (Test-Path -LiteralPath $src) { Copy-Item -LiteralPath $src -Destination $i.New -Recurse -Force }
        }
        [Environment]::SetEnvironmentVariable($i.Var, $i.New, 'User')
        Write-Log "Relocated $($i.Name): $($i.Var)=$($i.New)"
        if ((Test-Path -LiteralPath $i.Current) -and -not (Test-ProtectedPath $i.Current)) {
            $s = Remove-ReclaimPath @($i.Current) 'Contents' 0 3 ('Removing old ' + $i.Name)
            Out-Line ('  {0}: now in {1}, freed {2} on C:' -f $i.Name, $i.New, (Format-Size $s.Bytes)) 'Green'
        } else {
            Out-Line ('  {0}: now in {1}' -f $i.Name, $i.New) 'Green'
        }
    }
    Out-Line '  Close and reopen terminals and editors so they pick up the new locations.' 'Cyan'
    Wait-AnyKey
}

# ------------------------------------------------------------------ schedule, reports, tips
function Invoke-ScheduleMenu {
    while ($true) {
        Out-Line ''
        Out-Line '  Scheduled tasks' 'White'
        $s = @(Get-ReclaimSchedule)
        if (-not $s.Count) { Out-Line '     none yet' 'DarkGray' }
        foreach ($t in $s) { Out-Line ('     {0}  [{1}]  next: {2}  last result: {3}' -f $t.Name, $t.State, $t.NextRun, $t.LastResult) 'Gray' }
        Out-Line ''
        Show-MenuItem '1' 'Weekly quick clean' 'Sundays: safe caches and temp files, no admin, runs hidden'
        Show-MenuItem '2' 'Low space alert' ('daily + at sign-in: a notification when a drive has under {0} GB free' -f $script:Cfg.LowSpaceGB)
        Show-MenuItem '3' 'Remove' 'remove both scheduled tasks'
        Out-Line '     Enter = back' 'DarkGray'
        $a = (Read-Host '  >').Trim()
        try {
            switch ($a) {
                '' { return }
                '1' { $at = Read-Text 'Time (HH:mm)' '13:00'; $n = Register-ReclaimSchedule 'weekly' $at; Out-Line "  Created: $n" 'Green' }
                '2' { $n = Register-ReclaimSchedule 'alert' '12:30'; Out-Line "  Created: $n" 'Green' }
                '3' { Unregister-ReclaimSchedule; Out-Line '  Removed.' 'Green' }
            }
        } catch { Out-Line ('  Could not change scheduled tasks: ' + $_.Exception.Message) 'Red' }
    }
}

function Invoke-ReportsMenu {
    $h = @(Get-History)
    Out-Line ''
    if (-not $h.Count) { Out-Line '  No cleans recorded yet.' 'DarkGray' }
    $total = [int64]0
    foreach ($r in $h) { $total += [int64]$r.FreedBytes }
    foreach ($r in ($h | Select-Object -Last 15)) { Out-Line ('  {0}  {1,-20} {2,10}  {3} items' -f $r.Date, $r.Preset, (Format-Size ([int64]$r.FreedBytes)), $r.Items) 'Gray' }
    Out-Line ''
    Out-Line ('  Freed in total since you started using Reclaim: {0}' -f (Format-Size $total)) 'Green'
    $last = (Get-State)['LastReport']
    $a = Read-Text 'o = open the last report, f = open the reports folder, Enter = back' ''
    if ($a -eq 'o' -and $last -and (Test-Path -LiteralPath $last)) { Start-Process $last }
    if ($a -eq 'f') { Start-Process explorer.exe $script:Cfg.ReportsDir }
}

function Show-Tips {
    $tips = @(
        'Turn on Storage Sense (System > Storage) so Windows empties temp files and the Recycle Bin by itself.',
        'Shrink the hibernation file with "reduced" (System options) instead of turning it off: you keep Fast Startup.',
        'Keep projects, downloads and media on D:. Right-click Downloads / Documents > Properties > Location > Move.',
        'Move WSL to D: once: wsl --export Ubuntu D:\wsl\ubuntu.tar, wsl --unregister Ubuntu, wsl --import Ubuntu D:\wsl\Ubuntu D:\wsl\ubuntu.tar.',
        'Docker Desktop: Settings > Resources > Advanced > Disk image location lets you move its disk to D:.',
        'Android: set ANDROID_AVD_HOME to a folder on D: before creating emulators, and install the SDK on D:.',
        'Use "Move caches off C:" in the main menu for npm, Gradle, NuGet, pip, uv, Playwright and Hugging Face.',
        'Use pnpm instead of npm for many Node projects: one shared store instead of a full copy per project.',
        'OneDrive: turn on Files On-Demand and "Free up space" on folders you do not need offline.',
        'Never delete C:\Windows\WinSxS, C:\Windows\Installer or C:\ProgramData\Package Cache by hand: they break updates and uninstalls. Use the DISM item instead.',
        'Chrome downloads a 4 GB on-device AI model by itself. If you do not use it: chrome://settings/ai, or the policy GenAILocalFoundationalModelSettings = 1.',
        'Run "Space hogs" every few months: big files you forgot (videos, ISO files, old dumps) are the easiest wins.'
    )
    Out-Line ''
    Out-Line '  Recommendations' 'White'
    $i = 0
    foreach ($t in $tips) { $i++; Out-Line ('  {0,2}. {1}' -f $i, $t) 'Gray' }
    Wait-AnyKey
}

# ------------------------------------------------------------------ main menu
function Show-MainMenu {
    while ($true) {
        try { Clear-Host } catch { }
        Show-Banner
        Show-Drives
        Show-MenuItem '1' 'Quick clean' 'safe caches and temp files, no admin, nothing you would miss'
        Show-MenuItem '2' 'Developer clean' 'adds npm, Gradle, NuGet, IDE and emulator caches'
        Show-MenuItem '3' 'Deep clean' 'adds Windows Update, DISM, Recycle Bin, driver leftovers (admin)'
        Show-MenuItem '4' 'Choose items' 'scan every target and pick exactly what to clean'
        Out-Line ''
        Show-MenuItem '5' 'Space hogs' 'biggest folders and files on any drive or folder'
        Show-MenuItem '6' 'Old project folders' 'node_modules, .next, build, target... in your code folders'
        Show-MenuItem '7' 'Duplicate files' 'identical files (SHA-256), keep one copy'
        Show-MenuItem '8' 'WSL / Docker disks' 'compact virtual disks that never shrink'
        Show-MenuItem '9' 'System options' 'hibernation, page file, restore points, Compact OS'
        Show-MenuItem 'M' 'Move caches off C:' 'point npm, Gradle, pip... to another drive'
        Out-Line ''
        Show-MenuItem 'S' 'Schedule' 'weekly quick clean, low space alert'
        Show-MenuItem 'R' 'Reports' 'history and total space freed'
        Show-MenuItem 'T' 'Tips' 'recommendations to keep C: from filling up'
        Show-MenuItem 'D' 'Dry run' $(if ($script:DryRun) { 'ON: nothing is deleted (press D to turn off)' } else { 'off (press D to only simulate)' })
        if (-not $script:IsAdmin) { Show-MenuItem 'A' 'Run as administrator' 'needed for system items' }
        Show-MenuItem 'Q' 'Quit' ''
        Out-Line ''
        $a = (Read-Host '  Choose').Trim().ToUpperInvariant()
        try {
            switch ($a) {
                '1' { Invoke-InteractiveClean (Get-PresetTargets 'Quick') 'Quick clean' 'Quick' -PreselectAll }
                '2' { Invoke-InteractiveClean (Get-PresetTargets 'Dev') 'Developer clean' 'Dev' -PreselectAll }
                '3' { Invoke-InteractiveClean (Get-PresetTargets 'Deep') 'Deep clean' 'Deep' -PreselectAll }
                '4' { Invoke-InteractiveClean $script:Catalog 'All targets (Safe ones are preselected)' '' }
                '5' { Invoke-SpaceHogsMenu }
                '6' { Invoke-DevFoldersMenu }
                '7' { Invoke-DuplicatesMenu }
                '8' { Invoke-VirtualDisksMenu }
                '9' { Invoke-SystemMenu }
                'M' { Invoke-RelocateMenu }
                'S' { Invoke-ScheduleMenu }
                'R' { Invoke-ReportsMenu }
                'T' { Show-Tips }
                'D' { $script:DryRun = -not $script:DryRun }
                'A' { if (Restart-Elevated '') { return } }
                'Q' { return }
                ''  { }
            }
        } catch {
            Out-Line ('  Error: ' + $_.Exception.Message) 'Red'
            Write-Log ("Menu error: " + $_.Exception.ToString()) 'ERROR'
            Wait-AnyKey
        }
    }
}
