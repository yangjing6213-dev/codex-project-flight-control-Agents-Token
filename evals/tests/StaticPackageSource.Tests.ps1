function Invoke-PfcStaticPackageSourceTests {
    param([Parameter(Mandatory=$true)][string]$RepositoryRoot)
    $results = New-Object System.Collections.Generic.List[object]
    foreach ($mode in @('missing','tampered')) {
        $id = 'harness.canonical-source.' + $mode
        $tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')
        $fixture = Join-Path $tempRoot ('pfc-source-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $fixture -Force | Out-Null
        try {
            $sourceSkill = Join-Path $RepositoryRoot 'skill\project-flight-control'
            Copy-Item -LiteralPath (Join-Path $sourceSkill 'SKILL.md') -Destination (Join-Path $fixture 'SKILL.md')
            Copy-Item -LiteralPath (Join-Path $RepositoryRoot 'codex-agents') -Destination (Join-Path $fixture 'agents') -Recurse
            Copy-Item -LiteralPath (Join-Path $sourceSkill 'agents\openai.yaml') -Destination (Join-Path $fixture 'agents\openai.yaml')
            $legacyPolicy = Join-Path $fixture 'agents\openai.yaml'
            Set-Content -LiteralPath $legacyPolicy -Value ("# explicit-only policy`n" + (Get-Content -Raw -LiteralPath $legacyPolicy))
            Copy-Item -LiteralPath (Join-Path $sourceSkill 'references') -Destination (Join-Path $fixture 'references') -Recurse
            Copy-Item -LiteralPath (Join-Path $sourceSkill 'assets\templates') -Destination (Join-Path $fixture 'templates') -Recurse
            if ($mode -eq 'missing') {
                $failedIds = @('package.skill.path','package.skill.frontmatter','package.prompt_budget.report','package.agents.policy','package.agents.explicit_only','package.references.paths','package.templates.paths','package.formal_agents.count','package.custom_agent.fields','package.builder.efficiency','package.verifier.evidence')
            } else {
                New-Item -ItemType Directory -Path (Join-Path $fixture 'skill') -Force | Out-Null
                Copy-Item -LiteralPath $sourceSkill -Destination (Join-Path $fixture 'skill\project-flight-control') -Recurse
                Copy-Item -LiteralPath (Join-Path $RepositoryRoot 'codex-agents') -Destination (Join-Path $fixture 'codex-agents') -Recurse
                $failedIds = @('package.skill.frontmatter','package.agents.explicit_only','package.formal_agents.count','package.custom_agent.fields','package.builder.efficiency','package.verifier.evidence')
                $valid = @(Invoke-PfcStaticChecks -RepositoryRoot (Get-Item $fixture) -Phase RED)
                foreach ($checkId in $failedIds) {
                    $check = @($valid | Where-Object { $_.ScenarioId -eq $checkId })
                    Assert-PfcEqual -Expected 'PASS' -Actual $check.Status -ScenarioId ($id + '.positive.' + $checkId)
                }
                Set-Content -LiteralPath (Join-Path $fixture 'skill\project-flight-control\SKILL.md') -Value 'invalid frontmatter'
                Set-Content -LiteralPath (Join-Path $fixture 'skill\project-flight-control\agents\openai.yaml') -Value "policy:`n  allow_implicit_invocation: true"
                Set-Content -LiteralPath (Join-Path $fixture 'codex-agents\project-flight-builder.toml') -Value 'model = "forbidden-override"'
                Set-Content -LiteralPath (Join-Path $fixture 'codex-agents\project-flight-verifier.toml') -Value 'model = "forbidden-override"'
                Set-Content -LiteralPath (Join-Path $fixture 'codex-agents\extra.toml') -Value 'name = "extra"'
            }
            $actual = @(Invoke-PfcStaticChecks -RepositoryRoot (Get-Item $fixture) -Phase RED)
            foreach ($checkId in $failedIds) {
                $check = @($actual | Where-Object { $_.ScenarioId -eq $checkId })
                Assert-PfcEqual -Expected 'FAIL' -Actual $check.Status -ScenarioId ($id + '.' + $checkId)
            }
            $results.Add((New-PfcResult -ScenarioId $id -Status PASS -Message 'Root copies cannot mask missing or tampered canonical install sources'))
        } catch {
            $results.Add((New-PfcResult -ScenarioId $id -Status FAIL -Message $_.Exception.Message))
        } finally {
            $resolved = [IO.Path]::GetFullPath($fixture)
            if ((Split-Path -Parent $resolved) -cne $tempRoot -or (Split-Path -Leaf $resolved) -notmatch '^pfc-source-[a-f0-9]{32}$') { throw 'Unsafe test fixture cleanup path' }
            Remove-Item -LiteralPath $resolved -Recurse -Force
        }
    }
    return $results.ToArray()
}
