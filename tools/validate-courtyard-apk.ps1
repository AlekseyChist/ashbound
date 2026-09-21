param([Parameter(Mandatory = $true)][string]$ApkPath)
$ErrorActionPreference = 'Stop'
# Export success does not imply that transitive autoload scripts were packaged.
# Check literal script preloads recursively, then still run the actual build.
$projectRoot = Split-Path -Parent $PSScriptRoot
$projectText = [IO.File]::ReadAllText((Join-Path $projectRoot 'project.godot'))
$autoloadSection = [regex]::Match($projectText, '(?s)\[autoload\](.*?)(?:\r?\n\[|\z)').Groups[1].Value
$pending = [Collections.Generic.Queue[string]]::new()
foreach ($match in [regex]::Matches($autoloadSection, 'res://([^"\r\n]+\.gd)')) {
    $pending.Enqueue($match.Groups[1].Value)
}
$scripts = [Collections.Generic.HashSet[string]]::new()
while ($pending.Count -gt 0) {
    $relative = $pending.Dequeue()
    if (-not $scripts.Add($relative)) { continue }
    $source = [IO.File]::ReadAllText((Join-Path $projectRoot $relative))
    foreach ($match in [regex]::Matches($source, '(?:preload|load)\s*\(\s*"res://([^"\r\n]+\.gd)"\s*\)')) {
        $pending.Enqueue($match.Groups[1].Value)
    }
}
Add-Type -AssemblyName System.IO.Compression.FileSystem
$archive = [IO.Compression.ZipFile]::OpenRead((Resolve-Path -LiteralPath $ApkPath).Path)
try {
    $files = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($entry in $archive.Entries) { [void]$files.Add($entry.FullName) }
    $missing = @()
    foreach ($script in $scripts) {
        $resource = 'assets/' + $script
        if (-not $files.Contains($resource) -and -not $files.Contains($resource + '.remap')) { $missing += $script }
    }
    if ($missing.Count -gt 0) { throw ('Missing runtime scripts: ' + ($missing -join ', ')) }
    $diagnostics = @($files | Where-Object { $_ -match '^assets/scripts/tools/|back_probe\.tscn' })
    if ($diagnostics.Count -gt 0) { throw ('QA-only files included: ' + ($diagnostics -join ', ')) }
    Write-Output "ASHBOUND_APK_DEPENDENCIES_OK autoload_scripts=$($scripts.Count) qa_files=0"
} finally {
    $archive.Dispose()
}
