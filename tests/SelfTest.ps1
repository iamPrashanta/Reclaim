# Reclaim self test: builds a throw-away folder tree in %TEMP% and checks the safety rules
# and the engine against it. Touches nothing outside that sandbox. Run: reclaim -SelfTest
$ErrorActionPreference = 'Stop'
$script:Root = Split-Path $PSScriptRoot -Parent
foreach ($f in 'Core', 'System', 'Targets', 'Analyze', 'Report', 'Move', 'UI') { . (Join-Path $script:Root "src\$f.ps1") }
$script:Cfg = Import-ReclaimSettings
$script:Quiet = $true
$script:DryRun = $false
$script:IsAdmin = Test-IsAdmin
$script:NoReport = $true
Initialize-Engine
$script:Catalog = Import-ReclaimTargets

$script:pass = 0; $script:fail = 0
function Check([string]$name, [scriptblock]$test) {
    try {
        $ok = & $test
        if ($ok) { $script:pass++; Write-Host ("  PASS  {0}" -f $name) -ForegroundColor Green }
        else { $script:fail++; Write-Host ("  FAIL  {0}" -f $name) -ForegroundColor Red }
    } catch { $script:fail++; Write-Host ("  FAIL  {0}: {1}" -f $name, $_.Exception.Message) -ForegroundColor Red }
}
function Throws([scriptblock]$s) { try { & $s; return $false } catch { return $true } }
function New-File([string]$path, [int]$bytes, [int]$ageDays = 0) {
    $dir = Split-Path $path -Parent
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $buf = New-Object byte[] $bytes
    (New-Object Random 42).NextBytes($buf)
    [IO.File]::WriteAllBytes($path, $buf)
    if ($ageDays) { (Get-Item -LiteralPath $path).LastWriteTime = (Get-Date).AddDays(-$ageDays) }
}

$id = [guid]::NewGuid().ToString('N').Substring(0, 8)
$sb = Join-Path $env:TEMP "reclaim-test-$id"
$precious = Join-Path $env:TEMP "reclaim-test-$id-precious"
Write-Host "Reclaim self test in $sb" -ForegroundColor Cyan
try {
    New-File (Join-Path $precious 'keep.txt') 1000
    $t = Join-Path $sb 'target'
    New-File (Join-Path $t 'a.bin') 10000
    New-File (Join-Path $t 'sub\b.bin') 20000
    New-File (Join-Path $t 'readonly.txt') 500
    (Get-Item -LiteralPath (Join-Path $t 'readonly.txt')).IsReadOnly = $true
    New-File (Join-Path $t 'old.log') 300 10
    New-File (Join-Path $t 'new.log') 300 0
    New-Item -ItemType Junction -Path (Join-Path $t 'link-to-precious') -Target $precious | Out-Null
    # a path longer than 260 characters
    $long = $t
    while ($long.Length -lt 320) { $long = Join-Path $long 'a-rather-long-folder-name-for-testing' }
    $longOk = $true
    try { [IO.Directory]::CreateDirectory('\\?\' + $long) | Out-Null; [IO.File]::WriteAllText('\\?\' + (Join-Path $long 'deep.txt'), 'x') } catch { $longOk = $false }

    Write-Host 'Safety guard' -ForegroundColor Cyan
    Check 'refuses a drive root' { Throws { [Reclaim.Engine]::Guard('C:\', 3) } }
    Check 'refuses a top-level folder' { Throws { [Reclaim.Engine]::Guard('C:\Windows', 3) } }
    Check 'refuses wildcards' { Throws { [Reclaim.Engine]::Guard((Join-Path $sb '*'), 3) } }
    Check 'refuses relative paths' { Throws { [Reclaim.Engine]::Guard('target\x', 3) } }
    Check 'protects Windows, user profile, Program Files, Documents' {
        (Test-ProtectedPath $env:SystemRoot) -and (Test-ProtectedPath $env:USERPROFILE) -and (Test-ProtectedPath $env:ProgramFiles) -and
        (Test-ProtectedPath "$env:USERPROFILE\Documents") -and (Test-ProtectedPath "$env:SystemRoot\System32\drivers") -and (Test-ProtectedPath $script:Root)
    }
    Check 'does not protect a normal cache folder' { -not (Test-ProtectedPath "$env:LOCALAPPDATA\npm-cache\_cacache") }
    Check 'Remove-ReclaimPath skips a protected path' { (Remove-ReclaimPath @($env:USERPROFILE) 'Contents' 0 3 'x').Bytes -eq 0 }

    Write-Host 'Engine' -ForegroundColor Cyan
    Check 'measure counts files and ignores the junction' {
        $m = [Reclaim.Engine]::Measure($t, 0, $null)
        $expect = 10000 + 20000 + 500 + 300 + 300 + $(if ($longOk) { 1 } else { 0 })
        ($m.Bytes -eq $expect) -and ($m.Links -ge 1)
    }
    Check 'dry run deletes nothing' {
        $script:DryRun = $true
        $r = Remove-ReclaimPath @($t) 'Contents' 0 3 'dry'
        $script:DryRun = $false
        ($r.Bytes -gt 0) -and (Test-Path -LiteralPath (Join-Path $t 'a.bin'))
    }
    Check 'age filter keeps new files' {
        $r = Remove-ReclaimPath @($t) 'Contents' 5 3 'age'
        (-not (Test-Path -LiteralPath (Join-Path $t 'old.log'))) -and (Test-Path -LiteralPath (Join-Path $t 'new.log')) -and (Test-Path -LiteralPath (Join-Path $t 'a.bin'))
    }
    Check 'full clean empties the folder but keeps it' {
        $r = Remove-ReclaimPath @($t) 'Contents' 0 3 'full'
        (Test-Path -LiteralPath $t) -and (@(Get-ChildItem -LiteralPath $t -Force).Count -eq 0)
    }
    Check 'junction target was NOT touched' { Test-Path -LiteralPath (Join-Path $precious 'keep.txt') }
    Check 'read-only files are deleted' { -not (Test-Path -LiteralPath (Join-Path $t 'readonly.txt')) }
    if ($longOk) { Check 'paths over 260 characters are deleted' { -not [IO.Directory]::Exists('\\?\' + $long) } }
    else { Write-Host '  SKIP  long path test (could not create one here)' -ForegroundColor Yellow }
    Check 'folder mode removes the folder itself' {
        $f = Join-Path $sb 'gone'; New-File (Join-Path $f 'x.bin') 100
        Remove-ReclaimPath @($f) 'Folder' 0 3 'folder' | Out-Null
        -not (Test-Path -LiteralPath $f)
    }
    Check 'file in use is skipped, not fatal' {
        $f = Join-Path $sb 'locked\l.bin'; New-File $f 100
        $fs = [IO.File]::Open($f, 'Open', 'Read', 'None')
        try { $r = Remove-ReclaimPath @((Split-Path $f -Parent)) 'Contents' 0 3 'locked' } finally { $fs.Close() }
        ($r.InUse -eq 1) -and (Test-Path -LiteralPath $f)
    }

    Write-Host 'Paths and catalog' -ForegroundColor Cyan
    New-File (Join-Path $sb 'w\p1\Cache\1.bin') 10
    New-File (Join-Path $sb 'w\p2\Cache\2.bin') 10
    New-File (Join-Path $sb 'w\p3\Other\3.bin') 10
    Check 'wildcard expansion' { (Expand-ReclaimPath (Join-Path $sb 'w\*\Cache')).Count -eq 2 }
    Check 'environment variables expand' { (Expand-ReclaimPath '%TEMP%').Count -eq 1 }
    Check 'catalog loads with unique ids' { $script:Catalog.Count -ge 40 }
    Check 'Careful targets are in no preset' { -not ($script:Catalog | Where-Object { $_.Risk -eq 'Careful' -and ((Test-InPreset $_ 'Quick') -or (Test-InPreset $_ 'Dev') -or (Test-InPreset $_ 'Deep')) }) }
    Check 'Quick preset has no admin or Moderate target' { -not (Get-PresetTargets 'Quick' | Where-Object { $_.Admin -or $_.Risk -ne 'Safe' }) }
    Check 'no target resolves to a protected folder' {
        $bad = @()
        foreach ($x in $script:Catalog) { foreach ($p in $x.Paths) { foreach ($e in (Expand-ReclaimPath $p)) { if ($e -and (Test-ProtectedPath $e) -and -not $x.Handler) { $bad += $e } } } }
        if ($bad) { Write-Host ('        ' + ($bad -join ', ')) -ForegroundColor Yellow }
        $bad.Count -eq 0
    }
    Check 'number list parser' { ((ConvertFrom-NumberList '1, 3 5-7 9-8 99' 10) -join ',') -eq '1,3,5,6,7,8,9' }
    Check 'size formatting' { (Format-Size 1536MB) -eq ('{0:N2} GB' -f 1.5) }

    Write-Host 'Analyzers' -ForegroundColor Cyan
    $d = Join-Path $sb 'dups'
    New-File (Join-Path $d 'one\photo.jpg') 2000000
    Copy-Item -LiteralPath (Join-Path $d 'one\photo.jpg') -Destination (Join-Path $d 'two-copy.jpg')
    New-File (Join-Path $d 'same-size-different.jpg') 2000000
    [IO.File]::WriteAllBytes((Join-Path $d 'same-size-different.jpg'), (New-Object byte[] 2000000))
    New-Item -ItemType HardLink -Path (Join-Path $d 'hardlink.jpg') -Target (Join-Path $d 'one\photo.jpg') | Out-Null
    Check 'duplicates: same content found, hard link and lookalike ignored' {
        $g = @([Reclaim.Engine]::FindDuplicates([string[]]@($d), 1MB, [string[]]@(), $null))
        ($g.Count -eq 1) -and ($g[0].Files.Count -eq 2)
    }
    New-File (Join-Path $sb 'code\app\package.json') 20
    New-File (Join-Path $sb 'code\app\node_modules\lib\index.js') 5000
    New-File (Join-Path $sb 'code\app\.next\cache\x') 3000
    New-File (Join-Path $sb 'code\loose\node_modules\y.js') 100
    New-File (Join-Path $sb 'code\rust\Cargo.toml') 20
    New-File (Join-Path $sb 'code\rust\target\debug\app.exe') 7000
    Check 'build folders: found with markers, ignored without' {
        $a = @(Find-DevArtifacts @((Join-Path $sb 'code')))
        $names = ($a | ForEach-Object { $_.Name } | Sort-Object) -join ','
        $names -eq '.next,node_modules,target'
    }
    Check 'space scan sums folders' {
        $r = [Reclaim.Engine]::Scan((Join-Path $sb 'code'), 2, 5, 1, 365, $null)
        $r.DirBytes[(Join-Path $sb 'code\app')] -eq (20 + 5000 + 3000)
    }
    Check 'labels big non-cache folders (Podman, WSL)' {
        ((Get-PathLabel 'C:\Users\x\.local\share\containers\podman').Label -like 'Podman*') -and ((Get-PathLabel 'C:\Users\x\AppData\Local\wsl\{id}').Label -like 'WSL*') -and (-not (Get-PathLabel 'C:\Users\x\Documents'))
    }
    Check 'what grew: a child that explains the growth replaces its parent' {
        $old = [pscustomobject]@{ Folders = @{ 'C:\u\a' = [int64]1GB; 'C:\u\a\b' = [int64]0 } }
        $scan = [pscustomobject]@{ Folders = @([pscustomobject]@{ Path = 'C:\u\a'; Relative = 'a'; Bytes = [int64]6GB }, [pscustomobject]@{ Path = 'C:\u\a\b'; Relative = 'a\b'; Bytes = [int64]5GB }) }
        $r = @(Compare-SizeSnapshot $scan $old)
        ($r.Count -eq 1) -and ($r[0].Relative -eq 'a\b')
    }
    Check 'HTML report renders' {
        $html = New-HtmlReport 'T' 's' @(@{ Label = 'a'; Value = '1' }) @(@{ Title = 'x'; Headers = @('a', 'b'); Rows = (New-Object System.Collections.ArrayList(, @(, @('1', '2')))); Align = @('', 'n') })
        $html -match '<td class="n">2</td>'
    }
} finally {
    foreach ($p in @($sb, $precious)) { if (Test-Path -LiteralPath $p) { [Reclaim.Engine]::Delete($p, $false, 0, $false, 3, $null) | Out-Null } }
}
Write-Host ''
$color = if ($script:fail) { 'Red' } else { 'Green' }
Write-Host ("{0} passed, {1} failed" -f $script:pass, $script:fail) -ForegroundColor $color
exit $(if ($script:fail) { 1 } else { 0 })
