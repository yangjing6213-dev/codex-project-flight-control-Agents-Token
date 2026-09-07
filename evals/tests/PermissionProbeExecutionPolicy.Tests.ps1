[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
Import-Module (Join-Path $PSScriptRoot '..\lib\TestHarness.psm1') -Force
Import-Module (Join-Path $PSScriptRoot '..\lib\PermissionProbeHandshake.psm1') -Force
function Check([bool]$Condition,[string]$Id,[string]$Expected = 'PASS') { Assert-PfcTrue -Actual $Condition -ScenarioId $Id -Expected $Expected }
$launcherPath = Join-Path $PSScriptRoot '..\scenarios\permission-probe\launch-probe.ps1'
$probePath = Join-Path $PSScriptRoot '..\scenarios\permission-probe\probe\permission-probe.ps1'
$launcherSource = Get-Content -Raw -LiteralPath $launcherPath
$probeSource = Get-Content -Raw -LiteralPath $probePath
$argv = @('C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe','-NoLogo','-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-OutputFormat','Text','-File','fixture-root\probe\permission-probe.ps1','-RequestPath','fixture-root\probe\probe-request.json')
$validation = Test-PfcPermissionProbeLauncherArguments -Arguments $argv
Check ($validation.status -ceq 'PASS' -and $validation.execution_policy_scope -ceq 'PROBE_PROCESS') 'EP-01.process-scoped-bypass'
$epIndex = [Array]::IndexOf($argv,'-ExecutionPolicy'); $fileIndex = [Array]::IndexOf($argv,'-File')
Check ($epIndex -ge 0 -and $argv[$epIndex + 1] -ceq 'Bypass' -and $fileIndex -gt ($epIndex + 1)) 'EP-02.file-after-policy'
Check ($launcherSource -match '(?m)-ExecutionPolicy' -and $launcherSource -match '(?m)Bypass' -and $launcherSource -match '(?m)-File') 'EP-03.launcher-declares-bypass'
Check ($launcherSource -match 'SystemRoot' -and $launcherSource -match 'WindowsPowerShell\\v1\.0\\powershell\.exe' -and $launcherSource -match 'WINDOWS_POWERSHELL_PATH_MISMATCH') 'EP-03b.fixed-windows-powershell-path'
Check ($launcherSource -notmatch '(?i)Set-ExecutionPolicy|EncodedCommand|Invoke-Expression|Start-Process|System\.Diagnostics\.Process') 'EP-04.no-policy-or-inline-exec'
Check ($probeSource -notmatch '(?i)Set-ExecutionPolicy|EncodedCommand|Invoke-Expression|Start-Process|System\.Diagnostics\.Process') 'EP-05.probe-no-policy-mutation'
Check ($launcherSource -match 'Get-PfcPermissionProbeLauncherArguments' -and $launcherSource -match 'return @\(') 'EP-06.argv-array-builder'
Check ($argv -notcontains '-Command' -and $argv -notcontains ('Enc' + 'odedCommand')) 'EP-07.no-command-argv'
$ordinary = @()
foreach ($root in @((Join-Path $repoRoot 'scripts'),(Join-Path $repoRoot 'skill'))) { if (Test-Path -LiteralPath $root -PathType Container) { $ordinary += @(Get-ChildItem -LiteralPath $root -Recurse -File -ErrorAction Stop) } }
$ordinaryBypass = @($ordinary | Where-Object { $_.FullName -ne $launcherPath -and (Get-Content -Raw -LiteralPath $_.FullName) -match '(?i)-ExecutionPolicy\s+Bypass' })
Check ($ordinaryBypass.Count -eq 0) 'EP-08.ordinary-scripts-no-bypass'
Check ($probeSource -match '(?i)Get-ExecutionPolicy' -and $probeSource -notmatch '(?i)Set-ExecutionPolicy') 'EP-09.diagnostic-policy-only'
Check ($launcherSource -notmatch '(?i)stdin|StandardInput|ReadToEnd') 'EP-10.launcher-no-stdin-script'

'PERMISSION_PROBE_EXECUTION_POLICY_TESTS=10/10 PASS'
