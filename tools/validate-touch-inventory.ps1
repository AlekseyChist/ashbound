param(
  [string[]]$Cases = @('wearable_storage','touch_inventory','backpack_visual','inventory_menu','inventory_back','inventory_storage_layout','inventory_storage','inventory_snapshot','inventory_snapshot_edges','inventory_trade','inventory_trade_edges','inventory_ownership','inventory_ownership_edges','localization','courtyard_localization','courtyard','inventory_gesture','courtyard_input_order','menu_journal','character_progress','character_sheet'),
  [switch]$Render
)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
$engine = Join-Path $projectRoot '.tools/godot/Godot_v4.7.2-stable_win64_console.exe'
$failed = 0
foreach ($case in $Cases) {
  if ($case -notmatch '^[a-z_]+$') { throw 'Invalid QA case name' }
  $outputPath = Join-Path $projectRoot ".tools/touch-qa-$case.txt"
  $errorPath = Join-Path $projectRoot ".tools/touch-qa-$case-stderr.txt"
  $engineArgs = @('--path','.', '--script',"res://scripts/tools/validate_$case.gd",'--log-file',".tools/touch-qa-$case.log")
  if (-not $Render) { $engineArgs = @('--headless') + $engineArgs }
  $proc = Start-Process -FilePath $engine -WorkingDirectory $projectRoot -ArgumentList $engineArgs -PassThru -WindowStyle Hidden -RedirectStandardOutput $outputPath -RedirectStandardError $errorPath
  if (-not $proc.WaitForExit(45000)) {
    Stop-Process -Id $proc.Id
    $failed++
    Write-Output "FAIL $case timeout"
    continue
  }
  $content = [IO.File]::ReadAllText($outputPath) + [IO.File]::ReadAllText($errorPath)
  if ($proc.ExitCode -eq 0 -and $content -match 'ASHBOUND_[A-Z_]+_OK' -and $content -notmatch '(?m)^(SCRIPT ERROR:|ERROR:|.*_FAIL:|.*_FAILED|.*_TIMEOUT)') {
    Write-Output "PASS $case"
  } else {
    $failed++
    Write-Output "FAIL $case exit=$($proc.ExitCode)"
    $content -split "`n" | Where-Object { $_ -match 'ERROR:|_FAIL|_TIMEOUT|ASHBOUND_.*OK' } | Select-Object -First 16 | Write-Output
  }
}
Write-Output "TOUCH_QA_COMPLETE cases=$($Cases.Count) failed=$failed"
if ($failed -gt 0) { exit 1 }
exit 0
