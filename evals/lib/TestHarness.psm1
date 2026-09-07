Set-StrictMode -Version 2.0

function Assert-PfcTrue {
    param(
        [Parameter(Mandatory = $true)][bool]$Actual,
        [Parameter(Mandatory = $true)][string]$ScenarioId,
        [Parameter(Mandatory = $true)][string]$Expected = 'True'
    )
    if (-not $Actual) {
        throw ("[{0}] expected={1}; actual={2}" -f $ScenarioId, $Expected, $Actual)
    }
}

function Assert-PfcEqual {
    param(
        [Parameter(Mandatory = $true)]$Expected,
        [Parameter(Mandatory = $true)]$Actual,
        [Parameter(Mandatory = $true)][string]$ScenarioId
    )
    if ($Expected -cne $Actual) {
        throw ("[{0}] expected={1}; actual={2}" -f $ScenarioId, $Expected, $Actual)
    }
}

function New-PfcResult {
    param(
        [Parameter(Mandatory = $true)][string]$ScenarioId,
        [Parameter(Mandatory = $true)][ValidateSet('PASS','FAIL','PARTIAL','NOT_RUN')][string]$Status,
        [string]$Message = ''
    )
    [pscustomobject]@{ ScenarioId = $ScenarioId; Status = $Status; Message = $Message }
}

function Write-PfcSummary {
    param(
        [Parameter(Mandatory = $true)][System.Collections.IEnumerable]$Results,
        [switch]$Json
    )
    if ($Json) {
        $Results | ConvertTo-Json -Compress
    } else {
        $Results | ForEach-Object { '{0}: {1} {2}' -f $_.ScenarioId, $_.Status, $_.Message }
    }
}

Export-ModuleMember -Function Assert-PfcTrue, Assert-PfcEqual, New-PfcResult, Write-PfcSummary
