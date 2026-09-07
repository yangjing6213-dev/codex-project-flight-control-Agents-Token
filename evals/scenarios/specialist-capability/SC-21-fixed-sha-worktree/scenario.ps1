param([ValidateSet('RED','GREEN')][string]$Phase='GREEN',[string]$RepositoryRoot)
Import-Module (Join-Path (Split-Path -Parent $PSScriptRoot) 'ScenarioSupport.psm1') -Force
Invoke-PfcSpecialistScenario -ScenarioId 'SC-21-fixed-sha-worktree' -RepositoryRoot $RepositoryRoot -Invariant 'fixed SHA and detached worktree require observable Specialist Smoke adapters'
