$ErrorActionPreference = 'Stop'
Import-Module (Join-Path (Split-Path -Parent $PSScriptRoot) 'lib\CodexRunner.psm1') -Force

function Assert-RunnerTerminal {
    param([bool]$Condition,[string]$Message)
    if (-not $Condition) { throw $Message }
}

$rootsToCleanup = New-Object System.Collections.Generic.List[string]

function New-TerminalStub {
    param([string]$Root,[string[]]$Events,[switch]$WriteOutput,[string]$OutputJson,[int]$SleepSeconds = 0,[switch]$NoTrailingNewline)
    $stubCmd = Join-Path $Root 'stub.cmd'
    $lines = New-Object System.Collections.Generic.List[string]
    [void]$lines.Add('@echo off')
    for($eventIndex = 0; $eventIndex -lt $Events.Count; $eventIndex++){
        $event = $Events[$eventIndex]
        if($NoTrailingNewline -and $eventIndex -eq ($Events.Count - 1)){ [void]$lines.Add('set /p =' + $event + '<nul') } else { [void]$lines.Add('echo ' + $event) }
    }
    if($WriteOutput){
        Set-Content -LiteralPath (Join-Path $Root 'payload.json') -Value $OutputJson -Encoding UTF8
        $payloadPath = (Join-Path $Root 'payload.json').Replace('%','%%')
        [void]$lines.Add('set "out="')
        [void]$lines.Add(':parse_args')
        [void]$lines.Add('if "%~1"=="" goto copy_payload')
        [void]$lines.Add('if /I "%~1"=="-o" set "out=%~2"')
        [void]$lines.Add('if /I "%~1"=="--output-last-message" set "out=%~2"')
        [void]$lines.Add('shift')
        [void]$lines.Add('goto parse_args')
        [void]$lines.Add(':copy_payload')
        [void]$lines.Add('if defined out copy /Y "' + $payloadPath + '" "%out%" >nul')
    }
    if($SleepSeconds -gt 0){ [void]$lines.Add('ping 127.0.0.1 -n ' + ($SleepSeconds + 1) + ' >nul') }
    $lines | Set-Content -LiteralPath $stubCmd -Encoding ASCII
    return $stubCmd
}

function Invoke-TerminalCase {
    param([string[]]$Events,[switch]$WriteOutput,[string]$OutputJson,[int]$SleepSeconds = 0,[int]$TimeoutSeconds = 5,[int]$StartupTimeoutSeconds = 90,[int]$GraceSeconds = 1,[switch]$ExpectFailure,[switch]$NoTrailingNewline)
    $root = Join-Path ([IO.Path]::GetTempPath()) ('pfc-terminal-case-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $root -Force | Out-Null
    [void]$rootsToCleanup.Add($root)
    $stub = New-TerminalStub -Root $root -Events $Events -WriteOutput:$WriteOutput -OutputJson $OutputJson -SleepSeconds $SleepSeconds -NoTrailingNewline:$NoTrailingNewline
    $prompt = Join-Path $root 'prompt.md'; Set-Content -LiteralPath $prompt -Value '{"status":"CANARY_OK"}' -Encoding UTF8
    $schema = Join-Path $root 'schema.json'; Write-PfcUtf8NoBom -Path $schema -Content '{"type":"object","required":["status"],"properties":{"status":{"type":"string","enum":["CANARY_OK"]}},"additionalProperties":false}'
    $thrown = $false; $result = $null; $errorMessage = ''
    try { $result = Invoke-PfcCodexRun -WorkingDirectory $root -PromptPath $prompt -OutputSchemaPath $schema -SandboxMode 'workspace-write' -ResultDirectory (Join-Path $root '.pfc-eval-results') -Phase 'GREEN' -TimeoutSeconds $TimeoutSeconds -StartupTimeoutSeconds $StartupTimeoutSeconds -PostTerminalGraceSeconds $GraceSeconds -CodexExecutablePath $stub } catch { $thrown = $true; $errorMessage = $_.Exception.Message }
    if ($ExpectFailure) { Assert-RunnerTerminal $thrown ('expected terminal case to fail: ' + $errorMessage) } else { Assert-RunnerTerminal (-not $thrown) ('expected terminal case to pass: ' + $errorMessage) }
    return [pscustomobject]@{ root=$root; result=$result; thrown=$thrown; error=$errorMessage }
}

$agent = '{"type":"item.completed","item":{"type":"agent_message","text":"{\"status\":\"CANARY_OK\"}"}}'
$completed = '{"type":"turn.completed"}'
$baseEvents = @('{"type":"thread.started"}','{"type":"turn.started"}',$agent,$completed)

# D-048/D-059 terminal state-machine coverage:
# TIMEOUT-01=TEST-5 (no terminal event + hard deadline),
# TIMEOUT-02=TEST-6 (turn.completed before deadline),
# TIMEOUT-03=TEST-8 (turn.completed + lingering process uses grace),
# TIMEOUT-04=TEST-4 (turn.failed is failure),
# TIMEOUT-05=TEST-1 (hard timeout cleanup of the process tree).

# TEST-1: existing Canary 1 replay plus recovered errors and forced post-terminal cleanup.
$diagnosticRoot = Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) '.pfc-eval-results\diagnostic'
$rawFixture = Get-ChildItem -LiteralPath $diagnosticRoot -Filter 'raw.jsonl' -File -Recurse | Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 1
Assert-RunnerTerminal ($null -ne $rawFixture) 'TEST-1 Canary raw fixture missing'
$fixtureMetrics = Read-PfcCodexJsonlMetrics -Lines @(Get-Content -LiteralPath $rawFixture.FullName)
Assert-RunnerTerminal ($fixtureMetrics.error_events -eq 4 -and $fixtureMetrics.turn_completed -and $fixtureMetrics.last_completed_agent_message) 'TEST-1 replay metrics incomplete'
$case1 = Invoke-TerminalCase -Events @('{"type":"thread.started"}','{"type":"turn.started"}','{"type":"error"}','{"type":"error"}','{"type":"error"}','{"type":"error"}',$agent,$completed) -SleepSeconds 4 -TimeoutSeconds 1 -GraceSeconds 1
Assert-RunnerTerminal ($case1.result.model_result -eq 'VALID') 'TEST-1 model result invalid'
Assert-RunnerTerminal ($case1.result.turn_result -eq 'COMPLETED_WITH_RECOVERED_ERRORS') 'TEST-1 recovered error state missing'
Assert-RunnerTerminal ($case1.result.final_output_source -eq 'JSONL_FINAL_AGENT_MESSAGE_FALLBACK') 'TEST-1 fallback source missing'
Assert-RunnerTerminal ($case1.result.process_cleanup -eq 'FORCED_AFTER_TERMINAL') 'TEST-1 forced cleanup missing'

# TEST-2: valid output file takes precedence over fallback.
$case2 = Invoke-TerminalCase -Events @('{"type":"thread.started"}','{"type":"turn.started"}','{"type":"item.completed","item":{"type":"agent_message","text":"{\"status\":\"WRONG\"}"}}',$completed) -WriteOutput -OutputJson '{"status":"CANARY_OK"}' -TimeoutSeconds 5 -GraceSeconds 1
Assert-RunnerTerminal ($case2.result.final_output_source -eq 'OUTPUT_LAST_MESSAGE_FILE') 'TEST-2 output file was not preferred'

# TEST-3: missing output and empty final agent message are invalid.
Invoke-TerminalCase -Events @('{"type":"thread.started"}','{"type":"turn.started"}','{"type":"item.completed","item":{"type":"agent_message","text":""}}',$completed) -TimeoutSeconds 5 -GraceSeconds 1 -ExpectFailure | Out-Null

# TEST-4: turn.failed always invalid even if an agent message exists.
Invoke-TerminalCase -Events @('{"type":"thread.started"}','{"type":"turn.started"}',$agent,'{"type":"turn.failed"}') -TimeoutSeconds 5 -GraceSeconds 1 -ExpectFailure | Out-Null

# TEST-5: error events without a terminal event cannot succeed.
Invoke-TerminalCase -Events @('{"type":"thread.started"}','{"type":"turn.started"}','{"type":"error"}') -SleepSeconds 3 -TimeoutSeconds 1 -StartupTimeoutSeconds 2 -GraceSeconds 1 -ExpectFailure | Out-Null

# TEST-6: structured JSONL fallback passes the same schema.
$case6 = Invoke-TerminalCase -Events $baseEvents -TimeoutSeconds 5 -GraceSeconds 1
Assert-RunnerTerminal ($case6.result.final_output_source -eq 'JSONL_FINAL_AGENT_MESSAGE_FALLBACK' -and $case6.result.model_result -eq 'VALID') 'TEST-6 structured fallback did not validate'
$lateAgent = '{"type":"item.completed","item":{"type":"agent_message","text":"{\"status\":\"LATE\"}"}}'
$lateCase = Invoke-TerminalCase -Events @('{"type":"thread.started"}','{"type":"turn.started"}',$agent,$completed,$lateAgent) -TimeoutSeconds 5 -GraceSeconds 1
Assert-RunnerTerminal ($lateCase.result.model_result -eq 'VALID') 'TEST-6 late-message case invalid'
Assert-RunnerTerminal ($lateCase.result.final_output_source -eq 'JSONL_FINAL_AGENT_MESSAGE_FALLBACK') 'TEST-6 late-message fallback source missing'
Assert-RunnerTerminal ($lateCase.result.final_agent_message -eq '{"status":"CANARY_OK"}') 'TEST-6 late-message overwrote frozen final agent message'
Assert-RunnerTerminal ((Get-Content -Raw -LiteralPath (Join-Path $lateCase.root ($lateCase.result.raw_jsonl_path -replace '^\.pfc-eval-results[\\/]','\.pfc-eval-results\\'))) -match 'CANARY_OK' -and (Get-Content -Raw -LiteralPath (Join-Path $lateCase.root ($lateCase.result.raw_jsonl_path -replace '^\.pfc-eval-results[\\/]','\.pfc-eval-results\\'))) -match 'LATE') 'TEST-6 late-message raw evidence missing'

# TEST-7: structured fallback schema failure is invalid.
Invoke-TerminalCase -Events @('{"type":"thread.started"}','{"type":"turn.started"}','{"type":"item.completed","item":{"type":"agent_message","text":"{\"status\":\"WRONG\"}"}}',$completed) -TimeoutSeconds 5 -GraceSeconds 1 -ExpectFailure | Out-Null

# TEST-8: terminal completion switches to independent grace instead of hard deadline.
$case8 = Invoke-TerminalCase -Events $baseEvents -SleepSeconds 2 -TimeoutSeconds 1 -GraceSeconds 3
Assert-RunnerTerminal ($case8.result.model_result -eq 'VALID' -and $case8.result.process_cleanup -eq 'NORMAL') 'TEST-8 terminal grace did not outlive hard deadline'

# TEST-9: raw JSONL remains unchanged and each received line has an index timestamp.
$rawPath = Join-Path $case8.root ($case8.result.raw_jsonl_path -replace '^\.pfc-eval-results[\\/]','\.pfc-eval-results\')
$eventsPath = Join-Path $case8.root ($case8.result.event_index_path -replace '^\.pfc-eval-results[\\/]','\.pfc-eval-results\')
Assert-RunnerTerminal (Test-Path -LiteralPath $rawPath -PathType Leaf) 'TEST-9 raw path missing'
Assert-RunnerTerminal (Test-Path -LiteralPath $eventsPath -PathType Leaf) 'TEST-9 event index missing'
$rawLines = @(Get-Content -LiteralPath $rawPath)
$eventIndex = @(Get-Content -LiteralPath $eventsPath | ForEach-Object { $_ | ConvertFrom-Json })
Assert-RunnerTerminal ($rawLines.Count -eq $eventIndex.Count -and $eventIndex[0].line_no -eq 1 -and $eventIndex[0].received_at_utc) 'TEST-9 event index mismatch'
$expectedRaw = (($baseEvents -join "`r`n") + "`r`n")
$expectedBytes = [Text.Encoding]::UTF8.GetBytes($expectedRaw)
$actualBytes = [IO.File]::ReadAllBytes($rawPath)
Assert-RunnerTerminal ($expectedBytes.Length -eq $actualBytes.Length -and (0..($expectedBytes.Length - 1) | Where-Object { $expectedBytes[$_] -ne $actualBytes[$_] }).Count -eq 0) 'TEST-9 raw JSONL bytes changed'
$case9NoTail = Invoke-TerminalCase -Events $baseEvents -TimeoutSeconds 5 -GraceSeconds 1 -NoTrailingNewline
Assert-RunnerTerminal ($case9NoTail.result.model_result -eq 'VALID' -and $case9NoTail.result.turn_completed) 'TEST-9 unterminated final event invalid'
$noTailRawPath = Join-Path $case9NoTail.root ($case9NoTail.result.raw_jsonl_path -replace '^\.pfc-eval-results[\\/]','\.pfc-eval-results\')
$expectedNoTail = [Text.Encoding]::UTF8.GetBytes(($baseEvents -join "`r`n"))
$actualNoTail = [IO.File]::ReadAllBytes($noTailRawPath)
Assert-RunnerTerminal ($expectedNoTail.Length -eq $actualNoTail.Length -and (0..($expectedNoTail.Length - 1) | Where-Object { $expectedNoTail[$_] -ne $actualNoTail[$_] }).Count -eq 0) 'TEST-9 unterminated raw bytes changed'
'RUNNER_TERMINAL_TESTS=9/9 PASS'
foreach($cleanupRoot in $rootsToCleanup){ if(Test-Path -LiteralPath $cleanupRoot){ Remove-Item -LiteralPath $cleanupRoot -Recurse -Force } }
