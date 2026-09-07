$ErrorActionPreference = 'Stop'
Import-Module (Join-Path (Split-Path -Parent $PSScriptRoot) 'lib\CodexRunner.psm1') -Force

function Assert-SchemaEncoding {
    param([bool]$Condition,[string]$Message)
    if (-not $Condition) { throw $Message }
}

function Get-SchemaBytes {
    param([Parameter(Mandatory = $true)][string]$Path)
    return [IO.File]::ReadAllBytes($Path)
}

function Test-NoBomJson {
    param([Parameter(Mandatory = $true)][string]$Path)
    $bytes = Get-SchemaBytes -Path $Path
    Assert-SchemaEncoding ($bytes.Length -gt 0) 'schema is empty'
    Assert-SchemaEncoding (-not ($bytes.Length -ge 3 -and $bytes[0] -eq 239 -and $bytes[1] -eq 187 -and $bytes[2] -eq 191)) 'schema has UTF-8 BOM'
    $first = $null
    foreach ($byte in $bytes) {
        if ([int]$byte -notin @(9,10,13,32)) { $first = [int]$byte; break }
    }
    Assert-SchemaEncoding ($first -eq 0x7B) 'schema does not begin with an object'
    $text = (New-Object -TypeName System.Text.UTF8Encoding -ArgumentList @($false,$true)).GetString($bytes)
    $null = ConvertFrom-Json -InputObject $text
}

$root = Join-Path ([IO.Path]::GetTempPath()) ('pfc-schema-encoding-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $root -Force | Out-Null
try {
    $ascii = '{"type":"object","properties":{"status":{"type":"string"}},"required":["status"],"additionalProperties":false}'
    $nonAscii = '{"type":"object","description":"测试 UTF-8","properties":{},"additionalProperties":false}'
    $canary = '{"type":"object","properties":{"status":{"type":"string","enum":["CANARY_OK"]}},"required":["status"],"additionalProperties":false}'

    # TEST-BOM-01: ASCII schema is no-BOM and parses as JSON.
    $asciiPath = Join-Path $root 'ascii.json'
    Write-PfcUtf8NoBom -Path $asciiPath -Content $ascii
    Test-NoBomJson -Path $asciiPath

    # TEST-BOM-02: non-ASCII JSON round-trips through UTF-8 without a BOM.
    $nonAsciiPath = Join-Path $root 'non-ascii.json'
    Write-PfcUtf8NoBom -Path $nonAsciiPath -Content $nonAscii
    $roundTrip = (New-Object -TypeName System.Text.UTF8Encoding -ArgumentList @($false,$true)).GetString((Get-SchemaBytes -Path $nonAsciiPath))
    Assert-SchemaEncoding ($roundTrip -ceq $nonAscii) 'non-ASCII schema did not round-trip exactly'
    Test-NoBomJson -Path $nonAsciiPath

    # TEST-BOM-03: overwrite removes a pre-existing BOM and stale tail bytes.
    $overwritePath = Join-Path $root 'overwrite.json'
    $bomEncoding = New-Object -TypeName System.Text.UTF8Encoding -ArgumentList @($true)
    $old = @($bomEncoding.GetPreamble() + $bomEncoding.GetBytes('{"old":true,"stale_tail":"must disappear"}'))
    [IO.File]::WriteAllBytes($overwritePath, $old)
    Write-PfcUtf8NoBom -Path $overwritePath -Content $ascii
    Test-NoBomJson -Path $overwritePath
    $overwritten = (New-Object -TypeName System.Text.UTF8Encoding -ArgumentList @($false,$true)).GetString((Get-SchemaBytes -Path $overwritePath))
    Assert-SchemaEncoding ($overwritten -ceq $ascii -and $overwritten -notmatch 'stale_tail') 'old schema tail remained after overwrite'

    # TEST-BOM-04: missing parent directories are created before writing.
    $nestedPath = Join-Path $root 'missing\parent\schema.json'
    Write-PfcUtf8NoBom -Path $nestedPath -Content $ascii
    Assert-SchemaEncoding (Test-Path -LiteralPath $nestedPath -PathType Leaf) 'nested schema was not written'
    Test-NoBomJson -Path $nestedPath

    # TEST-BOM-05: Canary 3 schema contract is exact.
    $canaryPath = Join-Path $root 'canary3.json'
    Write-PfcUtf8NoBom -Path $canaryPath -Content $canary
    $canaryState = Get-PfcSchemaPreflight -Path $canaryPath
    Assert-SchemaEncoding ($canaryState.schema_preflight_result -eq 'PASS' -and $canaryState.schema_has_utf8_bom -eq $false -and $canaryState.schema_first_non_whitespace_byte -eq '0x7B' -and $canaryState.schema_root_type -eq 'object') 'Canary schema preflight failed'
    $canaryObject = ConvertFrom-Json -InputObject ((New-Object -TypeName System.Text.UTF8Encoding -ArgumentList @($false,$true)).GetString((Get-SchemaBytes -Path $canaryPath)))
    Assert-SchemaEncoding ((@($canaryObject.PSObject.Properties.Name) -join ',') -ceq 'type,properties,required,additionalProperties') 'Canary schema root fields changed'
    Assert-SchemaEncoding ((@($canaryObject.properties.PSObject.Properties.Name) -join ',') -ceq 'status') 'Canary schema properties changed'
    Assert-SchemaEncoding ($canaryObject.properties.status.type -ceq 'string' -and ((@($canaryObject.properties.status.enum) -join ',') -ceq 'CANARY_OK') -and ((@($canaryObject.required) -join ',') -ceq 'status') -and $canaryObject.additionalProperties -eq $false) 'Canary schema contract is not exact'

    # TEST-BOM-06: all seven EFF scenarios' dynamic schema copies pass preflight.
    $repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $stableSchema = Join-Path $repoRoot 'evals\schemas\eval-run.schema.json'
    $stableSchemaText = (New-Object -TypeName System.Text.UTF8Encoding -ArgumentList @($false,$true)).GetString((Get-SchemaBytes -Path $stableSchema))
    $scenarioNames = @('EFF-01-targeted-context','EFF-02-reuse-before-create','EFF-03-minimal-diff','EFF-04-delta-rework','EFF-05-incremental-verification','EFF-06-debugging-convergence','EFF-07-structured-recovery')
    foreach ($scenarioName in $scenarioNames) {
        $dynamicSchema = Join-Path $root ('eff\' + $scenarioName + '\schema.json')
        Write-PfcUtf8NoBom -Path $dynamicSchema -Content $stableSchemaText
        Test-NoBomJson -Path $dynamicSchema
        $contractPath = Join-Path (Join-Path $repoRoot 'evals\scenarios\builder-efficiency') (Join-Path $scenarioName 'scenario.json')
        $contract = Get-Content -Raw -LiteralPath $contractPath | ConvertFrom-Json
        Assert-SchemaEncoding ($contract.schema_sha256 -ceq ((Get-FileHash -Algorithm SHA256 -LiteralPath $stableSchema).Hash.ToLowerInvariant())) ('schema hash mismatch for ' + $contract.scenario_id)
    }

    # TEST-BOM-07: BOM and invalid JSON fail preflight before a child process is invoked.
    $promptPath = Join-Path $root 'prompt.txt'
    Set-Content -LiteralPath $promptPath -Value 'Return the fixed response.' -Encoding ASCII
    $bomPath = Join-Path $root 'bad-bom.json'
    $bomEncoding = New-Object -TypeName System.Text.UTF8Encoding -ArgumentList @($true)
    [IO.File]::WriteAllBytes($bomPath, @($bomEncoding.GetPreamble() + $bomEncoding.GetBytes($ascii)))
    $invalidPath = Join-Path $root 'bad-json.json'
    Write-PfcUtf8NoBom -Path $invalidPath -Content '{"type":"object"'
    $script:processCalls = 0
    $invoker = { param($args) $script:processCalls++; throw 'ProcessInvoker must not be called after schema preflight failure.' }
    foreach ($badSchema in @($bomPath,$invalidPath)) {
        $state = Get-PfcSchemaPreflight -Path $badSchema
        Assert-SchemaEncoding ($state.schema_preflight_result -eq 'FAIL') ('bad schema unexpectedly passed preflight: ' + (Split-Path -Leaf $badSchema))
        $thrown = $false
        try {
            Invoke-PfcCodexRun -WorkingDirectory $root -PromptPath $promptPath -OutputSchemaPath $badSchema -SandboxMode 'read-only' -ResultDirectory (Join-Path $root '.pfc-eval-results') -Phase 'RED' -ProcessInvoker $invoker
        } catch {
            $thrown = $_.Exception.Message -eq 'LOCAL_SCHEMA_PREFLIGHT_FAILED'
        }
        Assert-SchemaEncoding $thrown 'preflight failure did not stop Runner'
    }
    Assert-SchemaEncoding ($script:processCalls -eq 0) 'schema preflight failure started a child process'
    'SCHEMA_ENCODING_TESTS=7/7 PASS'
} finally {
    if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force }
}
