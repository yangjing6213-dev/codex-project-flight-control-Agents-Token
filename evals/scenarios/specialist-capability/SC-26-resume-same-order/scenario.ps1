param([ValidateSet('RED','GREEN')][string]$Phase='GREEN',[string]$RepositoryRoot)
Import-Module (Join-Path (Split-Path -Parent $PSScriptRoot) 'ScenarioSupport.psm1') -Force
Invoke-PfcSpecialistScenario -ScenarioId 'SC-26-resume-same-order' -RepositoryRoot $RepositoryRoot -Invariant 'resume order requires a disposable, observable smoke context'
