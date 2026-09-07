param([ValidateSet('RED','GREEN')][string]$Phase='GREEN',[string]$RepositoryRoot)
Import-Module (Join-Path (Split-Path -Parent $PSScriptRoot) 'ScenarioSupport.psm1') -Force
Invoke-PfcSpecialistScenario -ScenarioId 'SC-29-explicit-smoke' -RepositoryRoot $RepositoryRoot -Invariant 'Specialist Smoke remains explicit-only and is not inferred from ordinary execution'
