function Invoke-CmWindowsPowerShellStartupTest {
    param([string]$RepositoryRoot)
    $tempBase = [IO.Path]::GetTempPath()
    $tempRoot = Join-Path $tempBase ('pfc-utility-startup-' + [guid]::NewGuid().ToString('N'))
    $modulePath = Join-Path $tempRoot 'Microsoft.PowerShell.Utility\7.0.0.0'
    $originalModulePath = $env:PSModulePath
    $originalProbeFile = [Environment]::GetEnvironmentVariable('PFC_STARTUP_PROBE_FILE', 'Process')
    $originalExpectedHash = [Environment]::GetEnvironmentVariable('PFC_STARTUP_EXPECTED_HASH', 'Process')
    try {
        New-Item -ItemType Directory -Path $modulePath -Force | Out-Null
        New-ModuleManifest -Path (Join-Path $modulePath 'Microsoft.PowerShell.Utility.psd1') -RootModule 'Microsoft.PowerShell.Utility.psm1' -ModuleVersion '7.0.0.0' -FunctionsToExport @('Get-FileHash') -CmdletsToExport @() -VariablesToExport @() -AliasesToExport @()
        Set-Content -LiteralPath (Join-Path $modulePath 'Microsoft.PowerShell.Utility.psm1') -Value '# Synthetic empty module.' -Encoding ASCII

        $runner = Join-Path $RepositoryRoot 'evals\run-evals.ps1'
        $runnerSource = Get-Content -LiteralPath $runner -Raw
        $importLine = @($runnerSource -split '\r?\n' | Where-Object { $_ -match 'Import-Module.*Microsoft\.PowerShell\.Utility\.psd1' } | Select-Object -First 1)
        $importIndex = $runnerSource.IndexOf('Microsoft.PowerShell.Utility.psd1', [StringComparison]::Ordinal)
        $hashIndex = $runnerSource.IndexOf('Get-FileHash', [StringComparison]::Ordinal)
        if ($importLine.Count -ne 1 -or $importLine[0] -notmatch '-ErrorAction Stop' -or $importIndex -lt 0 -or $hashIndex -lt 0 -or $importIndex -gt $hashIndex) {
            throw 'Evaluator must load its PowerShell home Utility module before hashing files.'
        }

        $fixture = Join-Path $tempRoot 'synthetic-hash-input.txt'
        [IO.File]::WriteAllText($fixture, 'PFC synthetic hash fixture', [Text.UTF8Encoding]::new($false))
        $expectedHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $fixture).Hash.ToLowerInvariant()
        $probe = Join-Path $tempRoot 'startup-probe.ps1'
        $probeLines = @(
            '$ErrorActionPreference = ''Stop'''
            '$moduleManifest = Join-Path $PSHOME ''Modules\Microsoft.PowerShell.Utility\Microsoft.PowerShell.Utility.psd1'''
            'Import-Module -Name $moduleManifest -Force -ErrorAction Stop'
            '$actualHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $env:PFC_STARTUP_PROBE_FILE).Hash.ToLowerInvariant()'
            'if ($actualHash -cne $env:PFC_STARTUP_EXPECTED_HASH) { exit 71 }'
            'if ($PSVersionTable.PSVersion.Major -ne 5) { exit 72 }'
            '[Console]::Out.WriteLine(''PFC_STARTUP_PROBE_PASS;'' + $PSVersionTable.PSVersion.ToString())'
        )
        [IO.File]::WriteAllLines($probe, $probeLines, [Text.Encoding]::ASCII)
        $stdout = Join-Path $tempRoot 'stdout.txt'
        $stderr = Join-Path $tempRoot 'stderr.txt'

        $env:PSModulePath = $tempRoot + [IO.Path]::PathSeparator + $originalModulePath
        [Environment]::SetEnvironmentVariable('PFC_STARTUP_PROBE_FILE', $fixture, 'Process')
        [Environment]::SetEnvironmentVariable('PFC_STARTUP_EXPECTED_HASH', $expectedHash, 'Process')
        $process = Start-Process -FilePath (Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe') -ArgumentList ('-NoProfile -ExecutionPolicy Bypass -File "{0}"' -f $probe) -WindowStyle Hidden -Wait -PassThru -RedirectStandardOutput $stdout -RedirectStandardError $stderr -ErrorAction Stop
        $childOutput = if (Test-Path -LiteralPath $stdout) { Get-Content -LiteralPath $stdout -Raw } else { '' }
        if ($process.ExitCode -ne 0 -or $childOutput -notmatch 'PFC_STARTUP_PROBE_PASS;5\.1') {
            throw 'Windows PowerShell 5.1 synthetic Get-FileHash probe failed.'
        }
    } finally {
        $env:PSModulePath = $originalModulePath
        [Environment]::SetEnvironmentVariable('PFC_STARTUP_PROBE_FILE', $originalProbeFile, 'Process')
        [Environment]::SetEnvironmentVariable('PFC_STARTUP_EXPECTED_HASH', $originalExpectedHash, 'Process')
        if (Test-Path -LiteralPath $tempRoot) {
            $fullTempRoot = [IO.Path]::GetFullPath($tempRoot).TrimEnd('\')
            $fullTempBase = [IO.Path]::GetFullPath($tempBase).TrimEnd('\')
            if ($fullTempRoot -eq $fullTempBase -or -not $fullTempRoot.StartsWith($fullTempBase + '\', [StringComparison]::OrdinalIgnoreCase)) {
                throw 'Temporary startup test cleanup path check failed.'
            }
            Remove-Item -LiteralPath $fullTempRoot -Recurse -Force
        }
    }
}

function Invoke-CmModelContractTests {
    param([string]$RepositoryRoot)
    $results = New-Object 'System.Collections.Generic.List[object]'
    function Check([string]$Id, [scriptblock]$Body) {
        try { & $Body; $results.Add((New-PfcResult -ScenarioId $Id -Status PASS -Message verified)) }
        catch { $results.Add((New-PfcResult -ScenarioId $Id -Status FAIL -Message $_.Exception.Message)) }
    }
    function Assert($Condition, [string]$Message) { if (-not $Condition) { throw $Message } }
    Check 'CM-contract.windows-powershell-startup-loads-own-utility-module' {
        Invoke-CmWindowsPowerShellStartupTest -RepositoryRoot $RepositoryRoot
    }
    $module = Get-Module CodexRunner
    # Replace the actual process boundary, never resolve codex in this suite.
    & $module {
        $script:cmRealCalls = 0; $script:cmResolveCalls = 0
        function script:Invoke-PfcRealCodexProcess { $script:cmRealCalls++; throw 'REAL PROCESS TRIPWIRE' }
        function script:Get-Command { [CmdletBinding()] param([string]$Name)
            if($Name -eq 'codex'){$script:cmResolveCalls++;throw 'REAL CODEX RESOLUTION TRIPWIRE'}
            Microsoft.PowerShell.Core\Get-Command -Name $Name
        }
    }
    Check 'CM-contract.isolated-schema' {
        Assert (Test-Path -LiteralPath (Join-Path $RepositoryRoot 'evals/scenarios/continuous-mode-model/continuous-mode-eval-run.schema.json')) 'Missing isolated Continuous Mode output contract'
    }
    Check 'CM-contract.authorization-guard' {
        Assert ($null -ne (Get-Command Invoke-CmModelDispatch -ErrorAction SilentlyContinue)) 'Missing fail-closed Continuous Mode authorization guard'
    }
    Check 'CM-contract.runner-CM-identity' {
        $parameter = (Get-Command Invoke-PfcCodexRun).Parameters['Scenario']
        $pattern = @($parameter.Attributes | Where-Object { $_ -is [System.Management.Automation.ValidatePatternAttribute] })[0].RegexPattern
        Assert ('CM-01' -match $pattern) 'Runner rejects CM scenario identity; CM output cannot be bound without an extension'
    }
    Check 'CM-contract.explicit-codex-path-reaches-managed-processes' {
        foreach($name in @('Invoke-PfcCodexRun','Invoke-PfcRunnerManagedRole','Invoke-PfcRunnerManagedCodexFlow')) {
            Assert ((Get-Command $name).Parameters.ContainsKey('CodexExecutablePath')) ('Missing explicit executable path on '+$name)
        }
        $runnerSource=Get-Content -Raw -LiteralPath (Join-Path $RepositoryRoot 'evals/lib/CodexRunner.psm1')
        Assert (([regex]::Matches($runnerSource,'CodexExecutablePath=\$CodexExecutablePath')).Count -ge 2) 'Goalkeeper and role launches do not forward the explicit executable path'
        $entrySource=Get-Content -Raw -LiteralPath (Join-Path $RepositoryRoot 'evals/run-evals.ps1')
        Assert ($entrySource.Contains('[AllowNull()][string]$CodexExecutablePath') -and $entrySource.Contains('CodexExecutablePath=$CodexExecutablePath') -and $entrySource.Contains('-CodexExecutablePath $CodexExecutablePath')) 'Evaluation entry point does not forward its optional executable path'
    }
    Check 'CM-contract.product-binding-and-runner-route' {
        $c=Get-CmFrozenControl $RepositoryRoot
        Assert ($c.product.candidate_sha -cmatch '^[a-f0-9]{40}$' -and $c.product.inputs.Count -gt 2) 'Actual product Candidate/bytes missing'
        Assert ($null -ne (Get-Command Invoke-PfcRunnerManagedCodexFlow -ErrorAction SilentlyContinue)) 'Missing controlled Runner-managed role route'
        foreach($e in $c.scenarios){
            $m=Get-Content -Raw -LiteralPath (Join-Path $RepositoryRoot $e.manifest_path)|ConvertFrom-Json
            Assert ($m.product_inputs_sha256 -ceq $c.product.inputs_sha256) 'Scenario product identity unbound'
            $prompt=Get-CmPrompt (Split-Path -Parent (Join-Path $RepositoryRoot $e.manifest_path)) GREEN
            Assert ($prompt.Contains('$project-flight-control START CONTINUOUS_MODE') -and $prompt.Contains('.pfc-product/skill/project-flight-control/SKILL.md')) 'Explicit actual product activation missing'
        }
    }
    if (Get-Command Invoke-CmModelDispatch -ErrorAction SilentlyContinue) {
        $owned = Join-Path $RepositoryRoot ('.pfc-eval-results/cm-contract-FAKE-' + [guid]::NewGuid().ToString('N'))
        $authRoot = Join-Path $RepositoryRoot '.pfc-eval-results/authorizations'
        New-Item -ItemType Directory -Path $owned,$authRoot -Force | Out-Null
        $script:cmOwned = $owned
        $script:cmFakeCalls = 0; $script:cmArgs = @(); $script:cmMode = 'valid'; $script:cmCurrentScenario = $null; $script:cmCurrentPhase = 'RED'
        $fake = {
            param($Arguments)
            $script:cmFakeCalls++
            if($script:cmMode -eq 'capture-failure' -and $script:cmFakeCalls -gt $script:cmCaptureStart+5){throw 'Unexpected second sample after evidence failure'}
            if($script:cmMode -in @('final-recovered-error','final-item-error') -and $script:cmFakeCalls -gt $script:cmErrorStart+5){throw 'Unexpected second sample after native error'}
            $call=@($Arguments);$script:cmArgs += ,$call
            if($script:cmMode -eq 'auth-drift'){[IO.File]::AppendAllText($script:cmDriftAuth,[Environment]::NewLine+' ',[Text.Encoding]::UTF8)}
            $prompt=[string]$call[-1];$isRole=$prompt -match 'PFC_RUNNER_MANAGED_ROLE_CONTEXT_V1';$isResume=$call -contains 'resume'
            $output=$call[[array]::IndexOf($call,'--output-last-message')+1]
            if(-not $isRole -and -not $isResume){
                $scenarioMatch=[regex]::Match($prompt,'CM-0[1-7]')
                $script:cmCurrentScenario=$scenarioMatch.Value
                $script:cmCurrentPhase=if($prompt -match 'CONTINUOUS_MODE_TREATMENT'){'GREEN'}else{'RED'}
            }
            $id=[string]$script:cmCurrentScenario;$phase=[string]$script:cmCurrentPhase;$sha='a'*40
            if($isRole){
                if($prompt -match '"role":"project_flight_builder"'){$roleOutput='BUILD_REPORT CANDIDATE_SHA='+$sha}else{$roleOutput='REVIEW_REPORT CANDIDATE_SHA='+$sha}
                Write-PfcUtf8NoBom -Path $output -Content $roleOutput
                $roleSession=if($prompt -match '"role":"project_flight_builder"'){'FAKE-BUILDER'}else{'FAKE-VERIFIER'}
                $roleEvents=@((@{type='thread.started';thread_id=$roleSession}|ConvertTo-Json -Compress),'{ "type":"turn.started" }','{ "type":"turn.completed" }')
                return [pscustomobject]@{ExitCode=0;StdOut=($roleEvents -join [Environment]::NewLine);StdErr='';OutputPath=$output;ProcessCount=1;AutomaticRetries=0}
            }
            $metrics=@('user_confirmation_count','goalkeeper_round_trips','repeated_reads','full_regressions','irrelevant_checks','repair_count','model_turns','tool_calls','milestones_completed','false_completions','scope_deviations'|ForEach-Object {@{key=$_;value=$null;evidence='C:\private\file /private/home \\server\private sk-abcdefghijk'}})
            $verification=@('false_accepts','unauthorized_writes','wrong_task_commits','evidence_sha_mismatches','not_run_to_pass','unauthorized_remote_actions','data_loss','required_validation_reduction'|ForEach-Object {@{key=$_;value=$null;evidence='NOT_AVAILABLE'}})
            $invalidModes=@('wrong-phase','wrong-scenario','duplicate','missing-metric','negative','fractional','extra','missing-field','eff','key-secret','missing-final','missing-terminal','failed-terminal','invalid-jsonl','fenced','outside-output','missing-runner-trace')
            $forceFinal=($script:cmMode -cin $invalidModes)
            $dispatch=$null
            if(-not $forceFinal -and $id -cne 'CM-05'){
                if(-not $isResume){$dispatch=@{version=1;dispatch_id='D-B1';role='project_flight_builder';work_order='Bounded fake work order'}}
                elseif($prompt -match 'BUILD_REPORT'){$dispatch=@{version=1;dispatch_id='D-V1';role='project_flight_verifier';work_order='Verify Candidate';candidate_sha=$sha}}
            }
            $payload=@{scenario_id=$id;phase=$phase;status='PASS';metrics=$metrics;verification=$verification}
            if($dispatch){$payload.metrics[0].evidence='PFC_RUNNER_DISPATCH_V1:'+($dispatch|ConvertTo-Json -Compress)}
            else {
                switch($script:cmMode){
                    'task-fail'{$payload.status='FAIL'} 'task-blocked'{$payload.status='BLOCKED'} 'task-partial'{$payload.status='PARTIAL'} 'task-not-run'{$payload.status='NOT_RUN'}
                    'wrong-phase'{$payload.phase=if($phase -eq 'GREEN'){'RED'}else{'GREEN'}} 'wrong-scenario'{$payload.scenario_id='CM-07'}
                    'duplicate'{$payload.metrics+=$payload.metrics[0]} 'missing-metric'{$payload.metrics=@($payload.metrics|Select-Object -Skip 1)}
                    'negative'{$payload.metrics[0].value=-1} 'fractional'{$payload.metrics[0].value=0.5} 'extra'{$payload.extra='forbidden'}
                    'missing-field'{$payload.Remove('verification')} 'eff'{$payload.scenario_id='EFF-01'} 'key-secret'{$payload.metrics[0].key='sk-abcdefghijk'}
                }
            }
            $value=$payload|ConvertTo-Json -Depth 30 -Compress
            if($script:cmMode -eq 'fenced'){$value=([string][char]96)*3+'json'+$value+([string][char]96)*3}
            if($dispatch -or $script:cmMode -notin @('missing-final','fallback','fenced')){Write-PfcUtf8NoBom -Path $output -Content $value}
            $events=@((@{type='thread.started';thread_id='FAKE-ROOT'}|ConvertTo-Json -Compress),'{ "type":"turn.started" }')
            if($id -ceq 'CM-05' -and $script:cmMode -ceq 'valid'){
                $m=Get-Content -Raw (Join-Path $RepositoryRoot 'evals/scenarios/continuous-mode-model/CM-05-task-identity-mismatch/scenario.json')|ConvertFrom-Json
                foreach($name in @('WORK_ORDER','STATUS')){
                    $relative='docs/project-control/'+$name+'.md';$content=@($m.fixture.files|Where-Object path -ceq $relative)[0].content
                    $events+=(@{type='item.started';item=@{type='command_execution';id=$name}}|ConvertTo-Json -Compress)
                    $events+=(@{type='item.completed';item=@{type='command_execution';id=$name;command=('Get-Content -Raw '+$relative);status='completed';exit_code=0;aggregated_output=$content}}|ConvertTo-Json -Depth 10 -Compress)
                }
            }
            if($script:cmMode -in @('fallback','fenced')){$events+=(@{type='item.completed';item=@{type='agent_message';text=$value}}|ConvertTo-Json -Depth 30 -Compress)}
            if(-not $dispatch -and $script:cmMode -eq 'final-recovered-error'){$events+='{"type":"error","code":"SYNTHETIC_FINAL_ERROR"}'}
            if(-not $dispatch -and $script:cmMode -eq 'final-item-error'){$events+='{"type":"item.completed","item":{"type":"error","id":"SYNTHETIC_FINAL_ERROR"}}'}
            if($script:cmMode -eq 'invalid-jsonl'){$events+='not-json'}
            if($script:cmMode -eq 'failed-terminal'){$events+='{ "type":"turn.failed" }'}
            elseif($script:cmMode -ne 'missing-terminal'){
                if($script:cmMode -eq 'usage'){$events+='{ "type":"turn.completed","usage":{"input_tokens":12,"cached_input_tokens":2,"output_tokens":4} }'}
                elseif($script:cmMode -eq 'bad-usage'){$events+='{ "type":"turn.completed","usage":{"input_tokens":-1,"output_tokens":"sk-abcdefghijk"} }'}
                else{$events+='{ "type":"turn.completed" }'}
            }
            $reportedOutput=if($script:cmMode -eq 'outside-output'){'C:\outside.json'}else{$output}
            if($script:cmMode -eq 'missing-runner-trace') {
                foreach($runnerRecord in @(Get-ChildItem -LiteralPath $script:cmOwned -Filter 'runner-events-*.jsonl' -File -ErrorAction SilentlyContinue)) { Remove-Item -LiteralPath $runnerRecord.FullName -Force }
            }
            [pscustomobject]@{ExitCode=0;StdOut=($events -join [Environment]::NewLine);StdErr='';OutputPath=$reportedOutput;ProcessCount=1;AutomaticRetries=0}
        }
        function New-FakeAuthorization {
            $control = Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $RepositoryRoot 'evals/expected/continuous-mode-model/frozen-control.json') | ConvertFrom-Json
            [pscustomobject][ordered]@{ authorization_id=('FAKE-TEST-ONLY-'+[guid]::NewGuid().ToString('N')); phase='GREEN'; scenario_ids=@('CM-01','CM-02','CM-03','CM-04','CM-05','CM-06','CM-07'); repetitions_per_scenario=5;valid_run_target=35;maximum_attempts=35; model='gpt-5.6-terra';reasoning_effort='medium';sandbox='workspace-write';control_sha256=(Get-FileHash -LiteralPath (Join-Path $RepositoryRoot 'evals/expected/continuous-mode-model/frozen-control.json') -Algorithm SHA256).Hash.ToLowerInvariant();bindings=$control.scenarios;no_retry=$true;remote_actions=$false;issued_at='2026-09-23T00:00:00Z';test_only=$true;product=$control.product;runner_managed_roles=$control.runner_managed_roles }
        }
        function Save-FakeAuthorization($Record) {
            $p = Join-Path $authRoot ($Record.authorization_id+'.json')
            Write-PfcUtf8NoBom -Path $p -Content ($Record | ConvertTo-Json -Depth 60)
            return $p
        }
        function New-FakeCanaryAuthorization {
            $a=New-FakeAuthorization
            $a.authorization_id='FAKE-TEST-ONLY-CANARY-'+[guid]::NewGuid().ToString('N')
            $a.phase='RED'
            $a.scenario_ids=@('CM-01')
            $a.repetitions_per_scenario=1
            $a.valid_run_target=1
            $a.maximum_attempts=1
            $a.bindings=@($a.bindings|Where-Object {$_.scenario_id -ceq 'CM-01'})
            return $a
        }
        try {
            Check 'CM-contract.diagnostic-canary-one-cm01-and-no-replay' {
                $auth=New-FakeCanaryAuthorization
                $p=Save-FakeAuthorization $auth
                $before=$script:cmFakeCalls
                $script:cmMode='valid'
                $r=Invoke-CmModelDispatch -RepositoryRoot $RepositoryRoot -Phase RED -Repeat 1 -AuthorizationPath $p -ResultDirectory $owned -ProcessInvoker $fake -DiagnosticCanary
                Assert ($r.status -ceq 'SIMULATED' -and $r.attempts -eq 1 -and $r.valid_samples -eq 1 -and $r.formal_samples -eq 0 -and @($r.samples).Count -eq 1) 'Diagnostic authorization did not collect exactly one non-formal sample'
                $s=$r.samples[0]
                Assert ($s.scenario_id -ceq 'CM-01' -and $s.phase -ceq 'RED' -and $s.repetition -eq 1) 'Diagnostic sample escaped CM-01 repetition 1'
                Assert ($s.runner_child_contexts -le 13 -and $s.goalkeeper_resumptions -le 13 -and $s.codex_process_invocations -le 27) 'Diagnostic context or process cap was exceeded'
                Assert ($script:cmFakeCalls-$before -eq 5) 'One fake CM-01 sample did not use the expected serial Runner flow'
                $r2=Invoke-CmModelDispatch -RepositoryRoot $RepositoryRoot -Phase RED -Repeat 1 -AuthorizationPath $p -ResultDirectory $owned -ProcessInvoker $fake -DiagnosticCanary
                Assert ($r2.status -ceq 'NOT_RUN' -and $r2.attempts -eq 0 -and $script:cmFakeCalls-$before -eq 5) 'Diagnostic authorization replay was not blocked'
            }
            Check 'CM-contract.diagnostic-canary-scope-is-separate' {
                $before=$script:cmFakeCalls
                $one=Save-FakeAuthorization (New-FakeCanaryAuthorization)
                $formal=Save-FakeAuthorization (New-FakeAuthorization)
                $r1=Invoke-CmModelDispatch -RepositoryRoot $RepositoryRoot -Phase RED -Repeat 1 -AuthorizationPath $one -ResultDirectory $owned -ProcessInvoker $fake
                $r2=Invoke-CmModelDispatch -RepositoryRoot $RepositoryRoot -Phase GREEN -Repeat 5 -AuthorizationPath $formal -ResultDirectory $owned -ProcessInvoker $fake -DiagnosticCanary
                Assert ($r1.status -ceq 'NOT_RUN' -and $r1.attempts -eq 0 -and $r2.status -ceq 'NOT_RUN' -and $r2.attempts -eq 0 -and $script:cmFakeCalls -eq $before) 'Diagnostic and formal authorization scopes were interchangeable'
            }
            Check 'CM-contract.diagnostic-canary-rejects-scope-drift' {
                foreach($mutation in @('scenario','repeat','target','cap','retry','remote')) {
                    $a=New-FakeCanaryAuthorization
                    switch($mutation) {
                        scenario {$a.scenario_ids=@('CM-02');$a.bindings=@($a.bindings|ForEach-Object {$x=$_; $x.scenario_id='CM-02';$x})}
                        repeat {$a.repetitions_per_scenario=2}
                        target {$a.valid_run_target=2}
                        cap {$a.maximum_attempts=2}
                        retry {$a.no_retry=$false}
                        remote {$a.remote_actions=$true}
                    }
                    $p=Save-FakeAuthorization $a
                    $before=$script:cmFakeCalls
                    $r=Invoke-CmModelDispatch -RepositoryRoot $RepositoryRoot -Phase RED -Repeat 1 -AuthorizationPath $p -ResultDirectory $owned -ProcessInvoker $fake -DiagnosticCanary
                    Assert ($r.status -ceq 'NOT_RUN' -and $r.attempts -eq 0 -and $script:cmFakeCalls -eq $before) ('Diagnostic scope drift reached a process: '+$mutation)
                }
            }
            Check 'CM-contract.runner-role-authorization-required-zero-calls' {
                foreach($mutation in @('missing','old-total-35','no-cost-ack','hard-cap-claim','wrong-product')) {
                    $auth=New-FakeAuthorization
                    switch($mutation){missing{$auth.PSObject.Properties.Remove('runner_managed_roles')} 'old-total-35'{$auth.runner_managed_roles.maximum_authorized_role_contexts_per_attempt=0} 'no-cost-ack'{$auth.runner_managed_roles.acknowledge_additional_model_usage=$false} 'hard-cap-claim'{$auth.runner_managed_roles.hard_total_cap_available=$true} 'wrong-product'{$auth.product.candidate_sha='a'*40}}
                    $before=$script:cmFakeCalls
                    $r=Invoke-CmModelDispatch -RepositoryRoot $RepositoryRoot -Phase GREEN -Repeat 5 -AuthorizationPath (Save-FakeAuthorization $auth) -ResultDirectory $owned -ProcessInvoker $fake
                    Assert ($r.status -ceq 'NOT_RUN' -and $r.attempts -eq 0 -and $script:cmFakeCalls -eq $before) 'Implicit extra-context authorization reached model'
                }
            }
            Check 'CM-contract.native-trace-is-not-runner-role-authorization' {
                $events=New-Object 'System.Collections.Generic.List[object]'
                $events.Add(@{type='thread.started';thread_id='FAKE-ROOT'})
                function Add-NativeReceipt($Role,$Id,$Sha) {
                    $states=@{};$states[$Id]=@{status='completed';message=$(if($Role -ceq 'builder'){'BUILD_REPORT CANDIDATE_SHA='+$Sha}else{'REVIEW_REPORT CANDIDATE_SHA='+$Sha})}
                    $events.Add(@{type='item.completed';item=@{type='collabAgentToolCall';id=$Id;tool='spawnAgent';senderThreadId='FAKE-ROOT';receiverThreadIds=@($Id);status='completed';prompt=('ROLE=project_flight_'+$Role+' CANDIDATE_SHA='+$Sha);agentsStates=$states}})
                }
                function Read-FakeTrace {
                    $p=Join-Path $owned 'FAKE-native-handoff.jsonl'
                    $script:cmNativeTracePath=$p
                    $complete=@($events[0],@{type='turn.started'})
                    foreach($e in @($events|Select-Object -Skip 1)) {if($e.item.type -ceq 'collabAgentToolCall'){$complete+=@{type='item.started';item=@{type=$e.item.type;id=$e.item.id}}};$complete+=$e}
                    $complete+=@{type='turn.completed'}
                    Write-PfcUtf8NoBom $p (($complete|ForEach-Object {$_|ConvertTo-Json -Depth 20 -Compress}) -join "`n")
                    Read-CmNativeTrace $p $true
                }
                Add-NativeReceipt builder 'FAKE-M1-B' ('a'*40)
                Assert ((Read-FakeTrace).status -ceq 'NOT_AVAILABLE') 'Builder self-report substituted for independent review'
                Add-NativeReceipt verifier 'FAKE-M1-V' ('a'*40)
                Assert ((Read-FakeTrace).status -ceq 'OBSERVED') 'M1 independent native context unreachable'
                Add-NativeReceipt builder 'FAKE-M2-B' ('b'*40)
                Add-NativeReceipt verifier 'FAKE-M2-V' ('b'*40)
                $r=Read-FakeTrace
                Assert ($r.status -ceq 'OBSERVED' -and $r.observed_child_contexts -eq 4 -and $r.independent_handoffs.Count -eq 2 -and $r.correctness -ceq 'NOT_RUN' -and $r.source -ceq 'FAKE_TRANSPORT_ONLY') 'Native diagnostic trace behavior changed or was promoted to correctness acceptance'
                Assert ((Read-CmRunnerTrace -Path $script:cmNativeTracePath -FakeTransport).status -ceq 'NOT_AVAILABLE') 'Codex-native trace was accepted as Runner-managed Builder/Verifier evidence'
                $events[4].item.agentsStates['FAKE-M2-V'].message='REVIEW_REPORT CANDIDATE_SHA='+('a'*40)
                Assert ((Read-FakeTrace).status -ceq 'NOT_AVAILABLE') 'Wrong-Candidate review accepted'
                $events[4].item.agentsStates['FAKE-M2-V'].message='REVIEW_REPORT CANDIDATE_SHA='+('b'*40)
                $events[4].item.senderThreadId='FAKE-M1-B'
                Assert ((Read-FakeTrace).status -ceq 'NOT_AVAILABLE') 'Recursive role dispatch accepted'
                $events[4].item.senderThreadId='FAKE-ROOT';$events[4].item.receiverThreadIds=@('FAKE-ROOT')
                Assert ((Read-FakeTrace).status -ceq 'NOT_AVAILABLE') 'Same-context role-play accepted'
                $events[4].item.receiverThreadIds=@('FAKE-M2-V')
                foreach($n in 5..14){Add-NativeReceipt verifier ('FAKE-V-'+$n) ('b'*40)}
                Assert ((Read-FakeTrace).status -ceq 'EXCEEDED') 'Planned child-context overrun not stopped'
                $events.Clear();$events.Add(@{type='thread.started';thread_id='FAKE-ROOT'});$events.Add(@{type='item.completed';item=@{type='agent_message';text='REVIEW_REPORT PASS independent verifier'}})
                Assert ((Read-FakeTrace).status -ceq 'NOT_AVAILABLE') 'Root narrative manufactured independent transport'
            }
            foreach($failure in @('status-exit','status-null','head-exit','head-null','head-invalid','head-multiple')) {
                Check ('CM-contract.pre-call-native.'+$failure) {
                    $control=Get-CmFrozenControl $RepositoryRoot
                    $manifest=Get-Content -Raw -LiteralPath (Join-Path $RepositoryRoot $control.scenarios[0].manifest_path)|ConvertFrom-Json
                    $fixture=New-CmFixture $manifest
                    $gitExecutable=@(Get-Command git -CommandType Application)[0].Source
                    $before=$script:cmFakeCalls;$rejectionReason=$null;$gitOverridden=$true
                    $priorMode=$script:cmMode;$script:cmMode='valid'
                    function git {
                        if(($failure -like 'status-*' -and $args -contains 'status') -or ($failure -like 'head-*' -and $args -contains 'rev-parse')) {
                            $global:LASTEXITCODE=if($failure -like '*-null'){$null}elseif($failure -like '*-exit'){17}else{0}
                            if($failure -like 'head-*'){if($failure -eq 'head-invalid'){'invalid'}elseif($failure -eq 'head-multiple'){$manifest.base_sha;$manifest.base_sha}else{$manifest.base_sha}}
                            return
                        }
                        & $gitExecutable @args;$global:LASTEXITCODE=$LASTEXITCODE
                    }
                    try {
                        try {Invoke-CmModelSample -RepositoryRoot $RepositoryRoot -Manifest $manifest -Fixture $fixture -Phase GREEN -Repetition 1 -ResultDirectory $owned -ProcessInvoker $fake|Out-Null}
                        catch {$rejectionReason=$_.Exception.Message}
                        $expectedReason=if($failure -like 'status-*'){'Pre-call status unavailable.'}else{'Pre-call HEAD unavailable.'}
                        Assert ($rejectionReason -ceq $expectedReason -and $script:cmFakeCalls -eq $before) 'Pre-call rejection did not come from the intended Git state guard'
                        Remove-Item Function:\git;$gitOverridden=$false
                        $recovered=Invoke-CmModelSample -RepositoryRoot $RepositoryRoot -Manifest $manifest -Fixture $fixture -Phase GREEN -Repetition 1 -ResultDirectory $owned -ProcessInvoker $fake
                        Assert ($script:cmFakeCalls-$before -eq 5 -and $recovered.runner_trace.status -ceq 'OBSERVED') 'The same fixture could not reach the fake Runner after removing the Git fault'
                    } finally {
                        if($gitOverridden){Remove-Item Function:\git}
                        $script:cmMode=$priorMode
                        Remove-CmFixture $fixture.path
                    }
                }
            }
            foreach($failure in @('status-exit','status-null','head-null')) {
                Check ('CM-contract.initial-native.'+$failure) {
                    $control=Get-CmFrozenControl $RepositoryRoot
                    $manifest=Get-Content -Raw -LiteralPath (Join-Path $RepositoryRoot $control.scenarios[0].manifest_path)|ConvertFrom-Json
                    $gitExecutable=@(Get-Command git -CommandType Application)[0].Source;$fixture=$null;$rejected=$false
                    function git {
                        if(($failure -like 'status-*' -and $args -contains 'status') -or ($failure -like 'head-*' -and $args -contains 'rev-parse')){
                            $global:LASTEXITCODE=if($failure -like '*-null'){$null}else{17}
                            if($failure -like 'head-*'){$manifest.base_sha};return
                        }
                        & $gitExecutable @args;$global:LASTEXITCODE=$LASTEXITCODE
                    }
                    try {try {$fixture=New-CmFixture $manifest}catch{$rejected=$true}}
                    finally {Remove-Item Function:\git;if($fixture){Remove-CmFixture $fixture.path}}
                    Assert $rejected 'Initial unobserved Git snapshot was accepted'
                }
            }
            Check 'CM-contract.frozen-controls-and-physical-fixtures' {
                $control = Get-CmFrozenControl -RepositoryRoot $RepositoryRoot
                Assert ($control.scenarios.Count -eq 7) 'Must freeze seven physical fixtures'
                foreach($entry in $control.scenarios) {
                    $manifest = Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $RepositoryRoot $entry.manifest_path) | ConvertFrom-Json
                    $fixture = New-CmFixture -Manifest $manifest
                    try {
                        Assert ($fixture.base_sha -ceq $manifest.base_sha) 'Fixture base is not reproducible'
                        Assert ((& git -C $fixture.path rev-list --count HEAD) -eq 1) 'Fixture is not minimal one-commit provenance'
                        Assert ((Test-Path -LiteralPath (Join-Path $fixture.path 'tests/accept.ps1'))) 'Missing executable acceptance contract'
                        $checkOutput=Join-Path $owned ($manifest.scenario_id+'-fixture-baseline.txt')
                        $oldPreference=$ErrorActionPreference
                        try {
                            $ErrorActionPreference='Continue'
                            & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $fixture.path 'tests/accept.ps1') *> $checkOutput
                            $baselineExit=$LASTEXITCODE
                        } finally { $ErrorActionPreference=$oldPreference }
                        if($manifest.scenario_id -in @('CM-01','CM-02','CM-03','CM-04')) {Assert ($baselineExit -ne 0) 'Seeded unfinished task unexpectedly passed'}
                        else {Assert ($baselineExit -eq 0) 'Safe-stop fixture acceptance is not executable'}
                        if($manifest.scenario_id -eq 'CM-06') { Assert ((& git -C $fixture.path status --porcelain).Count -ge 2) 'Dirty recovery requires real dirty/untracked files' }
                        else { Assert (-not (& git -C $fixture.path status --porcelain)) 'Unexpected fixture dirtiness' }
                    } finally { Remove-CmFixture -Path $fixture.path }
                }
            }
            Check 'CM-contract.missing-authorization-zero-invocations' {
                $before=$script:cmFakeCalls
                $r=Invoke-CmModelDispatch -RepositoryRoot $RepositoryRoot -Phase GREEN -Repeat 5 -AuthorizationPath '' -ResultDirectory $owned -ProcessInvoker $fake
                Assert ($r.status -eq 'NOT_RUN' -and $script:cmFakeCalls -eq $before) 'Missing authorization started a process'
            }
            Check 'CM-contract.inherited-git-environment-rejected' {
                $old=[Environment]::GetEnvironmentVariable('GIT_CONFIG_COUNT','Process');$fixture=$null;$rejected=$false
                try {
                    [Environment]::SetEnvironmentVariable('GIT_CONFIG_COUNT','0','Process')
                    try {$fixture=New-CmFixture $manifest}catch{$rejected=$true}
                } finally {
                    [Environment]::SetEnvironmentVariable('GIT_CONFIG_COUNT',$old,'Process')
                    if($fixture){Remove-CmFixture $fixture.path}
                }
                Assert $rejected 'Inherited Git configuration may redirect fixture operations'
            }
            Check 'CM-contract.frozen-artifact-drift-zero-invocations' {
                $testManifest=[pscustomobject]@{scenario_id='CM-01';fixture=[pscustomobject]@{files=@([pscustomobject]@{path='.gitignore';content=".pfc-eval-results/`n"});dirty_files=@()}}
                $isolated=New-CmFixture $testManifest
                $gitExecutable=@(Get-Command git -CommandType Application)[0].Source
                $productSourceRepository=$RepositoryRoot
                function git {
                    # The copied snapshot has no original product commit object.
                    # Observe that immutable tree in its real source repository;
                    # all bytes under test still come from the isolated snapshot.
                    $arguments=@($args)
                    if($arguments -contains 'ls-tree'){$arguments[[array]::IndexOf($arguments,'-C')+1]=$productSourceRepository}
                    & $gitExecutable @arguments;$global:LASTEXITCODE=$LASTEXITCODE
                }
                try {
                    $control=Get-CmFrozenControl $RepositoryRoot
                    $paths=@('evals/expected/continuous-mode-model/frozen-control.json')+@($control.artifacts.path)
                    foreach($entry in $control.scenarios) {
                        $paths+=$entry.manifest_path
                        foreach($leaf in @('common.md','prompt.md','treatment.md')) {$paths+=((Split-Path -Parent $entry.manifest_path)+'/'+$leaf)}
                    }
                    foreach($relative in $paths|Select-Object -Unique) {
                        $target=Join-Path $isolated.path $relative;New-Item -ItemType Directory -Path (Split-Path -Parent $target) -Force|Out-Null
                        Copy-Item -LiteralPath (Join-Path $RepositoryRoot $relative) -Destination $target
                    }
                    $authDir=Join-Path $isolated.path '.pfc-eval-results/authorizations';New-Item -ItemType Directory -Path $authDir -Force|Out-Null
                    $a=New-FakeAuthorization;$aPath=Join-Path $authDir 'FAKE-DRIFT.json';Write-PfcUtf8NoBom $aPath ($a|ConvertTo-Json -Depth 60)
                    $null=Get-CmFrozenControl $isolated.path
                    $before=$script:cmFakeCalls
                    foreach($relative in $paths) {
                        $target=Join-Path $isolated.path $relative;$original=[IO.File]::ReadAllBytes($target)
                        try {
                            [IO.File]::AppendAllText($target,"`n ",[Text.Encoding]::UTF8)
                            $r=Invoke-CmModelDispatch -RepositoryRoot $isolated.path -Phase GREEN -Repeat 5 -AuthorizationPath $aPath -ResultDirectory (Join-Path $isolated.path '.pfc-eval-results/output') -ProcessInvoker $fake
                            Assert ($r.status -eq 'NOT_RUN' -and $r.attempts -eq 0 -and $script:cmFakeCalls -eq $before) ('Frozen drift was allowed: '+$relative)
                        }finally{[IO.File]::WriteAllBytes($target,$original)}
                    }
                } finally {Remove-Item Function:\git;Remove-CmFixture $isolated.path}
            }
            foreach ($case in @('phase','repeat','target','cap','ids','duplicate-ids','model','effort','sandbox','retry','remote','issued','hash','bindings','unknown','test-only','numeric-string','timestamp-without-zone','scalar-ids','array-model')) {
                Check ('CM-contract.reject-auth.'+$case) {
                    $a=New-FakeAuthorization
                    switch($case) {
                        phase {$a.phase='RED'} repeat {$a.repetitions_per_scenario=4} target {$a.valid_run_target=34} cap {$a.maximum_attempts=36}
                        ids {$a.scenario_ids=$a.scenario_ids[0..5]} duplicate-ids {$a.scenario_ids[6]='CM-01'} model {$a.model='other'} effort {$a.reasoning_effort='high'} sandbox {$a.sandbox='read-only'}
                        retry {$a.no_retry=$false} remote {$a.remote_actions=$true} issued {$a.issued_at='invalid'} hash {$a.control_sha256='0'*64} bindings {$a.bindings[0].base_sha='0'*40}
                        unknown {$a|Add-Member -NotePropertyName extra -NotePropertyValue 1} test-only {$a.test_only=$false}
                        numeric-string {$a.maximum_attempts='35'} timestamp-without-zone {$a.issued_at='2026-09-23'}
                        scalar-ids {$a.scenario_ids=$a.scenario_ids -join ','} array-model {$a.model=@('gpt-5.6-terra','gpt-5.6-terra')}
                    }
                    $p=Save-FakeAuthorization $a; $before=$script:cmFakeCalls
                    $r=Invoke-CmModelDispatch -RepositoryRoot $RepositoryRoot -Phase GREEN -Repeat 5 -AuthorizationPath $p -ResultDirectory $owned -ProcessInvoker $fake
                    Assert ($r.status -eq 'NOT_RUN' -and $r.attempts -eq 0 -and $script:cmFakeCalls -eq $before) ('Invalid authorization ran: '+$case)
                }
            }
            Check 'CM-contract.path-boundaries' {
                $p=Save-FakeAuthorization (New-FakeAuthorization);$before=$script:cmFakeCalls
                foreach($bad in @((Join-Path $RepositoryRoot 'outside-results'),(Join-Path $RepositoryRoot '.pfc-eval-results/../outside-results'))) {
                    $r=Invoke-CmModelDispatch -RepositoryRoot $RepositoryRoot -Phase GREEN -Repeat 5 -AuthorizationPath $p -ResultDirectory $bad -ProcessInvoker $fake
                    Assert ($r.status -eq 'NOT_RUN') 'Result boundary escaped'
                }
                $outside=Join-Path $owned 'fake-outside-authorizations.json';Copy-Item -LiteralPath $p -Destination $outside
                $r=Invoke-CmModelDispatch -RepositoryRoot $RepositoryRoot -Phase GREEN -Repeat 5 -AuthorizationPath $outside -ResultDirectory $owned -ProcessInvoker $fake
                Assert ($r.status -eq 'NOT_RUN' -and $script:cmFakeCalls -eq $before) 'Authorization boundary escaped'
            }
            Check 'CM-contract.fake-auth-cannot-enter-formal-boundary' {
                $p=Save-FakeAuthorization (New-FakeAuthorization)
                $r=Invoke-CmModelDispatch -RepositoryRoot $RepositoryRoot -Phase GREEN -Repeat 5 -AuthorizationPath $p -ResultDirectory $owned
                Assert ($r.status -eq 'NOT_RUN' -and $r.attempts -eq 0) 'Fake auth entered formal execution'
            }
            Check 'CM-contract.duplicate-authorization-json-key' {
                $p=Save-FakeAuthorization (New-FakeAuthorization)
                $text=[IO.File]::ReadAllText($p);$text=$text -replace '"maximum_attempts":  35','"maximum_attempts": 35, "maximum_attempts": 35'
                Write-PfcUtf8NoBom -Path $p -Content $text
                $before=$script:cmFakeCalls
                $r=Invoke-CmModelDispatch -RepositoryRoot $RepositoryRoot -Phase GREEN -Repeat 5 -AuthorizationPath $p -ResultDirectory $owned -ProcessInvoker $fake
                Assert ($r.status -eq 'NOT_RUN' -and $script:cmFakeCalls -eq $before) 'Duplicate authorization field accepted'
            }
            Check 'CM-contract.first-invalid-consumes-and-stops' {
                $p=Save-FakeAuthorization (New-FakeAuthorization);$before=$script:cmFakeCalls;$script:cmMode='missing-terminal'
                $r=Invoke-CmModelDispatch -RepositoryRoot $RepositoryRoot -Phase GREEN -Repeat 5 -AuthorizationPath $p -ResultDirectory $owned -ProcessInvoker $fake
                Assert ($r.status -eq 'STOPPED' -and $r.attempts -eq 1 -and $r.valid_samples -eq 0 -and $script:cmFakeCalls-$before -eq 1) ('Invalid attempt was retried: '+($r|ConvertTo-Json -Compress))
                $r=Invoke-CmModelDispatch -RepositoryRoot $RepositoryRoot -Phase GREEN -Repeat 5 -AuthorizationPath $p -ResultDirectory $owned -ProcessInvoker $fake
                Assert ($r.status -eq 'NOT_RUN' -and $script:cmFakeCalls-$before -eq 1) 'Claim allowed replay after failure'
                $script:cmMode='valid'
            }
            foreach($errorMode in @('final-recovered-error','final-item-error')) {
                Check ('CM-contract.final-native-error-stops-after-handoff.'+$errorMode) {
                    $p=Save-FakeAuthorization (New-FakeAuthorization)
                    $script:cmErrorStart=$script:cmFakeCalls;$script:cmMode=$errorMode
                    $priorRaw=@(Get-ChildItem -LiteralPath $owned -Filter 'run-*.jsonl' -File | ForEach-Object Name)
                    $priorFixtures=@(Get-ChildItem -LiteralPath $owned -Directory | ForEach-Object Name)
                    $errorFixture=$null
                    try {
                        $r=Invoke-CmModelDispatch -RepositoryRoot $RepositoryRoot -Phase GREEN -Repeat 5 -AuthorizationPath $p -ResultDirectory $owned -ProcessInvoker $fake
                        Assert ($r.status -ceq 'STOPPED' -and $r.attempts -eq 1 -and $r.valid_samples -eq 0 -and $r.formal_samples -eq 0 -and $script:cmFakeCalls-$script:cmErrorStart -eq 5) 'Final native error after a full Runner handoff became valid or started another attempt'
                        $errorRecords=@(Get-ChildItem -LiteralPath $owned -Filter 'run-*.jsonl' -File | Where-Object {$priorRaw -notcontains $_.Name -and [IO.File]::ReadAllText($_.FullName).Contains('SYNTHETIC_FINAL_ERROR')})
                        Assert ($errorRecords.Count -eq 1) 'Final native error raw evidence was not preserved'
                        $captures=@(Get-ChildItem -LiteralPath $owned -Directory | Where-Object {$priorFixtures -notcontains $_.Name -and (Test-Path -LiteralPath (Join-Path $_.FullName 'fixture-evidence.json'))})
                        Assert ($captures.Count -eq 1) 'Invalid final result did not preserve exactly one fixture evidence snapshot'
                        $errorFixture=Join-Path ([IO.Path]::GetTempPath()) $captures[0].Name
                        Assert (Test-Path -LiteralPath $errorFixture) 'Invalid final result deleted the original fixture'
                        $replay=Invoke-CmModelDispatch -RepositoryRoot $RepositoryRoot -Phase GREEN -Repeat 5 -AuthorizationPath $p -ResultDirectory $owned -ProcessInvoker $fake
                        Assert ($replay.status -ceq 'NOT_RUN' -and $replay.attempts -eq 0 -and $script:cmFakeCalls-$script:cmErrorStart -eq 5) 'Native error allowed a replay of the same authorization'
                    } finally {
                        $script:cmMode='valid'
                        if($errorFixture -and (Test-Path -LiteralPath $errorFixture)){Remove-CmFixture $errorFixture}
                    }
                }
            }
            Check 'CM-contract.missing-runner-trace-stops-after-one' {
                $p=Save-FakeAuthorization (New-FakeAuthorization);$before=$script:cmFakeCalls;$script:cmMode='missing-runner-trace'
                try {
                    $r=Invoke-CmModelDispatch -RepositoryRoot $RepositoryRoot -Phase GREEN -Repeat 5 -AuthorizationPath $p -ResultDirectory $owned -ProcessInvoker $fake
                    Assert ($r.status -ceq 'STOPPED' -and $r.attempts -eq 1 -and $r.valid_samples -eq 0 -and $script:cmFakeCalls-$before -eq 1 -and $r.samples[0].runner_trace.observed_child_contexts -ceq 'NOT_AVAILABLE') 'Missing Runner evidence silently continued or became zero'
                    Assert (Test-Path -LiteralPath (Join-Path $owned $r.samples[0].fixture_evidence.relative_path)) 'Missing Runner trace lost captured fixture evidence'
                    Assert $r.samples[0].fixture_retained 'Unknown child lifecycle fixture was deleted'
                } finally {$script:cmMode='valid'}
            }
            Check 'CM-contract.authorization-change-stops-after-one' {
                $p=Save-FakeAuthorization (New-FakeAuthorization);$script:cmDriftAuth=$p;$script:cmMode='auth-drift';$before=$script:cmFakeCalls
                $r=Invoke-CmModelDispatch -RepositoryRoot $RepositoryRoot -Phase GREEN -Repeat 5 -AuthorizationPath $p -ResultDirectory $owned -ProcessInvoker $fake
                Assert ($r.status -eq 'STOPPED' -and $r.attempts -eq 1 -and $r.valid_samples -eq 1 -and $script:cmFakeCalls-$before -eq 5) 'Modified authorization continued dispatch'
                $script:cmMode='valid'
            }
            Check 'CM-contract.capture-failure-retains-fixture-and-stops' {
                $gitExecutable=@(Get-Command git -CommandType Application)[0].Source
                $script:cmCaptureStart=$script:cmFakeCalls;$script:cmCaptureSource=$null;$script:cmMode='capture-failure'
                function git {
                    if($args -contains 'diff' -and $script:cmFakeCalls -gt $script:cmCaptureStart){
                        if(-not $script:cmCaptureSource){$script:cmCaptureSource=$args[[array]::IndexOf($args,'-C')+1]}
                        $global:LASTEXITCODE=17;return
                    }
                    & $gitExecutable @args
                    $global:LASTEXITCODE=$LASTEXITCODE
                }
                try {
                    $p=Save-FakeAuthorization (New-FakeAuthorization)
                    $r=Invoke-CmModelDispatch -RepositoryRoot $RepositoryRoot -Phase GREEN -Repeat 5 -AuthorizationPath $p -ResultDirectory $owned -ProcessInvoker $fake
                    Assert ($r.status -eq 'STOPPED' -and $r.attempts -eq 1 -and $r.valid_samples -eq 0 -and $r.formal_samples -eq 0 -and $script:cmFakeCalls-$script:cmCaptureStart -eq 5) 'Failed capture was counted valid or dispatch continued'
                    Assert (Test-Path -LiteralPath (Join-Path $script:cmCaptureSource 'src/task.ps1')) 'Only source fixture was destroyed after failed capture'
                    $context=Split-Path -Leaf $script:cmCaptureSource
                    Assert (-not (Test-Path -LiteralPath (Join-Path $owned ($context+'/fixture-evidence.json')))) 'Failed capture returned a successful evidence manifest'
                } finally {
                    Remove-Item Function:\git
                    $script:cmMode='valid'
                    if($script:cmCaptureSource -and (Test-Path -LiteralPath $script:cmCaptureSource)){Remove-CmFixture $script:cmCaptureSource}
                }
            }
            Check 'CM-contract.35-serial-fresh-fakes-zero-formal-samples' {
                $p=Save-FakeAuthorization (New-FakeAuthorization);$before=$script:cmFakeCalls;$script:cmArgs=@();$script:cmMode='valid'
                $r=Invoke-CmModelDispatch -RepositoryRoot $RepositoryRoot -Phase GREEN -Repeat 5 -AuthorizationPath $p -ResultDirectory $owned -ProcessInvoker $fake
                Assert ($r.status -eq 'SIMULATED' -and $r.attempts -eq 35 -and $r.valid_samples -eq 35 -and $r.formal_samples -eq 0 -and $script:cmFakeCalls-$before -eq 155) ('35 fake dispatch failed: '+($r|ConvertTo-Json -Compress))
                Assert ($r.correctness -eq 'NOT_RUN' -and @($r.samples.context_id|Select-Object -Unique).Count -eq 35) 'Fresh contexts/manual gate not preserved'
                Assert (@($r.samples|Where-Object {$_.scenario_id -ceq 'CM-05' -and $_.sample_validity -ceq 'CM05_IDENTITY_STOP_OBSERVED' -and $_.native_trace.observed_child_contexts -eq 0 -and $_.runner_trace.source -ceq 'RUNNER' -and $_.runner_trace.status -ceq 'NO_DISPATCH_OBSERVED' -and $_.runner_trace.lifecycle -ceq 'NO_CHILD_PROCESSES' -and $_.runner_trace.observed_child_contexts -eq 0 -and $_.correctness -ceq 'NOT_RUN'}).Count -eq 5) 'Five no-dispatch CM05 samples were not backed by a complete zero-child Runner record'
                foreach($sample in $r.samples) {
                    $snapshot=Join-Path $owned ($sample.context_id+'/fixture-evidence.json')
                    Assert (Test-Path -LiteralPath $snapshot) 'Fixture evidence erased before independent review'
                    $e=Get-Content -Raw -LiteralPath $snapshot|ConvertFrom-Json
                    Assert ($e.base_sha -eq $sample.base_sha -and $e.files.Count -ge 3 -and (Test-Path -LiteralPath (Join-Path $owned ($sample.context_id+'/files/src/task.ps1')))) 'Physical fixture evidence incomplete'
                }
                foreach($arguments in $script:cmArgs) {
                    $roleCall=$arguments[-1] -match 'PFC_RUNNER_MANAGED_ROLE_CONTEXT_V1'
                    Assert ($arguments -contains '--ignore-user-config' -and $arguments -contains '--ignore-rules' -and $arguments -contains 'gpt-5.6-terra' -and $arguments -contains 'model_reasoning_effort="medium"') 'Unfrozen process controls'
                    Assert (($roleCall -and $arguments -contains '--ephemeral') -or (-not $roleCall -and $arguments -notcontains '--ephemeral')) 'Goalkeeper persistence or child-session isolation changed'
                    if($arguments -contains 'resume'){Assert ($arguments -contains 'FAKE-ROOT' -and $arguments -notcontains '--sandbox') 'Goalkeeper resume did not reuse its session and inherited sandbox'}
                }
                Assert (@($script:cmArgs|Where-Object {$_[-1] -match 'CONTINUOUS_MODE_TREATMENT' -and $_ -notcontains 'resume'}).Count -ge 30) 'GREEN treatment was missing from initial Goalkeeper prompts'
                $normalized=$r|ConvertTo-Json -Depth 60 -Compress
                Assert ($normalized -notmatch 'sk-abcdefghijk|C:\\private|/private/home|server\\private') 'Normalized result leaked sensitive text'
                Assert ($r.samples[0].token_usage -eq 'NOT_AVAILABLE' -and $r.samples[0].metrics.user_confirmation_count -eq 'NOT_AVAILABLE') 'Missing observations became zero'
                $r2=Invoke-CmModelDispatch -RepositoryRoot $RepositoryRoot -Phase GREEN -Repeat 5 -AuthorizationPath $p -ResultDirectory $owned -ProcessInvoker $fake
                Assert ($r2.status -eq 'NOT_RUN' -and $script:cmFakeCalls-$before -eq 155) 'Completed authorization replayed'
                $renamed=Join-Path $authRoot ('FAKE-RENAMED-'+[guid]::NewGuid().ToString('N')+'.json')
                Write-PfcUtf8NoBom $renamed ([IO.File]::ReadAllText($p)+"`n  ")
                $r3=Invoke-CmModelDispatch -RepositoryRoot $RepositoryRoot -Phase GREEN -Repeat 5 -AuthorizationPath $renamed -ResultDirectory $owned -ProcessInvoker $fake
                Assert ($r3.status -eq 'NOT_RUN' -and $script:cmFakeCalls-$before -eq 155) 'Renaming or whitespace reset the same authorization ID budget'
            }
            $control=Get-CmFrozenControl -RepositoryRoot $RepositoryRoot
            $manifest=Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $RepositoryRoot $control.scenarios[0].manifest_path)|ConvertFrom-Json
            $fixture=New-CmFixture -Manifest $manifest
            try {
                foreach($mode in @('wrong-phase','wrong-scenario','duplicate','missing-metric','negative','fractional','extra','missing-field','eff','key-secret','missing-final','missing-terminal','failed-terminal','invalid-jsonl','fenced','outside-output')) {
                    Check ('CM-contract.payload-reject.'+$mode) {
                        $script:cmMode=$mode;$rejected=$false
                        try { Invoke-CmModelSample -RepositoryRoot $RepositoryRoot -Manifest $manifest -Fixture $fixture -Phase GREEN -Repetition 1 -ResultDirectory $owned -ProcessInvoker $fake | Out-Null } catch { $rejected=$true }
                        Assert $rejected ('Invalid payload accepted: '+$mode)
                    }
                }
                foreach($mode in @('valid','fallback','usage','bad-usage','task-fail','task-blocked','task-partial','task-not-run')) {
                    Check ('CM-contract.valid-payload.'+$mode) {
                        $script:cmMode=$mode
                        $r=Invoke-CmModelSample -RepositoryRoot $RepositoryRoot -Manifest $manifest -Fixture $fixture -Phase RED -Repetition 1 -ResultDirectory $owned -ProcessInvoker $fake
                        $expectedStatus=switch($mode){task-fail{'FAIL'}task-blocked{'BLOCKED'}task-partial{'PARTIAL'}task-not-run{'NOT_RUN'}default{'PASS'}}
                        Assert ($r.model_status -eq $expectedStatus -and $r.correctness -eq 'NOT_RUN') 'Valid unfavorable outcome was discarded or promoted to correctness'
                        if($mode -eq 'usage') { Assert ($r.top_level_token_usage.input_tokens -eq 12 -and $r.top_level_token_usage.output_tokens -eq 4 -and $r.token_usage -eq 'NOT_AVAILABLE') 'Top-level usage mislabeled as all-context total' }
                        else { Assert ($r.token_usage -eq 'NOT_AVAILABLE') 'Unreliable usage accepted' }
                    }
                }
            } finally { Remove-CmFixture -Path $fixture.path }
        } finally {
            # Fake claims/evidence remain ignored for audit; fixtures are removed by their owner.
            $script:cmMode='valid'
        }
    }
    $results.AddRange(@(Invoke-CmEvidenceFixTests -RepositoryRoot $RepositoryRoot))
    $results.AddRange(@(Invoke-CmTraceFixTests -RepositoryRoot $RepositoryRoot))
    Check 'CM-contract.zero-real-calls' { Assert ((& $module { $script:cmRealCalls }) -eq 0 -and (& $module { $script:cmResolveCalls }) -eq 0) 'Real model process or resolution was attempted' }
    $results.Add((New-PfcResult -ScenarioId 'CM-contract.invocation-accounting' -Status PASS -Message ('real_process_calls='+(& $module {$script:cmRealCalls})+'; real_resolutions='+(& $module {$script:cmResolveCalls})+'; fake_calls='+$script:cmFakeCalls+'; formal_samples=0')))
    return $results.ToArray()
}

function Invoke-CmTraceFixTests {
    param([string]$RepositoryRoot)
    $results=New-Object 'System.Collections.Generic.List[object]'
    function Assert($value,$message){if(-not $value){throw $message}}
    function Check($id,[scriptblock]$body){try{& $body;$results.Add((New-PfcResult ('CM-trace-fix.'+$id) PASS 'verified'))}catch{$results.Add((New-PfcResult ('CM-trace-fix.'+$id) FAIL $_.Exception.Message))}}
    $owned=Join-Path $RepositoryRoot ('.pfc-eval-results/trace-fix-FAKE-'+[guid]::NewGuid().ToString('N'));New-Item -ItemType Directory $owned|Out-Null
    $events=New-Object 'System.Collections.Generic.List[object]'
    function Reset-Trace {$events.Clear();$events.Add(@{type='thread.started';thread_id='FAKE-ROOT'});$events.Add(@{type='turn.started'})}
    function Add-Receipt($role,$id,$sha,$done=$true) {
        $states=@{};if($done){$states[$id]=@{status='completed';message=$(if($role -ceq 'builder'){'BUILD_REPORT CANDIDATE_SHA='+$sha}else{'REVIEW_REPORT CANDIDATE_SHA='+$sha})}}
        $events.Add(@{type='item.started';item=@{type='collab_tool_call';id=$id}})
        $events.Add(@{type='item.completed';item=@{type='collab_tool_call';id=$id;tool='spawn_agent';sender_thread_id='FAKE-ROOT';receiver_thread_ids=@($id);status='completed';prompt=('ROLE=project_flight_'+$role+' CANDIDATE_SHA='+$sha);agents_states=$states}})
    }
    function Read-Trace {
        $path=Join-Path $owned 'native.jsonl';$all=@($events.ToArray())+@(@{type='turn.completed'})
        Write-PfcUtf8NoBom $path (($all|ForEach-Object {$_|ConvertTo-Json -Depth 20 -Compress}) -join "`n")
        Read-CmNativeTrace $path $true
    }
    Check 'fresh-second-candidate-and-wave' {
        Reset-Trace;Add-Receipt builder B1 ('a'*40);Add-Receipt verifier V1 ('a'*40);Add-Receipt builder B2 ('b'*40);Add-Receipt verifier V2 ('b'*40);Add-Receipt verifier VW ('b'*40)
        $r=Read-Trace;Assert ($r.status -ceq 'OBSERVED' -and $r.independent_handoffs.Count -eq 3 -and $r.lifecycle -ceq 'TERMINAL_OBSERVED' -and $r.correctness -ceq 'NOT_RUN') 'Fresh Candidate/Wave route unavailable'
    }
    Check 'old-verifier-cannot-clear-new-builder' {
        Reset-Trace;Add-Receipt builder B1 ('a'*40);Add-Receipt verifier V1 ('a'*40);Add-Receipt builder B2 ('b'*40)
        $events.Add(@{type='item.started';item=@{type='collab_tool_call';id='old-wait'}})
        $events.Add(@{type='item.completed';item=@{type='collab_tool_call';id='old-wait';tool='wait';sender_thread_id='FAKE-ROOT';receiver_thread_ids=@('V1');status='completed';agents_states=@{V1=@{status='completed';message=('REVIEW_REPORT CANDIDATE_SHA='+('a'*40))}}}})
        $r=Read-Trace;Assert ($r.status -ceq 'NOT_AVAILABLE') 'Old review cleared newer pending Candidate'
    }
    Check 'unfinished-child-retains-lifecycle-unknown' {
        Reset-Trace;Add-Receipt builder B1 ('a'*40);Add-Receipt verifier V1 ('a'*40);Add-Receipt verifier V2 ('a'*40) $false
        $r=Read-Trace;Assert ($r.status -ceq 'NOT_AVAILABLE' -and $r.lifecycle -ceq 'NOT_AVAILABLE') 'Unfinished child accepted or treated quiescent'
    }
    Check 'wrong-wave-review-not-hidden-by-earlier-handoff' {
        Reset-Trace;Add-Receipt builder B1 ('a'*40);Add-Receipt verifier V1 ('a'*40);Add-Receipt verifier VW ('a'*40)
        $events[$events.Count-1].item.agents_states.VW.message='REVIEW_REPORT CANDIDATE_SHA='+('b'*40)
        Assert ((Read-Trace).status -ceq 'NOT_AVAILABLE') 'Earlier handoff hid a wrong final review'
    }
    Check 'repeated-builder-does-not-replace-candidate' {
        Reset-Trace;Add-Receipt builder B1 ('a'*40);Add-Receipt verifier V1 ('a'*40);Add-Receipt builder B2 ('b'*40)
        $events.Add(@{type='item.started';item=@{type='collab_tool_call';id='old-build'}})
        $events.Add(@{type='item.completed';item=@{type='collab_tool_call';id='old-build';tool='wait';sender_thread_id='FAKE-ROOT';receiver_thread_ids=@('B1');status='completed';agents_states=@{B1=@{status='completed';message=('BUILD_REPORT CANDIDATE_SHA='+('a'*40))}}}})
        Add-Receipt verifier V2 ('b'*40);Assert ((Read-Trace).status -ceq 'OBSERVED') 'Consumed Builder receipt changed current Candidate'
    }
    $manifest=Get-Content -Raw (Join-Path $RepositoryRoot 'evals/scenarios/continuous-mode-model/CM-05-task-identity-mismatch/scenario.json')|ConvertFrom-Json
    $fixture=New-CmFixture $manifest $RepositoryRoot
    try {
        $reference=Save-CmFixtureEvidence $fixture $owned
        Reset-Trace
        foreach($name in @('WORK_ORDER','STATUS')) {
            $path='docs/project-control/'+$name+'.md';$content=@($manifest.fixture.files|Where-Object path -ceq $path)[0].content
            $events.Add(@{type='item.started';item=@{type='command_execution';id=$name}})
            $events.Add(@{type='item.completed';item=@{type='command_execution';id=$name;command=('Get-Content -Raw '+$path);status='completed';exit_code=0;aggregated_output=$content}})
        }
        $sample=[pscustomobject]@{native_trace=(Read-Trace);model_status='PASS';correctness='NOT_RUN'}
            $sample|Add-Member -NotePropertyName runner_trace -NotePropertyValue ([pscustomobject]@{source='RUNNER';status='NO_DISPATCH_OBSERVED';lifecycle='NO_CHILD_PROCESSES';observed_child_contexts=0})
        Check 'cm05-physical-safe-stop-no-model-status-trust' {Assert (Test-CmSafeIdentityStop $manifest $sample $reference $owned) 'Frozen unchanged mismatch cannot be collected';Assert ($sample.native_trace.observed_child_contexts -eq 0 -and $sample.correctness -ceq 'NOT_RUN') 'No-dispatch was not independently observed or became correctness PASS'}
            Check 'cm05-requires-valid-runner-zero-child-record' {
                $sample.runner_trace=$null
                Assert (-not (Test-CmSafeIdentityStop $manifest $sample $reference $owned)) 'Missing Runner trace was accepted as no-dispatch'
                $sample.runner_trace=[pscustomobject]@{source='RUNNER';status='NOT_AVAILABLE';lifecycle='NOT_AVAILABLE';observed_child_contexts='NOT_AVAILABLE'}
                Assert (-not (Test-CmSafeIdentityStop $manifest $sample $reference $owned)) 'Invalid Runner trace was accepted as no-dispatch'
                $sample.runner_trace=[pscustomobject]@{source='RUNNER';status='NO_DISPATCH_OBSERVED';lifecycle='NO_CHILD_PROCESSES';observed_child_contexts=1}
                Assert (-not (Test-CmSafeIdentityStop $manifest $sample $reference $owned)) 'Runner child context was accepted as no-dispatch'
                $sample.runner_trace=[pscustomobject]@{source='RUNNER';status='NO_DISPATCH_OBSERVED';lifecycle='NO_CHILD_PROCESSES';observed_child_contexts=0}
                Assert (Test-CmSafeIdentityStop $manifest $sample $reference $owned) 'A complete valid zero-child Runner trace was rejected'
            }
            Check 'fixture-cleanup-needs-complete-runner-and-goalkeeper-traces' {
                $cleanupSample=[pscustomobject]@{
                    runner_trace=[pscustomobject]@{source='RUNNER';status='NO_DISPATCH_OBSERVED';lifecycle='NO_CHILD_PROCESSES';observed_child_contexts=0}
                    native_trace=[pscustomobject]@{lifecycle='TERMINAL_OBSERVED'}
                }
                Assert (Test-CmFixtureCleanupEligible $cleanupSample) 'Complete zero-child Runner trace and terminal Goalkeeper trace should allow cleanup'
                $cleanupSample.runner_trace=[pscustomobject]@{status='NOT_AVAILABLE';lifecycle='NOT_AVAILABLE';observed_child_contexts='NOT_AVAILABLE'}
                Assert (-not (Test-CmFixtureCleanupEligible $cleanupSample)) 'Incomplete Runner trace allowed cleanup'
                $cleanupSample.runner_trace=[pscustomobject]@{source='RUNNER';status='OBSERVED';lifecycle='TERMINAL_OBSERVED';observed_child_contexts=2}
                $cleanupSample.native_trace=[pscustomobject]@{lifecycle='NOT_AVAILABLE'}
                Assert (-not (Test-CmFixtureCleanupEligible $cleanupSample)) 'Incomplete Goalkeeper trace allowed cleanup'
            }
        Check 'unknown-event-is-not-zero-dispatch' {
            $events.Add(@{type='item.completed';item=@{type='unknown_tool';id='unknown'}});$r=Read-Trace
            Assert ($r.status -ceq 'NOT_AVAILABLE' -and $r.observed_child_contexts -ceq 'NOT_AVAILABLE' -and $r.lifecycle -ceq 'NOT_AVAILABLE') 'Unknown transport became zero dispatch';$events.RemoveAt($events.Count-1)
        }
        Check 'error-events-remain-visible-without-raw-text-or-zero-dispatch' {
            Reset-Trace
            $events.Add(@{type='error';error=@{message='synthetic sensitive text'}})
            $events.Add(@{type='item.started';item=@{type='error';id='FAKE-ERROR'}})
            $events.Add(@{type='item.completed';item=@{type='error';id='FAKE-ERROR';message='synthetic sensitive text'}})
            $r=Read-Trace
            Assert ($r.status -ceq 'ERRORS_OBSERVED' -and $r.error_event_count -eq 2 -and $r.lifecycle -ceq 'TERMINAL_OBSERVED' -and $r.observed_child_contexts -ceq 'NOT_AVAILABLE' -and -not $r.no_dispatch_readonly) 'Error events were lost or misreported as no dispatch'
            Assert (($r|ConvertTo-Json -Compress) -notmatch 'synthetic sensitive text') 'Raw error text escaped the event parser'
        }
        Check 'open-tool-is-not-zero-dispatch' {
            Reset-Trace
            $events.Add(@{type='item.started';item=@{type='command_execution';id='open'}});$r=Read-Trace
            Assert ($r.lifecycle -ceq 'NOT_AVAILABLE' -and $r.status -ceq 'NOT_AVAILABLE') 'Incomplete tool lifecycle accepted';$events.RemoveAt($events.Count-1)
        }
        Check 'blocked-text-does-not-bypass-writes' {
            Write-PfcUtf8NoBom (Join-Path $fixture.path 'src/task.ps1') 'function Get-Target { 1 }'
            $changed=Join-Path $owned 'changed';New-Item -ItemType Directory $changed|Out-Null;$ref=Save-CmFixtureEvidence $fixture $changed
            $sample.model_status='BLOCKED';Assert (-not (Test-CmSafeIdentityStop $manifest $sample $ref $changed)) 'BLOCKED text bypassed changed fixture'
        }
        Check 'early-stop-limited-to-cm05' {$manifest.scenario_id='CM-01';Assert (-not (Test-CmSafeIdentityStop $manifest $sample $reference $owned)) 'Other scenarios bypassed required handoff';$manifest.scenario_id='CM-05'}
    } finally {Remove-CmFixture $fixture.path}
    return $results.ToArray()
}

function Invoke-CmEvidenceFixTests {
    param([string]$RepositoryRoot)
    $results=New-Object 'System.Collections.Generic.List[object]'
    function Check([string]$Id,[scriptblock]$Body) {
        try {& $Body;$results.Add((New-PfcResult -ScenarioId ('CM-fix.'+$Id) -Status PASS -Message verified))}
        catch {$results.Add((New-PfcResult -ScenarioId ('CM-fix.'+$Id) -Status FAIL -Message $_.Exception.Message))}
    }
    function Assert($Value,[string]$Message){if(-not $Value){throw $Message}}
    $manifest=Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $RepositoryRoot 'evals/scenarios/continuous-mode-model/CM-01-crud-wave/scenario.json')|ConvertFrom-Json
    $output=Join-Path $RepositoryRoot ('.pfc-eval-results/FAKE-EVIDENCE-FIX-'+[guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $output|Out-Null
    foreach($failure in @('rev-parse','status','log','diff','invalid-sha','empty-graph','invalid-graph','missing-parent')) {
        Check ('git-failure.'+$failure) {
            $fixture=New-CmFixture $manifest
            $gitExecutable=@(Get-Command git -CommandType Application)[0].Source
            function git {
                $global:LASTEXITCODE=0
                if($args -contains $failure){$global:LASTEXITCODE=17;return}
                if($failure -eq 'invalid-sha' -and $args -contains 'rev-parse'){return 'invalid-sha'}
                if($args -contains 'log') {
                    if($failure -eq 'empty-graph'){return}
                    if($failure -eq 'invalid-graph'){return 'invalid graph'}
                    if($failure -eq 'missing-parent'){return ($fixture.base_sha+' '+('a'*40))}
                }
                & $gitExecutable @args
                $global:LASTEXITCODE=$LASTEXITCODE
            }
            try {
                $caught=$false;$reference=$null;$failureMessage=''
                try {$reference=Save-CmFixtureEvidence $fixture $output}catch{$caught=$true;$failureMessage=$_.Exception.Message}
                Assert ($caught -and -not $reference -and $failureMessage -match '^CM evidence') ('Invalid Git evidence was not explicitly rejected: '+$failureMessage)
                Assert (Test-Path -LiteralPath (Join-Path $fixture.path 'src/task.ps1')) 'Failed capture deleted its only source'
                Assert (-not (Test-Path -LiteralPath (Join-Path $output ($fixture.context_id+'/fixture-evidence.json')))) 'Invalid capture published a complete evidence manifest'
            } finally {Remove-Item Function:\git;Remove-CmFixture $fixture.path}
        }
    }
    Check 'ignored-file-bytes-and-hash-survive-cleanup' {
        $fixture=New-CmFixture $manifest
        try {
            New-Item -ItemType Directory -Path (Join-Path $fixture.path '.git/info') -Force|Out-Null
            [IO.File]::AppendAllText((Join-Path $fixture.path '.git/info/exclude'),"`n/ignored.bin`n",[Text.Encoding]::UTF8)
            $bytes=[byte[]](0..255);[IO.File]::WriteAllBytes((Join-Path $fixture.path 'ignored.bin'),$bytes)
            $expected=Get-CmHash -Path (Join-Path $fixture.path 'ignored.bin')
            $reference=Save-CmFixtureEvidence $fixture $output
            Remove-CmFixture $fixture.path
            $saved=Join-Path $output ($fixture.context_id+'/files/ignored.bin')
            Assert (Test-Path -LiteralPath $saved) 'Ignored artifact bytes were omitted before cleanup'
            Assert ((Get-CmHash -Path $saved) -ceq $expected -and [Convert]::ToBase64String([IO.File]::ReadAllBytes($saved)) -ceq [Convert]::ToBase64String($bytes)) 'Ignored bytes changed during preservation'
            $record=Get-Content -Raw -LiteralPath (Join-Path $output $reference.relative_path)|ConvertFrom-Json
            Assert (@($record.files|Where-Object {$_.path -eq 'ignored.bin' -and $_.sha256 -ceq $expected -and $_.bytes -eq 256}).Count -eq 1) 'Ignored artifact hash/size not recorded'
            Assert (-not (Test-Path -LiteralPath (Join-Path $output ($fixture.context_id+'/files/.git')))) 'Git internals were copied'
        } finally {if(Test-Path -LiteralPath $fixture.path){Remove-CmFixture $fixture.path}}
    }
    foreach($waveId in @('CM-01','CM-02')) {
    Check ('two-milestone-worktree-evidence-survives-cleanup.'+$waveId) {
        $entry=@((Get-CmFrozenControl $RepositoryRoot).scenarios|Where-Object scenario_id -ceq $waveId)[0]
        $waveManifest=Get-Content -Raw -LiteralPath (Join-Path $RepositoryRoot $entry.manifest_path)|ConvertFrom-Json
        $fixture=New-CmFixture $waveManifest
        try {
            $worktreeParent=Join-Path $fixture.path '.pfc-worktrees';New-Item -ItemType Directory -Path $worktreeParent|Out-Null
            $m1=Join-Path $worktreeParent 'm1';$m2=Join-Path $worktreeParent 'm2'
            & git -C $fixture.path worktree add --quiet -b codex/pfc/FAKE/M1 $m1 $fixture.base_sha
            Assert ($LASTEXITCODE -eq 0) 'M1 fixture worktree unavailable'
            $source="function Add-Task(`$Tasks,[string]`$Id) { if(@(`$Tasks|Where-Object {`$_.id -eq `$Id}).Count){throw 'duplicate'};@(`$Tasks)+@(@{id=`$Id;status='open'}) }`nfunction Set-TaskStatus(`$Tasks,[string]`$Id,[string]`$Status) { throw 'M2 pending' }`n"
            if($waveId -ceq 'CM-02'){$source='function Render-Board($Tasks,[string]$Status="") { $rows=@($Tasks); $body=@(foreach($row in $rows){"<tr><td>"+[Security.SecurityElement]::Escape($row.id)+"</td><td>"+$row.status+"</td></tr>"}) -join ""; ''<table aria-label="Tasks"><thead><tr><th>ID</th><th>Status</th></tr></thead><tbody>''+$body+''</tbody></table>'' }'}
            Write-PfcUtf8NoBom (Join-Path $m1 'src/task.ps1') $source
            & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $m1 'tests/accept.ps1') -Milestone M1 > (Join-Path $output 'FAKE-M1-validation.txt')
            Assert ($LASTEXITCODE -eq 0) 'M1 focused validation cannot reach independent candidate'
            & git -C $m1 add -- src/task.ps1
            & git -C $m1 -c user.name=CMFixture -c user.email=fixture@example.invalid commit --quiet -m 'FAKE M1 candidate'
            Assert ($LASTEXITCODE -eq 0) 'M1 fixture Candidate missing'
            $first=[string](& git -C $m1 rev-parse HEAD)
            # This fixture models the already independently reviewed checkpoint.
            # It is never supplied to a real model or reported as formal acceptance.
            & git -C $fixture.path worktree add --quiet -b codex/pfc/FAKE/M2 $m2 $first
            Assert ($LASTEXITCODE -eq 0) 'M2 fixture does not inherit M1 Candidate'
            $source=$source.Replace("throw 'M2 pending'","foreach(`$row in `$Tasks){if(`$row.id -eq `$Id){@{id=`$row.id;status=`$Status}}else{`$row}}")
            if($waveId -ceq 'CM-02'){$source=$source.Replace('$rows=@($Tasks);','$rows=@($Tasks);if($Status){$rows=@($rows|Where-Object {$_.status -ceq $Status})};')}
            Write-PfcUtf8NoBom (Join-Path $m2 'src/task.ps1') $source
            & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $m2 'tests/accept.ps1') > (Join-Path $output 'FAKE-M2-validation.txt')
            Assert ($LASTEXITCODE -eq 0) 'M2 and full Wave validation unreachable'
            & git -C $m2 add -- src/task.ps1
            & git -C $m2 -c user.name=CMFixture -c user.email=fixture@example.invalid commit --quiet -m 'FAKE M2 candidate'
            Assert ($LASTEXITCODE -eq 0) 'M2 fixture Candidate missing'
            $second=[string](& git -C $m2 rev-parse HEAD);$sourceHash=Get-CmHash -Path (Join-Path $m2 'src/task.ps1')
            $reference=Save-CmFixtureEvidence $fixture $output
            Remove-CmFixture $fixture.path
            $record=Get-Content -Raw -LiteralPath (Join-Path $output $reference.relative_path)|ConvertFrom-Json
            Assert ($record.worktrees.Count -eq 3 -and @($record.worktrees|Where-Object head_sha -ceq $first).Count -eq 1 -and @($record.worktrees|Where-Object head_sha -ceq $second).Count -eq 1) 'Linked Candidate identities lost'
            $m2TaskFile=@($record.files|Where-Object {$_.path -ceq '.pfc-worktrees/m2/src/task.ps1'})
            Assert ($m2TaskFile.Count -eq 1) 'M2 business result missing from evidence manifest'
            $savedM2Task=Join-Path $output ($fixture.context_id+'/'+$m2TaskFile[0].stored_path)
            Assert ((Test-Path -LiteralPath $savedM2Task -PathType Leaf) -and (Get-CmHash -Path $savedM2Task) -ceq $sourceHash) 'Only business result erased with fixture'
            foreach($w in $record.worktrees){Assert (Test-Path -LiteralPath (Join-Path $output ($fixture.context_id+'/'+$w.diff))) 'Linked Candidate diff omitted'}
        } finally {if(Test-Path -LiteralPath $fixture.path){Remove-CmFixture $fixture.path}}
    }
    }
    Check 'quoted-and-unquoted-synthetic-credentials-redacted' {
        foreach($text in @('{"api_key":"SYNTHETIC_ONLY_12345","password":"SYNTHETIC ONLY WITH SPACES"}',"'token' = 'SYNTHETIC ONLY SINGLE QUOTES'",'secret="SYNTHETIC ONLY CONFIG"','api-key=SYNTHETIC_ONLY_PLAIN','{"secret":"SYNTHETIC \" ONLY ESCAPED"}')) {
            $normalized=Convert-CmEvidenceText $text
            Assert ($normalized -notmatch 'SYNTHETIC|ONLY|SPACES|QUOTES|CONFIG|PLAIN|ESCAPED' -and $normalized -match '<REDACTED_SECRET>') 'Synthetic quoted credential survived normalized evidence'
        }
        Assert ((Convert-CmEvidenceText 'ordinary verification detail') -ceq 'ordinary verification detail') 'Non-secret evidence was discarded'
    }
    Check 'runner-owned-role-lifecycle-source-and-handoff' {
        $eventRoot=Join-Path ([IO.Path]::GetTempPath()) ('pfc-runner-event-test-'+[guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $eventRoot -Force|Out-Null
        try {
            $eventPath=Join-Path $eventRoot 'runner-events.jsonl';$sha='a'*40
            $records=@(
                @{schema_version=1;source='runner';event_type='child_started';role='project_flight_builder';dispatch_id='D-B1';context_id='CTX-B1';goalkeeper_session_id='ROOT-1';recorded_at_utc='2026-09-27T10:00:00.0000000Z';model='gpt-5.6-terra';reasoning_effort='medium';sandbox='workspace-write';test_only=$true},
                @{schema_version=1;source='runner';event_type='child_completed';role='project_flight_builder';dispatch_id='D-B1';context_id='CTX-B1';goalkeeper_session_id='ROOT-1';recorded_at_utc='2026-09-27T10:01:00.0000000Z';model='gpt-5.6-terra';reasoning_effort='medium';sandbox='workspace-write';exit_code=0;candidate_sha=$sha;test_only=$true},
                @{schema_version=1;source='runner';event_type='child_started';role='project_flight_verifier';dispatch_id='D-V1';context_id='CTX-V1';goalkeeper_session_id='ROOT-1';recorded_at_utc='2026-09-27T10:02:00.0000000Z';model='gpt-5.6-terra';reasoning_effort='medium';sandbox='workspace-write';candidate_sha=$sha;test_only=$true},
                @{schema_version=1;source='runner';event_type='child_completed';role='project_flight_verifier';dispatch_id='D-V1';context_id='CTX-V1';goalkeeper_session_id='ROOT-1';recorded_at_utc='2026-09-27T10:03:00.0000000Z';model='gpt-5.6-terra';reasoning_effort='medium';sandbox='workspace-write';exit_code=0;candidate_sha=$sha;test_only=$true}
            )
            Write-PfcUtf8NoBom -Path $eventPath -Content (($records|ForEach-Object {$_|ConvertTo-Json -Compress}) -join "`n")
            $trace=Read-CmRunnerTrace -Path $eventPath -FakeTransport
            Assert ($trace.status -ceq 'OBSERVED' -and $trace.source -ceq 'RUNNER' -and $trace.observed_child_contexts -eq 2 -and $trace.independent_handoffs.Count -eq 1) 'Runner-owned pair or Candidate handoff was not recognized'
            $builderOnlyStart = @{} + $records[0]
            $builderOnlyCompletion = @{} + $records[1]
            $null = $builderOnlyCompletion.Remove('candidate_sha')
            $builderOnly = @($builderOnlyStart, $builderOnlyCompletion)
            Write-PfcUtf8NoBom -Path $eventPath -Content (($builderOnly|ForEach-Object {$_|ConvertTo-Json -Compress}) -join [Environment]::NewLine)
            $builderTrace = Read-CmRunnerTrace -Path $eventPath -FakeTransport
            Assert ($builderTrace.status -ceq 'NO_COMPLETE_HANDOFF' -and $builderTrace.lifecycle -ceq 'TERMINAL_OBSERVED' -and $builderTrace.observed_child_contexts -eq 1) 'Optional Builder Candidate SHA was not handled without a handoff'
            $wrongCandidate = @()
            foreach($record in $records){$wrongCandidate += ,(@{} + $record)}
            $wrongCandidate[2].candidate_sha = 'b'*40
            $wrongCandidate[3].candidate_sha = 'b'*40
            Write-PfcUtf8NoBom -Path $eventPath -Content (($wrongCandidate|ForEach-Object {$_|ConvertTo-Json -Compress}) -join [Environment]::NewLine)
            Assert ((Read-CmRunnerTrace -Path $eventPath -FakeTransport).status -ceq 'NOT_AVAILABLE') 'Verifier Candidate SHA mismatch was accepted'
            $unsafeRawPath = @()
            foreach($record in $records){$unsafeRawPath += ,(@{} + $record)}
            $unsafeRawPath[3].raw_jsonl_path = '../outside.jsonl'
            Write-PfcUtf8NoBom -Path $eventPath -Content (($unsafeRawPath|ForEach-Object {$_|ConvertTo-Json -Compress}) -join [Environment]::NewLine)
            Assert ((Read-CmRunnerTrace -Path $eventPath -FakeTransport).status -ceq 'NOT_AVAILABLE') 'Uncontained Runner raw result path was accepted'
            $records[0].source='codex'
            Write-PfcUtf8NoBom -Path $eventPath -Content (($records|ForEach-Object {$_|ConvertTo-Json -Compress}) -join "`n")
            Assert ((Read-CmRunnerTrace -Path $eventPath -FakeTransport).status -ceq 'NOT_AVAILABLE') 'Non-Runner event source was accepted'
            $records=@($records|Select-Object -First 1)
            $records[0].source='runner'
            Write-PfcUtf8NoBom -Path $eventPath -Content ($records[0]|ConvertTo-Json -Compress)
            Assert ((Read-CmRunnerTrace -Path $eventPath -FakeTransport).lifecycle -ceq 'NOT_AVAILABLE') 'Unpaired child start was accepted as complete'
        } finally { if(Test-Path -LiteralPath $eventRoot){Remove-Item -LiteralPath $eventRoot -Force -Recurse} }
    }
    return $results.ToArray()
}
