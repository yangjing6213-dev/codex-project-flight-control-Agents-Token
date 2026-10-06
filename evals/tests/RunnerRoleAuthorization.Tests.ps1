$ErrorActionPreference = 'Stop'
$repositoryRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$controlPath = Join-Path $repositoryRoot 'evals/expected/continuous-mode-model/frozen-control.json'
$runnerPath = Join-Path $repositoryRoot 'evals/run-evals.ps1'
$control = Get-Content -Raw -Encoding UTF8 -LiteralPath $controlPath | ConvertFrom-Json
if ($control.PSObject.Properties['runner_managed_roles'] -eq $null) { throw 'Frozen control does not identify Runner-managed roles.' }
if ($control.PSObject.Properties['native_agents']) { throw 'Frozen control still describes Builder and Verifier as native agents.' }

$tokens = $null
$parseErrors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile($runnerPath, [ref]$tokens, [ref]$parseErrors)
if ($parseErrors.Count -gt 0) { throw 'Runner authorization script does not parse.' }
function Get-FunctionDefinitionText([string]$Name) {
    $definition = $ast.Find({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -ceq $Name }, $true)
    if ($null -eq $definition) { throw ('Missing authorization helper: ' + $Name) }
    return $definition.Extent.Text
}
Import-Module (Join-Path $repositoryRoot 'evals/lib/CodexRunner.psm1') -Force
foreach ($name in @('Get-CmHash','Assert-CmProperties','Assert-CmPath','Get-CmPrompt','Assert-CmRunnerManagedRoleControl','Assert-CmRunnerRoleAuthorization','Get-CmFrozenControl')) {
    Invoke-Expression (Get-FunctionDefinitionText $name)
}

$validatedControl = Get-CmFrozenControl -RepositoryRoot $repositoryRoot
if ($validatedControl.runner_managed_roles.launch_source -cne 'runner') { throw 'Frozen controls did not validate Runner as the role launch source.' }
Assert-CmRunnerManagedRoleControl -RoleControl $control.runner_managed_roles
Assert-CmRunnerRoleAuthorization -Expected $control.runner_managed_roles -Authorized $control.runner_managed_roles

$mismatch = $control.runner_managed_roles | ConvertTo-Json -Depth 30 | ConvertFrom-Json
$mismatch.launch_source = 'codex_native'
$rejected = $false
try { Assert-CmRunnerRoleAuthorization -Expected $control.runner_managed_roles -Authorized $mismatch }
catch { $rejected = $true }
if (-not $rejected) { throw 'Authorization with a different role source was accepted.' }

$nativeRoot = Join-Path ([IO.Path]::GetTempPath()) ('pfc-native-role-source-test-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $nativeRoot -Force | Out-Null
try {
    $nativePath = Join-Path $nativeRoot 'native-events.jsonl'
    $nativeEvents = @(
        @{type='thread.started';thread_id='NATIVE-ROOT'},
        @{type='turn.started'},
        @{type='item.started';item=@{type='collabAgentToolCall';id='NATIVE-B'}},
        @{type='item.completed';item=@{type='collabAgentToolCall';id='NATIVE-B';tool='spawnAgent';senderThreadId='NATIVE-ROOT';receiverThreadIds=@('NATIVE-B');prompt='ROLE=project_flight_builder';status='completed';agentsStates=@{}}},
        @{type='turn.completed'}
    )
    [IO.File]::WriteAllText($nativePath,(($nativeEvents | ForEach-Object { $_ | ConvertTo-Json -Depth 20 -Compress }) -join "`n"),[Text.UTF8Encoding]::new($false))
    if ((Read-PfcRunnerLifecycle -Path $nativePath -FakeTransport).status -cne 'NOT_AVAILABLE') { throw 'Codex-native child events were accepted as Runner-managed role evidence.' }
} finally { Remove-Item -LiteralPath $nativeRoot -Force -Recurse }

$dispatch = $ast.Find({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -ceq 'Invoke-CmModelDispatch' }, $true)
if ($null -eq $dispatch -or $dispatch.Extent.Text -notmatch 'Assert-CmRunnerRoleAuthorization' -or $dispatch.Extent.Text -notmatch 'runner_managed_roles') {
    throw 'Formal authorization guard does not bind Runner-managed role control.'
}
Write-Output 'PASS: Runner role authorization control and mismatch rejection verified; no Codex/model process started.'
