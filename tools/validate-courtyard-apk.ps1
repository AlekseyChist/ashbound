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
# The modal menu is reached through a scene, not through an autoload.
# Include its script closure so section controllers cannot disappear in exports.
foreach ($relative in @('scripts/courtyard/courtyard_save_schema.gd', 'scripts/courtyard/courtyard_save_store.gd', 'scripts/courtyard/touch_inventory_panel.gd', 'scripts/courtyard/courtyard_level.gd', 'scripts/courtyard/courtyard_map_stand.gd', 'scripts/characters/character_progress.gd')) {
    $pending.Enqueue($relative)
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
    # Selected-scene exports may omit art loaded only through a script preload.
    # Require both its import descriptor and every referenced GPU texture.
    $inventoryArt = @(
        'assets/ui/inventory/items-v1.png',
        'assets/ui/inventory/pocket-v1.png',
        'assets/ui/inventory/backpack-v1.png',
        'assets/ui/inventory/pouch-v1.png',
        'assets/ui/maps/courtyard-sketch-v1.png',
        'assets/characters/courtyard/painted-backpack/traveler-side-pack.png',
        'assets/characters/courtyard/painted-backpack/traveler-back-pack.png',
        'assets/characters/courtyard/painted-backpack/traveler-front-pack.png',
        'assets/characters/courtyard/painted-backpack/traveler-front-idle-correction.png',
        'assets/characters/courtyard/painted-backpack/traveler-run-side-pack.png',
        'assets/characters/courtyard/painted-backpack/traveler-run-back-pack.png',
        'assets/characters/courtyard/painted-backpack/traveler-run-front-pack.png',
        'assets/characters/courtyard/painted-backpack/traveler-pocket-pack.png'
    )
    foreach ($relative in $inventoryArt) {
        $descriptor = $archive.GetEntry('assets/' + $relative + '.import')
        if ($null -eq $descriptor) { throw "Missing inventory texture descriptor: $relative" }
        $reader = [IO.StreamReader]::new($descriptor.Open())
        try { $importText = $reader.ReadToEnd() } finally { $reader.Dispose() }
        $paths = @([regex]::Matches($importText, '(?m)^path(?:\.[^=]+)?="res://([^"\r\n]+)"'))
        if ($paths.Count -eq 0) { throw "Texture descriptor has no runtime path: $relative" }
        foreach ($match in $paths) {
            if (-not $files.Contains('assets/' + $match.Groups[1].Value)) { throw "Missing imported inventory image: $($match.Groups[1].Value)" }
        }
    }
    foreach ($relative in @('assets/characters/courtyard/traveler_backpack_frames.tres','assets/characters/courtyard/traveler_backpack_pocket_frames.tres')) {
        if (-not $files.Contains('assets/' + $relative) -and -not $files.Contains('assets/' + $relative + '.remap')) { throw "Missing painted frame resource: $relative" }
    }
    if ($files.Contains('assets/assets/characters/courtyard/traveler-backpack-layer-v1.png.import')) { throw 'Rejected accessory overlay still exported' }
    $diagnostics = @($files | Where-Object { $_ -match '^assets/scripts/tools/|back_probe\.tscn' })
    if ($diagnostics.Count -gt 0) { throw ('QA-only files included: ' + ($diagnostics -join ', ')) }
    Write-Output "ASHBOUND_APK_DEPENDENCIES_OK autoload_scripts=$($scripts.Count) inventory_images=$($inventoryArt.Count) qa_files=0"
} finally {
    $archive.Dispose()
}
