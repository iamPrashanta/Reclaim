# Special cleaners (handlers), virtual disk compaction, system options, scheduling, notifications.

function Invoke-External([string]$exe, [string[]]$arguments, [switch]$ShowOutput) {
    # Runs a tool, returns @{ Code; Output }. Output is shown live when -ShowOutput and not quiet.
    Write-Log "Run: $exe $($arguments -join ' ')"
    if ($ShowOutput -and -not $script:Quiet) {
        & $exe @arguments | Out-Host
        return @{ Code = $LASTEXITCODE; Output = '' }
    }
    $out = & $exe @arguments 2>&1 | Out-String
    return @{ Code = $LASTEXITCODE; Output = $out }
}

function ConvertFrom-SizeText([string]$t) {
    # "1.234GB", "12.5 MB", "980kB", "0B" -> bytes
    if ($t -match '([\d\.,]+)\s*([kKMGT]?i?B)') {
        $n = [double]::Parse(($Matches[1] -replace ',', ''), [Globalization.CultureInfo]::InvariantCulture)
        switch -regex ($Matches[2]) {
            '^[kK]' { return [int64]($n * 1KB) }
            '^M' { return [int64]($n * 1MB) }
            '^G' { return [int64]($n * 1GB) }
            '^T' { return [int64]($n * 1TB) }
            default { return [int64]$n }
        }
    }
    return [int64]0
}

function Get-MyRecycleBinFolders([switch]$AllUsers) {
    $sid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    $out = @()
    foreach ($d in (Get-FixedDrives)) {
        $bin = Join-Path ($d.Name + '\') '$Recycle.Bin'
        if (-not (Test-Exists $bin)) { continue }
        if ($AllUsers) {
            Get-ChildItem -LiteralPath $bin -Directory -Force -ErrorAction SilentlyContinue | ForEach-Object { $out += $_.FullName }
        } else {
            $mine = Join-Path $bin $sid
            if (Test-Exists $mine) { $out += $mine }
        }
    }
    return $out
}

$script:Handlers = @{
    'recycle-bin' = @{
        Measure = {
            param($t)
            $folders = Get-MyRecycleBinFolders -AllUsers:$script:IsAdmin
            $s = Measure-ReclaimPath $folders 0 'Measuring Recycle Bin'
            $note = if ($script:IsAdmin) { 'all accounts' } else { 'your account only (run as admin for all accounts)' }
            @{ Paths = $folders; Bytes = $s.Bytes; Note = $note; Status = $(if ($s.Bytes -gt 0) { 'ready' } else { 'empty' }) }
        }
        Clean = {
            param($t, $row)
            $s = Remove-ReclaimPath $row.Paths 'Contents' 0 3 'Emptying Recycle Bin'
            @{ Freed = $s.Bytes; InUse = $s.InUse; Errors = $s.Errors; Note = 'emptied' }
        }
    }

    'windows-update-cache' = @{
        Measure = {
            param($t)
            $p = Resolve-TargetPaths $t
            $s = Measure-ReclaimPath $p 0 'Measuring Windows Update cache'
            @{ Paths = $p; Bytes = $s.Bytes; Status = $(if ($p) { 'ready' } else { 'not found' }) }
        }
        Clean = {
            param($t, $row)
            $stopped = @()
            try {
                if (-not $script:DryRun) {
                    foreach ($svc in 'wuauserv', 'bits', 'UsoSvc') {
                        $sv = Get-Service -Name $svc -ErrorAction SilentlyContinue
                        if ($sv -and $sv.Status -eq 'Running') { Stop-Service -Name $svc -Force -ErrorAction SilentlyContinue; $stopped += $svc }
                    }
                }
                $s = Remove-ReclaimPath $row.Paths 'Contents' 0 3 'Cleaning Windows Update cache'
                @{ Freed = $s.Bytes; InUse = $s.InUse; Errors = $s.Errors; Note = 'done' }
            } finally {
                foreach ($svc in $stopped) { Start-Service -Name $svc -ErrorAction SilentlyContinue }
            }
        }
    }

    'delivery-optimization' = @{
        Measure = {
            param($t)
            $p = Resolve-TargetPaths $t
            $s = Measure-ReclaimPath $p 0 'Measuring Delivery Optimization'
            @{ Paths = $p; Bytes = $s.Bytes; Status = $(if ($p) { 'ready' } else { 'not found' }) }
        }
        Clean = {
            param($t, $row)
            if ($script:DryRun) { return @{ Freed = $row.Bytes; Note = 'dry run' } }
            if (Get-Command Delete-DeliveryOptimizationCache -ErrorAction SilentlyContinue) {
                Delete-DeliveryOptimizationCache -Force -ErrorAction SilentlyContinue
                return @{ Freed = 0; Note = 'cleared with Delete-DeliveryOptimizationCache' }
            }
            $s = Remove-ReclaimPath $row.Paths 'Contents' 0 3 'Cleaning Delivery Optimization'
            @{ Freed = $s.Bytes; InUse = $s.InUse; Errors = $s.Errors }
        }
    }

    'dism' = @{
        Measure = {
            param($t)
            @{ Paths = @(); Bytes = -1; Note = 'size is known only after it runs (often 2-10 GB)'; Status = 'ready' }
        }
        Clean = {
            param($t, $row)
            if ($script:DryRun) { return @{ Freed = 0; Note = 'dry run: DISM not started' } }
            Out-Line '  DISM component cleanup is running. This takes 5-15 minutes, please wait...' 'Cyan'
            $argsList = @('/Online', '/Cleanup-Image', '/StartComponentCleanup')
            if ($script:Quiet) { $argsList += '/Quiet' }
            $r = Invoke-External 'dism.exe' $argsList -ShowOutput
            @{ Freed = 0; Errors = $(if ($r.Code -ne 0) { 1 } else { 0 }); Note = "DISM exit code $($r.Code)" }
        }
    }

    'windows-old' = @{
        Measure = {
            param($t)
            $p = @()
            foreach ($x in $t.Paths) { $e = Expand-EnvPath $x; if (Test-Exists $e) { $p += $e } }
            $s = Measure-ReclaimPath $p 0 'Measuring previous Windows'
            @{ Paths = $p; Bytes = $s.Bytes; Status = $(if ($p) { 'ready' } else { 'not found' }) }
        }
        Clean = {
            param($t, $row)
            if ($script:DryRun) { return @{ Freed = $row.Bytes; Note = 'dry run' } }
            $total = New-Object Reclaim.WalkStats
            foreach ($p in $row.Paths) {
                Out-Line "  Taking ownership of $p (can take a few minutes)..." 'Cyan'
                & takeown.exe /F $p /R /A /D Y 2>&1 | Out-Null
                & icacls.exe $p /grant '*S-1-5-32-544:F' /T /C /Q 2>&1 | Out-Null
                $total.Add((Remove-ReclaimPath @($p) 'Folder' 0 2 "Removing $p"))
            }
            @{ Freed = $total.Bytes; InUse = $total.InUse; Errors = $total.Errors }
        }
    }

    'old-ide-versions' = @{
        Measure = {
            param($t)
            $p = @(Get-OldIdeVersionFolders)
            if (-not $p.Count) { return @{ Paths = @(); Bytes = 0; Status = 'not found' } }
            $s = Measure-ReclaimPath $p 0 'Measuring old IDE versions'
            @{ Paths = $p; Bytes = $s.Bytes; Note = ('{0} old version folder(s)' -f $p.Count) }
        }
        Clean = {
            param($t, $row)
            $s = Remove-ReclaimPath $row.Paths 'Folder' 0 3 'Removing old IDE version folders'
            @{ Freed = $s.Bytes; InUse = $s.InUse; Errors = $s.Errors }
        }
    }

    'pnpm-store' = @{
        Measure = {
            param($t)
            $store = $null
            if (Test-Command 'pnpm') { try { $store = (& pnpm store path 2>$null | Select-Object -First 1) } catch { } }
            if (-not $store) { $store = Expand-EnvPath '%LOCALAPPDATA%\pnpm\store' }
            if (-not (Test-Path -LiteralPath $store)) { return @{ Paths = @(); Bytes = 0; Status = 'not found' } }
            if (-not (Test-Command 'pnpm')) { return @{ Paths = @($store); Bytes = 0; Status = 'unavailable'; Note = 'pnpm is not on PATH' } }
            $s = Measure-ReclaimPath @($store) 0 'Measuring pnpm store'
            @{ Paths = @($store); Bytes = $s.Bytes; Note = 'store size; prune removes only unused packages' }
        }
        Clean = {
            param($t, $row)
            if ($script:DryRun) { return @{ Freed = 0; Note = 'dry run: pnpm store prune not run' } }
            $r = Invoke-External 'pnpm' @('store', 'prune')
            @{ Freed = 0; Errors = $(if ($r.Code -ne 0) { 1 } else { 0 }); Note = 'pnpm store prune' }
        }
    }

    'conda' = @{
        Measure = {
            param($t)
            $conda = Get-CondaExe
            $p = Resolve-TargetPaths $t
            if (-not $p) { return @{ Paths = @(); Bytes = 0; Status = 'not found' } }
            if (-not $conda) { return @{ Paths = $p; Bytes = 0; Status = 'unavailable'; Note = 'conda not found' } }
            $s = Measure-ReclaimPath $p 0 'Measuring conda packages'
            @{ Paths = $p; Bytes = $s.Bytes; Note = 'up to this much; files still used by environments stay' }
        }
        Clean = {
            param($t, $row)
            if ($script:DryRun) { return @{ Freed = 0; Note = 'dry run: conda clean not run' } }
            $r = Invoke-External (Get-CondaExe) @('clean', '--all', '-y')
            @{ Freed = 0; Errors = $(if ($r.Code -ne 0) { 1 } else { 0 }); Note = 'conda clean --all' }
        }
    }

    'docker-prune' = @{
        Measure = {
            param($t)
            if (-not (Test-Command 'docker')) { return @{ Paths = @(); Bytes = 0; Status = 'not found' } }
            $lines = & docker system df --format '{{.Type}}|{{.Reclaimable}}' 2>$null
            if ($LASTEXITCODE -ne 0 -or -not $lines) { return @{ Paths = @(); Bytes = 0; Status = 'unavailable'; Note = 'Docker is not running' } }
            $b = [int64]0
            foreach ($l in $lines) {
                $parts = $l -split '\|'
                if ($parts[0] -notmatch 'Volume') { $b += ConvertFrom-SizeText $parts[1] }
            }
            @{ Paths = @(); Bytes = $b; Note = 'up to; volumes are never touched' }
        }
        Clean = {
            param($t, $row)
            if ($script:DryRun) { return @{ Freed = $row.Bytes; Note = 'dry run' } }
            $r = Invoke-External 'docker' @('system', 'prune', '-f')
            $freed = [int64]0
            if ($r.Output -match 'Total reclaimed space:\s*(.+)') { $freed = ConvertFrom-SizeText $Matches[1] }
            @{ Freed = $freed; Errors = $(if ($r.Code -ne 0) { 1 } else { 0 }); Note = 'docker system prune -f (compact the Docker disk to get the space back on C:)' }
        }
    }
}

# Cache folders of IDE versions older than the newest one of the same product
# (for example Google\AndroidStudio2026.1.2 when AndroidStudio2026.1.4 exists). Settings in Roaming are not touched.
function Get-OldIdeVersionFolders {
    $re = '^(AndroidStudio|IntelliJIdea|IdeaIC|PyCharm|PyCharmCE|WebStorm|Rider|PhpStorm|GoLand|CLion|RustRover|DataGrip|DataSpell|RubyMine|Aqua|Writerside)(\d{4}(?:\.\d+){1,2})$'
    $out = @()
    foreach ($base in @("$env:LOCALAPPDATA\Google", "$env:LOCALAPPDATA\JetBrains")) {
        if (-not (Test-Exists $base)) { continue }
        $byProduct = @{}
        foreach ($d in (Get-ChildItem -LiteralPath $base -Directory -Force -ErrorAction SilentlyContinue)) {
            if ($d.Name -match $re) {
                $prod = $Matches[1]
                if (-not $byProduct.ContainsKey($prod)) { $byProduct[$prod] = @() }
                $byProduct[$prod] += [pscustomobject]@{ Path = $d.FullName; Version = [version]$Matches[2] }
            }
        }
        foreach ($k in $byProduct.Keys) {
            $sorted = @($byProduct[$k] | Sort-Object Version -Descending)
            if ($sorted.Count -gt 1) { $out += @($sorted | Select-Object -Skip 1 | ForEach-Object { $_.Path }) }
        }
    }
    return $out
}

function Get-CondaExe {
    $c = Get-Command conda -ErrorAction SilentlyContinue
    if ($c) { return $c.Source }
    foreach ($p in @("$env:USERPROFILE\anaconda3\Scripts\conda.exe", "$env:USERPROFILE\miniconda3\Scripts\conda.exe",
                     "$env:LOCALAPPDATA\anaconda3\Scripts\conda.exe", "$env:LOCALAPPDATA\miniconda3\Scripts\conda.exe", "$env:ProgramData\anaconda3\Scripts\conda.exe")) {
        if (Test-Path -LiteralPath $p) { return $p }
    }
    return $null
}

# ------------------------------------------------------------------ WSL / Docker virtual disks
function Get-VirtualDisks {
    $list = New-Object System.Collections.Generic.List[object]
    $seen = @{}
    $lxss = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Lxss'
    if (Test-Path $lxss) {
        foreach ($k in (Get-ChildItem $lxss -ErrorAction SilentlyContinue)) {
            $p = Get-ItemProperty $k.PSPath -ErrorAction SilentlyContinue
            if (-not $p.BasePath) { continue }
            $base = ([string]$p.BasePath) -replace '^\\\\\?\\', ''
            $vhd = if ($p.VhdFileName) { [string]$p.VhdFileName } else { 'ext4.vhdx' }
            $file = Join-Path $base $vhd
            if (-not (Test-Exists $file)) { continue }
            $seen[$file.ToLowerInvariant()] = $true
            $list.Add([pscustomobject]@{ Name = [string]$p.DistributionName; Kind = 'WSL'; Path = $file
                Bytes = [Reclaim.Engine]::SizeOnDisk($file); Distro = [string]$p.DistributionName })
        }
    }
    foreach ($pat in @('%LOCALAPPDATA%\Docker\wsl\*\*.vhdx', '%LOCALAPPDATA%\Docker\wsl\*\*\*.vhdx')) {
        foreach ($f in (Expand-ReclaimPath $pat)) {
            if (-not $f -or $seen.ContainsKey($f.ToLowerInvariant())) { continue }
            $seen[$f.ToLowerInvariant()] = $true
            $list.Add([pscustomobject]@{ Name = 'Docker Desktop (' + (Split-Path $f -Leaf) + ')'; Kind = 'Docker'; Path = $f
                Bytes = [Reclaim.Engine]::SizeOnDisk($f); Distro = '' })
        }
    }
    return $list
}

function Invoke-WslCommand([string[]]$arguments) {
    # wsl.exe writes UTF-16; read it as such so names come out clean
    $old = [Console]::OutputEncoding
    try {
        [Console]::OutputEncoding = [Text.Encoding]::Unicode
        $o = & wsl.exe @arguments 2>&1
        return @(($o | Out-String) -split "`r?`n" | ForEach-Object { ($_ -replace "`0", '').Trim() } | Where-Object { $_ })
    } finally { [Console]::OutputEncoding = $old }
}

function Compress-VirtualDisks($disks, [switch]$Trim) {
    if (-not $script:IsAdmin) { throw 'Compacting virtual disks needs administrator rights.' }
    $rows = @()
    foreach ($d in $disks) { $rows += [pscustomobject]@{ Disk = $d; Before = [int64]$d.Bytes; After = [int64]0; Result = '' } }
    if ($script:DryRun) {
        foreach ($r in $rows) { $r.After = $r.Before; $r.Result = 'dry run' }
        return $rows
    }
    if ($Trim) {
        foreach ($d in ($disks | Where-Object { $_.Distro })) {
            Out-Line ("  fstrim inside {0} (tells the disk which blocks are free)..." -f $d.Distro) 'Cyan'
            Invoke-WslCommand @('-d', $d.Distro, '-u', 'root', '-e', 'sh', '-c', 'fstrim -a 2>/dev/null || true') | Out-Null
        }
    }
    Out-Line '  Shutting down WSL...' 'Cyan'
    Invoke-WslCommand @('--shutdown') | Out-Null
    Start-Sleep -Seconds 4
    foreach ($r in $rows) {
        $f = $r.Disk.Path
        Out-Line ("  Compacting {0} ({1})..." -f $r.Disk.Name, (Format-Size $r.Before)) 'Cyan'
        $dpFile = Join-Path $env:TEMP ("reclaim-diskpart-{0}.txt" -f ([guid]::NewGuid().ToString('N').Substring(0, 8)))
        @("select vdisk file=""$f""", 'attach vdisk readonly', 'compact vdisk', 'detach vdisk') | Set-Content -LiteralPath $dpFile -Encoding ASCII
        try {
            $out = & diskpart.exe /s $dpFile 2>&1 | Out-String
            Write-Log "diskpart $f : $out"
            $r.Result = if ($out -match 'successfully compacted|100 percent completed') { 'compacted' } else { 'see log' }
        } finally {
            Remove-Item -LiteralPath $dpFile -Force -ErrorAction SilentlyContinue
            # make sure the disk is never left attached
            @("select vdisk file=""$f""", 'detach vdisk') | Set-Content -LiteralPath $dpFile -Encoding ASCII
            & diskpart.exe /s $dpFile 2>&1 | Out-Null
            Remove-Item -LiteralPath $dpFile -Force -ErrorAction SilentlyContinue
        }
        $r.After = [Reclaim.Engine]::SizeOnDisk($f)
    }
    return $rows
}

# ------------------------------------------------------------------ system information and options
function Get-BigSystemFiles {
    $sd = $env:SystemDrive + '\'
    $out = @()
    foreach ($n in 'hiberfil.sys', 'pagefile.sys', 'swapfile.sys') {
        $f = Get-Item -LiteralPath (Join-Path $sd $n) -Force -ErrorAction SilentlyContinue
        if ($f) { $out += [pscustomobject]@{ Name = $n; Path = $f.FullName; Bytes = [int64]$f.Length } }
    }
    $dmp = Get-Item -LiteralPath (Join-Path $env:SystemRoot 'MEMORY.DMP') -Force -ErrorAction SilentlyContinue
    if ($dmp) { $out += [pscustomobject]@{ Name = 'MEMORY.DMP'; Path = $dmp.FullName; Bytes = [int64]$dmp.Length } }
    return $out
}

function Get-HibernationInfo {
    $k = 'HKLM:\SYSTEM\CurrentControlSet\Control\Power'
    $p = Get-ItemProperty $k -ErrorAction SilentlyContinue
    $f = Get-Item -LiteralPath (Join-Path ($env:SystemDrive + '\') 'hiberfil.sys') -Force -ErrorAction SilentlyContinue
    $type = switch ([int]$p.HiberFileType) { 1 { 'reduced' } 2 { 'full' } default { 'default' } }
    [pscustomobject]@{
        Enabled = ([int]$p.HibernateEnabled -eq 1) -or [bool]$f
        Type    = $type
        Bytes   = $(if ($f) { [int64]$f.Length } else { [int64]0 })
    }
}

function Set-Hibernation([ValidateSet('reduced', 'off', 'full')][string]$mode) {
    if (-not $script:IsAdmin) { throw 'Changing hibernation needs administrator rights.' }
    if ($script:DryRun) { Out-Line "  Dry run: powercfg would set hibernation to $mode" 'Yellow'; return }
    switch ($mode) {
        'off'     { & powercfg.exe /hibernate off }
        'reduced' { & powercfg.exe /hibernate on; & powercfg.exe /hibernate /type reduced }
        'full'    { & powercfg.exe /hibernate on; & powercfg.exe /hibernate /type full }
    }
    Write-Log "Hibernation set to $mode"
}

function Get-PageFileInfo {
    $u = Get-CimInstance Win32_PageFileUsage -ErrorAction SilentlyContinue
    $cs = Get-CimInstance Win32_ComputerSystem -ErrorAction SilentlyContinue
    foreach ($x in $u) {
        [pscustomobject]@{ Path = $x.Name; AllocatedMB = $x.AllocatedBaseSize; CurrentMB = $x.CurrentUsage; PeakMB = $x.PeakUsage
            Automatic = [bool]$cs.AutomaticManagedPagefile; RamGB = [math]::Round($cs.TotalPhysicalMemory / 1GB, 1) }
    }
}

# ------------------------------------------------------------------ scheduling
$script:TaskWeekly = 'Reclaim - weekly quick clean'
$script:TaskAlert = 'Reclaim - low disk space alert'

function Get-ReclaimLaunchArgs([string]$extra) {
    $ps1 = Join-Path $script:Root 'Reclaim.ps1'
    return ('-NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File "{0}" {1}' -f $ps1, $extra)
}

function Register-ReclaimSchedule([ValidateSet('weekly', 'daily', 'monthly', 'alert')][string]$kind, [string]$at = '13:00') {
    $settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit (New-TimeSpan -Hours 2)
    $time = [datetime]::ParseExact($at, 'HH:mm', $null)
    if ($kind -eq 'alert') {
        $action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument (Get-ReclaimLaunchArgs '-CheckSpace -Quiet')
        $triggers = @((New-ScheduledTaskTrigger -Daily -At $time), (New-ScheduledTaskTrigger -AtLogOn -User "$env:USERDOMAIN\$env:USERNAME"))
        Register-ScheduledTask -TaskName $script:TaskAlert -Action $action -Trigger $triggers -Settings $settings `
            -Description "Shows a notification when a drive has less than $($script:Cfg.LowSpaceGB) GB free." -Force | Out-Null
        return $script:TaskAlert
    }
    $trigger = switch ($kind) {
        'daily'   { New-ScheduledTaskTrigger -Daily -At $time }
        'weekly'  { New-ScheduledTaskTrigger -Weekly -DaysOfWeek Sunday -At $time }
        'monthly' { New-ScheduledTaskTrigger -Weekly -WeeksInterval 4 -DaysOfWeek Sunday -At $time }
    }
    $action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument (Get-ReclaimLaunchArgs '-Clean -Preset Quick -Yes -Quiet')
    Register-ScheduledTask -TaskName $script:TaskWeekly -Action $action -Trigger $trigger -Settings $settings `
        -Description 'Reclaim quick clean: safe caches and temp files only (no admin, nothing you would miss).' -Force | Out-Null
    return $script:TaskWeekly
}

function Unregister-ReclaimSchedule {
    foreach ($n in @($script:TaskWeekly, $script:TaskAlert)) {
        if (Get-ScheduledTask -TaskName $n -ErrorAction SilentlyContinue) { Unregister-ScheduledTask -TaskName $n -Confirm:$false }
    }
}

function Get-ReclaimSchedule {
    foreach ($n in @($script:TaskWeekly, $script:TaskAlert)) {
        $t = Get-ScheduledTask -TaskName $n -ErrorAction SilentlyContinue
        if (-not $t) { continue }
        $i = Get-ScheduledTaskInfo -TaskName $n -ErrorAction SilentlyContinue
        [pscustomobject]@{ Name = $n; State = [string]$t.State; NextRun = $i.NextRunTime; LastRun = $i.LastRunTime; LastResult = $i.LastTaskResult }
    }
}

# ------------------------------------------------------------------ notifications
function Show-Notification([string]$title, [string]$text) {
    $esc = { param($s) [Security.SecurityElement]::Escape($s) }
    try {
        [void][Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime]
        [void][Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom.XmlDocument, ContentType = WindowsRuntime]
        $xml = New-Object Windows.Data.Xml.Dom.XmlDocument
        $xml.LoadXml(("<toast><visual><binding template='ToastGeneric'><text>{0}</text><text>{1}</text></binding></visual></toast>" -f (& $esc $title), (& $esc $text)))
        $appId = '{1AC14E77-02E7-4E5D-B744-2EB1AE5198B7}\WindowsPowerShell\v1.0\powershell.exe'
        [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier($appId).Show([Windows.UI.Notifications.ToastNotification]::new($xml))
        return
    } catch { }
    try {
        Add-Type -AssemblyName System.Windows.Forms, System.Drawing
        $n = New-Object System.Windows.Forms.NotifyIcon
        $n.Icon = [System.Drawing.SystemIcons]::Warning
        $n.Visible = $true
        $n.ShowBalloonTip(10000, $title, $text, 'Warning')
        Start-Sleep -Seconds 10
        $n.Dispose()
    } catch { Write-Log "Notification failed: $($_.Exception.Message)" 'WARN' }
}

function Invoke-SpaceCheck {
    $low = @()
    foreach ($d in (Get-FixedDrives)) {
        if ($d.Free -lt ($script:Cfg.LowSpaceGB * 1GB)) { $low += '{0} {1} free' -f $d.Name, (Format-Size $d.Free) }
    }
    if ($low.Count -gt 0) {
        Show-Notification 'Low disk space' (($low -join ', ') + '. Run Reclaim to free some space.')
        Write-Log ('Low space alert: ' + ($low -join ', '))
        return 1
    }
    return 0
}
