param([ValidateSet('RED','GREEN')][string]$Phase='GREEN',[string]$RepositoryRoot)
Import-Module (Join-Path (Split-Path -Parent $PSScriptRoot) 'ScenarioSupport.psm1') -Force
Invoke-PfcSpecialistScenario -ScenarioId 'SC-22-no-formal-verdict' -RepositoryRoot $RepositoryRoot -Invariant 'formal verdict authority is unavailable without an explicit Specialist adapter'
