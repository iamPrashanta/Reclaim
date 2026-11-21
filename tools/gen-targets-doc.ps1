# Regenerates docs/TARGETS.md from config/targets.psd1. Run after adding or changing a target.
$root = Split-Path $PSScriptRoot -Parent
$data = Import-PowerShellDataFile -LiteralPath (Join-Path $root 'config\targets.psd1')
$groups = @('Windows', 'Browsers', 'Developer', 'Apps', 'GPU and drivers', 'Android and phones', 'System (admin)')
$lines = New-Object System.Collections.Generic.List[string]
$lines.Add('# Cleaning targets')
$lines.Add('')
$lines.Add('Generated from `config/targets.psd1` by `tools/gen-targets-doc.ps1`. Do not edit by hand.')
$lines.Add('')
$lines.Add('**Risk**: Safe = you will not notice anything. Moderate = something is downloaded or rebuilt again (slower once). Careful = removes things you may want back; never part of a preset, always needs typing `YES`.')
$lines.Add('')
$lines.Add('**Presets**: Q = Quick (Safe, no admin), D = Developer (Safe + Moderate, no admin), X = Deep (Safe + Moderate, with admin).')
$lines.Add('')
foreach ($g in $groups) {
    $ts = @($data.Targets | Where-Object { $_.Group -eq $g })
    if (-not $ts.Count) { continue }
    $lines.Add("## $g")
    $lines.Add('')
    $lines.Add('| Id | What | Risk | Admin | Presets | After cleaning |')
    $lines.Add('| --- | --- | --- | --- | --- | --- |')
    foreach ($t in $ts) {
        $risk = if ($t.Risk) { $t.Risk } else { 'Safe' }
        $p = @()
        if ($risk -ne 'Careful') {
            if ($t.Presets) { $map = @{ Quick = 'Q'; Dev = 'D'; Deep = 'X' }; $p = @($t.Presets | ForEach-Object { $map[$_] }) }
            else {
                if ($risk -eq 'Safe' -and -not $t.Admin) { $p += 'Q' }
                if (-not $t.Admin) { $p += 'D' }
                $p += 'X'
            }
        }
        $after = ([string]$t.After) -replace '\|', '/'
        $lines.Add(('| `{0}` | {1} | {2} | {3} | {4} | {5} |' -f $t.Id, $t.Name, $risk, $(if ($t.Admin) { 'yes' } else { '' }), ($p -join ' '), $after))
    }
    $lines.Add('')
}
$lines.Add(('{0} targets in total.' -f $data.Targets.Count))
[IO.File]::WriteAllLines((Join-Path $root 'docs\TARGETS.md'), $lines, (New-Object Text.UTF8Encoding($false)))
Write-Host ('docs\TARGETS.md written ({0} targets)' -f $data.Targets.Count)
