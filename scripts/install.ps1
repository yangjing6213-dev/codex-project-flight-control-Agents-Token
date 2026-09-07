[CmdletBinding()]
param([string]$SourceRoot,[string]$UserHome,[string]$StateRoot,[switch]$Json)
$ErrorActionPreference='Stop'; $repo=Split-Path -Parent $PSScriptRoot
if (-not $SourceRoot) {$SourceRoot=$repo}; if (-not $UserHome) {$UserHome=$HOME}; if (-not $StateRoot) {$StateRoot=Join-Path $env:LOCALAPPDATA 'ProjectFlightControl'}
Import-Module (Join-Path $PSScriptRoot 'lib\ProjectFlightControl.Install.psm1') -Force
try {$plan=Get-PfcInstallPlan -SourceRoot $SourceRoot -UserHome $UserHome -StateRoot $StateRoot; $result=Invoke-PfcInstallPlan -Plan $plan } catch {$msg=$_.Exception.Message; if($msg -notmatch 'operation=[^;]+; path=[^;]+; recovery='){ $msg="operation=install; path=$StateRoot; recovery=inspect the structured failure and retry" }; $result=[pscustomobject]@{status='FAIL';error=$msg}}
if ($Json) {$result|ConvertTo-Json -Depth 20 -Compress} else {$result|Format-List|Out-String|Write-Host}; if ($result.status -ne 'PASS'){exit 1}
