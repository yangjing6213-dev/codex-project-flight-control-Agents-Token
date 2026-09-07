param([ValidateSet('RED','GREEN')][string]$Phase='GREEN',[string]$RepositoryRoot=(Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))))
$ErrorActionPreference='Stop'; Import-Module (Join-Path $RepositoryRoot 'evals\lib\TestHarness.psm1') -Force
function Invoke-Sc28 {
    Import-Module (Join-Path $RepositoryRoot 'scripts\lib\ProjectFlightControl.Doctor.psm1') -Force
    $root=Join-Path ([IO.Path]::GetTempPath()) ('pfc-sc28-'+[guid]::NewGuid().ToString('N'));$fixtureHome=Join-Path $root 'home';$state=Join-Path $root 'state';New-Item -ItemType Directory -Path $fixtureHome,$state,(Join-Path $fixtureHome '.codex')|Out-Null;$results=New-Object System.Collections.Generic.List[object]
    function Check([string]$id,[bool]$ok,[string]$message){$results.Add((New-PfcResult $id $(if($ok){'PASS'}else{'FAIL'}) $message))}
    try {
        $spy=Join-Path $root 'spy.log';Set-Content $spy ''
        $genericInvoker={param($a);Add-Content -LiteralPath $spy -Value ($a -join ' ');$j=$a -join ' ';if($j -match '(?i)exec|app-server|spawn_agent|responses|chat/completions'){throw 'forbidden process invocation'};if($j -match '--version'){return [pscustomobject]@{ExitCode=0;StdOut='codex 0.1';StdErr=''}};if($j -match '--help'){return [pscustomobject]@{ExitCode=0;StdOut='generic help';StdErr=''}};return [pscustomobject]@{ExitCode=0;StdOut='';StdErr=''}}
        $fp=Get-PfcDoctorFingerprint -RepositoryRoot $RepositoryRoot -UserHome $fixtureHome -ProcessInvoker $genericInvoker
        Check 'sc28.generic-help-unknown' ($fp.components.codex_help -eq 'UNKNOWN') ('codex_help='+$fp.components.codex_help)
        Check 'sc28.worktree-unknown-when-unobservable' ($fp.components.git_worktree_probe -eq 'UNKNOWN') ('worktree_probe='+$fp.components.git_worktree_probe)
        Set-Content -LiteralPath (Join-Path $fixtureHome '.codex\config.toml') -Value 'sandbox_mode = "read-only"'
        $explicitInvoker={param($a);$j=$a -join ' ';if($j -match '--version'){return [pscustomobject]@{ExitCode=0;StdOut='codex 0.1';StdErr=''}};if($j -match '--help'){return [pscustomobject]@{ExitCode=0;StdOut='Subagent capability: available';StdErr=''}};return [pscustomobject]@{ExitCode=0;StdOut='';StdErr=''}}
        $explicit=Get-PfcDoctorFingerprint -RepositoryRoot $RepositoryRoot -UserHome $fixtureHome -ProcessInvoker $explicitInvoker
        Check 'sc28.explicit-capability-pass' ($explicit.components.codex_help -eq 'PASS') ('codex_help='+$explicit.components.codex_help)
        Check 'sc28.explicit-read-only-pass' ($explicit.components.sandbox_permission -eq 'PASS' -and $explicit.components.sandbox_permission_mode -eq 'read-only') ('permission='+$explicit.components.sandbox_permission)
        Check 'sc28.read-only-worktree-unobservable' ($explicit.components.git_worktree_probe -eq 'UNKNOWN') ('worktree_probe='+$explicit.components.git_worktree_probe)
        Set-Content -LiteralPath (Join-Path $fixtureHome '.codex\config.toml') -Value 'sandbox_mode = "workspace-write"'
        $writable=Get-PfcDoctorFingerprint -RepositoryRoot $RepositoryRoot -UserHome $fixtureHome -ProcessInvoker $explicitInvoker
        Check 'sc28.writable-permission-unknown' ($writable.components.sandbox_permission -eq 'UNKNOWN' -and $writable.components.sandbox_permission_mode -eq 'workspace-write') ('permission='+$writable.components.sandbox_permission)
        Check 'sc28.writable-worktree-unknown' ($writable.components.git_worktree_probe -eq 'UNKNOWN') ('worktree_probe='+$writable.components.git_worktree_probe)
        Set-Content -LiteralPath (Join-Path $fixtureHome '.codex\config.toml') -Value 'sandbox_mode = ['
        $malformed=Get-PfcDoctorFingerprint -RepositoryRoot $RepositoryRoot -UserHome $fixtureHome -ProcessInvoker $explicitInvoker
        Check 'sc28.malformed-permission-unknown' ($malformed.components.sandbox_permission -eq 'UNKNOWN') ('permission='+$malformed.components.sandbox_permission)
        Remove-Item -LiteralPath (Join-Path $fixtureHome '.codex\config.toml')
        $missing=Get-PfcDoctorFingerprint -RepositoryRoot $RepositoryRoot -UserHome $fixtureHome -ProcessInvoker $explicitInvoker
        Check 'sc28.missing-permission-unknown' ($missing.components.sandbox_permission -eq 'UNKNOWN') ('permission='+$missing.components.sandbox_permission)
        $d=Invoke-PfcPassiveDoctor -UserHome $fixtureHome -StateRoot $state -RepositoryRoot $RepositoryRoot -ProcessInvoker $genericInvoker
        Check 'sc28.core-blocked' ($d.core_status -eq 'BLOCKED') ('core_status='+$d.core_status)
        $calls=@(Get-Content -LiteralPath $spy|Where-Object{$_.Trim()});Check 'sc28.process-adapter-used' ($calls.Count -gt 0) ('calls='+$calls.Count)
        Check 'sc28.forbidden-families-absent' (-not ((Get-Content -Raw -LiteralPath $spy)-match '(?i)exec|app-server|spawn_agent|responses|chat/completions')) 'forbidden process families absent'
    } catch { $results.Add((New-PfcResult 'sc28.failure' 'FAIL' $_.Exception.Message)) } finally { if(Test-Path $root){Remove-Item -LiteralPath $root -Recurse -Force} }
    return $results.ToArray()
}
Invoke-Sc28
