# Reports: every clean and every analysis can be saved as JSON + a self-contained HTML page.
# History of cleans goes to history.csv (date, preset, freed) so you can see the total over time.

function ConvertTo-HtmlText([string]$s) { return [System.Net.WebUtility]::HtmlEncode([string]$s) }

function New-HtmlReport([string]$title, [string]$subtitle, $summary, $sections) {
    # summary: ordered list of @{ Label; Value }   sections: list of @{ Title; Note; Headers; Rows (arrays); Align }
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.Append(@"
<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>$(ConvertTo-HtmlText $title)</title>
<style>
:root{--bg:#f6f7f4;--card:#fff;--fg:#1d2420;--muted:#5f6b64;--line:#dfe4df;--accent:#1f7a4d;--warn:#a86a00;--bad:#b3261e;--bar:#cfe6d8}
@media (prefers-color-scheme:dark){:root{--bg:#121614;--card:#1a201d;--fg:#e6ece8;--muted:#9aa8a0;--line:#2b342f;--accent:#5cc58f;--warn:#e0a83a;--bad:#ef6b62;--bar:#24412f}}
*{box-sizing:border-box}body{margin:0;background:var(--bg);color:var(--fg);font:14px/1.5 "Segoe UI",system-ui,sans-serif}
main{max-width:1100px;margin:0 auto;padding:24px max(16px,env(safe-area-inset-left))}
h1{font-size:24px;margin:0 0 4px}h2{font-size:17px;margin:28px 0 8px}.sub{color:var(--muted);margin:0 0 20px}
.cards{display:grid;grid-template-columns:repeat(auto-fit,minmax(170px,1fr));gap:12px}
.card{background:var(--card);border:1px solid var(--line);border-radius:10px;padding:12px 14px}
.card b{display:block;font-size:20px;font-variant-numeric:tabular-nums}.card span{color:var(--muted);font-size:12px;text-transform:uppercase;letter-spacing:.04em}
.wrap{overflow-x:auto;background:var(--card);border:1px solid var(--line);border-radius:10px}
table{border-collapse:collapse;width:100%;min-width:560px}th,td{padding:7px 10px;border-bottom:1px solid var(--line);text-align:left;vertical-align:top}
th{font-size:12px;color:var(--muted);text-transform:uppercase;letter-spacing:.04em}td.n{text-align:right;font-variant-numeric:tabular-nums;white-space:nowrap}
td.p{font-family:Consolas,monospace;font-size:12px;word-break:break-all}tr:last-child td{border-bottom:0}
.note{color:var(--muted);font-size:13px;margin:6px 0 0}.Safe{color:var(--accent)}.Moderate{color:var(--warn)}.Careful{color:var(--bad)}
.bar{height:6px;background:var(--bar);border-radius:3px;min-width:2px}
footer{color:var(--muted);font-size:12px;margin:28px 0 8px}
</style></head><body><main>
<h1>$(ConvertTo-HtmlText $title)</h1><p class="sub">$(ConvertTo-HtmlText $subtitle)</p>
"@)
    if ($summary) {
        [void]$sb.Append('<div class="cards">')
        foreach ($c in $summary) { [void]$sb.AppendFormat('<div class="card"><span>{0}</span><b>{1}</b></div>', (ConvertTo-HtmlText $c.Label), (ConvertTo-HtmlText $c.Value)) }
        [void]$sb.Append('</div>')
    }
    foreach ($s in $sections) {
        [void]$sb.AppendFormat('<h2>{0}</h2>', (ConvertTo-HtmlText $s.Title))
        if ($s.Note) { [void]$sb.AppendFormat('<p class="note">{0}</p>', (ConvertTo-HtmlText $s.Note)) }
        [void]$sb.Append('<div class="wrap"><table><thead><tr>')
        foreach ($h in $s.Headers) { [void]$sb.AppendFormat('<th>{0}</th>', (ConvertTo-HtmlText $h)) }
        [void]$sb.Append('</tr></thead><tbody>')
        foreach ($r in $s.Rows) {
            [void]$sb.Append('<tr>')
            for ($i = 0; $i -lt $r.Count; $i++) {
                $cls = ''
                if ($s.Align -and $i -lt $s.Align.Count) { $cls = $s.Align[$i] }
                $v = [string]$r[$i]
                if ($cls -eq 'bar') {
                    $pct = [Math]::Min(100, [Math]::Max(0, [double]$v))
                    [void]$sb.AppendFormat('<td style="width:120px"><div class="bar" style="width:{0}%"></div></td>', $pct.ToString([Globalization.CultureInfo]::InvariantCulture))
                } elseif ($cls -eq 'risk') {
                    [void]$sb.AppendFormat('<td class="{0}">{0}</td>', (ConvertTo-HtmlText $v))
                } else {
                    [void]$sb.AppendFormat('<td class="{0}">{1}</td>', $cls, (ConvertTo-HtmlText $v))
                }
            }
            [void]$sb.Append('</tr>')
        }
        [void]$sb.Append('</tbody></table></div>')
    }
    [void]$sb.AppendFormat('<footer>Reclaim {0} &middot; {1} &middot; {2}</footer></main></body></html>', $script:ReclaimVersion, (ConvertTo-HtmlText $env:COMPUTERNAME), (Get-Date -Format 'yyyy-MM-dd HH:mm'))
    return $sb.ToString()
}

function Save-Report([string]$kind, $data, [string]$html) {
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $base = Join-Path $script:Cfg.ReportsDir ("{0}-{1}" -f $kind, $stamp)
    ($data | ConvertTo-Json -Depth 6) | Set-Content -LiteralPath ($base + '.json') -Encoding UTF8
    $html | Set-Content -LiteralPath ($base + '.html') -Encoding UTF8
    Set-StateValue 'LastReport' ($base + '.html')
    return ($base + '.html')
}

function Get-DriveSnapshot { return @(Get-FixedDrives | ForEach-Object { [pscustomobject]@{ Drive = $_.Name; Free = $_.Free; Total = $_.Total } }) }

function Save-CleanReport($run) {
    $rows = @($run.Items | Sort-Object Freed -Descending)
    $data = [pscustomobject]@{
        Tool = 'Reclaim'; Version = $script:ReclaimVersion; Kind = 'clean'; Started = $run.Started; Finished = $run.Finished
        Preset = $run.Preset; DryRun = $run.DryRun; Admin = $run.Admin; Computer = $env:COMPUTERNAME
        Freed = $run.Freed; DrivesBefore = $run.DrivesBefore; DrivesAfter = $run.DrivesAfter
        Items = @($rows | ForEach-Object { [pscustomobject]@{ Id = $_.Id; Name = $_.Name; Group = $_.Group; Risk = $_.Risk
            Found = $_.Bytes; Freed = $_.Freed; InUse = $_.InUse; Errors = $_.Errors; Result = $_.Result; Paths = $_.Paths } })
    }
    $summary = @(
        @{ Label = $(if ($run.DryRun) { 'Would free' } else { 'Freed' }); Value = (Format-Size $run.Freed) }
        @{ Label = 'Items cleaned'; Value = ('{0}' -f $rows.Count) }
        @{ Label = 'Preset'; Value = $(if ($run.Preset) { $run.Preset } else { 'chosen items' }) }
        @{ Label = 'Duration'; Value = ('{0:N0} s' -f ($run.Finished - $run.Started).TotalSeconds) }
    )
    $drv = New-Object System.Collections.ArrayList
    foreach ($b in $run.DrivesBefore) {
        $a = $run.DrivesAfter | Where-Object { $_.Drive -eq $b.Drive }
        [void]$drv.Add(@($b.Drive, (Format-Size $b.Free), (Format-Size $a.Free), (Format-Size ($a.Free - $b.Free)), (Format-Size $b.Total)))
    }
    $items = New-Object System.Collections.ArrayList
    foreach ($r in $rows) { [void]$items.Add(@($r.Group, $r.Name, $r.Risk, (Format-Size $r.Bytes), (Format-Size $r.Freed), $r.Result)) }
    $sections = @(
        @{ Title = 'Drives'; Headers = @('Drive', 'Free before', 'Free after', 'Change', 'Size'); Rows = $drv; Align = @('', 'n', 'n', 'n', 'n') }
        @{ Title = 'What was cleaned'; Headers = @('Group', 'Item', 'Risk', 'Found', 'Freed', 'Result'); Rows = $items; Align = @('', '', 'risk', 'n', 'n', '') }
    )
    $title = if ($run.DryRun) { 'Reclaim dry run' } else { 'Reclaim clean report' }
    $html = New-HtmlReport $title ('{0} on {1}' -f $run.Started.ToString('dddd d MMMM yyyy, HH:mm'), $env:COMPUTERNAME) $summary $sections
    $path = Save-Report 'clean' $data $html
    if (-not $run.DryRun) {
        $hist = Join-Path $script:Cfg.ReportsDir 'history.csv'
        [pscustomobject]@{ Date = $run.Started.ToString('yyyy-MM-dd HH:mm'); Preset = $(if ($run.Preset) { $run.Preset } else { 'custom' })
            FreedBytes = $run.Freed; Items = $rows.Count; Report = $path } | Export-Csv -LiteralPath $hist -Append -NoTypeInformation -Encoding UTF8
    }
    return $path
}

function Save-ScanReport($scan) {
    $summary = @(
        @{ Label = 'Scanned'; Value = (Format-Size $scan.Total) }
        @{ Label = 'Files'; Value = ('{0:N0}' -f $scan.Files) }
        @{ Label = ('Untouched {0}+ days' -f $scan.OldDays); Value = (Format-Size $scan.OldBytes) }
        @{ Label = 'Unreadable folders'; Value = ('{0:N0}' -f $scan.Errors) }
    )
    $f = New-Object System.Collections.ArrayList
    $top = @($scan.Folders | Select-Object -First 60)
    $maxB = if ($top.Count) { [double]$top[0].Bytes } else { 1 }
    foreach ($x in $top) { [void]$f.Add(@($x.Relative, (Format-Size $x.Bytes), [math]::Round(100 * $x.Bytes / [Math]::Max([double]1, $maxB), 1), ('{0}%' -f $x.Percent), $x.Known)) }
    $b = New-Object System.Collections.ArrayList
    foreach ($x in $scan.TopFiles) { [void]$b.Add(@($x.Path, (Format-Size $x.Bytes), $x.LastWrite.ToString('yyyy-MM-dd'))) }
    $e = New-Object System.Collections.ArrayList
    foreach ($x in $scan.Extensions) { [void]$e.Add(@($x.Ext, (Format-Size $x.Bytes), ('{0:N0}' -f $x.Files))) }
    $sections = @(
        @{ Title = 'Biggest folders'; Note = 'Folders marked with a Reclaim id can be cleaned from the menu.'; Headers = @('Folder', 'Size', '', 'Share', 'Reclaim id'); Rows = $f; Align = @('p', 'n', 'bar', 'n', '') }
        @{ Title = 'Biggest files'; Headers = @('File', 'Size', 'Last changed'); Rows = $b; Align = @('p', 'n', 'n') }
        @{ Title = 'By file type'; Headers = @('Extension', 'Size', 'Files'); Rows = $e; Align = @('', 'n', 'n') }
    )
    $html = New-HtmlReport ('Space report: ' + $scan.Root) ('Scanned {0}' -f (Get-Date -Format 'dddd d MMMM yyyy, HH:mm')) $summary $sections
    $data = $scan | Select-Object Root, Total, Files, Dirs, Errors, OldBytes, OldDays, @{ n = 'Folders'; e = { @($_.Folders | Select-Object -First 200) } }, TopFiles, Extensions
    return (Save-Report 'space' $data $html)
}

function Get-History {
    $hist = Join-Path $script:Cfg.ReportsDir 'history.csv'
    if (-not (Test-Path -LiteralPath $hist)) { return @() }
    return @(Import-Csv -LiteralPath $hist)
}
