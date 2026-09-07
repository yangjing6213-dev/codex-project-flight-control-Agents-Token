Set-StrictMode -Version 2.0

function New-PfcFixtureRepository {
    param(
        [Parameter(Mandatory = $true)][ValidatePattern('^EFF-0[1-7]$')][string]$ScenarioId,
        [Parameter(Mandatory = $true)][string]$DestinationRoot
    )
    $root = [IO.Path]::GetFullPath($DestinationRoot)
    if (Test-Path -LiteralPath $root) { throw 'DestinationRoot must not already exist.' }
    New-Item -ItemType Directory -Path $root -Force | Out-Null
    $files = @{
        'README.md' = "# $ScenarioId fixture`nDeterministic evaluation repository.`n"
        'src/Target.ps1' = "function Invoke-Target { 'target' }`n"
        'tests/Target.Tests.ps1' = "Describe '$ScenarioId target' { It 'passes' { Invoke-Target | Should -Be 'target' } }`n"
        'src/Unrelated.ps1' = "function Invoke-Unrelated { 'noise' }`n"
    }
    if ($ScenarioId -eq 'EFF-02') { $files['src/Helpers.ps1'] = "function Convert-ToReusableValue { param(`$Value) `$Value }`n" }
    if ($ScenarioId -eq 'EFF-04') { $files['candidate/Candidate.ps1'] = "function Invoke-Candidate { param(`$Input); return `$Input }`n"; $files['REVIEW_REPORT.md'] = "# Narrow Verifier finding`nFinding: null input handling in Invoke-Candidate only.`nAccepted Candidate code must remain unchanged.`n"; $files['CANDIDATE.md'] = "R1 Candidate frozen; BASE_SHA will identify this baseline.`n" }
    if ($ScenarioId -eq 'EFF-05') { $files['tests/Target.Tests.ps1'] = "Describe '$ScenarioId target' { It 'passes' { Invoke-Target | Should -Be 'target' } }`n"; $files['tests/Dependency.Signal.ps1'] = "Seeded dependency signal: Target depends on shared helper; broaden to module test after signal.`n" }
    if ($ScenarioId -eq 'EFF-06') { $files['FAILURE.md'] = "Seeded failure: output is empty.`nHypothesis A: target receives null input.`nHypothesis B: shared helper returns empty string.`nForbidden: third speculative patch.`n" }
    if ($ScenarioId -eq 'EFF-07') { $files['BUILD_REPORT.md'] = "BUILD_REPORT: PASS`nTarget test command: Invoke-Target.`n"; $files['REVIEW_REPORT.md'] = "REVIEW_REPORT: PASS`nCandidate SHA is frozen and review is resumable.`n"; $files['STATUS'] = "STATUS: RESUMABLE`nBASE_SHA: PENDING`n"; $files['CONTRACT.md'] = "Persisted contract for $ScenarioId.`nBASE_SHA: PENDING`nRequired evidence: BUILD_REPORT, REVIEW_REPORT, STATUS.`n"; $files['BASE_SHA'] = 'PENDING' }
    foreach ($relative in $files.Keys) {
        $path = Join-Path $root $relative
        $parent = Split-Path -Parent $path
        if (-not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
        [IO.File]::WriteAllText($path, [string]$files[$relative], (New-Object Text.UTF8Encoding($false)))
    }
    & git -C $root init --quiet | Out-Null
    & git -C $root config user.email 'pfc-fixture@example.invalid'
    & git -C $root config user.name 'PFC Fixture'
    & git -C $root add --all
    $env:GIT_AUTHOR_DATE = '2000-01-01T00:00:00Z'; $env:GIT_COMMITTER_DATE = '2000-01-01T00:00:00Z'
    try { & git -C $root commit --quiet -m "fixture $ScenarioId" } finally { Remove-Item Env:GIT_AUTHOR_DATE -ErrorAction SilentlyContinue; Remove-Item Env:GIT_COMMITTER_DATE -ErrorAction SilentlyContinue }
    $baseSha = (& git -C $root rev-parse HEAD).Trim().ToLowerInvariant()
    $persistedFiles = @()
    if ($ScenarioId -eq 'EFF-04') {
        [IO.File]::WriteAllText((Join-Path $root 'CANDIDATE.md'), "R1 Candidate frozen.`nBASE_SHA: $baseSha`nCandidate code: candidate/Candidate.ps1`n", (New-Object Text.UTF8Encoding($false)))
        $persistedFiles += 'CANDIDATE.md'
    }
    if ($ScenarioId -eq 'EFF-07') {
        [IO.File]::WriteAllText((Join-Path $root 'BASE_SHA'), $baseSha + "`n", (New-Object Text.UTF8Encoding($false)))
        [IO.File]::WriteAllText((Join-Path $root 'STATUS'), "STATUS: RESUMABLE`nBASE_SHA: $baseSha`n", (New-Object Text.UTF8Encoding($false)))
        [IO.File]::WriteAllText((Join-Path $root 'CONTRACT.md'), "Persisted contract for $ScenarioId.`nBASE_SHA: $baseSha`nRequired evidence: BUILD_REPORT, REVIEW_REPORT, STATUS.`n", (New-Object Text.UTF8Encoding($false)))
        $persistedFiles += @('BASE_SHA','STATUS','CONTRACT.md')
    }
    $headSha = $baseSha
    if (@($persistedFiles).Count -gt 0) {
        & git -C $root add -- $persistedFiles
        if ($LASTEXITCODE -ne 0) { throw 'Unable to stage persisted fixture metadata.' }
        $env:GIT_AUTHOR_DATE = '2000-01-01T00:00:00Z'; $env:GIT_COMMITTER_DATE = '2000-01-01T00:00:00Z'
        try {
            # Metadata is a second ordinary commit.  Keep the first commit
            # reachable as base_sha so the expected graph reflects reality.
            & git -C $root commit --quiet -m "fixture $ScenarioId metadata"
            if ($LASTEXITCODE -ne 0) { throw 'Unable to create persisted metadata commit.' }
        } finally { Remove-Item Env:GIT_AUTHOR_DATE -ErrorAction SilentlyContinue; Remove-Item Env:GIT_COMMITTER_DATE -ErrorAction SilentlyContinue }
        $headSha = (& git -C $root rev-parse HEAD).Trim().ToLowerInvariant()
        if ($headSha -ceq $baseSha) { throw 'Fixture metadata commit did not create a distinct head SHA.' }
    }
    & git -C $root checkout --detach --quiet
    if ($LASTEXITCODE -ne 0) { throw 'Unable to detach fixture HEAD.' }
    foreach ($ref in @(& git -C $root for-each-ref --format='%(refname)' refs/heads)) { if (-not [string]::IsNullOrWhiteSpace($ref)) { & git -C $root update-ref -d $ref.Trim() } }
    $branchRefs = @(& git -C $root for-each-ref --format='%(refname)' refs/heads)
    if (@($branchRefs).Count -ne 0) { throw 'Fixture repository retains branch refs.' }
    $symbolicHead = (& git -C $root symbolic-ref -q --short HEAD 2>$null)
    if (-not [string]::IsNullOrWhiteSpace([string]$symbolicHead)) { throw 'Fixture HEAD is still attached to a branch.' }
    $statusLines = @(& git -C $root status --porcelain)
    if (@($statusLines).Count -ne 0) { throw 'Fixture repository is not clean after setup.' }
    $parentLine = ((& git -C $root rev-list --parents -n 1 HEAD) -join "`n").Trim()
    $parentTokens = @($parentLine -split '\s+' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    $expectedParentTokenCount = 1
    if (@($persistedFiles).Count -gt 0) { $expectedParentTokenCount = 2 }
    if ($parentTokens.Count -ne $expectedParentTokenCount) { throw 'Fixture commit graph has an unexpected parent count.' }
    if ($parentTokens[0] -cne $headSha) { throw 'Fixture HEAD does not match the expected head SHA.' }
    if (@($persistedFiles).Count -gt 0 -and $parentTokens[1] -cne $baseSha) { throw 'Fixture metadata commit does not parent the base commit.' }
    foreach ($metadata in @($persistedFiles)) {
        $workingText = [IO.File]::ReadAllText((Join-Path $root $metadata))
        $treeText = ((& git -C $root show ('HEAD:' + $metadata)) -join "`n") + "`n"
        if ($workingText -cne $treeText) { throw ('Fixture metadata is not present in HEAD: ' + $metadata) }
    }
    $commitList = if (@($persistedFiles).Count -gt 0) { @($baseSha, $headSha) } else { @($baseSha) }
    $expectedGraph = [ordered]@{ commits = $commitList; base_sha = $baseSha; head_sha = $headSha; parent_count = @($commitList).Count - 1; branchless = (@($branchRefs).Count -eq 0); branch_refs = @($branchRefs); detached = ([string]::IsNullOrWhiteSpace([string]$symbolicHead)); clean = (@($statusLines).Count -eq 0) }
    [pscustomobject]@{ root = $root; base_sha = $baseSha; head_sha = $headSha; expected_files = @($files.Keys | Sort-Object); expected_graph = $expectedGraph }
}

Export-ModuleMember -Function New-PfcFixtureRepository
