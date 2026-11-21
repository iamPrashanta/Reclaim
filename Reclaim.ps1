<#
.SYNOPSIS
    Reclaim - free up disk space on Windows, safely.

.DESCRIPTION
    Interactive menu (run without parameters) or command line. Cleans caches and temp files from
    Windows, browsers, developer tools and apps; finds space hogs, old project build folders and
    duplicate files; compacts WSL / Docker disks; schedules a weekly clean. Every target has a risk
    level, a dry run shows what would happen, and every run is saved as an HTML + JSON report.

.EXAMPLE
    .\reclaim.cmd                                   # interactive menu
.EXAMPLE
    .\reclaim.cmd -Scan -Preset Dev                 # measure only
.EXAMPLE
    .\reclaim.cmd -Clean -Preset Quick -Yes         # clean safe items without questions
.EXAMPLE
    .\reclaim.cmd -Clean -Targets npm-cache,gradle-caches -DryRun
.EXAMPLE
    .\reclaim.cmd -Analyze C:\                      # biggest folders and files
.EXAMPLE
    .\reclaim.cmd -DevFolders D:\Code               # old node_modules, .next, build, target...
#>
[CmdletBinding()]
param(
    [switch]$List,
    [switch]$Scan,
    [switch]$Clean,
    [ValidateSet('Quick', 'Dev', 'Deep')][string]$Preset,
    [string[]]$Targets,
    [string[]]$Skip,
    [switch]$DryRun,
    [switch]$Yes,
    [switch]$Force,
    [switch]$Quiet,
    [switch]$Pause,
    [switch]$NoReport,
    [string]$Analyze,
    [string]$Growth,
    [string[]]$DevFolders,
    [string[]]$Duplicates,
    [int]$MinMB = 0,
    [int]$StaleDays = 0,
    [ValidateSet('weekly', 'daily', 'monthly', 'alert', 'remove', 'status')][string]$Schedule,
    [string]$At = '13:00',
    [switch]$CheckSpace,
    [switch]$Json,
    [switch]$SelfTest,
    [switch]$Version,
    [ValidateSet('disks', 'system', 'dev', 'space', 'duplicates', 'relocate', 'move', 'growth')][string]$Menu
)

$ErrorActionPreference = 'Stop'
$script:Root = $PSScriptRoot
foreach ($f in 'Core', 'System', 'Targets', 'Analyze', 'Report', 'Move', 'UI') { . (Join-Path $script:Root "src\$f.ps1") }

# values arrive as one string from reclaim.cmd ("a,b"): split them
function Split-List([string[]]$v) { return @($v | ForEach-Object { $_ -split '[,;]' } | ForEach-Object { $_.Trim().Trim('"') } | Where-Object { $_ }) }
$Targets = Split-List $Targets; $Skip = Split-List $Skip; $DevFolders = Split-List $DevFolders; $Duplicates = Split-List $Duplicates

$script:Cfg = Import-ReclaimSettings
if ($StaleDays -gt 0) { $script:Cfg.StaleDays = $StaleDays }
$logDir = Join-Path $script:Cfg.DataDir 'logs'
if (-not (Test-Path -LiteralPath $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }
$script:LogFile = Join-Path $logDir ('reclaim-{0}.log' -f (Get-Date -Format 'yyyyMMdd'))
$script:IsAdmin = Test-IsAdmin
$script:DryRun = [bool]$DryRun
$script:Quiet = [bool]$Quiet
$script:Force = [bool]$Force
$script:NoReport = [bool]$NoReport
$script:NonInteractive = ($Quiet -or $Yes) -and -not $Pause
Write-Log ("Start {0} admin={1} dry={2} args={3}" -f $script:ReclaimVersion, $script:IsAdmin, $script:DryRun, ($PSBoundParameters.Keys -join ','))

function Exit-Reclaim([int]$code) {
    if ($Pause) { Wait-AnyKey }
    exit $code
}

function Show-RowsTable($rows) {
    $w = Get-ConsoleWidth
    $lastGroup = $null
    foreach ($r in $rows) {
        if ($r.Group -ne $lastGroup) { Out-Line ("-- {0}" -f $r.Group) 'DarkCyan'; $lastGroup = $r.Group }
        $size = if ($r.Bytes -lt 0) { '?' } else { Format-Size $r.Bytes }
        $flag = if ($r.Status -ne 'ready') { "  ($($r.Status))" } else { '' }
        Out-Line ('{0,10}  {1,-8} {2,-24} {3}{4}' -f $size, $r.Risk, $r.Id, (Limit-Text $r.Name ($w - 50)), $flag) $(if ($r.Status -eq 'ready') { Get-RiskColor $r.Risk } else { 'DarkGray' })
    }
}

try {
    if ($Version) { Out-Line "Reclaim $script:ReclaimVersion"; Exit-Reclaim 0 }

    if ($SelfTest) { & (Join-Path $script:Root 'tests\SelfTest.ps1'); Exit-Reclaim $LASTEXITCODE }

    Initialize-Engine
    $script:Catalog = Import-ReclaimTargets

    if ($CheckSpace) { Exit-Reclaim (Invoke-SpaceCheck) }

    if ($List) {
        $rows = $script:Catalog | Sort-Object @{ e = { [array]::IndexOf($script:Groups, $_.Group) } }, Id | ForEach-Object {
            $p = @(); foreach ($x in 'Quick', 'Dev', 'Deep') { if (Test-InPreset $_ $x) { $p += $x } }
            [pscustomobject]@{ Id = $_.Id; Group = $_.Group; Risk = $_.Risk; Admin = $_.Admin; Presets = ($p -join ','); Name = $_.Name }
        }
        if ($Json) { $rows | ConvertTo-Json -Depth 3 } else { $rows | Format-Table -AutoSize | Out-String -Width 220 | Write-Host }
        Exit-Reclaim 0
    }

    if ($Schedule) {
        switch ($Schedule) {
            'remove' { Unregister-ReclaimSchedule; Out-Line 'Scheduled tasks removed.' 'Green' }
            'status' { Get-ReclaimSchedule | Format-Table -AutoSize | Out-String | Write-Host }
            default  { $n = Register-ReclaimSchedule $Schedule $At; Out-Line "Created scheduled task: $n" 'Green' }
        }
        Exit-Reclaim 0
    }

    if ($Menu) {
        switch ($Menu) {
            'disks' { Invoke-VirtualDisksMenu } 'system' { Invoke-SystemMenu } 'dev' { Invoke-DevFoldersMenu }
            'space' { Invoke-SpaceHogsMenu } 'duplicates' { Invoke-DuplicatesMenu } 'relocate' { Invoke-RelocateMenu }
            'move' { Invoke-MoveMenu } 'growth' { Invoke-GrowthMenu }
        }
        Exit-Reclaim 0
    }

    if ($Growth) { Invoke-GrowthMenu $Growth -NoWait; Exit-Reclaim 0 }

    if ($Analyze) {
        $result = Invoke-SpaceScan $Analyze
        if ($Json) { $result | ConvertTo-Json -Depth 4; Exit-Reclaim 0 }
        Out-Line ('{0}: {1} in {2:N0} files' -f $result.Root, (Format-Size $result.Total), $result.Files) 'White'
        Out-Line 'Biggest folders:' 'Cyan'
        foreach ($f in ($result.Folders | Select-Object -First 25)) { Out-Line ('{0,10}  {1,5}%  {2}{3}' -f (Format-Size $f.Bytes), $f.Percent, $f.Relative, $(if ($f.Known) { "   [clean: $($f.Known)]" } else { '' })) }
        Out-Line 'Biggest files:' 'Cyan'
        foreach ($f in ($result.TopFiles | Select-Object -First 20)) { Out-Line ('{0,10}  {1:yyyy-MM-dd}  {2}' -f (Format-Size $f.Bytes), $f.LastWrite, $f.Path) }
        if (-not $NoReport) { Out-Line ('Report: ' + (Save-ScanReport $result)) 'DarkGray' }
        Exit-Reclaim 0
    }

    if ($DevFolders) {
        $items = Find-DevArtifacts $DevFolders
        if ($Json) { $items | ConvertTo-Json -Depth 3; Exit-Reclaim 0 }
        $total = [int64]0; $stale = @($items | Where-Object { $_.Selected }); $staleBytes = [int64]0
        foreach ($i in $items) { $total += $i.Bytes }; foreach ($i in $stale) { $staleBytes += $i.Bytes }
        $shown = @($items | Where-Object { $_.Bytes -ge 1MB })
        foreach ($i in $shown) {
            $tag = if ($i.Selected) { 'STALE' } elseif ($i.Risk -eq 'Careful') { 'keep?' } else { '     ' }
            Out-Line ('{0,10}  {1,5}d  {2}  {3}' -f (Format-Size $i.Bytes), $(if ($i.AgeDays -ge 9999) { '?' } else { $i.AgeDays }), $tag, $i.Path) $(if ($i.Selected) { 'Yellow' } else { 'Gray' })
        }
        if ($items.Count -gt $shown.Count) { Out-Line ('({0} folders under 1 MB not listed)' -f ($items.Count - $shown.Count)) 'DarkGray' }
        Out-Line ('{0} build folders, {1}; stale ({2}+ days): {3} folders, {4}' -f $items.Count, (Format-Size $total), $script:Cfg.StaleDays, $stale.Count, (Format-Size $staleBytes)) 'White'
        if ($Clean -and $stale.Count) {
            if (-not $Yes -and -not (Read-YesNo ('Delete the {0} stale build folders?' -f $stale.Count) $false)) { Exit-Reclaim 0 }
            $freed = [int64]0
            foreach ($i in $stale) { $freed += (Remove-ReclaimPath @($i.Path) 'Folder' 0 3 $i.Path).Bytes }
            Out-Line ('{0} {1}' -f $(if ($script:DryRun) { 'Would free' } else { 'Freed' }), (Format-Size $freed)) 'Green'
        }
        Exit-Reclaim 0
    }

    if ($Duplicates) {
        $min = if ($MinMB -gt 0) { $MinMB } else { [int]$script:Cfg.DuplicateMinMB }
        $groups = Find-DuplicateFiles $Duplicates $min
        if ($Json) { $groups | ConvertTo-Json -Depth 4; Exit-Reclaim 0 }
        $wasted = [int64]0
        foreach ($g in $groups) {
            $wasted += $g.Wasted
            Out-Line ('{0,10} x{1}' -f (Format-Size $g.Bytes), $g.Files.Count) 'Cyan'
            foreach ($f in $g.Files) { Out-Line ('            {0}' -f $f.Path) 'Gray' }
        }
        Out-Line ('{0} groups, {1} could be freed. Use the menu (7) to choose what to remove.' -f $groups.Count, (Format-Size $wasted)) 'White'
        Exit-Reclaim 0
    }

    if ($Scan -or $Clean) {
        $set = if ($Targets) { Get-TargetsById $Targets } elseif ($Preset) { Get-PresetTargets $Preset } elseif ($Scan) { $script:Catalog } else { throw 'Use -Preset Quick|Dev|Deep or -Targets id1,id2 with -Clean' }
        if ($Skip) { $set = @($set | Where-Object { $Skip -notcontains $_.Id }) }
        $rows = Measure-Targets @($set)
        $rows = @($rows | Sort-Object @{ e = { [array]::IndexOf($script:Groups, $_.Group) } }, @{ e = { $_.Bytes }; Descending = $true })
        if ($Scan) {
            if ($Json) { $rows | Select-Object Id, Group, Name, Risk, Admin, Status, Bytes, Files, Note, Paths | ConvertTo-Json -Depth 3; Exit-Reclaim 0 }
            Show-RowsTable @($rows | Where-Object { $_.Status -notin @('not found') })
            $sum = [int64]0; foreach ($r in $rows) { if ($r.Bytes -gt 0 -and $r.Status -eq 'ready' -and $r.Risk -ne 'Careful') { $sum += $r.Bytes } }
            Out-Line ''
            Out-Line ('Safe + Moderate items you can free now: {0}{1}' -f (Format-Size $sum), $(if (-not $script:IsAdmin) { ' (run as administrator to include system items)' } else { '' })) 'Green'
            Exit-Reclaim 0
        }
        foreach ($r in $rows) {
            $r.Selected = $r.Status -in @('ready', 'needs admin')
            if ($r.Risk -eq 'Careful' -and -not ($Targets -and $Force)) {
                if ($r.Selected) { Out-Line ("Skipping {0}: Careful items need -Targets {0} -Force" -f $r.Id) 'Yellow' }
                $r.Selected = $false
            }
            if ($r.Selected -and $r.Admin -and -not $script:IsAdmin) { Out-Line ("Skipping {0}: needs administrator" -f $r.Id) 'Yellow'; $r.Selected = $false }
        }
        $sel = @($rows | Where-Object { $_.Selected })
        if (-not $Quiet) { Show-RowsTable $sel }
        if (-not $sel.Count) { Out-Line 'Nothing to clean.' 'Green'; Exit-Reclaim 0 }
        if (-not $Yes) { if (-not (Confirm-Selection $rows)) { Out-Line 'Cancelled.' 'Yellow'; Exit-Reclaim 0 } }
        $run = Invoke-CleanRows $rows $Preset
        $errors = 0; foreach ($r in $sel) { $errors += $r.Errors }
        if ($Json) { $run | Select-Object Started, Finished, Preset, DryRun, Freed | ConvertTo-Json }
        Exit-Reclaim $(if ($errors -gt 0) { 2 } else { 0 })
    }

    Show-MainMenu
    Exit-Reclaim 0
} catch {
    Write-Log ("Fatal: " + $_.Exception.ToString()) 'ERROR'
    Write-Host ("Reclaim error: " + $_.Exception.Message) -ForegroundColor Red
    Exit-Reclaim 1
}
