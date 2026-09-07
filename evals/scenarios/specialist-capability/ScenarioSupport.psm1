Set-StrictMode -Version 2.0
Import-Module (Join-Path (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))) 'scripts\lib\ProjectFlightControl.Doctor.psm1') -Force

function Invoke-PfcSpecialistScenario {
    param([Parameter(Mandatory=$true)][string]$ScenarioId,[Parameter(Mandatory=$true)][string]$RepositoryRoot,[Parameter(Mandatory=$true)][string]$Invariant)
    $root = Join-Path ([IO.Path]::GetTempPath()) ('pfc-scenario-' + [guid]::NewGuid().ToString('N'))
    try {
        New-Item -ItemType Directory -Path $root -Force | Out-Null
        $record = Invoke-PfcSpecialistSmoke -SpecialistSmoke -RepositoryRoot $RepositoryRoot -UserHome $root -StateRoot $root
        $observed = ([string]$record.status -in @('UNKNOWN','UNAVAILABLE')) -and -not [string]::IsNullOrWhiteSpace([string]$record.invalidation_reason)
        $message = if ($observed) { $Invariant + '; observed=' + $record.status + '; reason=' + $record.invalidation_reason } else { $Invariant + '; untruthful capability result' }
        [pscustomobject]@{ScenarioId=$ScenarioId;Status=$(if($observed){'PASS'}else{'FAIL'});Message=$message}
    } catch { [pscustomobject]@{ScenarioId=$ScenarioId;Status='FAIL';Message=($Invariant + '; exception=' + $_.Exception.Message)} }
    finally { if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue } }
}
Export-ModuleMember -Function Invoke-PfcSpecialistScenario
