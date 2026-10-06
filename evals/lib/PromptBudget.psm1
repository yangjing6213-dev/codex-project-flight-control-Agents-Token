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

function Measure-PfcAgentPromptBudget {
    param([Parameter(Mandatory = $true)][System.IO.FileInfo]$Path)
    # Frozen V1 commit 8d2fe2df69b4167f4fb37df41ccd99fd29615395, raw UTF-8 blobs:
    # builder c5cc84ddbf667029e2fafbdff4e2812b42bc586e; verifier 8e18795dd4e98741323e3f1e96b51da7fca1f7f6.
    $baseline = switch -Exact ($Path.Name) {
        'project-flight-builder.toml' { 2795 }
        'project-flight-verifier.toml' { 2680 }
        default { throw 'No frozen V1 Agent baseline for this file.' }
    }
    $bytes = [IO.File]::ReadAllBytes($Path.FullName).LongLength
    $tokens = [long][Math]::Ceiling($bytes / 4.0)
    $baselineTokens = [long][Math]::Ceiling($baseline / 4.0)
    [pscustomobject]@{
        baseline_utf8_bytes = $baseline
        baseline_conservative_estimated_tokens = $baselineTokens
        utf8_bytes = $bytes
        conservative_estimated_tokens = $tokens
        estimate_basis = 'utf8_bytes_divided_by_4'
        token_data_status = 'NOT_AVAILABLE'
        warning = 'Estimate only; client token usage is unavailable and no savings claim is made.'
        # No text-based exception: a new reviewed limit requires an explicit code change.
        status = if ($bytes * 100 -le [long]$baseline * 115 -and $tokens * 100 -le $baselineTokens * 115) { 'PASS' } else { 'FAIL' }
    }
}

Export-ModuleMember -Function Measure-PfcPromptBudget, Measure-PfcAgentPromptBudget
