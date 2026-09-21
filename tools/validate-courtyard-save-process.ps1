param()
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
$engine = Join-Path $projectRoot '.tools/godot/Godot_v4.7.2-stable_win64_console.exe'
$qaName = 'save-process-' + [guid]::NewGuid().ToString('N')
$qaPath = "res://.tools/$qaName"
$baseArgs = @('--headless','--path',$projectRoot,'--script','res://scripts/tools/validate_courtyard_save_process.gd')
$writerOut = Join-Path $projectRoot ".tools/$qaName-writer.txt"
$writerErr = Join-Path $projectRoot ".tools/$qaName-writer-stderr.txt"
$writer = Start-Process $engine -ArgumentList ($baseArgs + @('--',"--save-qa-path=$qaPath",'--save-qa-phase=write')) -PassThru -WindowStyle Hidden -RedirectStandardOutput $writerOut -RedirectStandardError $writerErr
$ready = $false
try {
    $deadline = [DateTime]::UtcNow.AddSeconds(35)
    while ([DateTime]::UtcNow -lt $deadline -and -not $writer.HasExited) {
        if ((Get-Content $writerOut -Raw -ErrorAction SilentlyContinue) -match 'ASHBOUND_SAVE_PROCESS_WRITER_READY') { $ready=$true; break }
        Start-Sleep -Milliseconds 200
        $writer.Refresh()
    }
    if (-not $ready) { throw 'Save process writer did not complete its checkpoint' }
    if ((Get-Content $writerErr -Raw) -match 'SCRIPT ERROR:|ERROR:|_FAIL:') { throw 'Writer errors' }
} finally {
    if (-not $writer.HasExited) { Stop-Process -Id $writer.Id }
}
$readerOut = Join-Path $projectRoot ".tools/$qaName-reader.txt"
$readerErr = Join-Path $projectRoot ".tools/$qaName-reader-stderr.txt"
$reader = Start-Process $engine -ArgumentList ($baseArgs + @('--',"--save-qa-path=$qaPath",'--save-qa-phase=read')) -PassThru -WindowStyle Hidden -RedirectStandardOutput $readerOut -RedirectStandardError $readerErr
if (-not $reader.WaitForExit(35000)) { Stop-Process -Id $reader.Id; throw 'Save process reader timed out' }
$logs = [IO.File]::ReadAllText($readerOut) + [IO.File]::ReadAllText($readerErr)
if ($reader.ExitCode -ne 0 -or $logs -notmatch 'ASHBOUND_COURTYARD_SAVE_PROCESS_OK' -or $logs -match 'SCRIPT ERROR:|ERROR:|_FAIL:') { throw "Save process reader failed: $logs" }
Write-Output "ASHBOUND_COURTYARD_SAVE_PROCESS_OK killed_writer=$($writer.Id) fresh_reader=$($reader.Id) directory=$qaPath"
