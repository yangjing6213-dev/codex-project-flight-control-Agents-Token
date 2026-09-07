[CmdletBinding()]
param(
    [AllowNull()][string]$PowerShellPath,
    [Parameter(Mandatory = $true)][string]$ProbeScriptPath,
    [Parameter(Mandatory = $true)][string]$RequestPath
)
$ErrorActionPreference = 'Stop'
function Resolve-PfcWindowsPowerShell51Path {
    $systemRoot = [Environment]::GetEnvironmentVariable('SystemRoot','Process')
    if ([string]::IsNullOrWhiteSpace($systemRoot)) { throw 'SYSTEMROOT_MISSING' }
    $expected = [IO.Path]::GetFullPath((Join-Path $systemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'))
    if (-not [IO.Path]::IsPathRooted($expected) -or [IO.Path]::GetFileName($expected) -cne 'powershell.exe') { throw 'WINDOWS_POWERSHELL_PATH_INVALID' }
    if (-not (Test-Path -LiteralPath $expected -PathType Leaf)) { throw 'WINDOWS_POWERSHELL_51_NOT_FOUND' }
    $item = Get-Item -LiteralPath $expected -Force -ErrorAction Stop
    if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'WINDOWS_POWERSHELL_PATH_REPARSE' }
    return $expected
}
function Get-PfcPermissionProbeLauncherArguments {
    param([Parameter(Mandatory = $true)][string]$PowerShell,[Parameter(Mandatory = $true)][string]$Script,[Parameter(Mandatory = $true)][string]$Request)
    return @($PowerShell,'-NoLogo','-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-OutputFormat','Text','-File',$Script,'-RequestPath',$Request)
}
# This helper deliberately builds argv only; the parent runner owns process creation.
$resolvedPowerShell = Resolve-PfcWindowsPowerShell51Path
if (-not [string]::IsNullOrWhiteSpace($PowerShellPath)) {
    $provided = [IO.Path]::GetFullPath($PowerShellPath)
    if (-not $provided.Equals($resolvedPowerShell,[StringComparison]::OrdinalIgnoreCase)) { throw 'WINDOWS_POWERSHELL_PATH_MISMATCH' }
}
Get-PfcPermissionProbeLauncherArguments -PowerShell $resolvedPowerShell -Script $ProbeScriptPath -Request $RequestPath
