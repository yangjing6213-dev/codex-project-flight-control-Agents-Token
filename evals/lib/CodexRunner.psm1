Set-StrictMode -Version 2.0

function Convert-PfcRedactedText {
    param([AllowNull()][string]$Text)
    if ($null -eq $Text) { return $null }
    $v = $Text -replace '(?i)(?:[A-Za-z]:\\|\\\\)[^\s"'']+', '<ABSOLUTE_PATH>'
    $v = $v -replace '(?i)(?<![A-Za-z0-9])/[^\s"'']+', '<ABSOLUTE_PATH>'
    $v = $v -replace '(?i)(sk-[A-Za-z0-9_-]{8,}|gh[pousr]_[A-Za-z0-9_-]{8,}|Bearer\s+[A-Za-z0-9._-]+)', '<REDACTED_SECRET>'
    return $v
}

function Test-PfcPathDescendant {
    param([Parameter(Mandatory = $true)][string]$Path,[Parameter(Mandatory = $true)][string]$Parent)
    $candidate = [IO.Path]::GetFullPath($Path).TrimEnd('\')
    $root = [IO.Path]::GetFullPath($Parent).TrimEnd('\')
    return $candidate.Equals($root, [StringComparison]::OrdinalIgnoreCase) -or $candidate.StartsWith($root + '\', [StringComparison]::OrdinalIgnoreCase)
}

function Test-PfcReparsePath {
    param([Parameter(Mandatory = $true)][string]$Path)
    $current = [IO.Path]::GetFullPath($Path)
    while (-not [string]::IsNullOrWhiteSpace($current)) {
        if (Test-Path -LiteralPath $current) {
            $item = Get-Item -LiteralPath $current -Force -ErrorAction Stop
            if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { return $true }
        }
        $parent = Split-Path -Parent $current
        if ($parent -eq $current) { break }
        $current = $parent
    }
    return $false
}

function Get-PfcEvaluationPromptText {
    param(
        [Parameter(Mandatory = $true)][string]$CommonPromptPath,
        [AllowNull()][string]$TreatmentPromptPath,
        [Parameter(Mandatory = $true)][ValidateSet('RED','GREEN')][string]$Phase
    )
    if (-not (Test-Path -LiteralPath $CommonPromptPath -PathType Leaf)) { throw 'Common task contract is missing.' }
    $common = Read-PfcUtf8TextStrict -Path $CommonPromptPath
    if (-not $TreatmentPromptPath) { return [pscustomobject]@{ text = $common; treatment_enabled = $false } }
    if (-not (Test-Path -LiteralPath $TreatmentPromptPath -PathType Leaf)) { throw 'Treatment prompt file is missing.' }
    $treatment = Read-PfcUtf8TextStrict -Path $TreatmentPromptPath
    if ($Phase -eq 'RED') {
        if (-not [string]::IsNullOrWhiteSpace($treatment)) { Throw-PfcRevision3Failure -Classification 'RED_TREATMENT_LEAKAGE' -Message 'RED treatment must be NONE.' }
        return [pscustomobject]@{ text = $common; treatment_enabled = $false }
    }
    if ([string]::IsNullOrWhiteSpace($treatment)) { return [pscustomobject]@{ text = $common; treatment_enabled = $false } }
    return [pscustomobject]@{ text = ($common.TrimEnd() + "`n`n" + $treatment.Trim() + "`n"); treatment_enabled = $true }
}

function Get-PfcRunnerPhaseDecision {
    param([Parameter(Mandatory = $true)][ValidateSet('RED','GREEN')][string]$AuthorizedPhase,[AllowNull()][string]$ModelReportedPhase)
    [pscustomobject]@{
        runner_authorized_phase = $AuthorizedPhase
        model_reported_phase = if ([string]::IsNullOrWhiteSpace($ModelReportedPhase)) { 'NOT_AVAILABLE' } else { $ModelReportedPhase }
        model_report_consistency = if ([string]::IsNullOrWhiteSpace($ModelReportedPhase)) { 'NOT_AVAILABLE' } elseif ($ModelReportedPhase -ceq $AuthorizedPhase) { 'PASS' } else { 'FAIL' }
    }
}

function Read-PfcCodexJsonlMetrics {
    param([Parameter(Mandatory = $true)][AllowEmptyCollection()][string[]]$Lines,[AllowNull()][string[]]$ReceivedAtUtc)
    $eventTypes = New-Object System.Collections.Generic.List[string]
    $filePaths = New-Object System.Collections.Generic.List[string]
    $toolCount = 0
    $commandCount = 0
    $mcpToolCount = 0
    $webSearchCount = 0
    $usage = $null
    $turnResult = 'NOT_AVAILABLE'
    $turnFailed = $false
    $hadError = $false
    $errorCount = 0
    $transportErrorCount = 0
    $firstTransportErrorAt = $null
    $lastTransportErrorAt = $null
    $lastNonErrorAt = $null
    $reconnectAttempts = 0
    $invalidJsonLines = 0
    $threadStarted = $false; $turnStarted = $false; $turnCompleted = $false
    $threadStartedAt = $null; $turnStartedAt = $null
    $lastCompletedAgentMessage = $null
    $terminalAt = $null; $lastEventAt = $null
    $rawLineCount = 0
    foreach ($line in $Lines) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        $rawLineCount++
        $timestampIndex = $rawLineCount - 1
        $lastEventAt = if ($null -ne $ReceivedAtUtc -and $timestampIndex -lt $ReceivedAtUtc.Count) { $ReceivedAtUtc[$timestampIndex] } else { [DateTime]::UtcNow.ToString('o') }
        try { $event = $line | ConvertFrom-Json } catch { $invalidJsonLines++; continue }
        if ($null -eq $event.type) { continue }
        $type = [string]$event.type
        $item = $event.PSObject.Properties['item']
        $itemType = if ($null -ne $item -and $null -ne $item.Value -and $null -ne $item.Value.PSObject.Properties['type']) { [string]$item.Value.type } else { '' }
        if ($type -match '^item\.completed$' -and $itemType -eq 'command_execution') { $commandCount++; $type = 'command_execution' }
        elseif ($type -match '^item\.completed$' -and $itemType -eq 'file_change') { $type = 'file_change' }
        elseif ($type -match '^item\.completed$' -and $itemType -eq 'mcp_tool_call') { $mcpToolCount++ }
        elseif ($type -match '^item\.completed$' -and $itemType -eq 'web_search') { $webSearchCount++ }
        if ($type -eq 'error') {
            if (-not $turnCompleted) { $hadError = $true }
            $errorCount++; $transportErrorCount++
            if ($null -eq $firstTransportErrorAt) { $firstTransportErrorAt = $lastEventAt }
            $lastTransportErrorAt = $lastEventAt
            $message = [string](Get-PfcSchemaProperty -Object $event -Name 'message')
            if ($message -match '(?i)retry|reconnect') { $reconnectAttempts++ }
            if (-not $eventTypes.Contains($type)) { [void]$eventTypes.Add($type) }; continue
        }
        $lastNonErrorAt = $lastEventAt
        if ($type -match '^(turn\.failed|item\.failed)$') { $turnFailed = $true; if (-not $eventTypes.Contains($type)) { [void]$eventTypes.Add($type) }; $terminalAt = $lastEventAt; continue }
        if ($type -notmatch '^(thread\.started|turn\.started|turn\.completed|tool\.call|tool_use|tool\.result|file\.changed|item\.completed|command\.[A-Za-z0-9_.-]+|command_execution|file_change)$') { continue }
        if (-not $eventTypes.Contains($type)) { [void]$eventTypes.Add($type) }
        if ($type -eq 'thread.started') { $threadStarted = $true; if ($null -eq $threadStartedAt) { $threadStartedAt = $lastEventAt } }
        if ($type -eq 'turn.started') { $turnStarted = $true; if ($null -eq $turnStartedAt) { $turnStartedAt = $lastEventAt } }
        if ($type -match '^(tool\.call|tool_use|tool\.result)$') { $toolCount++ }
        if ($type -match '^command\.') { $commandCount++ }
        if ($type -eq 'turn.completed') { $turnCompleted = $true; $terminalAt = $lastEventAt; $turnResult = 'COMPLETED' }
        if ($type -eq 'item.completed' -and $itemType -eq 'agent_message' -and -not $turnCompleted -and -not $turnFailed) {
            $messageText = Get-PfcAgentMessageText -Item $item.Value
            if (-not [string]::IsNullOrWhiteSpace([string]$messageText)) { $lastCompletedAgentMessage = Convert-PfcRedactedText ([string]$messageText) }
        }
        foreach ($name in @('path','file_path','filePath')) {
            $property = $event.PSObject.Properties[$name]
            if ($null -ne $property -and $null -ne $property.Value -and -not [string]::IsNullOrEmpty([string]$property.Value)) { [void]$filePaths.Add((Convert-PfcRedactedText ([string]$property.Value))) }
        }
        if ($null -ne $item -and $null -ne $item.Value) {
            foreach ($name in @('path','file_path','filePath')) { $property = $item.Value.PSObject.Properties[$name]; if ($null -ne $property -and $null -ne $property.Value) { [void]$filePaths.Add((Convert-PfcRedactedText ([string]$property.Value))) } }
            $changesProperty = $item.Value.PSObject.Properties['changes']
            if ($null -ne $changesProperty -and $null -ne $changesProperty.Value) { foreach ($change in @($changesProperty.Value)) { foreach ($name in @('path','file_path','filePath')) { $property = $change.PSObject.Properties[$name]; if ($null -ne $property -and $null -ne $property.Value) { [void]$filePaths.Add((Convert-PfcRedactedText ([string]$property.Value))) } } } }
        }
        $usageProperty = $event.PSObject.Properties['usage']
        if ($type -eq 'turn.completed' -and $null -eq $usage -and $null -ne $usageProperty -and $null -ne $usageProperty.Value) { $usage = $usageProperty.Value }
    }
    [pscustomobject]@{
        event_types = @($eventTypes)
        tool_call_count = $toolCount
        command_count = $commandCount
        mcp_tool_call_count = $mcpToolCount
        web_search_count = $webSearchCount
        file_change_paths = @($filePaths)
        thread_started = $threadStarted
        turn_started = $turnStarted
        last_completed_agent_message = $lastCompletedAgentMessage
        final_agent_message = $lastCompletedAgentMessage
        turn_completed = $turnCompleted
        thread_started_at_utc = $threadStartedAt
        turn_started_at_utc = $turnStartedAt
        turn_failed = $turnFailed
        error_events = $errorCount
        transport_error_count = $transportErrorCount
        first_transport_error_at_utc = $firstTransportErrorAt
        last_transport_error_at_utc = $lastTransportErrorAt
        reconnect_attempts_observed = $reconnectAttempts
        last_non_error_event_received_at_utc = $lastNonErrorAt
        transport_status = if ($transportErrorCount -eq 0) { 'NONE' } elseif ($turnCompleted -and -not $turnFailed) { 'RECOVERED' } else { 'UNRECOVERED' }
        invalid_json_lines = $invalidJsonLines
        terminal_event_received_at_utc = $terminalAt
        last_jsonl_event_received_at_utc = $lastEventAt
        raw_lines = $rawLineCount
        turn_result = if ($turnFailed) { 'FAILED' } elseif ($turnCompleted -and $hadError) { 'COMPLETED_WITH_RECOVERED_ERRORS' } else { $turnResult }
        usage = if ($null -ne $usage) { $usage } else { 'NOT_AVAILABLE' }
        raw_result = $null
    }
}

function Get-PfcEvaluationArtifactReadCount {
    param(
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][string[]]$Lines,
        [Parameter(Mandatory = $true)][string]$ResultRoot
    )
    # Count only explicit path observations in event payloads.  If the event
    # stream exposes no path, report NOT_AVAILABLE instead of inventing zero.
    $root = [IO.Path]::GetFullPath($ResultRoot).TrimEnd('\')
    $observed = New-Object System.Collections.Generic.HashSet[string]([StringComparer]::OrdinalIgnoreCase)
    function Visit-PfcArtifactNode { param($Node)
        if ($null -eq $Node) { return }
        if ($Node -is [System.Collections.IEnumerable] -and -not ($Node -is [string])) { foreach ($child in $Node) { Visit-PfcArtifactNode $child }; return }
        if ($Node -is [psobject]) {
            foreach ($name in @('path','file_path','filePath')) {
                $p = $Node.PSObject.Properties[$name]
                if ($null -eq $p -or [string]::IsNullOrWhiteSpace([string]$p.Value)) { continue }
                try {
                    $full = [IO.Path]::GetFullPath([string]$p.Value).TrimEnd('\')
                    if ($full.Equals($root,[StringComparison]::OrdinalIgnoreCase) -or $full.StartsWith($root+'\',[StringComparison]::OrdinalIgnoreCase)) { [void]$observed.Add($full) }
                } catch { }
            }
            foreach ($prop in $Node.PSObject.Properties) {
                if ($prop.Name -in @('path','file_path','filePath')) { continue }
                if ($prop.Value -is [psobject] -or ($prop.Value -is [System.Collections.IEnumerable] -and -not ($prop.Value -is [string]))) { Visit-PfcArtifactNode $prop.Value }
            }
        }
    }
    foreach ($line in $Lines) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        try { $event = $line | ConvertFrom-Json } catch { continue }
        Visit-PfcArtifactNode $event
    }
    if ($observed.Count -eq 0) { return 'NOT_AVAILABLE' }
    return [int]$observed.Count
}

function Convert-PfcProcessArgument {
    param([AllowNull()][string]$Value)
    if ($null -eq $Value) { return '""' }
    if ($Value -notmatch '[\s"]') { return $Value }
    return '"' + (($Value -replace '(\\*)"', '$1$1\"') -replace '(\\+)$', '$1$1') + '"'
}

function Get-PfcSchemaProperty {
    param([AllowNull()]$Object,[Parameter(Mandatory = $true)][string]$Name)
    if ($null -eq $Object) { return $null }
    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) { return $null }
    return $property.Value
}

function Get-PfcStrictSchemaPreflight {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Path)
    $state = [ordered]@{
        strict_schema_preflight = 'FAIL'
        json_valid = $false
        utf8_no_bom = $false
        root_type_object = $false
        root_anyof_forbidden = $false
        object_count = 0
        objects_with_additional_properties_false = 0
        required_check = 'FAIL'
        unsupported_keywords = @()
        optional_fields_nullable = 'PASS'
    }
    $allowed = @('$schema','type','required','properties','additionalProperties','items','enum','pattern','anyOf','definitions','$defs','description')
    try {
        $bytes = [IO.File]::ReadAllBytes([IO.Path]::GetFullPath($Path))
        $state.utf8_no_bom = -not ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)
        $utf8 = New-Object System.Text.UTF8Encoding -ArgumentList @($false,$true)
        $schema = ConvertFrom-Json -InputObject $utf8.GetString($bytes)
        $state.json_valid = $true
        if ($null -eq $schema -or $schema -is [Array] -or $schema -is [ValueType] -or $schema -is [string]) { return [pscustomobject]$state }
        $state.root_type_object = ([string](Get-PfcSchemaProperty -Object $schema -Name 'type') -eq 'object')
        $state.root_anyof_forbidden = ($null -eq (Get-PfcSchemaProperty -Object $schema -Name 'anyOf'))
        $unsupported = New-Object System.Collections.Generic.List[string]
        $stats = @{ requiredOK = $true; objectsOK = $true; nullableOK = $true; count = 0; falseCount = 0 }
        function Visit-PfcStrictNode { param($Node,[hashtable]$Stats,[bool]$IsRoot = $false)
            if ($null -eq $Node -or $Node -is [ValueType] -or $Node -is [string]) { return }
            foreach ($prop in $Node.PSObject.Properties) { if ($allowed -notcontains $prop.Name -and -not $unsupported.Contains($prop.Name)) { [void]$unsupported.Add($prop.Name) } }
            $type = Get-PfcSchemaProperty -Object $Node -Name 'type'
            $types = if ($type -is [Array]) { @($type | ForEach-Object { [string]$_ }) } else { @([string]$type) }
            if ($types -contains 'object') {
                $Stats.count++
                if ((Get-PfcSchemaProperty -Object $Node -Name 'additionalProperties') -ne $false) { $Stats.objectsOK = $false } else { $Stats.falseCount++ }
                $props = Get-PfcSchemaProperty -Object $Node -Name 'properties'; $req = @(Get-PfcSchemaProperty -Object $Node -Name 'required')
                if ($null -eq $props) { if ($req.Count -gt 0) { $Stats.requiredOK = $false } }
                else { foreach ($p in $props.PSObject.Properties) {
                        $pt = Get-PfcSchemaProperty -Object $p.Value -Name 'type'; $ptypes = if ($pt -is [Array]) { @($pt | ForEach-Object { [string]$_ }) } else { @([string]$pt) }
                        if ($req -notcontains $p.Name) { $Stats.requiredOK = $false; if ($ptypes -notcontains 'null') { $Stats.nullableOK = $false } }
                        Visit-PfcStrictNode $p.Value $Stats $false
                    } }
            }
            $items = Get-PfcSchemaProperty -Object $Node -Name 'items'; if ($null -ne $items) { Visit-PfcStrictNode $items $Stats $false }
            $anyOf = Get-PfcSchemaProperty -Object $Node -Name 'anyOf'; if ($null -ne $anyOf) { foreach ($entry in @($anyOf)) { Visit-PfcStrictNode $entry $Stats $false } }
            foreach ($branchName in @('definitions','$defs')) { $branch = Get-PfcSchemaProperty -Object $Node -Name $branchName; if ($null -ne $branch) { foreach ($definition in $branch.PSObject.Properties) { Visit-PfcStrictNode $definition.Value $Stats $false } } }
        }
        Visit-PfcStrictNode $schema $stats $true
        $state.object_count = $stats.count; $state.objects_with_additional_properties_false = $stats.falseCount
        $state.required_check = if ($stats.requiredOK) { 'PASS' } else { 'FAIL' }
        $state.unsupported_keywords = @($unsupported | Sort-Object -Unique)
        $state.optional_fields_nullable = if ($stats.nullableOK) { 'PASS' } else { 'FAIL' }
        if ($state.json_valid -and $state.utf8_no_bom -and $state.root_type_object -and $state.root_anyof_forbidden -and $stats.objectsOK -and $stats.requiredOK -and $stats.nullableOK -and $state.unsupported_keywords.Count -eq 0) { $state.strict_schema_preflight = 'PASS' }
    } catch { $state.strict_schema_preflight = 'FAIL' }
    return [pscustomobject]$state
}

function Test-PfcSchemaValue {
    param([AllowNull()]$Value,[Parameter(Mandatory = $true)]$Schema)
    $schemaType = Get-PfcSchemaProperty -Object $Schema -Name 'type'
    $schemaEnum = Get-PfcSchemaProperty -Object $Schema -Name 'enum'
    $schemaRequired = Get-PfcSchemaProperty -Object $Schema -Name 'required'
    $schemaProperties = Get-PfcSchemaProperty -Object $Schema -Name 'properties'
    $schemaAdditional = Get-PfcSchemaProperty -Object $Schema -Name 'additionalProperties'
    $schemaItems = Get-PfcSchemaProperty -Object $Schema -Name 'items'
    $schemaPattern = Get-PfcSchemaProperty -Object $Schema -Name 'pattern'
    if ($null -ne $schemaEnum) {
        $match = $false
        foreach ($allowed in @($schemaEnum)) { if ($null -eq $Value -and $null -eq $allowed) { $match = $true } elseif ($null -ne $Value -and ([string]$Value -ceq [string]$allowed)) { $match = $true } }
        if (-not $match) { return $false }
    }
    if ($null -eq $Value) { return ($schemaType -eq 'null' -or ($schemaType -is [Array] -and @($schemaType) -contains 'null') -or $null -eq $schemaType) }
    if ($schemaType -is [Array]) { foreach ($candidateType in @($schemaType)) { if (Test-PfcSchemaValue -Value $Value -Schema ([pscustomobject]@{ type = [string]$candidateType })) { return $true } }; return $false }
    switch ([string]$schemaType) {
        'object' {
            if ($Value -is [string] -or $Value -is [ValueType] -or $Value -is [Array]) { return $false }
            if ($null -ne $schemaRequired) { foreach ($name in @($schemaRequired)) { if ($null -eq $Value.PSObject.Properties[[string]$name]) { return $false } } }
            if ($null -ne $schemaProperties) {
                foreach ($property in $schemaProperties.PSObject.Properties) {
                    $actual = $Value.PSObject.Properties[$property.Name]
                    if ($null -ne $actual -and -not (Test-PfcSchemaValue -Value $actual.Value -Schema $property.Value)) { return $false }
                }
            }
            if ($schemaAdditional -eq $false) {
                # With no declared properties, additionalProperties=false means
                # that the object must be empty.  Keep this check independent of
                # the properties branch so the strict schema is enforced even
                # when the schema omits a properties member entirely.
                $allowed = if ($null -ne $schemaProperties) { @($schemaProperties.PSObject.Properties.Name) } else { @() }
                foreach ($actual in $Value.PSObject.Properties) { if ($allowed -notcontains $actual.Name) { return $false } }
            }
            return $true
        }
        'array' {
            if ($Value -isnot [Array]) { return $false }
            if ($null -ne $schemaItems) { foreach ($entry in $Value) { if (-not (Test-PfcSchemaValue -Value $entry -Schema $schemaItems)) { return $false } } }
            return $true
        }
        'string' {
            if ($Value -isnot [string]) { return $false }
            if ($schemaPattern -and ([string]$Value -notmatch [string]$schemaPattern)) { return $false }
            return $true
        }
        'boolean' { return ($Value -is [bool]) }
        'integer' { return ($Value -is [int] -or $Value -is [long] -or $Value -is [short] -or $Value -is [byte]) }
        'number' { return ($Value -is [ValueType] -and $Value -isnot [bool] -and $Value -isnot [char]) }
        default { return $true }
    }
}

function Test-PfcSchemaShape {
    param([AllowNull()]$Value,[Parameter(Mandatory = $true)][string]$SchemaPath)
    try { $schemaText = Read-PfcUtf8TextStrict -Path $SchemaPath; $schema = ConvertFrom-Json -InputObject $schemaText } catch { return $false }
    return (Test-PfcSchemaValue -Value $Value -Schema $schema)
}

function Convert-PfcStructuredMetrics {
    param([AllowNull()]$Metrics)
    $normalized = [ordered]@{}
    if ($null -eq $Metrics) { return [pscustomobject]$normalized }
    $entries = $null
    if ($Metrics -is [Array]) { $entries = @($Metrics) }
    elseif ($Metrics.PSObject.Properties['key'] -and $Metrics.PSObject.Properties['value']) { $entries = @($Metrics) }
    if ($null -ne $entries) {
        foreach ($entry in $entries) {
            if ($null -eq $entry) { continue }
            $key = Get-PfcSchemaProperty -Object $entry -Name 'key'; if ([string]::IsNullOrWhiteSpace([string]$key)) { continue }
            if ($normalized.Contains([string]$key)) { throw ('Duplicate structured metric key: ' + [string]$key) }
            $value = Get-PfcSchemaProperty -Object $entry -Name 'value'
            $normalized[[string]$key] = if ($null -eq $value) { 'NOT_AVAILABLE' } else { $value }
        }
    } else {
        foreach ($property in $Metrics.PSObject.Properties) { $normalized[$property.Name] = if ($null -eq $property.Value) { 'NOT_AVAILABLE' } else { $property.Value } }
    }
    return [pscustomobject]$normalized
}

function Write-PfcUtf8NoBom {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Content
    )
    try {
        $fullPath = [IO.Path]::GetFullPath($Path)
        $parent = Split-Path -Parent $fullPath
        if ([string]::IsNullOrWhiteSpace($parent)) { throw 'Target parent directory is missing.' }
        if (-not (Test-Path -LiteralPath $parent -PathType Container)) {
            New-Item -ItemType Directory -Path $parent -Force | Out-Null
        }
        # Windows PowerShell 5.1's Set-Content -Encoding UTF8 emits a BOM.
        # Use UTF8Encoding(false) explicitly for every dynamically generated
        # schema passed to --output-schema.
        $encoding = New-Object System.Text.UTF8Encoding -ArgumentList @($false)
        [IO.File]::WriteAllText($fullPath, [string]$Content, $encoding)
    } catch {
        throw 'Write-PfcUtf8NoBom failed.'
    }
}

function Read-PfcUtf8TextStrict {
    param([Parameter(Mandatory = $true)][string]$Path)
    $utf8 = New-Object -TypeName System.Text.UTF8Encoding -ArgumentList @($false,$true)
    $text = $utf8.GetString([IO.File]::ReadAllBytes($Path))
    if ($text.Length -gt 0 -and [int][char]$text[0] -eq 0xFEFF) { $text = $text.Substring(1) }
    return $text
}

function Get-PfcSchemaPreflight {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Path)
    $state = [ordered]@{
        schema_exists = $false
        schema_bytes = 0
        schema_has_utf8_bom = $false
        schema_first_non_whitespace_byte = $null
        schema_json_valid = $false
        schema_root_type = $null
        schema_preflight_result = 'FAIL'
        strict_schema_preflight = 'FAIL'
    }
    try {
        if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return [pscustomobject]$state }
        $state.schema_exists = $true
        $bytes = [IO.File]::ReadAllBytes([IO.Path]::GetFullPath($Path))
        $state.schema_bytes = $bytes.Length
        if ($bytes.Length -ge 3 -and [int]$bytes[0] -eq 0xEF -and [int]$bytes[1] -eq 0xBB -and [int]$bytes[2] -eq 0xBF) {
            $state.schema_has_utf8_bom = $true
        }
        foreach ($byte in $bytes) {
            $value = [int]$byte
            if ($value -notin @(0x09,0x0A,0x0D,0x20)) {
                $state.schema_first_non_whitespace_byte = ('0x{0:X2}' -f $value)
                break
            }
        }
        if ($state.schema_bytes -le 0 -or $state.schema_has_utf8_bom -or $state.schema_first_non_whitespace_byte -ne '0x7B') { return [pscustomobject]$state }
        $utf8 = New-Object System.Text.UTF8Encoding -ArgumentList @($false,$true)
        $schemaText = $utf8.GetString($bytes)
        $schema = ConvertFrom-Json -InputObject $schemaText
        if ($null -eq $schema -or $schema -is [Array] -or $schema -is [ValueType] -or $schema -is [string]) {
            $state.schema_root_type = if ($null -eq $schema) { 'null' } elseif ($schema -is [Array]) { 'array' } elseif ($schema -is [string]) { 'string' } else { 'scalar' }
            return [pscustomobject]$state
        }
        $state.schema_json_valid = $true
        $state.schema_root_type = 'object'
        $strict = Get-PfcStrictSchemaPreflight -Path $Path
        $state.strict_schema_preflight = $strict.strict_schema_preflight
        $state.schema_preflight_result = if ($strict.strict_schema_preflight -eq 'PASS') { 'PASS' } else { 'FAIL' }
    } catch {
        # Keep preflight fail-closed without returning file contents or paths.
        $state.schema_preflight_result = 'FAIL'
    }
    return [pscustomobject]$state
}

function Get-PfcAgentMessageText {
    param([AllowNull()]$Item)
    if ($null -eq $Item) { return $null }
    foreach ($name in @('text','message','content')) {
        $p = $Item.PSObject.Properties[$name]
        if ($null -eq $p -or $null -eq $p.Value) { continue }
        if ($p.Value -is [string] -and -not [string]::IsNullOrWhiteSpace([string]$p.Value)) { return [string]$p.Value }
        if ($p.Value -is [Array]) { foreach ($part in $p.Value) { $text = Get-PfcAgentMessageText -Item $part; if ($text) { return $text } } }
    }
    return $null
}

function Get-PfcRawFinalAgentMessage {
    param([Parameter(Mandatory = $true)][AllowEmptyCollection()][string[]]$Lines)
    $terminalSeen = $false
    $last = $null
    foreach ($line in $Lines) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        try { $event = $line | ConvertFrom-Json } catch { continue }
        if ($null -eq $event.type) { continue }
        if ([string]$event.type -eq 'turn.completed') { $terminalSeen = $true; continue }
        if ($terminalSeen -or [string]$event.type -ne 'item.completed') { continue }
        $itemProperty = $event.PSObject.Properties['item']
        if ($null -eq $itemProperty -or $null -eq $itemProperty.Value) { continue }
        $typeProperty = $itemProperty.Value.PSObject.Properties['type']
        if ($null -eq $typeProperty -or [string]$typeProperty.Value -ne 'agent_message') { continue }
        $text = Get-PfcAgentMessageText -Item $itemProperty.Value
        if (-not [string]::IsNullOrWhiteSpace([string]$text)) { $last = [string]$text }
    }
    return $last
}

function Stop-PfcProcessTree {
    param([Parameter(Mandatory = $true)][int]$ProcessId)
    try { & taskkill.exe /PID $ProcessId /T /F 2>$null | Out-Null } catch { }
}

function Throw-PfcRevision3Failure {
    param(
        [Parameter(Mandatory = $true)][ValidatePattern('^INVALID_[A-Z0-9_]+$')][string]$Classification,
        [Parameter(Mandatory = $true)][string]$Message
    )
    # Preserve the established message for callers while exposing a stable,
    # machine-readable fail-closed classification on the exception itself.
    $exception = New-Object System.InvalidOperationException($Message)
    [void]$exception.Data.Add('classification', $Classification)
    throw $exception
}

# Deterministic lifecycle model used by the no-model contract tests.  The
# production runner below follows the same state transitions, but this helper
# lets tests advance time without sleeping or starting a process.
function Invoke-PfcRunnerLifecycle {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][object[]]$Events,
        [int]$StartupTimeoutSeconds = 90,
        [int]$PreTerminalTimeoutSeconds = 600,
        [int]$PostTerminalGraceSeconds = 15,
        [bool]$ProcessCreated = $true,
        [bool]$RawWritable = $true,
        [AllowNull()][object]$Output = $null,
        [ValidateSet('','INVALID_SCHEMA','INVALID_NORMALIZATION','INVALID_FIXTURE_BINDING','INVALID_WORKTREE_CONTAMINATION','INVALID_PROCESS_CLEANUP')][string]$ForcedClassification = ''
    )
    $ordered = @($Events | Sort-Object { [double]$_.at_seconds })
    $threadStarted = $false; $turnStarted = $false; $terminal = $null
    $lastMessage = $null; $errors = 0; $turnStartedAt = $null; $terminalAt = $null
    foreach ($event in $ordered) {
        $at = [double]$event.at_seconds
        if (-not $turnStarted -and $at -gt $StartupTimeoutSeconds) { break }
        if ($turnStarted -and $null -eq $terminal -and $at -gt ($turnStartedAt + $PreTerminalTimeoutSeconds)) { break }
        switch ([string]$event.type) {
            'thread.started' { $threadStarted = $true }
            'turn.started' { if (-not $turnStarted) { $turnStarted = $true; $turnStartedAt = $at } }
            'error' { $errors++ }
            'item.completed' {
                if ($null -eq $terminal -and [string]$event.item_type -eq 'agent_message' -and -not [string]::IsNullOrWhiteSpace([string]$event.message)) { $lastMessage = [string]$event.message }
            }
            'turn.failed' { $terminal = 'turn.failed'; $terminalAt = $at; break }
            'turn.completed' { if ($null -eq $terminal) { $terminal = 'turn.completed'; $terminalAt = $at } }
        }
        if ($null -ne $terminal) { break }
    }
    $lastAt = if ($ordered.Count -gt 0) { [double]$ordered[-1].at_seconds } else { 0 }
    $classification = $null
    if ($ForcedClassification) { $classification = $ForcedClassification }
    elseif (-not $ProcessCreated -or -not $RawWritable -or -not $threadStarted -or -not $turnStarted) { $classification = 'INVALID_STARTUP_TIMEOUT' }
    elseif ($null -eq $terminal) { $classification = 'INVALID_PRE_TERMINAL_TIMEOUT' }
    elseif ($terminal -eq 'turn.failed') { $classification = 'INVALID_TURN_FAILED' }
    elseif ($Output -is [hashtable] -and $Output.ContainsKey('schema_valid') -and $Output['schema_valid'] -eq $false) { $classification = 'INVALID_SCHEMA' }
    elseif ($Output -is [hashtable] -and $Output.ContainsKey('normalization_valid') -and $Output['normalization_valid'] -eq $false) { $classification = 'INVALID_NORMALIZATION' }
    else { $classification = 'VALID' }
    $graceDeadline = if ($terminal -eq 'turn.completed') { $terminalAt + $PostTerminalGraceSeconds } else { $null }
    $outputAt = if ($Output -is [hashtable] -and $Output.ContainsKey('output_at_seconds') -and $null -ne $Output['output_at_seconds']) { [double]$Output['output_at_seconds'] } else { $null }
    $outputValid = -not ($Output -is [hashtable] -and $Output.ContainsKey('schema_valid') -and $Output['schema_valid'] -eq $false)
    $degraded = ($terminal -eq 'turn.completed' -and $null -ne $outputAt -and $outputAt -gt $graceDeadline)
    $outputSource = if ($null -ne $outputAt -and $outputValid) { 'OUTPUT_LAST_MESSAGE_FILE' } elseif ($lastMessage) { 'JSONL_FINAL_AGENT_MESSAGE_FALLBACK' } else { 'NONE' }
    [pscustomobject]@{
        classification = $classification
        process_count = 1
        automatic_retries = 0
        process_created = $ProcessCreated
        raw_jsonl_writable = $RawWritable
        thread_started = $threadStarted
        turn_started = $turnStarted
        turn_started_at_seconds = $turnStartedAt
        terminal = $terminal
        terminal_at_seconds = $terminalAt
        last_completed_agent_message = $lastMessage
        recovered_errors = if ($terminal -eq 'turn.completed' -and $errors -gt 0) { $true } else { $false }
        transport_status = if ($errors -eq 0) { 'NONE' } elseif ($terminal -eq 'turn.completed') { 'RECOVERED' } else { 'UNRECOVERED' }
        startup_timeout_seconds = $StartupTimeoutSeconds
        pre_terminal_timeout_seconds = $PreTerminalTimeoutSeconds
        post_terminal_grace_seconds = $PostTerminalGraceSeconds
        idle_timeout = 'DISABLED'
        grace_deadline_seconds = $graceDeadline
        output_source = $outputSource
        local_finalization = if ($degraded) { 'DEGRADED' } else { 'NORMAL' }
        process_cleanup = if ($degraded) { 'SAFE_TERMINATE' } elseif ($classification -eq 'VALID' -and $terminal -eq 'turn.completed') { 'NORMAL' } else { 'SAFE_TERMINATE' }
    }
}

function Invoke-PfcRealCodexProcess {
    param(
        [Parameter(Mandatory = $true)][string[]]$Arguments,
        [Parameter(Mandatory = $true)][string]$WorkingDirectory,
        [Parameter(Mandatory = $true)][string]$RawPath,
        [Parameter(Mandatory = $true)][string]$OutputPath,
        [Parameter(Mandatory = $true)][int]$TimeoutSeconds,
        [int]$StartupTimeoutSeconds = 90,
        [Parameter(Mandatory = $true)][int]$PostTerminalGraceSeconds,
        [AllowNull()][string]$CodexExecutablePath,
        [AllowNull()][hashtable]$EnvironmentOverrides,
        [scriptblock]$ClockProvider,
        [scriptblock]$SleepProvider
    )
    $command = if ($CodexExecutablePath) { Get-Item -LiteralPath $CodexExecutablePath -ErrorAction Stop } else { Get-Command codex -ErrorAction Stop }
    $si = New-Object System.Diagnostics.ProcessStartInfo
    $executable = if ($null -ne $command.PSObject.Properties['Path']) { [string]$command.Path } elseif ($null -ne $command.PSObject.Properties['Source']) { [string]$command.Source } else { [string]$command.FullName }
    if ($executable -match '(?i)\.(cmd|bat)$') {
        $si.FileName = $env:ComSpec
        $si.Arguments = '/d /c ""' + $executable + '" ' + (($Arguments | ForEach-Object { Convert-PfcProcessArgument ([string]$_) }) -join ' ') + '"'
    } else {
        $si.FileName = $executable
        $si.Arguments = (($Arguments | ForEach-Object { Convert-PfcProcessArgument ([string]$_) }) -join ' ')
    }
    $si.WorkingDirectory = $WorkingDirectory
    $si.UseShellExecute = $false
    $si.CreateNoWindow = $true
    $si.RedirectStandardInput = $true
    $si.RedirectStandardOutput = $true
    $si.RedirectStandardError = $true
    if ($null -ne $EnvironmentOverrides) {
        foreach ($key in $EnvironmentOverrides.Keys) {
            if ([string]::IsNullOrWhiteSpace([string]$key)) { throw 'Environment override key is empty.' }
            $si.EnvironmentVariables[[string]$key] = [string]$EnvironmentOverrides[$key]
        }
    }
    New-Item -ItemType Directory -Path (Split-Path -Parent $RawPath) -Force | Out-Null
    New-Item -ItemType Directory -Path (Split-Path -Parent $OutputPath) -Force | Out-Null
    [IO.File]::WriteAllText($RawPath, '', (New-Object Text.UTF8Encoding($false)))
    # Raw stdout is copied byte-for-byte.  A line reader would normalize CRLF,
    # drop a final unterminated line ending, and therefore corrupt evidence.
    $rawStream = New-Object IO.FileStream($RawPath, ([IO.FileMode]::Create), ([IO.FileAccess]::Write), ([IO.FileShare]::Read))
    $stderrPath = [IO.Path]::ChangeExtension($RawPath, '.stderr.txt')
    $eventsPath = [IO.Path]::ChangeExtension($RawPath, '.events.jsonl')
    $eventWriter = New-Object IO.StreamWriter($eventsPath, $false, (New-Object Text.UTF8Encoding($false)))
    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $si
    $stdoutLines = New-Object System.Collections.Generic.List[string]
    $stderrBuilder = New-Object Text.StringBuilder
    $started = $false
    $forcedAfterTerminal = $false
    $terminalReceivedAt = $null
    $processExitedAt = $null
    $threadStarted = $false
    $turnStarted = $false
    try {
        [void]$process.Start()
        $started = $true
        # Codex must receive EOF immediately; prompts are passed as an argument.
        $process.StandardInput.Close()
        $readBuffer = New-Object byte[] 8192
        $stdoutTask = $process.StandardOutput.BaseStream.ReadAsync($readBuffer, 0, $readBuffer.Length)
        # stderr is drained as a whole so a large unterminated diagnostic cannot block the pipe.
        $stderrTask = $process.StandardError.ReadToEndAsync()
        $stdoutDone = $false; $stderrDone = $false
        $now = if ($ClockProvider) { [DateTime](& $ClockProvider) } else { [DateTime]::UtcNow }
        $startupDeadline = $now.AddSeconds($StartupTimeoutSeconds)
        $deadline = $null
        $graceDeadline = $null; $lineNumber = 0; $eventTimes = New-Object System.Collections.Generic.List[string]
        $lineBuffer = New-Object IO.MemoryStream
        $utf8Strict = New-Object Text.UTF8Encoding($false, $true)
        $terminalType = $null
        while (-not $stdoutDone -or -not $stderrDone -or -not $process.HasExited -or ($null -ne $graceDeadline -and -not (Test-Path -LiteralPath $OutputPath -PathType Leaf))) {
            if (-not $stdoutDone -and $stdoutTask.IsCompleted) {
                $bytesRead = [int]$stdoutTask.Result
                if ($bytesRead -le 0) {
                    $stdoutDone = $true
                } else {
                    $rawStream.Write($readBuffer, 0, $bytesRead)
                    $rawStream.Flush()
                    for ($byteIndex = 0; $byteIndex -lt $bytesRead; $byteIndex++) {
                        $byteValue = [int]$readBuffer[$byteIndex]
                        $lineBuffer.WriteByte([byte]$byteValue)
                        if ($byteValue -ne 0x0A) { continue }
                        $lineBytes = $lineBuffer.ToArray()
                        $lineBuffer.SetLength(0)
                        if ($lineBytes.Length -gt 0 -and $lineBytes[$lineBytes.Length - 1] -eq 0x0A) {
                            $lineBytes = $lineBytes[0..($lineBytes.Length - 2)]
                        }
                        if ($lineBytes.Length -gt 0 -and $lineBytes[$lineBytes.Length - 1] -eq 0x0D) {
                            $lineBytes = $lineBytes[0..($lineBytes.Length - 2)]
                        }
                        try { $line = $utf8Strict.GetString($lineBytes) } catch { $line = $utf8Strict.GetString($lineBytes) }
                        $lineNumber++; $receivedAt = if ($ClockProvider) { [DateTime](& $ClockProvider) } else { [DateTime]::UtcNow }; $received = $receivedAt.ToString('o'); [void]$stdoutLines.Add([string]$line)
                        $eventType = 'unparsed'; try { $eventType = [string](($line | ConvertFrom-Json).type) } catch { }
                        if (-not [string]::IsNullOrWhiteSpace($line)) { [void]$eventTimes.Add($received) }
                        $eventWriter.WriteLine((@{line_no=$lineNumber;type=$eventType;received_at_utc=$received} | ConvertTo-Json -Compress)); $eventWriter.Flush()
                        if ($null -eq $deadline -and $receivedAt -gt $startupDeadline) { Stop-PfcProcessTree -ProcessId $process.Id; Throw-PfcRevision3Failure -Classification 'INVALID_STARTUP_TIMEOUT' -Message ('INVALID_STARTUP_TIMEOUT: startup events arrived after ' + $StartupTimeoutSeconds + ' seconds.') }
                        if ($eventType -eq 'thread.started') { $threadStarted = $true }
                        if ($eventType -eq 'turn.started' -and $null -eq $deadline) {
                            if (-not $threadStarted) { Stop-PfcProcessTree -ProcessId $process.Id; Throw-PfcRevision3Failure -Classification 'INVALID_STARTUP_TIMEOUT' -Message 'INVALID_STARTUP_TIMEOUT: turn.started arrived before thread.started.' }
                            $turnStarted = $true; $deadline = $receivedAt.AddSeconds($TimeoutSeconds)
                        }
                        if ($eventType -eq 'turn.completed' -and $null -eq $terminalReceivedAt) { $terminalReceivedAt = $received; $terminalType = 'turn.completed'; $graceDeadline = $receivedAt.AddSeconds($PostTerminalGraceSeconds) }
                        if ($eventType -eq 'turn.failed') { if ($null -eq $terminalReceivedAt) { $terminalReceivedAt = $received }; $terminalType = 'turn.failed'; Stop-PfcProcessTree -ProcessId $process.Id; $forcedAfterTerminal = $true; break }
                    }
                    if ($terminalType -eq 'turn.failed') { break }
                    if ($stdoutDone) { break }
                    $stdoutTask = $process.StandardOutput.BaseStream.ReadAsync($readBuffer, 0, $readBuffer.Length)
                }
            }
            if (-not $stderrDone -and $stderrTask.IsCompleted) {
                $stderrText = $stderrTask.Result
                if ($null -ne $stderrText) { [void]$stderrBuilder.Append([string]$stderrText) }
                $stderrDone = $true
            }
            $now = if ($ClockProvider) { [DateTime](& $ClockProvider) } else { [DateTime]::UtcNow }
            if ($process.HasExited -and $null -eq $processExitedAt) { $processExitedAt = $now.ToString('o') }
            if ($null -ne $graceDeadline) {
                if ($now -gt $graceDeadline) { if (-not $process.HasExited) { Stop-PfcProcessTree -ProcessId $process.Id; $forcedAfterTerminal = $true }; break }
            } elseif ($null -ne $deadline -and $now -gt $deadline) { Stop-PfcProcessTree -ProcessId $process.Id; Throw-PfcRevision3Failure -Classification 'INVALID_PRE_TERMINAL_TIMEOUT' -Message ('INVALID_PRE_TERMINAL_TIMEOUT: Codex run timed out after ' + $TimeoutSeconds + ' seconds.')
            } elseif ($null -eq $deadline -and $now -gt $startupDeadline) { Stop-PfcProcessTree -ProcessId $process.Id; Throw-PfcRevision3Failure -Classification 'INVALID_STARTUP_TIMEOUT' -Message ('INVALID_STARTUP_TIMEOUT: process did not emit thread.started and turn.started within ' + $StartupTimeoutSeconds + ' seconds.') }
            if ($SleepProvider) { & $SleepProvider 20 } else { Start-Sleep -Milliseconds 20 }
        }
        if ($null -ne $lineBuffer -and $lineBuffer.Length -gt 0) {
            $lineBytes = $lineBuffer.ToArray()
            try { $line = $utf8Strict.GetString($lineBytes) } catch { $line = $utf8Strict.GetString($lineBytes) }
            $lineNumber++; $receivedAt = if ($ClockProvider) { [DateTime](& $ClockProvider) } else { [DateTime]::UtcNow }; $received = $receivedAt.ToString('o'); [void]$stdoutLines.Add([string]$line)
            $eventType = 'unparsed'; try { $eventType = [string](($line | ConvertFrom-Json).type) } catch { }
            if (-not [string]::IsNullOrWhiteSpace($line)) { [void]$eventTimes.Add($received) }
            $eventWriter.WriteLine((@{line_no=$lineNumber;type=$eventType;received_at_utc=$received} | ConvertTo-Json -Compress)); $eventWriter.Flush()
            if ($null -eq $deadline -and $receivedAt -gt $startupDeadline) { Stop-PfcProcessTree -ProcessId $process.Id; Throw-PfcRevision3Failure -Classification 'INVALID_STARTUP_TIMEOUT' -Message ('INVALID_STARTUP_TIMEOUT: startup events arrived after ' + $StartupTimeoutSeconds + ' seconds.') }
            if ($eventType -eq 'thread.started') { $threadStarted = $true }
            if ($eventType -eq 'turn.started' -and $null -eq $deadline) {
                if (-not $threadStarted) { Stop-PfcProcessTree -ProcessId $process.Id; Throw-PfcRevision3Failure -Classification 'INVALID_STARTUP_TIMEOUT' -Message 'INVALID_STARTUP_TIMEOUT: turn.started arrived before thread.started.' }
                $turnStarted = $true; $deadline = $receivedAt.AddSeconds($TimeoutSeconds)
            }
            if ($eventType -eq 'turn.completed' -and $null -eq $terminalReceivedAt) { $terminalReceivedAt = $received; $terminalType = 'turn.completed'; $graceDeadline = $receivedAt.AddSeconds($PostTerminalGraceSeconds) }
        }
        if (-not $process.HasExited) { Stop-PfcProcessTree -ProcessId $process.Id; $forcedAfterTerminal = $true }
        try { $process.WaitForExit(1000) | Out-Null } catch { }
        if ($process.HasExited -and $null -eq $processExitedAt) { $processExitedAt = [DateTime]::UtcNow.ToString('o') }
        if ($terminalType -eq 'turn.failed') { Throw-PfcRevision3Failure -Classification 'INVALID_TURN_FAILED' -Message 'INVALID_TURN_FAILED: Codex reported a failed turn.' }
        if (-not $threadStarted -or -not $turnStarted) { Throw-PfcRevision3Failure -Classification 'INVALID_STARTUP_TIMEOUT' -Message ('INVALID_STARTUP_TIMEOUT: Codex startup timed out; process did not emit thread.started and turn.started within ' + $StartupTimeoutSeconds + ' seconds.') }
        [pscustomobject]@{ ExitCode = if ($process.HasExited) { $process.ExitCode } else { 0 }; StdOut = ($stdoutLines -join "`n"); StdErr = $stderrBuilder.ToString(); OutputPath = $OutputPath; StdErrPath = $stderrPath; EventsPath = $eventsPath; EventTimes = $eventTimes.ToArray(); TerminalReceivedAtUtc = $terminalReceivedAt; TerminalType = $terminalType; ProcessExitedAtUtc = $processExitedAt; ForcedAfterTerminal = $forcedAfterTerminal; LocalFinalization = if ($forcedAfterTerminal) { 'DEGRADED' } else { 'NORMAL' }; ProcessCleanup = if ($forcedAfterTerminal) { 'FORCED_AFTER_TERMINAL' } else { 'NORMAL' }; ProcessCleanupValid = $true; ProcessCount = 1 }
    } finally {
        if ($started -and -not $process.HasExited) { Stop-PfcProcessTree -ProcessId $process.Id }
        try { [IO.File]::WriteAllText($stderrPath, (Convert-PfcRedactedText $stderrBuilder.ToString()), (New-Object Text.UTF8Encoding($false))) } catch { }
        try { $rawStream.Dispose() } catch { }
        $eventWriter.Dispose(); $process.Dispose()
    }
}

function Invoke-PfcCodexRun {
    param(
        [Parameter(Mandatory = $true)][string]$WorkingDirectory,
        [Parameter(Mandatory = $true)][string]$PromptPath,
        [AllowNull()][string]$TreatmentPromptPath,
        [AllowNull()][string]$OutputSchemaPath,
        [Parameter(Mandatory = $true)][ValidateSet('workspace-write','read-only')][string]$SandboxMode,
        [Parameter(Mandatory = $true)][string]$ResultDirectory,
        [Parameter(Mandatory = $true)][ValidateSet('RED','GREEN')][string]$Phase,
        [ValidatePattern('^[A-Za-z0-9._-]+$')][string]$Model,
        [ValidateSet('none','minimal','low','medium','high','xhigh','max','ultra')][string]$ReasoningEffort,
        [ValidateRange(1,3600)][int]$TimeoutSeconds = 600,
        [ValidateRange(1,600)][int]$StartupTimeoutSeconds = 90,
        [ValidateRange(1,300)][int]$PostTerminalGraceSeconds = 15,
        [switch]$Ephemeral,
        [switch]$IgnoreUserConfig,
        [switch]$IgnoreRules,
        [switch]$SkipGitRepoCheck,
        [switch]$DisableWebSearch,
        [AllowNull()][int]$ProjectDocMaxBytes,
        [AllowNull()][string]$CodexExecutablePath,
        [AllowNull()][hashtable]$EnvironmentOverrides,
        [switch]$RequireExternalResultDirectory,
        [ValidateSet('CONTROLLED_EFFICACY','OPERATIONAL_PROFILE')][string]$Track = 'CONTROLLED_EFFICACY',
        [ValidatePattern('^[A-Za-z0-9._-]+$')][string]$SampleId,
        [ValidatePattern('^EFF-0[1-7]$')][string]$Scenario,
        [ValidateRange(1,5)][int]$Repetition = 1,
        [ValidateRange(1,99)][int]$EvalContractRevision = 4,
        [ValidateRange(1,99)][int]$FormalSchemaRevision = 2,
        [AllowNull()][string]$ProfileFingerprint,
        [Alias('PermissionProfile')][AllowNull()][string]$PermissionProfileName,
        [Alias('PermissionConfigPath','ConfigPath')][AllowNull()][string]$PermissionProfileConfigPath,
        [AllowNull()][string]$InstructionSourceManifestHash,
        [AllowNull()][string]$FixtureId,
        [AllowNull()][string]$FixtureBaseSha,
        [AllowNull()][string]$NormalizerVersion = 'R2',
        [scriptblock]$ProcessInvoker,
        [scriptblock]$ClockProvider,
        [scriptblock]$SleepProvider
    )
    if (-not (Test-Path -LiteralPath $WorkingDirectory -PathType Container)) { throw 'Working directory is missing.' }
    if (-not (Test-Path -LiteralPath $PromptPath -PathType Leaf)) { throw 'Prompt file is missing.' }
    $hasSchema = -not [string]::IsNullOrWhiteSpace([string]$OutputSchemaPath)
    if ($hasSchema) {
        $schemaPreflight = Get-PfcSchemaPreflight -Path $OutputSchemaPath
        if ($schemaPreflight.schema_preflight_result -ne 'PASS') { Throw-PfcRevision3Failure -Classification 'INVALID_SCHEMA' -Message 'LOCAL_SCHEMA_PREFLIGHT_FAILED' }
    }
    if ($SandboxMode -eq 'danger-full-access') { throw 'Unsafe sandbox mode refused.' }
    $customPermission = -not [string]::IsNullOrWhiteSpace($PermissionProfileName)
    if ($customPermission -and [string]::IsNullOrWhiteSpace($PermissionProfileConfigPath)) { throw 'Permission profile config path is required.' }
    if (-not $customPermission -and -not [string]::IsNullOrWhiteSpace($PermissionProfileConfigPath)) { throw 'Permission profile name is required with config path.' }
    if ($customPermission -and $IgnoreUserConfig) { throw 'IgnoreUserConfig cannot be combined with a controlled permission profile.' }
    if ($customPermission) {
        if (-not (Test-Path -LiteralPath $PermissionProfileConfigPath -PathType Leaf)) { throw 'Permission profile config is missing.' }
        if (Test-PfcReparsePath -Path $PermissionProfileConfigPath) { Throw-PfcRevision3Failure -Classification 'INVALID_WORKTREE_CONTAMINATION' -Message 'Permission profile config traverses a reparse point.' }
        $profileCodexHome = [IO.Path]::GetFullPath((Split-Path -Parent $PermissionProfileConfigPath)).TrimEnd('\')
        $profileRoot = Split-Path -Parent $profileCodexHome
        $controlledEnvironment = @{}
        if ($null -ne $EnvironmentOverrides) { foreach ($key in $EnvironmentOverrides.Keys) { $controlledEnvironment[[string]$key] = [string]$EnvironmentOverrides[$key] } }
        $requiredEnvironment = @{ CODEX_HOME = $profileCodexHome; HOME = (Join-Path $profileRoot 'home'); USERPROFILE = (Join-Path $profileRoot 'userprofile') }
        foreach ($key in $requiredEnvironment.Keys) {
            if ($controlledEnvironment.ContainsKey($key) -and -not ([IO.Path]::GetFullPath($controlledEnvironment[$key]).TrimEnd('\').Equals([IO.Path]::GetFullPath($requiredEnvironment[$key]).TrimEnd('\'),[StringComparison]::OrdinalIgnoreCase))) { throw ('Controlled permission profile ' + $key + ' must point inside the profile.') }
            $controlledEnvironment[$key] = $requiredEnvironment[$key]
        }
        $EnvironmentOverrides = $controlledEnvironment
    }
    if ($null -eq $ProcessInvoker -and $null -eq (Get-Command codex -ErrorAction SilentlyContinue)) { throw 'Codex executable is unavailable.' }
    $workingRoot = [IO.Path]::GetFullPath($WorkingDirectory).TrimEnd('\')
    $resultRoot = [IO.Path]::GetFullPath($ResultDirectory).TrimEnd('\')
    if ($RequireExternalResultDirectory) {
        if (Test-PfcPathDescendant -Path $resultRoot -Parent $workingRoot) { Throw-PfcRevision3Failure -Classification 'INVALID_WORKTREE_CONTAMINATION' -Message 'Controlled result root must be outside the fixture worktree.' }
        if (Test-PfcReparsePath -Path $resultRoot) { Throw-PfcRevision3Failure -Classification 'INVALID_WORKTREE_CONTAMINATION' -Message 'Controlled result root must not traverse a reparse point.' }
    } else {
        $expectedResultRoot = [IO.Path]::GetFullPath((Join-Path $workingRoot '.pfc-eval-results')).TrimEnd('\')
        if (-not $resultRoot.Equals($expectedResultRoot, [StringComparison]::OrdinalIgnoreCase)) { Throw-PfcRevision3Failure -Classification 'INVALID_WORKTREE_CONTAMINATION' -Message 'Raw results must equal the working directory .pfc-eval-results folder unless controlled external isolation is requested.' }
    }
    New-Item -ItemType Directory -Path $resultRoot -Force | Out-Null
    $rawPath = Join-Path $resultRoot ('run-' + [guid]::NewGuid().ToString('N') + '.jsonl')
    $outputPath = Join-Path $resultRoot ('final-' + [guid]::NewGuid().ToString('N') + '.json')
    $args = @('exec','--json')
    if ($Ephemeral) { $args += '--ephemeral' }
    if ($IgnoreUserConfig) { $args += '--ignore-user-config' }
    if ($IgnoreRules) { $args += '--ignore-rules' }
    if ($SkipGitRepoCheck) { $args += '--skip-git-repo-check' }
    if ($Model) { $args += @('--model', $Model) }
    if ($ReasoningEffort) { $args += @('-c', ('model_reasoning_effort="' + $ReasoningEffort + '"')) }
    if ($DisableWebSearch) { $args += @('-c','web_search="disabled"') }
    if ($null -ne $ProjectDocMaxBytes) { $args += @('-c',('project_doc_max_bytes=' + $ProjectDocMaxBytes)) }
    if ($customPermission) {
        # Official permission profiles and legacy --sandbox are mutually
        # exclusive.  Select the named profile through config precedence.
        $args += @('-c',('default_permissions="' + $PermissionProfileName + '"'))
    } else {
        $args += @('--sandbox',$SandboxMode)
    }
    if ($hasSchema) { $args += @('--output-schema',$OutputSchemaPath) }
    $promptComposition = Get-PfcEvaluationPromptText -CommonPromptPath $PromptPath -TreatmentPromptPath $TreatmentPromptPath -Phase $Phase
    $promptText = $promptComposition.text
    $treatmentEnabled = [bool]$promptComposition.treatment_enabled
    $args += @('--output-last-message',$outputPath,$promptText)
    if ($null -ne $ProcessInvoker) {
        $proc = & $ProcessInvoker $args
    } else {
        $proc = Invoke-PfcRealCodexProcess -Arguments $args -WorkingDirectory $WorkingDirectory -RawPath $rawPath -OutputPath $outputPath -TimeoutSeconds $TimeoutSeconds -StartupTimeoutSeconds $StartupTimeoutSeconds -PostTerminalGraceSeconds $PostTerminalGraceSeconds -CodexExecutablePath $CodexExecutablePath -EnvironmentOverrides $EnvironmentOverrides -ClockProvider $ClockProvider -SleepProvider $SleepProvider
    }
    if ($null -eq $proc) { Throw-PfcRevision3Failure -Classification 'INVALID_PROCESS_CLEANUP' -Message 'Codex process invocation returned no result.' }
    if ($proc.PSObject.Properties['FixtureBindingValid'] -and $proc.FixtureBindingValid -eq $false) { Throw-PfcRevision3Failure -Classification 'INVALID_FIXTURE_BINDING' -Message 'Codex fixture binding is invalid.' }
    if ($proc.PSObject.Properties['WorktreeContaminationDetected'] -and $proc.WorktreeContaminationDetected -eq $true) { Throw-PfcRevision3Failure -Classification 'INVALID_WORKTREE_CONTAMINATION' -Message 'Codex worktree contamination was detected.' }
    if ($proc.PSObject.Properties['WorktreeClean'] -and $proc.WorktreeClean -eq $false) { Throw-PfcRevision3Failure -Classification 'INVALID_WORKTREE_CONTAMINATION' -Message 'Codex worktree is not clean.' }
    if ($proc.PSObject.Properties['NormalizationValid'] -and $proc.NormalizationValid -eq $false) { Throw-PfcRevision3Failure -Classification 'INVALID_NORMALIZATION' -Message 'Structured output normalization failed.' }
    if ($proc.PSObject.Properties['ProcessCleanupValid'] -and $proc.ProcessCleanupValid -eq $false) { Throw-PfcRevision3Failure -Classification 'INVALID_PROCESS_CLEANUP' -Message 'Codex process cleanup failed.' }
    if ($proc.PSObject.Properties['ProcessCleanup'] -and [string]$proc.ProcessCleanup -match '^(?i:FAILED|INVALID|ERROR)$') { Throw-PfcRevision3Failure -Classification 'INVALID_PROCESS_CLEANUP' -Message 'Codex process cleanup failed.' }
    $stdout = if ($null -ne $proc.StdOut) { [string]$proc.StdOut } else { '' }
    $stderr = if ($null -ne $proc.StdErr) { [string]$proc.StdErr } else { '' }
    if ($null -ne $ProcessInvoker) { [IO.File]::WriteAllText($rawPath, $stdout, (New-Object Text.UTF8Encoding($false))) }
    if (($stdout + "`n" + $stderr) -match '(?i)unauthenticated|not authenticated|authentication required|login required') { throw 'Codex authentication is unavailable.' }
    $jsonlLines = @($stdout -split "`r?`n" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    $receivedTimes = if ($null -ne $proc.PSObject.Properties['EventTimes']) { $proc.EventTimes } else { $null }
    $metrics = Read-PfcCodexJsonlMetrics -Lines $jsonlLines -ReceivedAtUtc $receivedTimes
    if ($metrics.invalid_json_lines -gt 0) { Throw-PfcRevision3Failure -Classification 'INVALID_SCHEMA' -Message 'Codex JSONL contains invalid lines.' }
    $rawFinalAgentMessage = Get-PfcRawFinalAgentMessage -Lines $jsonlLines
    if ($metrics.turn_result -eq 'FAILED') { Throw-PfcRevision3Failure -Classification 'INVALID_TURN_FAILED' -Message 'INVALID_TURN_FAILED: Codex reported a failed turn.' }
    $finalValue = $null; $finalSource = $null
    if ($null -eq $ProcessInvoker) {
        if ($metrics.turn_result -notin @('COMPLETED','COMPLETED_WITH_RECOVERED_ERRORS')) { Throw-PfcRevision3Failure -Classification 'INVALID_PRE_TERMINAL_TIMEOUT' -Message 'Codex completion event is missing.' }
        $finalValue = $null; $finalSource = $null; $outputFileState = 'MISSING_AFTER_TERMINAL_GRACE'
        if (Test-Path -LiteralPath $outputPath -PathType Leaf) {
            try { $outputText = Read-PfcUtf8TextStrict -Path $outputPath } catch { $outputText = $null; $outputFileState = 'PRESENT_INVALID_UTF8' }
            if (-not [string]::IsNullOrWhiteSpace($outputText)) {
                if ($hasSchema) { try { $candidate = ConvertFrom-Json -InputObject $outputText; if (Test-PfcSchemaShape -Value $candidate -SchemaPath $OutputSchemaPath) { $finalValue = $candidate; $finalSource = 'OUTPUT_LAST_MESSAGE_FILE'; $outputFileState = 'PRESENT_VALID' } else { $outputFileState = 'PRESENT_SCHEMA_FAIL' } } catch { $outputFileState = 'PRESENT_INVALID' } }
                else { $finalValue = $outputText; $finalSource = 'OUTPUT_LAST_MESSAGE_FILE'; $outputFileState = 'PRESENT_VALID' }
            } else { $outputFileState = 'PRESENT_EMPTY' }
        }
        if ($null -eq $finalValue -and $rawFinalAgentMessage) {
            if ($hasSchema) {
                if ($rawFinalAgentMessage -match '^\s*```') { Throw-PfcRevision3Failure -Classification 'INVALID_SCHEMA' -Message 'Structured fallback is fenced and cannot be repaired.' }
                try { $candidate = $rawFinalAgentMessage | ConvertFrom-Json } catch { Throw-PfcRevision3Failure -Classification 'INVALID_SCHEMA' -Message 'Structured fallback is not valid JSON.' }
                if (-not (Test-PfcSchemaShape -Value $candidate -SchemaPath $OutputSchemaPath)) { Throw-PfcRevision3Failure -Classification 'INVALID_SCHEMA' -Message 'Structured fallback does not satisfy output schema.' }
                $finalValue = $candidate
            } else {
                if ([string]::IsNullOrWhiteSpace([string]$rawFinalAgentMessage)) { Throw-PfcRevision3Failure -Classification 'INVALID_SCHEMA' -Message 'Final agent message is empty.' }
                $finalValue = [string]$rawFinalAgentMessage
            }
            $finalSource = 'JSONL_FINAL_AGENT_MESSAGE_FALLBACK'
        }
        if ($null -eq $finalValue) { Throw-PfcRevision3Failure -Classification 'INVALID_SCHEMA' -Message 'Codex final output is missing and no final agent message is available.' }
        $metrics | Add-Member -NotePropertyName model_result -NotePropertyValue 'VALID'
        $metrics | Add-Member -NotePropertyName final_output_source -NotePropertyValue $finalSource
        $metrics | Add-Member -NotePropertyName output_file_state -NotePropertyValue $outputFileState
        $localFinal = if ($finalSource -eq 'OUTPUT_LAST_MESSAGE_FILE') { $proc.LocalFinalization } else { 'DEGRADED' }
        $metrics | Add-Member -NotePropertyName local_finalization -NotePropertyValue $localFinal
        if ($proc.PSObject.Properties['ProcessCleanup']) { $metrics | Add-Member -NotePropertyName process_cleanup -NotePropertyValue $proc.ProcessCleanup }
        if ($proc.PSObject.Properties['ForcedAfterTerminal']) { $metrics | Add-Member -NotePropertyName process_forced_after_terminal -NotePropertyValue $proc.ForcedAfterTerminal }
        if ($proc.PSObject.Properties['ExitCode']) { $metrics | Add-Member -NotePropertyName process_exit_code -NotePropertyValue $proc.ExitCode }
        if ($proc.PSObject.Properties['ProcessCleanup']) { $metrics | Add-Member -NotePropertyName process_exited_normally -NotePropertyValue ([string]$proc.ProcessCleanup -eq 'NORMAL') }
        $evidencePrefix = if ($RequireExternalResultDirectory) { 'external-evidence/' } else { '.pfc-eval-results/' }
        if ($proc.PSObject.Properties['EventsPath']) { $metrics | Add-Member -NotePropertyName event_index_path -NotePropertyValue ($evidencePrefix + (Split-Path -Leaf $proc.EventsPath)) }
        if ($proc.PSObject.Properties['StdErrPath']) { $metrics | Add-Member -NotePropertyName stderr_sidecar_path -NotePropertyValue ($evidencePrefix + (Split-Path -Leaf $proc.StdErrPath)) }
        if ($proc.PSObject.Properties['TerminalReceivedAtUtc']) { $metrics | Add-Member -Force -NotePropertyName terminal_event_received_at_utc -NotePropertyValue $proc.TerminalReceivedAtUtc }
        if ($proc.PSObject.Properties['ProcessExitedAtUtc']) { $metrics | Add-Member -NotePropertyName process_exited_at_utc -NotePropertyValue $proc.ProcessExitedAtUtc }
        if ($proc.PSObject.Properties['ProcessExitedAtUtc'] -and $proc.PSObject.Properties['TerminalReceivedAtUtc'] -and $null -ne $proc.ProcessExitedAtUtc -and $null -ne $proc.TerminalReceivedAtUtc) {
            try { $delay = ([DateTime]::Parse($proc.ProcessExitedAtUtc) - [DateTime]::Parse($proc.TerminalReceivedAtUtc)).TotalSeconds; $metrics | Add-Member -NotePropertyName post_terminal_exit_delay_seconds -NotePropertyValue ([Math]::Round($delay,3)) } catch { $metrics | Add-Member -NotePropertyName post_terminal_exit_delay_seconds -NotePropertyValue 'NOT_AVAILABLE' }
        } else { $metrics | Add-Member -NotePropertyName post_terminal_exit_delay_seconds -NotePropertyValue 'NOT_AVAILABLE' }
    }
    # Revision 2 structured output is normalized on the same path for real and
    # fixture-backed runs.  ProcessInvoker fixtures may provide the final file
    # via --output-last-message; lifecycle-only fixtures intentionally have no
    # structured payload and retain their existing metrics-only behavior.
    if ($hasSchema -and $null -eq $finalValue) {
        $candidate = $null
        $candidatePath = $null
        if ($proc.PSObject.Properties['OutputPath'] -and $proc.OutputPath) { $candidatePath = [string]$proc.OutputPath }
        $outputArgIndex = [Array]::IndexOf($args, '--output-last-message')
        if (-not $candidatePath -and $outputArgIndex -ge 0 -and $outputArgIndex + 1 -lt $args.Count) { $candidatePath = [string]$args[$outputArgIndex + 1] }
        if ($candidatePath -and (Test-Path -LiteralPath $candidatePath -PathType Leaf)) {
            try { $candidate = ConvertFrom-Json -InputObject (Read-PfcUtf8TextStrict -Path $candidatePath) } catch { Throw-PfcRevision3Failure -Classification 'INVALID_SCHEMA' -Message 'Structured output file is invalid JSON.' }
        } elseif ($rawFinalAgentMessage) {
            try { $candidate = ConvertFrom-Json -InputObject $rawFinalAgentMessage } catch { Throw-PfcRevision3Failure -Classification 'INVALID_SCHEMA' -Message 'Structured fallback is not valid JSON.' }
        }
        if ($null -ne $candidate) {
            if (-not (Test-PfcSchemaShape -Value $candidate -SchemaPath $OutputSchemaPath)) { Throw-PfcRevision3Failure -Classification 'INVALID_SCHEMA' -Message 'Structured output does not satisfy output schema.' }
            $finalValue = $candidate
            $finalSource = if ($candidatePath -and (Test-Path -LiteralPath $candidatePath -PathType Leaf)) { 'OUTPUT_LAST_MESSAGE_FILE' } else { 'JSONL_FINAL_AGENT_MESSAGE_FALLBACK' }
            $metrics | Add-Member -Force -NotePropertyName model_result -NotePropertyValue 'VALID'
            $metrics | Add-Member -Force -NotePropertyName final_output_source -NotePropertyValue $finalSource
            $metrics | Add-Member -Force -NotePropertyName structured_output_validated -NotePropertyValue $true
            try {
                $metrics | Add-Member -Force -NotePropertyName normalized_metrics -NotePropertyValue (Convert-PfcStructuredMetrics -Metrics (Get-PfcSchemaProperty -Object $candidate -Name 'metrics'))
                $metrics | Add-Member -Force -NotePropertyName normalized_verification -NotePropertyValue (Convert-PfcStructuredMetrics -Metrics (Get-PfcSchemaProperty -Object $candidate -Name 'verification'))
            } catch { Throw-PfcRevision3Failure -Classification 'INVALID_NORMALIZATION' -Message ([string]$_.Exception.Message) }
        } elseif ($proc.PSObject.Properties['OutputPath']) { Throw-PfcRevision3Failure -Classification 'INVALID_SCHEMA' -Message 'Structured output is missing.' }
    }
    if ($null -ne $finalValue -and $null -eq $metrics.PSObject.Properties['structured_output_validated']) {
        $metrics | Add-Member -Force -NotePropertyName structured_output_validated -NotePropertyValue $true
        try {
            $metrics | Add-Member -Force -NotePropertyName normalized_metrics -NotePropertyValue (Convert-PfcStructuredMetrics -Metrics (Get-PfcSchemaProperty -Object $finalValue -Name 'metrics'))
            $metrics | Add-Member -Force -NotePropertyName normalized_verification -NotePropertyValue (Convert-PfcStructuredMetrics -Metrics (Get-PfcSchemaProperty -Object $finalValue -Name 'verification'))
        } catch { Throw-PfcRevision3Failure -Classification 'INVALID_NORMALIZATION' -Message ([string]$_.Exception.Message) }
    }
    $relativeEvidenceName = (Split-Path -Leaf $rawPath)
    $evidencePath = '.pfc-eval-results/' + $relativeEvidenceName
    if ($RequireExternalResultDirectory) { $evidencePath = 'external-evidence/' + $relativeEvidenceName }
    $metrics | Add-Member -NotePropertyName raw_jsonl_path -NotePropertyValue $evidencePath
    $modelReportedPhase = if ($null -ne $finalValue) { Get-PfcSchemaProperty -Object $finalValue -Name 'phase' } else { $null }
    $modelPhaseText = $null
    if ($null -ne $modelReportedPhase) { $modelPhaseText = [string]$modelReportedPhase }
    $phaseDecision = Get-PfcRunnerPhaseDecision -AuthorizedPhase $Phase -ModelReportedPhase $modelPhaseText
    $metrics | Add-Member -NotePropertyName model_reported_phase -NotePropertyValue $phaseDecision.model_reported_phase
    $metrics | Add-Member -NotePropertyName runner_authorized_phase -NotePropertyValue $phaseDecision.runner_authorized_phase
    $metrics | Add-Member -NotePropertyName model_report_consistency -NotePropertyValue $phaseDecision.model_report_consistency
    $metrics | Add-Member -NotePropertyName phase -NotePropertyValue $Phase
    $metrics | Add-Member -NotePropertyName startup_timeout_seconds -NotePropertyValue $StartupTimeoutSeconds
    $metrics | Add-Member -NotePropertyName pre_terminal_timeout_seconds -NotePropertyValue $TimeoutSeconds
    $metrics | Add-Member -NotePropertyName post_terminal_grace_seconds -NotePropertyValue $PostTerminalGraceSeconds
    $metrics | Add-Member -NotePropertyName idle_timeout -NotePropertyValue 'DISABLED'
    $metrics | Add-Member -NotePropertyName automatic_retries -NotePropertyValue 0
    $processCount = 1
    if ($proc.PSObject.Properties['ProcessCount']) { $processCount = [int]$proc.ProcessCount }
    $metrics | Add-Member -NotePropertyName process_count -NotePropertyValue $processCount
    $metrics | Add-Member -NotePropertyName classification -NotePropertyValue 'VALID'
    $metrics | Add-Member -NotePropertyName arguments -NotePropertyValue @($args | ForEach-Object { Convert-PfcRedactedText ([string]$_) })
    $metrics | Add-Member -NotePropertyName track -NotePropertyValue $Track
    $sampleValue = if ($SampleId) { $SampleId } else { 'NOT_AVAILABLE' }
    $scenarioValue = if ($Scenario) { $Scenario } else { 'NOT_AVAILABLE' }
    $profileValue = if ($ProfileFingerprint) { Convert-PfcRedactedText $ProfileFingerprint } else { 'NOT_AVAILABLE' }
    $manifestValue = if ($InstructionSourceManifestHash) { $InstructionSourceManifestHash } else { 'NOT_AVAILABLE' }
    $fixtureValue = if ($FixtureId) { $FixtureId } else { 'NOT_AVAILABLE' }
    $baseValue = if ($FixtureBaseSha) { $FixtureBaseSha } else { 'NOT_AVAILABLE' }
    $modelValue = if ($Model) { $Model } else { 'NOT_AVAILABLE' }
    $reasoningValue = if ($ReasoningEffort) { $ReasoningEffort } else { 'NOT_AVAILABLE' }
    $promptHash = 'NOT_AVAILABLE'
    try { $promptHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $PromptPath).Hash.ToLowerInvariant() } catch { }
    $schemaHash = 'NOT_AVAILABLE'
    if ($hasSchema) { try { $schemaHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $OutputSchemaPath).Hash.ToLowerInvariant() } catch { } }
    $metrics | Add-Member -NotePropertyName sample_id -NotePropertyValue $sampleValue
    $metrics | Add-Member -NotePropertyName scenario -NotePropertyValue $scenarioValue
    $metrics | Add-Member -NotePropertyName repetition -NotePropertyValue $Repetition
    $metrics | Add-Member -NotePropertyName eval_contract_revision -NotePropertyValue $EvalContractRevision
    $metrics | Add-Member -NotePropertyName formal_schema_revision -NotePropertyValue $FormalSchemaRevision
    $metrics | Add-Member -NotePropertyName treatment_enabled -NotePropertyValue $treatmentEnabled
    $metrics | Add-Member -NotePropertyName profile_fingerprint -NotePropertyValue $profileValue
    $metrics | Add-Member -NotePropertyName instruction_source_manifest_hash -NotePropertyValue $manifestValue
    $metrics | Add-Member -NotePropertyName fixture_id -NotePropertyValue $fixtureValue
    $metrics | Add-Member -NotePropertyName fixture_base_sha -NotePropertyValue $baseValue
    $metrics | Add-Member -NotePropertyName normalizer_version -NotePropertyValue $NormalizerVersion
    $metrics | Add-Member -NotePropertyName model -NotePropertyValue $modelValue
    $metrics | Add-Member -NotePropertyName reasoning_effort -NotePropertyValue $reasoningValue
    $metrics | Add-Member -NotePropertyName sandbox -NotePropertyValue $SandboxMode
    $permissionProfileValue = if ($customPermission) { $PermissionProfileName } else { 'NOT_AVAILABLE' }
    $configSourceValue = if ($customPermission) { 'CONTROLLED_PROFILE_CONFIG' } else { 'LEGACY_CLI_OR_DEFAULT_CONFIG' }
    $permissionConfigPathValue = if ($customPermission) { Convert-PfcRedactedText $PermissionProfileConfigPath } else { 'NOT_AVAILABLE' }
    $metrics | Add-Member -NotePropertyName permission_profile -NotePropertyValue $permissionProfileValue
    $metrics | Add-Member -NotePropertyName config_source -NotePropertyValue $configSourceValue
    $metrics | Add-Member -NotePropertyName permission_profile_config_path -NotePropertyValue $permissionConfigPathValue
    $metrics | Add-Member -NotePropertyName prompt_hash -NotePropertyValue $promptHash
    $metrics | Add-Member -NotePropertyName schema_hash -NotePropertyValue $schemaHash
    $resultPolicy = 'WORKING_DIRECTORY_EVAL_RESULTS'
    if ($RequireExternalResultDirectory) { $resultPolicy = 'OUTSIDE_FIXTURE' }
    $metrics | Add-Member -NotePropertyName result_directory_policy -NotePropertyValue $resultPolicy
    $metrics | Add-Member -NotePropertyName result_root_outside_fixture -NotePropertyValue ([bool]$RequireExternalResultDirectory)
    $metrics | Add-Member -NotePropertyName evaluation_artifact_read_count -NotePropertyValue (Get-PfcEvaluationArtifactReadCount -Lines $jsonlLines -ResultRoot $resultRoot)
    $metrics | Add-Member -NotePropertyName primary_metric_name -NotePropertyValue 'files_read_before_first_relevant_edit'
    return $metrics
}

Export-ModuleMember -Function Invoke-PfcCodexRun, Invoke-PfcRunnerLifecycle, Read-PfcCodexJsonlMetrics, Get-PfcEvaluationArtifactReadCount, Write-PfcUtf8NoBom, Get-PfcSchemaPreflight, Get-PfcStrictSchemaPreflight, Convert-PfcStructuredMetrics, Test-PfcPathDescendant, Test-PfcReparsePath, Get-PfcEvaluationPromptText, Get-PfcRunnerPhaseDecision
