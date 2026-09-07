[CmdletBinding()]
param([string]$UserHome,[string]$StateRoot,[switch]$SpecialistSmoke,[switch]$Json)
$ErrorActionPreference='Stop'; $repo=Split-Path -Parent $PSScriptRoot
if (-not $UserHome) {$UserHome=$HOME}; if (-not $StateRoot) {$StateRoot=Join-Path $env:LOCALAPPDATA 'ProjectFlightControl'}
Import-Module (Join-Path $PSScriptRoot 'lib\ProjectFlightControl.Doctor.psm1') -Force
$result=Invoke-PfcPassiveDoctor -UserHome $UserHome -StateRoot $StateRoot -RepositoryRoot $repo
if ($SpecialistSmoke) {
    $smoke=Invoke-PfcSpecialistSmoke -SpecialistSmoke -UserHome $UserHome -StateRoot $StateRoot -RepositoryRoot $repo
    $result | Add-Member -NotePropertyName specialist_smoke -NotePropertyValue $smoke -Force
    if ($smoke.status -eq 'AVAILABLE') { $result.specialist_capability='AVAILABLE'; $result.capability_fingerprint=$smoke.report_sha256 }
}
if ($Json) {$result|ConvertTo-Json -Depth 20 -Compress} else {$result|Format-List|Out-String|Write-Host}
if ($result.status -notin @('PASS','OK')) { exit 1 }
