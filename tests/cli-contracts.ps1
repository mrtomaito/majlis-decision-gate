param()

$ErrorActionPreference = 'Stop'

# Recursion guard. 'majlis-cli verify' and 'majlis-cli test' both spawn THIS file,
# so adding either to the case lists below would fork-bomb the machine. Children
# inherit this variable, so a nested run bails instead of recursing.
if ($env:MAJLIS_CONTRACT_SUITE_RUNNING -eq '1') {
    Write-Host 'CLI contract suite is already running in a parent process; refusing to recurse.' -ForegroundColor Yellow
    exit 0
}
$env:MAJLIS_CONTRACT_SUITE_RUNNING = '1'

$testRoot = Split-Path -Parent $PSScriptRoot
$cliPath = Join-Path $testRoot 'scripts\majlis-cli.ps1'
$failures = [System.Collections.Generic.List[string]]::new()

# The harness must run on whatever PowerShell the machine actually has. Hard-coding
# 'pwsh' made every case die with CommandNotFoundException on a Windows PowerShell
# 5.1 box, so the suite reported nothing instead of failing loudly.
function Resolve-PowerShellHost {
    foreach ($candidate in @('pwsh', 'powershell')) {
        $resolved = Get-Command -Name $candidate -CommandType Application -ErrorAction SilentlyContinue |
            Select-Object -First 1
        if ($resolved) { return $resolved.Source }
    }
    throw 'No PowerShell host found on PATH (looked for pwsh, then powershell).'
}

$script:PowerShellHost = Resolve-PowerShellHost

function Invoke-MajlisCli {
    param([string[]]$CliArgs)

    # Negative cases deliberately make the CLI exit non-zero and write to stderr.
    # Windows PowerShell wraps native stderr in an ErrorRecord, which the script-wide
    # 'Stop' preference promotes to a terminating error -- aborting the whole suite on
    # the first *expected* failure. Relax it for the child process only.
    $previousPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $output = & $script:PowerShellHost -NoProfile -File $cliPath @CliArgs 2>&1 | Out-String
        $exitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $previousPreference
    }

    [PSCustomObject]@{
        ExitCode = $exitCode
        Output   = $output.Trim()
    }
}

function Add-Failure {
    param([string]$Message)
    $failures.Add($Message)
}

$jsonCases = @(
    @('status', '-Json'),
    @('triage', '-Json'),
    @('verify-entity', '-Json'),
    @('calc-cvi', '-Revenue', '600', '-Days', '14', '-Margin', '0.85', '-Json'),
    @('audit', '-Json'),
    @('help', '-Json')
)

foreach ($case in @(
    @('status'),
    @('triage'),
    @('verify-entity'),
    @('calc-cvi', '-Revenue', '600', '-Days', '14', '-Margin', '0.85'),
    @('audit'),
    @('help')
)) {
    $result = Invoke-MajlisCli -CliArgs $case
    if ($result.ExitCode -ne 0) {
        Add-Failure "text command failed: $($case -join ' ') (exit $($result.ExitCode))"
    }
}

foreach ($case in $jsonCases) {
    $result = Invoke-MajlisCli -CliArgs $case
    if ($result.ExitCode -ne 0) {
        Add-Failure "JSON command failed: $($case -join ' ') (exit $($result.ExitCode))"
        continue
    }
    try {
        $null = $result.Output | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        Add-Failure "JSON command returned invalid JSON: $($case -join ' ')"
    }
}

$privacyResult = Invoke-MajlisCli -CliArgs @('verify-entity', '-Json')
if ($privacyResult.ExitCode -eq 0) {
    $privacyJson = $privacyResult.Output | ConvertFrom-Json
    if ($privacyJson.PrivacyCheck.PSObject.Properties.Name -contains 'IsCompliant') {
        Add-Failure 'verify-entity must not self-certify legal compliance'
    }
    if (-not ($privacyJson.PrivacyCheck.PSObject.Properties.Name -contains 'NoContactDataDetected')) {
        Add-Failure 'verify-entity must report the narrow fact NoContactDataDetected'
    }
}

$statusResult = Invoke-MajlisCli -CliArgs @('status', '-Json')
if ($statusResult.ExitCode -eq 0) {
    $statusJson = $statusResult.Output | ConvertFrom-Json
    $systemDate = [DateTime]::ParseExact($statusJson.SystemDate, 'yyyy-MM-dd', $null)
    foreach ($deadline in $statusJson.Deadlines) {
        $targetDate = [DateTime]::ParseExact($deadline.TargetDate, 'yyyy-MM-dd', $null)
        $expectedDays = ($targetDate - $systemDate).Days
        if ($deadline.DaysRemaining -ne $expectedDays) {
            Add-Failure "status deadline uses time-of-day instead of date-only arithmetic: $($deadline.Milestone)"
        }
    }
}

$zeroMarginResult = Invoke-MajlisCli -CliArgs @('calc-cvi', '-Revenue', '600', '-Days', '14', '-Margin', '0', '-Json')
if ($zeroMarginResult.ExitCode -ne 0) {
    Add-Failure 'calc-cvi rejected a valid zero-margin scenario'
}
else {
    $zeroMarginJson = $zeroMarginResult.Output | ConvertFrom-Json
    if (($zeroMarginJson.Scenarios | Where-Object Scenario -like 'Conservative*').Margin -ne 0) {
        Add-Failure 'calc-cvi conservative scenario increased a zero margin above zero'
    }
}

$privacyText = Invoke-MajlisCli -CliArgs @('verify-entity')
if ($privacyText.Output -match 'PDPL Compliant') {
    Add-Failure 'verify-entity text must not label a regex scan as PDPL compliant'
}

$fixturePath = Join-Path $testRoot ('tests\.entity-contract-' + [guid]::NewGuid().ToString('N') + '.md')
try {
    $piiFixture = @'
<!-- entity-records-collection project=x target=1 gate=2099-01-01 -->
<!-- entity-record-v1 id=ER-001 -->
**entity-name:** Example
**organization-channel:** 0555555555
**verified-at`):** 2026-09-01
'@
    [System.IO.File]::WriteAllText($fixturePath, $piiFixture)
    $piiResult = Invoke-MajlisCli -CliArgs @('verify-entity', '-EntityFile', $fixturePath, '-Json')
    if ($piiResult.ExitCode -eq 0) {
        Add-Failure 'verify-entity returned success after detecting personal contact data'
    }

    [System.IO.File]::WriteAllText($fixturePath, '<!-- entity-records-collection project=x target=1 gate=2099-01-01 -->')
    $emptyResult = Invoke-MajlisCli -CliArgs @('verify-entity', '-EntityFile', $fixturePath, '-Json')
    if ($emptyResult.ExitCode -eq 0) {
        Add-Failure 'verify-entity returned success for a collection with no slots'
    }
}
finally {
    if (Test-Path -LiteralPath $fixturePath) {
        Remove-Item -LiteralPath $fixturePath -Force
    }
}

foreach ($invalidCase in @(
    @('calc-cvi', '-Revenue', '0', '-Days', '14', '-Margin', '0.85', '-Json'),
    @('calc-cvi', '-Revenue', '600', '-Days', '0', '-Margin', '0.85', '-Json'),
    @('calc-cvi', '-Revenue', '600', '-Days', '14', '-Margin', '-0.01', '-Json'),
    @('calc-cvi', '-Revenue', '600', '-Days', '14', '-Margin', '1.01', '-Json')
)) {
    $result = Invoke-MajlisCli -CliArgs $invalidCase
    if ($result.ExitCode -eq 0) {
        Add-Failure "invalid CVI input was accepted: $($invalidCase -join ' ')"
    }
}

$outsideFile = Join-Path ([System.IO.Path]::GetTempPath()) ('majlis-outside-' + [guid]::NewGuid().ToString('N') + '.md')
try {
    [System.IO.File]::WriteAllText($outsideFile, '<!-- entity-records-collection project=x target=0 gate=2099-01-01 -->')
    $outsideResult = Invoke-MajlisCli -CliArgs @('verify-entity', '-EntityFile', $outsideFile, '-Json')
    if ($outsideResult.ExitCode -eq 0) {
        Add-Failure 'verify-entity accepted a file outside the project root'
    }
}
finally {
    if (Test-Path -LiteralPath $outsideFile) {
        Remove-Item -LiteralPath $outsideFile -Force
    }
}

if ($failures.Count -gt 0) {
    foreach ($failure in $failures) {
        Write-Host "FAIL  $failure" -ForegroundColor Red
    }
    Write-Host "CLI contract summary: $($failures.Count) failed."
    $env:MAJLIS_CONTRACT_SUITE_RUNNING = $null
    exit 1
}

$env:MAJLIS_CONTRACT_SUITE_RUNNING = $null

Write-Host "CLI contract summary: all text/JSON commands and boundary cases passed (host: $script:PowerShellHost)."

# Without this, the suite falls off the end carrying $LASTEXITCODE from the last
# negative case -- reporting success while exiting 1, which any caller reads as failure.
exit 0
