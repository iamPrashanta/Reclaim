# Core helpers: settings, logging, sizes, safety guard, engine loading, delete / measure wrappers.
# Dot-sourced by Reclaim.ps1. Windows PowerShell 5.1 and PowerShell 7 compatible.

$script:ReclaimVersion = '1.1.0'

# ------------------------------------------------------------------ settings and state
function Expand-EnvPath([string]$p) {
    if (-not $p) { return $p }
    return [Environment]::ExpandEnvironmentVariables($p)
}

function Merge-Hashtable([hashtable]$base, [hashtable]$over) {
    $r = @{}
    foreach ($k in $base.Keys) { $r[$k] = $base[$k] }
    if ($over) { foreach ($k in $over.Keys) { $r[$k] = $over[$k] } }
    return $r
}

function Import-ReclaimSettings {
    $defaults = Import-PowerShellDataFile -LiteralPath (Join-Path $script:Root 'config\settings.psd1')
    $localFile = Join-Path $script:Root 'config\settings.local.psd1'
    $local = $null
    if (Test-Path -LiteralPath $localFile) { $local = Import-PowerShellDataFile -LiteralPath $localFile }
    $s = Merge-Hashtable $defaults $local
    $s.DataDir = Expand-EnvPath $s.DataDir
    $s.ReportsDir = Expand-EnvPath $s.ReportsDir
    foreach ($d in @($s.DataDir, $s.ReportsDir)) {
        if (-not (Test-Path -LiteralPath $d)) { New-Item -ItemType Directory -Path $d -Force | Out-Null }
    }
    return $s
}

function Get-State {
    $f = Join-Path $script:Cfg.DataDir 'state.json'
    $h = @{}
    if (Test-Path -LiteralPath $f) {
        try {
            $o = Get-Content -LiteralPath $f -Raw -Encoding UTF8 | ConvertFrom-Json
            foreach ($p in $o.PSObject.Properties) { $h[$p.Name] = $p.Value }
        } catch { }
    }
    return $h
}

function Set-StateValue([string]$name, $value) {
    $h = Get-State
    $h[$name] = $value
    $f = Join-Path $script:Cfg.DataDir 'state.json'
    ($h | ConvertTo-Json -Depth 5) | Set-Content -LiteralPath $f -Encoding UTF8
}

# ------------------------------------------------------------------ logging and output
function Write-Log([string]$msg, [string]$level = 'INFO') {
    if (-not $script:LogFile) { return }
    $line = '{0} [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $level, $msg
    try { Add-Content -LiteralPath $script:LogFile -Value $line -Encoding UTF8 } catch { }
}

function Out-Line([string]$text = '', [string]$color = '') {
    if ($script:Quiet) { return }
    if ($color) { Write-Host $text -ForegroundColor $color } else { Write-Host $text }
}

function Out-Part([string]$text, [string]$color = '') {
    if ($script:Quiet) { return }
    if ($color) { Write-Host $text -ForegroundColor $color -NoNewline } else { Write-Host $text -NoNewline }
}

function Format-Size([double]$bytes) {
    if ($bytes -lt 0) { return '?' }
    if ($bytes -ge 1TB) { return '{0:N2} TB' -f ($bytes / 1TB) }
    if ($bytes -ge 1GB) { return '{0:N2} GB' -f ($bytes / 1GB) }
    if ($bytes -ge 1MB) { return '{0:N0} MB' -f ($bytes / 1MB) }
    if ($bytes -ge 1KB) { return '{0:N0} KB' -f ($bytes / 1KB) }
    return '{0:N0} B' -f $bytes
}

function Get-RiskColor([string]$risk) {
    switch ($risk) { 'Safe' { 'Green' } 'Moderate' { 'Yellow' } 'Careful' { 'Red' } default { 'Gray' } }
}

function Get-ConsoleWidth {
    try { $w = [Console]::WindowWidth; if ($w -gt 40) { return $w } } catch { }
    return 100
}

function Limit-Text([string]$t, [int]$max) {
    if (-not $t) { return '' }
    if ($t.Length -le $max) { return $t }
    if ($max -le 3) { return $t.Substring(0, $max) }
    $keep = [int](($max - 3) / 2)
    return $t.Substring(0, $keep) + '...' + $t.Substring($t.Length - ($max - 3 - $keep))
}

# ------------------------------------------------------------------ environment
function Test-IsAdmin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    return (New-Object Security.Principal.WindowsPrincipal($id)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-FixedDrives {
    [System.IO.DriveInfo]::GetDrives() | Where-Object { $_.DriveType -eq 'Fixed' -and $_.IsReady } | ForEach-Object {
        [pscustomobject]@{
            Name  = $_.Name.TrimEnd('\')
            Label = $_.VolumeLabel
            Total = [int64]$_.TotalSize
            Free  = [int64]$_.AvailableFreeSpace
            Used  = [int64]($_.TotalSize - $_.TotalFreeSpace)
        }
    }
}

function Get-FreeBytes([string]$drive) {
    try { return [int64](New-Object System.IO.DriveInfo($drive)).AvailableFreeSpace } catch { return [int64]0 }
}

function Get-RunningProcess([string[]]$names) {
    if (-not $names) { return @() }
    $found = @()
    foreach ($n in $names) {
        $p = Get-Process -Name $n -ErrorAction SilentlyContinue
        if ($p) { $found += ($p | Select-Object -First 1).ProcessName }
    }
    return @($found | Select-Object -Unique)
}

function Test-Command([string]$name) { return [bool](Get-Command $name -ErrorAction SilentlyContinue) }

# ------------------------------------------------------------------ safety guard
function Get-ProtectedPaths {
    if ($script:ProtectedCache) { return $script:ProtectedCache }
    $list = New-Object System.Collections.Generic.List[string]
    foreach ($d in (Get-FixedDrives)) { $list.Add($d.Name + '\') }
    $known = @(
        $env:SystemRoot, "$env:SystemRoot\System32", "$env:SystemRoot\SysWOW64", "$env:SystemRoot\WinSxS",
        $env:ProgramFiles, ${env:ProgramFiles(x86)}, $env:ProgramData, $env:ProgramW6432,
        $env:USERPROFILE, (Split-Path $env:USERPROFILE -Parent), $env:APPDATA, $env:LOCALAPPDATA,
        "$env:LOCALAPPDATA\Packages", "$env:LOCALAPPDATA\Programs", "$env:LOCALAPPDATA\Microsoft",
        "$env:USERPROFILE\Documents", "$env:USERPROFILE\Desktop", "$env:USERPROFILE\Downloads",
        "$env:USERPROFILE\Pictures", "$env:USERPROFILE\Videos", "$env:USERPROFILE\Music",
        "$env:USERPROFILE\OneDrive", $env:OneDrive, "$env:USERPROFILE\.ssh", "$env:USERPROFILE\.gnupg",
        "$env:USERPROFILE\.android", "$env:USERPROFILE\.gradle", "$env:USERPROFILE\.m2", "$env:USERPROFILE\.cargo",
        "$env:LOCALAPPDATA\Android\Sdk", "$env:ProgramData\Package Cache", "$env:SystemRoot\Installer",
        $script:Root
    )
    foreach ($k in $known) { if ($k) { $list.Add(([IO.Path]::GetFullPath($k)).TrimEnd('\') + '\') } }
    $script:ProtectedCache = $list
    return $list
}

function Test-ProtectedPath([string]$path) {
    # $true when the path itself is a protected folder, or sits inside System32 / WinSxS / Program Files.
    $full = ([IO.Path]::GetFullPath($path)).TrimEnd('\') + '\'
    foreach ($p in (Get-ProtectedPaths)) { if ($full -ieq $p) { return $true } }
    $inside = @("$env:SystemRoot\System32\", "$env:SystemRoot\SysWOW64\", "$env:SystemRoot\WinSxS\",
        "$env:ProgramFiles\", "${env:ProgramFiles(x86)}\", "$env:SystemRoot\Installer\", ($script:Root.TrimEnd('\') + '\'))
    foreach ($p in $inside) { if ($p.Length -gt 3 -and $full.StartsWith($p, [StringComparison]::OrdinalIgnoreCase)) { return $true } }
    foreach ($x in @($script:Cfg.ExcludePaths)) {
        if (-not $x) { continue }
        $xp = (Expand-EnvPath $x).TrimEnd('\') + '\'
        if ($full.StartsWith($xp, [StringComparison]::OrdinalIgnoreCase)) { return $true }
    }
    return $false
}

# Existence check that never throws (Test-Path throws on access denied when ErrorAction is Stop).
function Test-Exists([string]$p) {
    try { return ([IO.Directory]::Exists($p) -or [IO.File]::Exists($p)) } catch { return $false }
}

# Expands %VARS% and * / ? in any path segment. Returns existing paths only.
function Expand-ReclaimPath([string]$pattern) {
    $p = Expand-EnvPath $pattern
    if ($p -notmatch '[\*\?]') {
        if (Test-Exists $p) { return , @($p) } else { return , @() }
    }
    $parts = $p.Split('\')
    $current = @($parts[0] + '\')
    for ($i = 1; $i -lt $parts.Length; $i++) {
        $seg = $parts[$i]
        if (-not $seg) { continue }
        $last = ($i -eq $parts.Length - 1)
        $next = @()
        foreach ($c in $current) {
            if ($seg -match '[\*\?]') {
                $items = if ($last) { Get-ChildItem -LiteralPath $c -Filter $seg -Force -ErrorAction SilentlyContinue }
                         else { Get-ChildItem -LiteralPath $c -Filter $seg -Directory -Force -ErrorAction SilentlyContinue }
                foreach ($it in $items) {
                    # never walk through a junction while expanding
                    if ((-not $last) -and ($it.Attributes -band [IO.FileAttributes]::ReparsePoint)) { continue }
                    $next += $it.FullName
                }
            } else {
                $cand = Join-Path $c $seg
                if (Test-Exists $cand) { $next += $cand }
            }
        }
        $current = $next
        if (-not $current) { break }
    }
    return , @($current)
}

# ------------------------------------------------------------------ engine
function Initialize-Engine {
    if ('Reclaim.Engine' -as [type]) { return }
    $src = Join-Path $script:Root 'src\Engine.cs'
    $hash = (Get-FileHash -LiteralPath $src -Algorithm SHA256).Hash.Substring(0, 12)
    $ps = $PSVersionTable.PSVersion.Major
    $dir = Join-Path $script:Cfg.DataDir 'engine'
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $dll = Join-Path $dir ("Reclaim.Engine-ps{0}-{1}.dll" -f $ps, $hash)
    if (Test-Path -LiteralPath $dll) {
        try { Add-Type -LiteralPath $dll; return } catch { Remove-Item -LiteralPath $dll -Force -ErrorAction SilentlyContinue }
    }
    $code = Get-Content -LiteralPath $src -Raw
    try {
        Add-Type -TypeDefinition $code -Language CSharp -OutputAssembly $dll -OutputType Library -ErrorAction Stop
        Add-Type -LiteralPath $dll
    } catch {
        # could not write the DLL (locked folder, policy): compile in memory instead
        Add-Type -TypeDefinition $code -Language CSharp -ErrorAction Stop
    }
}

# Waits for an engine Job and shows progress. Esc cancels. Returns the job result.
function Wait-EngineJob($job, [string]$activity) {
    $sw = [Diagnostics.Stopwatch]::StartNew()
    $canKey = $false
    try { $canKey = -not [Console]::IsInputRedirected } catch { }
    while (-not $job.Wait(300)) {
        if (-not $script:Quiet) {
            $status = '{0:N0} items  {1}  {2:N0}s  (Esc = stop)' -f $job.Progress, (Format-Size $job.ProgressBytes), $sw.Elapsed.TotalSeconds
            $cur = Limit-Text ([string]$job.Current) 90
            $phase = [string]$job.Phase
            if ($phase) { $status = (Limit-Text $phase 50) + ' | ' + $status }
            Write-Progress -Activity $activity -Status $status -CurrentOperation $cur
        }
        if ($canKey) {
            try {
                while ([Console]::KeyAvailable) {
                    $k = [Console]::ReadKey($true)
                    if ($k.Key -eq 'Escape') { $job.Cancel = $true; Out-Line '  Stopping...' 'Yellow' }
                }
            } catch { $canKey = $false }
        }
    }
    if (-not $script:Quiet) { Write-Progress -Activity $activity -Completed }
    if ($job.Error) { throw $job.Error }
    return $job.Result
}

function Measure-ReclaimPath([string[]]$paths, [int]$olderThanDays = 0, [string]$activity = 'Measuring') {
    if (-not $paths -or $paths.Count -eq 0) { return (New-Object Reclaim.WalkStats) }
    $job = [Reclaim.Engine]::StartMeasure([string[]]$paths, $olderThanDays)
    return (Wait-EngineJob $job $activity)
}

# Deletes paths through the engine after the PowerShell guard. Mode: Contents | Folder.
function Remove-ReclaimPath([string[]]$paths, [string]$mode = 'Contents', [int]$olderThanDays = 0,
                            [int]$minDepth = 3, [string]$activity = 'Cleaning') {
    $ok = @()
    foreach ($p in $paths) {
        if (Test-ProtectedPath $p) { Write-Log "Guard refused $p" 'WARN'; continue }
        if (($mode -eq 'Folder') -and [IO.Directory]::Exists($p)) {
            # removing a whole folder: its parent must not be protected-root level either
            if ([Reclaim.Engine]::Depth($p) -lt $minDepth) { Write-Log "Depth guard refused $p" 'WARN'; continue }
        }
        $ok += $p
    }
    if ($ok.Count -eq 0) { return (New-Object Reclaim.WalkStats) }
    $contents = ($mode -eq 'Contents')
    $job = [Reclaim.Engine]::StartDelete([string[]]$ok, $contents, $olderThanDays, [bool]$script:DryRun, $minDepth)
    $r = Wait-EngineJob $job $activity
    Write-Log ("{0} {1} paths: freed {2}, files {3}, in use {4}, errors {5}{6}" -f $mode, $ok.Count, (Format-Size $r.Bytes),
        $r.DeletedFiles, $r.InUse, $r.Errors, $(if ($script:DryRun) { ' (dry run)' } else { '' }))
    return $r
}

# Sends files or folders to the Recycle Bin (used for anything that is your data, not a cache).
function Send-ToRecycleBin([string[]]$paths) {
    Add-Type -AssemblyName Microsoft.VisualBasic
    $stats = New-Object Reclaim.WalkStats
    foreach ($p in $paths) {
        if (Test-ProtectedPath $p) { Write-Log "Guard refused recycle $p" 'WARN'; $stats.Errors++; continue }
        try {
            $item = Get-Item -LiteralPath $p -Force -ErrorAction Stop
            $size = if ($item.PSIsContainer) { (Measure-ReclaimPath @($p) 0 'Measuring').Bytes } else { $item.Length }
            if (-not $script:DryRun) {
                if ($item.PSIsContainer) {
                    [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteDirectory($p, 'OnlyErrorDialogs', 'SendToRecycleBin')
                } else {
                    [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteFile($p, 'OnlyErrorDialogs', 'SendToRecycleBin')
                }
            }
            $stats.Bytes += $size; $stats.DeletedFiles++
            Write-Log ("Recycled {0} ({1}){2}" -f $p, (Format-Size $size), $(if ($script:DryRun) { ' (dry run)' } else { '' }))
        } catch {
            $stats.Errors++; $stats.LastError = $_.Exception.Message
            Write-Log "Recycle failed $p : $($_.Exception.Message)" 'WARN'
        }
    }
    return $stats
}

# ------------------------------------------------------------------ input
function Read-Text([string]$prompt, [string]$default = '') {
    $suffix = if ($default) { " [$default]" } else { '' }
    $a = Read-Host "  $prompt$suffix"
    if (-not $a) { return $default }
    return $a.Trim()
}

function Read-YesNo([string]$prompt, [bool]$default = $false) {
    $hint = if ($default) { 'Y/n' } else { 'y/N' }
    $a = Read-Host "  $prompt ($hint)"
    if (-not $a) { return $default }
    return ($a.Trim() -match '^(y|yes)$')
}

# For anything permanent or risky: the user has to type the word.
function Read-TypedConfirm([string]$word = 'YES') {
    $a = Read-Host "  Type $word to continue, anything else cancels"
    return ($a -ceq $word)
}

# Parses "1,3,5-8" into an int list (1-based, within 1..max).
function ConvertFrom-NumberList([string]$text, [int]$max) {
    $out = New-Object System.Collections.Generic.List[int]
    foreach ($part in ($text -split '[,\s]+')) {
        if (-not $part) { continue }
        if ($part -match '^(\d+)-(\d+)$') {
            $a = [int]$Matches[1]; $b = [int]$Matches[2]
            if ($a -gt $b) { $t = $a; $a = $b; $b = $t }
            for ($i = $a; $i -le $b; $i++) { if ($i -ge 1 -and $i -le $max) { $out.Add($i) } }
        } elseif ($part -match '^\d+$') {
            $i = [int]$part
            if ($i -ge 1 -and $i -le $max) { $out.Add($i) }
        }
    }
    return , @($out | Select-Object -Unique)
}

function Wait-AnyKey {
    if ($script:Quiet) { return }
    Out-Line ''
    Read-Host '  Press Enter to continue' | Out-Null
}
