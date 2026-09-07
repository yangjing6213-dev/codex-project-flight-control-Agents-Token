[CmdletBinding()]
param([string]$UserHome,[string]$StateRoot,[switch]$Json)
$ErrorActionPreference='Stop'; if (-not $UserHome) {$UserHome=$HOME}; if (-not $StateRoot) {$StateRoot=Join-Path $env:LOCALAPPDATA 'ProjectFlightControl'}
Import-Module (Join-Path $PSScriptRoot 'lib\ProjectFlightControl.Install.psm1') -Force
try {$result=Invoke-PfcUninstall -UserHome $UserHome -StateRoot $StateRoot} catch {$msg=$_.Exception.Message; if($msg -notmatch 'operation=[^;]+; path=[^;]+; recovery='){ $msg="operation=uninstall; path=$StateRoot; recovery=inspect the structured failure and retry" }; $result=[pscustomobject]@{status='FAIL';error=$msg}}
if ($Json) {$result|ConvertTo-Json -Depth 20 -Compress} else {$result|Format-List|Out-String|Write-Host}; if ($result.status -ne 'PASS'){exit 1}
