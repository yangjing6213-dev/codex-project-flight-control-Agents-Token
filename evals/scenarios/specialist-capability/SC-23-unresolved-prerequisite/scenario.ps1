param([ValidateSet('RED','GREEN')][string]$Phase='GREEN',[string]$RepositoryRoot)
Import-Module (Join-Path (Split-Path -Parent $PSScriptRoot) 'ScenarioSupport.psm1') -Force
Invoke-PfcSpecialistScenario -ScenarioId 'SC-23-unresolved-prerequisite' -RepositoryRoot $RepositoryRoot -Invariant 'unresolved runtime prerequisites remain UNKNOWN/UNAVAILABLE'
