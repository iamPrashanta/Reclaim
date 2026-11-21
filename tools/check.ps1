# Developer check: parses every script (Windows PowerShell 5.1 and PowerShell 7 if present),
# compiles the engine, refuses non-ASCII characters in .ps1/.psd1 files, then runs the self test.
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$bad = 0
foreach ($f in (Get-ChildItem -LiteralPath $root -Recurse -File | Where-Object { $_.Extension -in @('.ps1', '.psd1') })) {
    $tokens = $null; $errors = $null
    [System.Management.Automation.Language.Parser]::ParseFile($f.FullName, [ref]$tokens, [ref]$errors) | Out-Null
    foreach ($e in $errors) { $bad++; Write-Host ("{0}:{1}: {2}" -f $f.Name, $e.Extent.StartLineNumber, $e.Message) -ForegroundColor Red }
    $text = [IO.File]::ReadAllText($f.FullName)
    if ($text -match '[^\x00-\x7F]') { $bad++; Write-Host ("{0}: contains non-ASCII characters (Windows PowerShell 5.1 would misread them)" -f $f.Name) -ForegroundColor Red }
}
foreach ($f in (Get-ChildItem -LiteralPath (Join-Path $root 'config') -Filter *.psd1)) {
    try { Import-PowerShellDataFile -LiteralPath $f.FullName | Out-Null } catch { $bad++; Write-Host ("{0}: {1}" -f $f.Name, $_.Exception.Message) -ForegroundColor Red }
}
try { Add-Type -TypeDefinition ([IO.File]::ReadAllText((Join-Path $root 'src\Engine.cs'))) -Language CSharp; Write-Host 'Engine compiles.' -ForegroundColor Green }
catch { $bad++; Write-Host ("Engine.cs: " + $_.Exception.Message) -ForegroundColor Red }
if ($bad) { Write-Host "$bad problem(s)." -ForegroundColor Red; exit 1 }
Write-Host ("Parse OK in PowerShell {0}." -f $PSVersionTable.PSVersion) -ForegroundColor Green
& (Join-Path $root 'tests\SelfTest.ps1')
exit $LASTEXITCODE
