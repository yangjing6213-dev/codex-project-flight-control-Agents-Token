param([ValidateSet('RED','GREEN')][string]$Phase='GREEN',[string]$RepositoryRoot)
Import-Module (Join-Path (Split-Path -Parent $PSScriptRoot) 'ScenarioSupport.psm1') -Force
Invoke-PfcSpecialistScenario -ScenarioId 'SC-25-stale-evidence' -RepositoryRoot $RepositoryRoot -Invariant 'stale or unverified evidence cannot establish capability'
