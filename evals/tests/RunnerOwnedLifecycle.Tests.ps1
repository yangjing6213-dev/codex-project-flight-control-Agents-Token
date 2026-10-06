param([switch]$AsFunction)

$modulePath = Join-Path $PSScriptRoot '..\lib\CodexRunner.psm1'
Import-Module $modulePath -Force

function Invoke-CmRunnerLifecycleTests {
    $failures = New-Object 'System.Collections.Generic.List[string]'
    function Assert-Lifecycle([bool]$Condition, [string]$Message) {
        if (-not $Condition) { throw $Message }
    }
    $root = Join-Path ([IO.Path]::GetTempPath()) ('pfc-runner-lifecycle-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $root -Force | Out-Null
    try {
        $path = Join-Path $root 'runner-events.jsonl'
        $sha = 'a' * 40
        Write-PfcRunnerLifecycleEvent -Path $path -EventType child_started -DispatchId D-B1 -ContextId CTX-B1 -Role project_flight_builder -GoalkeeperSessionId ROOT-1 -AtUtc '2026-09-27T10:00:00.0000000Z' -Model gpt-5.6-terra -ReasoningEffort medium -Sandbox workspace-write -TestOnly
        Write-PfcRunnerLifecycleEvent -Path $path -EventType child_completed -DispatchId D-B1 -ContextId CTX-B1 -Role project_flight_builder -GoalkeeperSessionId ROOT-1 -AtUtc '2026-09-27T10:01:00.0000000Z' -Model gpt-5.6-terra -ReasoningEffort medium -Sandbox workspace-write -ExitCode 0 -CandidateSha $sha -RawJsonlPath 'run-builder.jsonl' -TestOnly
        Write-PfcRunnerLifecycleEvent -Path $path -EventType child_started -DispatchId D-V1 -ContextId CTX-V1 -Role project_flight_verifier -GoalkeeperSessionId ROOT-1 -AtUtc '2026-09-27T10:02:00.0000000Z' -Model gpt-5.6-terra -ReasoningEffort medium -Sandbox workspace-write -CandidateSha $sha -TestOnly
        Write-PfcRunnerLifecycleEvent -Path $path -EventType child_completed -DispatchId D-V1 -ContextId CTX-V1 -Role project_flight_verifier -GoalkeeperSessionId ROOT-1 -AtUtc '2026-09-27T10:03:00.0000000Z' -Model gpt-5.6-terra -ReasoningEffort medium -Sandbox workspace-write -ExitCode 0 -CandidateSha $sha -RawJsonlPath 'run-verifier.jsonl' -TestOnly
        $trace = Read-PfcRunnerLifecycle -Path $path -FakeTransport
        Assert-Lifecycle ($trace.status -ceq 'OBSERVED' -and $trace.source -ceq 'RUNNER' -and $trace.observed_child_contexts -eq 2 -and $trace.independent_handoffs.Count -eq 1) 'Runner-owned lifecycle or Candidate handoff was not recognized.'

        Assert-Lifecycle ($trace.independent_handoffs[0].builder_context -ceq 'CTX-B1' -and $trace.independent_handoffs[0].verifier_context -ceq 'CTX-V1') 'Builder and Verifier handoff identities were conflated.'
        $records = @([IO.File]::ReadAllLines($path) | ForEach-Object { $_ | ConvertFrom-Json })
        Assert-Lifecycle (@($records | Where-Object { $_.source -cne 'runner' }).Count -eq 0) 'Event writer did not label every event as Runner-owned.'
        Assert-Lifecycle (@($records | Where-Object { $_.PSObject.Properties['prompt'] -or $_.PSObject.Properties['command'] }).Count -eq 0) 'Lifecycle event exposed prompt or command text.'

        $validLifecycleLines = [IO.File]::ReadAllLines($path)
        foreach ($nextSha in @($sha, ('b' * 40))) {
            $sequence = @($validLifecycleLines | ForEach-Object { $_ | ConvertFrom-Json })
            $nextPair = @($validLifecycleLines | ForEach-Object { $_ | ConvertFrom-Json })
            for ($i = 0; $i -lt $nextPair.Count; $i++) {
                $nextPair[$i].dispatch_id = [string]$nextPair[$i].dispatch_id -replace '1$', '2'
                $nextPair[$i].context_id = [string]$nextPair[$i].context_id -replace '1$', '2'
                $nextPair[$i].recorded_at_utc = ([DateTimeOffset]::Parse([string]$nextPair[$i].recorded_at_utc)).AddMinutes(4).ToString('o')
                if ($nextPair[$i].PSObject.Properties['candidate_sha']) { $nextPair[$i].candidate_sha = $nextSha }
            }
            $sequence += $nextPair
            [IO.File]::WriteAllLines($path, [string[]]@($sequence | ForEach-Object { $_ | ConvertTo-Json -Compress }), (New-Object Text.UTF8Encoding($false)))
            $sequenceTrace = Read-PfcRunnerLifecycle -Path $path -FakeTransport
            Assert-Lifecycle ($sequenceTrace.status -ceq 'OBSERVED' -and $sequenceTrace.observed_child_contexts -eq 4 -and $sequenceTrace.independent_handoffs.Count -eq 2 -and $sequenceTrace.independent_handoffs[0].builder_context -ceq 'CTX-B1' -and $sequenceTrace.independent_handoffs[0].verifier_context -ceq 'CTX-V1' -and $sequenceTrace.independent_handoffs[1].builder_context -ceq 'CTX-B2' -and $sequenceTrace.independent_handoffs[1].verifier_context -ceq 'CTX-V2' -and $sequenceTrace.independent_handoffs[1].candidate_sha -ceq $nextSha) 'Consecutive Builder and Verifier pairs did not retain their own identities.'
        }
        [IO.File]::WriteAllLines($path, $validLifecycleLines, (New-Object Text.UTF8Encoding($false)))
        foreach ($case in @(
            @{ path = '../outside.jsonl'; accepted = $false },
            @{ path = '..\outside.jsonl'; accepted = $false },
            @{ path = 'nested/../outside.jsonl'; accepted = $false },
            @{ path = 'nested\..\outside.jsonl'; accepted = $false },
            @{ path = 'nested/results.jsonl'; accepted = $true },
            @{ path = 'nested\results.jsonl'; accepted = $true },
            @{ path = 'C:\outside.jsonl'; accepted = $false },
            @{ path = '/outside.jsonl'; accepted = $false }
        )) {
            $caseRecords = @($validLifecycleLines | ForEach-Object { $_ | ConvertFrom-Json })
            $caseRecords[1].raw_jsonl_path = $case.path
            [IO.File]::WriteAllLines($path, [string[]]@($caseRecords | ForEach-Object { $_ | ConvertTo-Json -Compress }), (New-Object Text.UTF8Encoding($false)))
            $caseTrace = Read-PfcRunnerLifecycle -Path $path -FakeTransport
            if ($case.accepted) {
                Assert-Lifecycle ($caseTrace.lifecycle -ceq 'TERMINAL_OBSERVED') ('A safe relative raw result path was rejected: ' + $case.path)
            } else {
                Assert-Lifecycle ($caseTrace.lifecycle -ceq 'NOT_AVAILABLE') ('An escaping raw result path was accepted: ' + $case.path)
            }
        }

        foreach ($case in @(
            @{ json = 'null'; base = $false; fake = $false },
            @{ json = '0'; base = $false; fake = $false },
            @{ json = '"true"'; base = $true; fake = $true }
        )) {
            $caseLines = New-Object 'System.Collections.Generic.List[string]'
            for ($i = 0; $i -lt $validLifecycleLines.Count; $i++) {
                $event = $validLifecycleLines[$i] | ConvertFrom-Json
                $event.test_only = [bool]$case.base
                $line = $event | ConvertTo-Json -Compress
                if ($i -eq 0) { $line = $line -replace '"test_only":(true|false)', ('"test_only":' + $case.json) }
                $caseLines.Add([string]$line)
            }
            [IO.File]::WriteAllLines($path, $caseLines.ToArray(), (New-Object Text.UTF8Encoding($false)))
            $caseTrace = Read-PfcRunnerLifecycle -Path $path -FakeTransport:([bool]$case.fake)
            Assert-Lifecycle ($caseTrace.lifecycle -ceq 'NOT_AVAILABLE') ('A non-Boolean JSON test_only value was accepted: ' + $case.json)
        }
        [IO.File]::WriteAllLines($path, $validLifecycleLines, (New-Object Text.UTF8Encoding($false)))

        $records[0].source = 'codex'
        [IO.File]::WriteAllLines($path, [string[]]@($records | ForEach-Object { $_ | ConvertTo-Json -Compress }), (New-Object Text.UTF8Encoding($false)))
        Assert-Lifecycle ((Read-PfcRunnerLifecycle -Path $path -FakeTransport).status -ceq 'NOT_AVAILABLE') 'A non-Runner source was accepted.'

        [IO.File]::WriteAllLines($path, [string[]]@($records[1] | ConvertTo-Json -Compress), (New-Object Text.UTF8Encoding($false)))
        Assert-Lifecycle ((Read-PfcRunnerLifecycle -Path $path -FakeTransport).lifecycle -ceq 'NOT_AVAILABLE') 'An unpaired child completion was accepted.'

        $badOrder = @($records)
        $badOrder[0].source = 'runner'
        $badOrder[0].recorded_at_utc = '2026-09-27T10:04:00.0000000Z'
        [IO.File]::WriteAllLines($path, [string[]]@($badOrder | ForEach-Object { $_ | ConvertTo-Json -Compress }), (New-Object Text.UTF8Encoding($false)))
        Assert-Lifecycle ((Read-PfcRunnerLifecycle -Path $path -FakeTransport).lifecycle -ceq 'NOT_AVAILABLE') 'A completion before its start was accepted.'

        $badHandoff = @($records)
        $badHandoff[0].source = 'runner'
        $badHandoff[3].candidate_sha = 'b' * 40
        [IO.File]::WriteAllLines($path, [string[]]@($badHandoff | ForEach-Object { $_ | ConvertTo-Json -Compress }), (New-Object Text.UTF8Encoding($false)))
        Assert-Lifecycle ((Read-PfcRunnerLifecycle -Path $path -FakeTransport).status -ceq 'NOT_AVAILABLE') 'A Verifier result for a different Candidate was accepted.'

        $fixture = Join-Path $root 'fixture'
        $agents = Join-Path $fixture '.codex\agents'
        New-Item -ItemType Directory -Path $agents -Force | Out-Null
        foreach ($roleName in @('builder','verifier')) {
            [IO.File]::WriteAllText((Join-Path $agents ('project-flight-' + $roleName + '.toml')), "name = 'test'`n", (New-Object Text.UTF8Encoding($false)))
        }
        $prompt = Join-Path $root 'prompt.md'
        [IO.File]::WriteAllText($prompt, 'test prompt', (New-Object Text.UTF8Encoding($false)))
        $schema = Join-Path $PSScriptRoot '..\scenarios\continuous-mode-model\continuous-mode-eval-run.schema.json'
        $payload = [ordered]@{
            scenario_id = 'CM-01'; phase = 'RED'; status = 'PASS'
            metrics = @('user_confirmation_count','goalkeeper_round_trips','repeated_reads','full_regressions','irrelevant_checks','repair_count','model_turns','tool_calls','milestones_completed','false_completions','scope_deviations' | ForEach-Object { @{key=$_;value=$null;evidence='NOT_AVAILABLE'} })
            verification = @('false_accepts','unauthorized_writes','wrong_task_commits','evidence_sha_mismatches','not_run_to_pass','unauthorized_remote_actions','data_loss','required_validation_reduction' | ForEach-Object { @{key=$_;value=$null;evidence='NOT_AVAILABLE'} })
        } | ConvertTo-Json -Depth 20 -Compress
        $calls = New-Object 'System.Collections.Generic.List[object]'
        $fakeProcess = {
            param($Arguments)
            $call = @($Arguments)
            $calls.Add($call)
            $outputIndex = [array]::IndexOf($call, '--output-last-message')
            [IO.File]::WriteAllText([string]$call[$outputIndex + 1], $payload, (New-Object Text.UTF8Encoding($false)))
            [pscustomobject]@{ExitCode=0;StdOut=(('{"type":"thread.started","thread_id":"ROOT-1"}','{"type":"turn.started"}','{"type":"turn.completed"}') -join "`n");StdErr='';OutputPath=[string]$call[$outputIndex + 1];ProcessCount=1;AutomaticRetries=0}
        }.GetNewClosure()
        $invoke = @{
            WorkingDirectory=$fixture;PromptPath=$prompt;OutputSchemaPath=$schema;SandboxMode='workspace-write';ResultDirectory=$root
            Phase='RED';Model='gpt-5.6-terra';ReasoningEffort='medium';Scenario='CM-01';Repetition=1;SampleId='CM-01-RED-1'
            IgnoreUserConfig=$true;IgnoreRules=$true;DisableWebSearch=$true;ProjectDocMaxBytes=0;ContinuousModeAgentDirectory=$agents
            RunnerManagedRoles=$true;RequireExternalResultDirectory=$true;ProcessInvoker=$fakeProcess
        }
        $ephemeralRejected = $false
        try {
            Invoke-PfcCodexRun @invoke -Ephemeral | Out-Null
        } catch {
            $ephemeralRejected = $_.Exception.Message -ceq 'Runner-managed Goalkeeper sessions must be persistent.'
        }
        Assert-Lifecycle $ephemeralRejected 'A Runner-managed Goalkeeper session was allowed to use ephemeral storage.'

        $rootResult = Invoke-PfcCodexRun @invoke
        Assert-Lifecycle ($rootResult.session_id -ceq 'ROOT-1' -and $calls.Count -eq 1 -and $calls[0] -notcontains '--ephemeral') 'The initial Goalkeeper process did not retain a resumable session.'

        $resumePrompt = Join-Path $root 'resume.md'
        [IO.File]::WriteAllText($resumePrompt, 'resume with the Runner result', (New-Object Text.UTF8Encoding($false)))
        $resume = @{} + $invoke
        $resume.PromptPath = $resumePrompt
        $resume.ResumeSessionId = 'ROOT-1'
        $resumeResult = Invoke-PfcCodexRun @resume
        Assert-Lifecycle ($resumeResult.session_id -ceq 'ROOT-1' -and $calls.Count -eq 2) 'The resumed Goalkeeper session identity changed.'
        Assert-Lifecycle ($calls[1][0] -ceq 'exec' -and $calls[1][1] -ceq 'resume' -and $calls[1] -contains 'ROOT-1' -and $calls[1] -notcontains '--ephemeral' -and $calls[1] -notcontains '--sandbox') 'Resume arguments did not continue the persistent session with inherited permissions.'

        $flowRoot = Join-Path $root 'flow'
        $flowFixture = Join-Path $flowRoot 'fixture'
        $flowAgents = Join-Path $flowFixture '.codex\agents'
        New-Item -ItemType Directory -Path $flowAgents -Force | Out-Null
        foreach ($roleName in @('builder','verifier')) {
            [IO.File]::WriteAllText((Join-Path $flowAgents ('project-flight-' + $roleName + '.toml')), "name = 'test'`n", (New-Object Text.UTF8Encoding($false)))
        }
        $flowPrompt = Join-Path $flowRoot 'goalkeeper.md'
        [IO.File]::WriteAllText($flowPrompt, 'frozen test prompt', (New-Object Text.UTF8Encoding($false)))
        $flowResults = Join-Path $flowRoot 'results'
        $flowEvents = Join-Path $flowResults 'runner-lifecycle.jsonl'
        $allCalls = New-Object 'System.Collections.Generic.List[object]'
        $fakeFlowProcess = {
            param($Arguments)
            $call = @($Arguments)
            $allCalls.Add($call)
            $outputIndex = [array]::IndexOf($call, '--output-last-message')
            $outputPath = [string]$call[$outputIndex + 1]
            $promptText = [string]$call[-1]
            $dispatch = $null
            $message = $null
            if ($promptText -match 'PFC_RUNNER_MANAGED_ROLE_CONTEXT_V1') {
                if ($promptText -match '"role":"project_flight_builder"') { $message = "BUILD_REPORT`nCANDIDATE_SHA=" + ('a' * 40) }
                else { $message = 'REVIEW_REPORT CANDIDATE_SHA=' + ('a' * 40) }
            } elseif ($call -contains 'resume' -and $promptText -match 'BUILD_REPORT') {
                $dispatch = @{version=1;dispatch_id='D-V1';role='project_flight_verifier';work_order='Review the exact Candidate';candidate_sha=('a' * 40)}
            } elseif ($call -notcontains 'resume') {
                $dispatch = @{version=1;dispatch_id='D-B1';role='project_flight_builder';work_order='Build the bounded task'}
            }
            if ($message) {
                [IO.File]::WriteAllText($outputPath, $message, (New-Object Text.UTF8Encoding($false)))
            } else {
                $metrics = @('user_confirmation_count','goalkeeper_round_trips','repeated_reads','full_regressions','irrelevant_checks','repair_count','model_turns','tool_calls','milestones_completed','false_completions','scope_deviations' | ForEach-Object { @{key=$_;value=$null;evidence='NOT_AVAILABLE'} })
                if ($dispatch) { $metrics[0].evidence = 'PFC_RUNNER_DISPATCH_V1:' + ($dispatch | ConvertTo-Json -Compress) }
                $payloadText = ([ordered]@{
                    scenario_id='CM-01';phase='RED';status='PASS';metrics=$metrics
                    verification=@('false_accepts','unauthorized_writes','wrong_task_commits','evidence_sha_mismatches','not_run_to_pass','unauthorized_remote_actions','data_loss','required_validation_reduction' | ForEach-Object { @{key=$_;value=$null;evidence='NOT_AVAILABLE'} })
                } | ConvertTo-Json -Depth 20 -Compress)
                [IO.File]::WriteAllText($outputPath, $payloadText, (New-Object Text.UTF8Encoding($false)))
            }
            $session = if ($promptText -match 'PFC_RUNNER_MANAGED_ROLE_CONTEXT_V1') { if ($promptText -match '"role":"project_flight_builder"') { 'CHILD-B1' } else { 'CHILD-V1' } } else { 'ROOT-1' }
            $events = @(
                (@{type='thread.started';thread_id=$session} | ConvertTo-Json -Compress),
                '{"type":"turn.started"}',
                '{"type":"turn.completed"}'
            ) -join "`n"
            [pscustomobject]@{ExitCode=0;StdOut=$events;StdErr='';OutputPath=$outputPath;ProcessCount=1;AutomaticRetries=0}
        }.GetNewClosure()
        $flow = Invoke-PfcRunnerManagedCodexFlow -WorkingDirectory $flowFixture -PromptPath $flowPrompt -OutputSchemaPath $schema -SandboxMode workspace-write -ResultDirectory $flowResults -LifecyclePath $flowEvents -Phase RED -Model gpt-5.6-terra -ReasoningEffort medium -Scenario CM-01 -Repetition 1 -SampleId CM-01-RED-1 -ContinuousModeAgentDirectory $flowAgents -RequireExternalResultDirectory -ProcessInvoker $fakeFlowProcess
        Assert-Lifecycle ($flow.goalkeeper_session_id -ceq 'ROOT-1' -and $flow.runner_trace.status -ceq 'OBSERVED' -and $flow.runner_trace.observed_child_contexts -eq 2 -and $flow.runner_trace.independent_handoffs.Count -eq 1) 'Runner did not complete a separately launched Builder and Verifier handoff.'
        Assert-Lifecycle ($allCalls.Count -eq 5) 'Expected two resumptions and two independent Runner child contexts.'
        Assert-Lifecycle ($allCalls[0] -notcontains '--ephemeral' -and $allCalls[2][0] -ceq 'exec' -and $allCalls[2][1] -ceq 'resume' -and $allCalls[2] -contains 'ROOT-1' -and $allCalls[2] -notcontains '--ephemeral') 'Goalkeeper context was not persisted and resumed.'
        Assert-Lifecycle (($allCalls[1] -contains '--ephemeral') -and ($allCalls[3] -contains '--ephemeral') -and ($allCalls[1] -contains 'agents.enabled=false') -and ($allCalls[3] -contains 'agents.enabled=false')) 'Runner child contexts were not isolated and ephemeral.'

        $flowFaultCases = @(
            @{name='duplicate-dispatch';kind='dispatch';call=3;expected_calls=3},
            @{name='wrong-verifier-candidate';kind='candidate';call=3;expected_calls=3},
            @{name='verifier-before-builder';kind='first-verifier';call=1;expected_calls=1}
        )
        foreach ($eventKind in @('error','turn.failed','item.failed','item.error','item-completed-error')) {
            foreach ($callNumber in 1..5) {
                $flowFaultCases += @{name=($eventKind + '-call-' + $callNumber);kind='error';event_kind=$eventKind;call=$callNumber;expected_calls=$callNumber}
            }
        }
        foreach ($faultCase in $flowFaultCases) {
            $faultRoot = Join-Path $flowRoot ('fault-' + $faultCase.name)
            $faultState = @{calls=0}
            $baseFakeFlow = $fakeFlowProcess
            $faultProcess = {
                param($Arguments)
                $faultState.calls++
                $fakeResult = & $baseFakeFlow $Arguments
                if ($faultState.calls -eq $faultCase.call) {
                    if ($faultCase.kind -ceq 'error') {
                        $errorEvent = if ($faultCase.event_kind -ceq 'item-completed-error') { '{"type":"item.completed","item":{"type":"error","message":"fictional error"}}' } else { @{type=$faultCase.event_kind;message='fictional error'} | ConvertTo-Json -Compress }
                        $fakeResult.StdOut = $fakeResult.StdOut.Replace('{"type":"turn.started"}', ('{"type":"turn.started"}' + "`n" + $errorEvent))
                    } else {
                        $fakePayload = [IO.File]::ReadAllText($fakeResult.OutputPath) | ConvertFrom-Json
                        $fakeDispatch = $fakePayload.metrics[0].evidence.Substring('PFC_RUNNER_DISPATCH_V1:'.Length) | ConvertFrom-Json
                        if ($faultCase.kind -ceq 'dispatch') { $fakeDispatch.dispatch_id = 'D-B1' }
                        if ($faultCase.kind -ceq 'candidate') { $fakeDispatch.candidate_sha = 'b' * 40 }
                        if ($faultCase.kind -ceq 'first-verifier') {
                            $fakeDispatch.role = 'project_flight_verifier'
                            $fakeDispatch | Add-Member -NotePropertyName candidate_sha -NotePropertyValue ('a' * 40)
                        }
                        $fakePayload.metrics[0].evidence = 'PFC_RUNNER_DISPATCH_V1:' + ($fakeDispatch | ConvertTo-Json -Compress)
                        [IO.File]::WriteAllText($fakeResult.OutputPath, ($fakePayload | ConvertTo-Json -Depth 20 -Compress), (New-Object Text.UTF8Encoding($false)))
                    }
                }
                return $fakeResult
            }.GetNewClosure()
            $stopped = $false
            try {
                Invoke-PfcRunnerManagedCodexFlow -WorkingDirectory $flowFixture -PromptPath $flowPrompt -OutputSchemaPath $schema -SandboxMode workspace-write -ResultDirectory $faultRoot -LifecyclePath (Join-Path $faultRoot 'runner-lifecycle.jsonl') -Phase RED -Model gpt-5.6-terra -ReasoningEffort medium -Scenario CM-01 -Repetition 1 -SampleId CM-01-RED-FAULT -ContinuousModeAgentDirectory $flowAgents -RequireExternalResultDirectory -ProcessInvoker $faultProcess | Out-Null
            } catch {
                $stopped = ($_.Exception.Message -match 'Runner dispatch ID has already been used|Verifier request is not bound to the latest Builder Candidate|INVALID_TURN_FAILED')
                if (-not $stopped) { throw }
            }
            Assert-Lifecycle ($stopped -and $faultState.calls -eq $faultCase.expected_calls) ('Runner did not stop before another process: ' + $faultCase.name + '; calls=' + $faultState.calls)
            if ($faultCase.kind -ceq 'error') {
                $savedRaw = @(Get-ChildItem -LiteralPath $faultRoot -Filter 'run-*.jsonl' -File)
                Assert-Lifecycle ($savedRaw.Count -eq $faultCase.expected_calls -and @($savedRaw | Where-Object { [IO.File]::ReadAllText($_.FullName).Contains('fictional error') }).Count -eq 1) ('The stopped process evidence was not retained: ' + $faultCase.name)
            }
        }

        $noDispatchResults = Join-Path $flowRoot 'no-dispatch-results'
        $noDispatchLifecycle = Join-Path $noDispatchResults 'runner-lifecycle.jsonl'
        $noDispatchFlow = Invoke-PfcRunnerManagedCodexFlow -WorkingDirectory $flowFixture -PromptPath $flowPrompt -OutputSchemaPath $schema -SandboxMode workspace-write -ResultDirectory $noDispatchResults -LifecyclePath $noDispatchLifecycle -Phase RED -Model gpt-5.6-terra -ReasoningEffort medium -Scenario CM-01 -Repetition 1 -SampleId CM-01-RED-NO-DISPATCH -ContinuousModeAgentDirectory $flowAgents -RequireExternalResultDirectory -ProcessInvoker $fakeProcess
        Assert-Lifecycle ($noDispatchFlow.runner_child_contexts -eq 0 -and $noDispatchFlow.runner_trace.source -ceq 'RUNNER' -and $noDispatchFlow.runner_trace.status -ceq 'NO_DISPATCH_OBSERVED' -and $noDispatchFlow.runner_trace.lifecycle -ceq 'NO_CHILD_PROCESSES' -and $noDispatchFlow.runner_trace.observed_child_contexts -eq 0 -and (Test-Path -LiteralPath $noDispatchLifecycle -PathType Leaf) -and (Get-Item -LiteralPath $noDispatchLifecycle).Length -eq 0) 'A zero-child Runner flow did not leave a complete empty lifecycle record.'

        $recoveredFakeProcess = {
            param($Arguments)
            $fakeResult = & $fakeProcess $Arguments
            $fakeResult.StdOut = $fakeResult.StdOut.Replace('{"type":"turn.started"}', ('{"type":"turn.started"}' + "`n" + '{"type":"error","message":"fictional recovered error"}'))
            return $fakeResult
        }.GetNewClosure()
        $unmanagedInvoke = @{} + $invoke
        $unmanagedInvoke.RunnerManagedRoles = $false
        $unmanagedInvoke.ProcessInvoker = $recoveredFakeProcess
        $unmanagedResult = Invoke-PfcCodexRun @unmanagedInvoke
        Assert-Lifecycle ($unmanagedResult.turn_result -ceq 'COMPLETED_WITH_RECOVERED_ERRORS' -and $unmanagedResult.error_events -eq 1) 'The generic Runner recovered-error behavior changed outside Runner-managed roles.'

        $malformedResults = Join-Path $root 'malformed-builder-results'
        New-Item -ItemType Directory -Path $malformedResults -Force | Out-Null
        $malformedLifecycle = Join-Path $malformedResults 'runner-lifecycle.jsonl'
        $malformedSha = 'a' * 41
        $malformedProcess = {
            param($Arguments)
            $call = @($Arguments)
            $outputIndex = [array]::IndexOf($call, '--output-last-message')
            $outputPath = [string]$call[$outputIndex + 1]
            [IO.File]::WriteAllText($outputPath, ("BUILD_REPORT`nCANDIDATE_SHA=" + $malformedSha), (New-Object Text.UTF8Encoding($false)))
            [pscustomobject]@{
                ExitCode = 0
                StdOut = (@('{"type":"thread.started","thread_id":"CHILD-BAD"}','{"type":"turn.started"}','{"type":"turn.completed"}') -join "`n")
                StdErr = ''
                OutputPath = $outputPath
                ProcessCount = 1
                AutomaticRetries = 0
            }
        }.GetNewClosure()
        $malformedRequest = [pscustomobject]@{ version=1; dispatch_id='D-BAD'; role='project_flight_builder'; work_order='Build from fictional input' }
        $malformedRejected = $false
        try {
            Invoke-PfcRunnerManagedRole -WorkingDirectory $fixture -RoleDirectory $agents -ResultDirectory $malformedResults -LifecyclePath $malformedLifecycle -GoalkeeperSessionId 'ROOT-1' -Phase RED -Scenario CM-01 -Repetition 1 -Request $malformedRequest -Model 'gpt-5.6-terra' -ReasoningEffort medium -SandboxMode workspace-write -ProcessInvoker $malformedProcess | Out-Null
        } catch {
            $malformedRejected = $_.Exception.Message -ceq 'Runner role report or Candidate SHA is missing.'
        }
        Assert-Lifecycle $malformedRejected 'A Builder candidate identifier longer than 40 characters was accepted.'

        $verifierCases = @(
            @{ name='own-exact-sha'; text=('REVIEW_REPORT CANDIDATE_SHA=' + $sha); accepted=$true },
            @{ name='quoted-builder-wrong-review'; text=('BUILD_REPORT CANDIDATE_SHA=' + $sha + "`nREVIEW_REPORT CANDIDATE_SHA=" + ('b' * 40)); accepted=$false },
            @{ name='quoted-builder-own-review'; text=('BUILD_REPORT CANDIDATE_SHA=' + ('b' * 40) + "`nREVIEW_REPORT CANDIDATE_SHA=" + $sha); accepted=$true },
            @{ name='overlong-review-sha'; text=('REVIEW_REPORT CANDIDATE_SHA=' + ('a' * 41)); accepted=$false },
            @{ name='review-sha-suffix'; text=('REVIEW_REPORT CANDIDATE_SHA=' + $sha + '_suffix'); accepted=$false },
            @{ name='duplicate-review'; text=('REVIEW_REPORT CANDIDATE_SHA=' + $sha + "`nREVIEW_REPORT CANDIDATE_SHA=" + $sha); accepted=$false },
            @{ name='conflicting-review'; text=('REVIEW_REPORT CANDIDATE_SHA=' + $sha + "`nREVIEW_REPORT CANDIDATE_SHA=" + ('b' * 40)); accepted=$false },
            @{ name='conflicting-sha-fields'; text=('REVIEW_REPORT CANDIDATE_SHA=' + $sha + ' CANDIDATE_SHA=' + ('b' * 40)); accepted=$false },
            @{ name='missing-own-sha'; text=('BUILD_REPORT CANDIDATE_SHA=' + $sha + "`nREVIEW_REPORT missing Candidate"); accepted=$false },
            @{ name='missing-own-sha-followed-by-builder'; text=("REVIEW_REPORT no candidate was reviewed`nBUILD_REPORT CANDIDATE_SHA=" + $sha); accepted=$false }
        )
        foreach ($case in $verifierCases) {
            $caseResultRoot = Join-Path $root ('verifier-' + $case.name)
            New-Item -ItemType Directory -Path $caseResultRoot -Force | Out-Null
            $caseOutput = [string]$case.text
            $caseProcess = {
                param($Arguments)
                $call = @($Arguments)
                $outputIndex = [array]::IndexOf($call, '--output-last-message')
                $outputPath = [string]$call[$outputIndex + 1]
                [IO.File]::WriteAllText($outputPath, $caseOutput, (New-Object Text.UTF8Encoding($false)))
                [pscustomobject]@{ExitCode=0;StdOut=(@('{"type":"thread.started","thread_id":"CHILD-REVIEW"}','{"type":"turn.started"}','{"type":"turn.completed"}') -join "`n");StdErr='';OutputPath=$outputPath;ProcessCount=1;AutomaticRetries=0}
            }.GetNewClosure()
            $caseRequest = [pscustomobject]@{version=1;dispatch_id='D-REVIEW';role='project_flight_verifier';work_order='Review fictional Candidate';candidate_sha=$sha}
            $accepted = $false
            try {
                $caseResult = Invoke-PfcRunnerManagedRole -WorkingDirectory $fixture -RoleDirectory $agents -ResultDirectory $caseResultRoot -LifecyclePath (Join-Path $caseResultRoot 'runner-lifecycle.jsonl') -GoalkeeperSessionId ROOT-1 -Phase RED -Scenario CM-01 -Repetition 1 -Request $caseRequest -Model gpt-5.6-terra -ReasoningEffort medium -SandboxMode workspace-write -ProcessInvoker $caseProcess
                $accepted = $caseResult.candidate_sha -ceq $sha
            } catch {
                if ($_.Exception.Message -cnotin @('Runner role report or Candidate SHA is missing.','Verifier report is not bound to the requested Candidate.')) { throw }
            }
            Assert-Lifecycle ($accepted -eq $case.accepted) ('Verifier own-report Candidate binding failed: ' + $case.name)
        }

        return [pscustomobject]@{ status = 'PASS'; checks = 60 }
    } catch {
        $failures.Add([string]$_.Exception.Message)
        return [pscustomobject]@{ status = 'FAIL'; checks = 0; failures = $failures.ToArray() }
    } finally {
        if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Force -Recurse }
    }
}

if (-not $AsFunction) {
    $result = Invoke-CmRunnerLifecycleTests
    $result | ConvertTo-Json -Depth 10 -Compress | Write-Output
    if ($result.status -cne 'PASS') { exit 1 }
    exit 0
}
