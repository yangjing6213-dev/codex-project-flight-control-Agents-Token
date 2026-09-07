param([ValidateSet('RED','GREEN')][string]$Phase='GREEN',[string]$RepositoryRoot)
Import-Module (Join-Path (Split-Path -Parent $PSScriptRoot) 'ScenarioSupport.psm1') -Force
Invoke-PfcSpecialistScenario -ScenarioId 'SC-30-capability-invalidation' -RepositoryRoot $RepositoryRoot -Invariant 'failed smoke invariants produce UNKNOWN with an invalidation reason'
