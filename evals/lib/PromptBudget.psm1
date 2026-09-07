Set-StrictMode -Version 2.0

function Measure-PfcPromptBudget {
    param(
        [Parameter(Mandatory = $true)][System.IO.FileInfo]$Path,
        [Parameter(Mandatory = $true)][int]$Budget
    )
    $text = [System.IO.File]::ReadAllText($Path.FullName)
    $bytes = [System.Text.Encoding]::UTF8.GetByteCount($text)
    $estimated = [int][Math]::Ceiling($bytes / 4.0)
    [pscustomobject]@{
        chars = $text.Length
        utf8_bytes = $bytes
        conservative_estimated_tokens = $estimated
        budget = $Budget
        estimate_basis = 'utf8_bytes_divided_by_4'
        token_data_status = 'NOT_AVAILABLE'
        warning = 'Estimate only; client token usage is unavailable and no savings claim is made.'
        status = if ($estimated -le $Budget) { 'PASS' } else { 'FAIL' }
    }
}

Export-ModuleMember -Function Measure-PfcPromptBudget
