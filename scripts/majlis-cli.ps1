<#
.SYNOPSIS
    أداة القياس والتشغيل الحتمية لمستشار الأعمال والتسويق «مجلس».
.DESCRIPTION
    تتيح فرز المحفظة من سجل الدليل، متابعة القيد النشط، التحقق من سجلات الكيانات،
    وحساب سيناريو مؤشر سرعة النقد CVI، مع دعم الإخراج المهيكل (JSON).
.EXAMPLE
    .\scripts\majlis-cli.ps1 status
    .\scripts\majlis-cli.ps1 calc-cvi -Revenue 600 -Days 14 -Margin 0.85
    .\scripts\majlis-cli.ps1 triage -Json
#>

[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [ValidateSet('status', 'triage', 'verify-entity', 'calc-cvi', 'audit', 'test', 'verify', 'help')]
    [string]$Command = 'status',

    [Parameter()]
    [double]$Revenue = 600,

    [Parameter()]
    [int]$Days = 14,

    [Parameter()]
    [double]$Margin = 0.85,

    [Parameter()]
    [string]$EntityFile = 'docs/entity-records-draft.md',

    [Parameter()]
    [switch]$Json
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot

# ---------------------------------------------------------------------------
# FORK CONFIG -- edit this block to point the dashboard at YOUR constraint.
# These are the repo owner's values; they are copy, not logic.
# ---------------------------------------------------------------------------
$ActiveConstraint = @{
    Project     = 'khatm (field e-invoicing setup)'
    LaunchState = 'Validation Candidate (0 named buyers, 0 PII)'
    Sprint      = 'Overdue since 2026-09-03 (date not extended): next empty slot ER-KHATM-002'
    Metric      = 'Complete entity records count (Internal Draft)'
}

try {
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
    $OutputEncoding = [System.Text.Encoding]::UTF8
} catch {}

function Show-Header {
    param([string]$Title)
    if ($Json) { return }
    Write-Host ''
    Write-Host "======================================================================" -ForegroundColor Cyan
    Write-Host "  Majlis | $Title" -ForegroundColor Yellow
    Write-Host "======================================================================" -ForegroundColor Cyan
    Write-Host ''
}

function Resolve-ProjectFilePath {
    param([Parameter(Mandatory)][string]$Path)

    $rootPath = [System.IO.Path]::GetFullPath($projectRoot)
    $candidatePath = if ([System.IO.Path]::IsPathRooted($Path)) {
        [System.IO.Path]::GetFullPath($Path)
    }
    else {
        [System.IO.Path]::GetFullPath((Join-Path $rootPath $Path))
    }
    $rootPrefix = $rootPath.TrimEnd([System.IO.Path]::DirectorySeparatorChar) + [System.IO.Path]::DirectorySeparatorChar

    if (-not $candidatePath.StartsWith($rootPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "EntityFile must resolve inside the project root."
    }

    return $candidatePath
}

function Get-ProjectDeadlines {
    $now = (Get-Date).Date
    $deadlines = [ordered]@{
        'Constraint #001: 15 Entity Records (khatm)' = [DateTime]::Parse('2026-09-03')
        'Constraint #001: First 600 SAR Deal'       = [DateTime]::Parse('2026-09-17')
        'System Exit Standard: First Riyal (90d)'   = [DateTime]::Parse('2026-11-18')
        'ZATCA: Penalties Cancellation Deadline'    = [DateTime]::Parse('2026-12-31')
        'ZATCA: Wave 25 Integration Deadline'       = [DateTime]::Parse('2027-02-01')
    }

    if ($Json) {
        $result = @()
        foreach ($key in $deadlines.Keys) {
            $target = $deadlines[$key]
            $diff = ($target - $now).Days
            $result += [PSCustomObject]@{
                Milestone     = $key
                TargetDate    = $target.ToString('yyyy-MM-dd')
                DaysRemaining = $diff
                IsOverdue     = ($diff -lt 0)
            }
        }
        return $result
    }

    Write-Host "  Key Milestones & Deadlines:" -ForegroundColor White
    Write-Host "  --------------------------------------------------------------------" -ForegroundColor DarkGray
    foreach ($key in $deadlines.Keys) {
        $target = $deadlines[$key]
        $diff = ($target - $now).Days
        $statusStr = if ($diff -gt 0) { "$diff days remaining" } elseif ($diff -eq 0) { "TODAY IS TARGET DATE!" } else { "$([Math]::Abs($diff)) days overdue" }
        $color = if ($diff -gt 30) { 'Green' } elseif ($diff -gt 7) { 'Yellow' } elseif ($diff -ge 0) { 'Red' } else { 'DarkRed' }
        Write-Host ("  * {0,-44} : {1,10} ({2})" -f $key, $target.ToString('yyyy-MM-dd'), $statusStr) -ForegroundColor $color
    }
}

function Show-Status {
    $todayStr = (Get-Date).ToString('yyyy-MM-dd')

    # Check draft entities
    $draftPath = Resolve-ProjectFilePath -Path $EntityFile
    $slotsCount = 0
    $filledCount = 0
    if (Test-Path -LiteralPath $draftPath) {
        $text = Get-Content -LiteralPath $draftPath -Raw -Encoding UTF8
        $entityMatches = [regex]::Matches($text, '<!-- entity-record-v1 id=([^ ]+) -->')
        $slotsCount = $entityMatches.Count

        $slotBodies = [regex]::Split($text, '<!-- entity-record-v1 id=[^ ]+ -->')
        for ($i = 1; $i -lt $slotBodies.Count; $i++) {
            $body = $slotBodies[$i]
            $cut = $body.IndexOf('### ')
            if ($cut -ge 0) { $body = $body.Substring(0, $cut) }
            $hasPlaceholder = [regex]::IsMatch($body, '\[[^\]]+\]')
            $hasRealDate = [regex]::IsMatch($body, 'verified-at`\):\*\* \d{4}-\d{2}-\d{2}')
            if ((-not $hasPlaceholder) -and $hasRealDate) { $filledCount++ }
        }
    }

    if ($Json) {
        $data = [PSCustomObject]@{
            SystemDate       = $todayStr
            Deadlines        = (Get-ProjectDeadlines)
            ActiveConstraint = $ActiveConstraint
            EntityDraft      = [PSCustomObject]@{
                File        = $EntityFile
                SlotsCount  = $slotsCount
                FilledCount = $filledCount
            }
        }
        $data | ConvertTo-Json -Depth 4
        return
    }

    Show-Header "Operational Status & Active Constraints Dashboard"
    Write-Host "  Current System Date: $todayStr" -ForegroundColor Gray
    Write-Host ''

    Get-ProjectDeadlines
    Write-Host ''

    Write-Host "  Current Active Constraint:" -ForegroundColor White
    Write-Host "  --------------------------------------------------------------------" -ForegroundColor DarkGray
    Write-Host ("  Selected Project : {0}" -f $ActiveConstraint.Project) -ForegroundColor Green
    Write-Host ("  Launch State     : {0}" -f $ActiveConstraint.LaunchState) -ForegroundColor Yellow
    Write-Host ("  Weekly Sprint    : {0}" -f $ActiveConstraint.Sprint) -ForegroundColor Cyan
    Write-Host ("  Single Metric    : {0}" -f $ActiveConstraint.Metric) -ForegroundColor White
    Write-Host ''

    Write-Host "  Entity Records in Draft ($EntityFile): $slotsCount slots / $filledCount filled" -ForegroundColor Magenta
    Write-Host ''
}

function Read-CommentFields {
    param([string]$Body)

    $fields = @{}
    foreach ($m in [regex]::Matches($Body, '([A-Za-z][\w-]*)=(?:"([^"]*)"|(\S+))')) {
        $fields[$m.Groups[1].Value] = if ($m.Groups[2].Success) { $m.Groups[2].Value } else { $m.Groups[3].Value }
    }
    return $fields
}

function Get-ClosedStrangerCount {
    $logPath = Join-Path $projectRoot 'docs\decision-log.md'
    if (-not (Test-Path -LiteralPath $logPath)) { return 0 }
    $log = Get-Content -LiteralPath $logPath -Raw -Encoding UTF8
    $n = 0
    foreach ($rec in [regex]::Matches($log, '<!-- constraint-record ([^>]*?)-->')) {
        $body = $rec.Groups[1].Value
        $closed = $body -match '(?:^|\s)status=closed(?:\s|$)'
        $stranger = $body -match '(?:^|\s)mover=stranger(?:\s|$)'
        if ($closed -and $stranger) { $n++ }
    }
    return $n
}

function Show-Triage {
    $scoringPath = [System.IO.Path]::Combine($projectRoot, 'docs', 'scoring-model.md')
    if (-not (Test-Path -LiteralPath $scoringPath)) {
        Write-Error "File docs/scoring-model.md not found!"
        return
    }

    $scoringText = Get-Content -LiteralPath $scoringPath -Raw -Encoding UTF8
    $scoreEvidence = [regex]::Matches(
        $scoringText,
        '<!-- score-evidence project=([^ ]+) axis=([abcde]) score=([0-3]) grade=([abcd]) source=([^ ]+) -->'
    )

    $weights = @{ a = 3; b = 3; c = 2; d = 2; e = 1 }
    $projects = @($scoreEvidence | ForEach-Object { $_.Groups[1].Value } | Select-Object -Unique)

    $results = @()
    foreach ($proj in $projects) {
        $projRecords = @($scoreEvidence | Where-Object { $_.Groups[1].Value -eq $proj })
        $scores = @{}
        foreach ($rec in $projRecords) {
            $scores[$rec.Groups[2].Value] = [int]$rec.Groups[3].Value
        }

        $aWeighted = if ($scores.ContainsKey('a')) { $scores['a'] * $weights['a'] } else { 0 }
        $bWeighted = if ($scores.ContainsKey('b')) { $scores['b'] * $weights['b'] } else { 0 }
        $cWeighted = if ($scores.ContainsKey('c')) { $scores['c'] * $weights['c'] } else { 0 }
        $dWeighted = if ($scores.ContainsKey('d')) { $scores['d'] * $weights['d'] } else { 0 }
        $eWeighted = if ($scores.ContainsKey('e')) { $scores['e'] * $weights['e'] } else { 0 }

        $total = $aWeighted + $bWeighted + $cWeighted + $dWeighted + $eWeighted

        $results += [PSCustomObject]@{
            Project = $proj
            A = $aWeighted
            B = $bWeighted
            C = $cWeighted
            D = $dWeighted
            E = $eWeighted
            Total = $total
            RawScores = $scores
        }
    }

    $sortedResults = @($results | Sort-Object Total -Descending)
    for ($idx = 0; $idx -lt $sortedResults.Count; $idx++) {
        $item = $sortedResults[$idx]
        $statusStr = if ($idx -eq 0) { "Validation Cand (1)" } elseif ($idx -eq 1) { "Validation Cand (2)" } else { "Not Ready" }
        $item | Add-Member -NotePropertyName "Status" -NotePropertyValue $statusStr -Force
        $item | Add-Member -NotePropertyName "Rank" -NotePropertyValue ($idx + 1) -Force
    }

    $topCandidate = if ($sortedResults.Count -gt 0) { $sortedResults[0] } else { $null }

    $outsideMatch = [regex]::Match($scoringText, '<!-- outside-view\s+(.*?)\s*-->')
    if (-not $outsideMatch.Success) { throw 'scoring model is missing the outside-view marker' }
    $outsideFields = Read-CommentFields -Body $outsideMatch.Groups[1].Value
    foreach ($key in @('class', 'distribution', 'grade', 'source', 'as-of', 'note')) {
        if (-not $outsideFields.ContainsKey($key) -or [string]::IsNullOrWhiteSpace([string]$outsideFields[$key])) {
            throw "outside-view marker is missing $key"
        }
    }

    $standardPath = Join-Path $projectRoot 'docs\evidence-standard.md'
    $standardText = Get-Content -LiteralPath $standardPath -Raw -Encoding UTF8
    $floorMatch = [regex]::Match($standardText, '<!-- forecast-floor closed-stranger=(\d+) -->')
    if (-not $floorMatch.Success) { throw 'evidence standard is missing forecast-floor' }
    $floor = [int]$floorMatch.Groups[1].Value
    $closedStranger = Get-ClosedStrangerCount
    $sortKeyNote = 'مفتاح فرز لا احتمال'
    $outsideLine = "class=$($outsideFields['class']) internal=$($outsideFields['distribution']) grade=$($outsideFields['grade']) source=$($outsideFields['source']) as-of=$($outsideFields['as-of']) | $($outsideFields['note'])"
    $belowFloor = $closedStranger -lt $floor
    $calibration = if ($belowFloor) { 'غير قابل للترتيب' } else { $null }

    if ($Json) {
        $data = [PSCustomObject]@{
            Scorecard        = $sortedResults
            TopCandidate     = $topCandidate
            SortKeyNote      = $sortKeyNote
            OutsideView      = [PSCustomObject]@{
                Class        = $outsideFields['class']
                Distribution = $outsideFields['distribution']
                Grade        = $outsideFields['grade']
                Source       = $outsideFields['source']
                AsOf         = $outsideFields['as-of']
                Note         = $outsideFields['note']
                Line         = $outsideLine
            }
            Calibration      = $calibration
            Weights          = $weights
            TieBreakers      = @(
                "1) Named Buyer Evidence",
                "2) Demand Proof (Axis B)",
                "3) Monthly Cash Bleed (Axis C)",
                "4) Measured CVI (Grade B/C only)",
                "5) External Binding Deadline"
            )
        }
        $data | ConvertTo-Json -Depth 4
        return
    }

    Show-Header "Deterministic Portfolio Triage & Scoring Engine"

    Write-Host "  Deterministic Evidence-Backed Scorecard:" -ForegroundColor White
    Write-Host "  +--------------------------+----+----+----+----+----+-----------+--------------------+" -ForegroundColor DarkGray
    Write-Host "  | Project Name             | Ax3| Bx3| Cx2| Dx2| Ex1| Total /33 | Launch Status      |" -ForegroundColor Cyan
    Write-Host "  +--------------------------+----+----+----+----+----+-----------+--------------------+" -ForegroundColor DarkGray

    foreach ($res in $sortedResults) {
        Write-Host ("  | {0,-24} | {1,2} | {2,2} | {3,2} | {4,2} | {5,2} |   {6,2}/33  | {7,-19} |" -f `
            $res.Project, $res.A, $res.B, $res.C, $res.D, $res.E, $res.Total, $res.Status) -ForegroundColor White
    }
    Write-Host "  +--------------------------+----+----+----+----+----+-----------+--------------------+" -ForegroundColor DarkGray
    Write-Host ''
    Write-Host "  $sortKeyNote" -ForegroundColor Gray
    Write-Host "  outside-view: $outsideLine" -ForegroundColor Gray
    if ($belowFloor) {
        Write-Host "  $calibration ($closedStranger/$floor closed stranger constraints)" -ForegroundColor Gray
    }
    Write-Host "  Tie-Breaker: 1) Buyer Evidence 2) Demand Proof 3) Cash Bleed 4) Measured CVI 5) External Deadline" -ForegroundColor Gray
    Write-Host ''
}

function Verify-EntityRecords {
    $filePath = Resolve-ProjectFilePath -Path $EntityFile
    if (-not (Test-Path -LiteralPath $filePath)) {
        # The owner's entity draft is a PRIVATE ledger and is gitignored, so on a
        # fresh clone of the published repo this path does not exist. Treating
        # that as a hard failure made the contract suite red on first run for
        # every fork -- punishing them for the owner's gitignore. An explicitly
        # passed -EntityFile that is missing is still a real error.
        if ($PSBoundParameters.ContainsKey('EntityFile')) {
            Write-Error "File $filePath not found!"
            exit 1
        }
        # NOTHING WAS MEASURED. Say so in the loudest terms the command has --
        # a silent exit 0 here would be the green anesthesia this project exists
        # to prevent. No count is printed, because no count was read.
        if ($Json) {
            [PSCustomObject]@{
                File        = $EntityFile
                LedgerFound = $false
                Measured    = $false
                Note        = 'Private entity ledger absent (published or forked tree). Nothing was measured. Copy docs/entity-records-draft.example.md to docs/entity-records-draft.md to start your own.'
            } | ConvertTo-Json -Depth 3
            return
        }
        Show-Header "Entity Records Validation & Privacy (PDPL) Check"
        Write-Host "  [NO LEDGER] $EntityFile is not present." -ForegroundColor Yellow
        Write-Host "              This is expected on a published or forked tree: the entity" -ForegroundColor Yellow
        Write-Host "              draft is a private ledger and is gitignored." -ForegroundColor Yellow
        Write-Host "  NOTHING WAS MEASURED -- this is not a pass and not a market reading." -ForegroundColor Yellow
        Write-Host "  Start your own: copy docs/entity-records-draft.example.md to $EntityFile" -ForegroundColor Cyan
        Write-Host ''
        return
    }

    $content = Get-Content -LiteralPath $filePath -Raw -Encoding UTF8
    $records = [regex]::Matches($content, '<!-- entity-record-v1 id=([^ ]+) -->')

    # PII Scan: Phones and personal emails
    $phoneRegex = '(\+966|00966|05)\d{8}'
    $emailRegex = '\b[A-Za-z0-9._%+-]+@(?!example\.com)[A-Za-z0-9.-]+\.[A-Za-z]{2,}\b'

    $phoneHits = [regex]::Matches($content, $phoneRegex)
    $emailHits = [regex]::Matches($content, $emailRegex)
    $isPiiClean = ($phoneHits.Count -eq 0 -and $emailHits.Count -eq 0)

    # A slot is FILLED only when no unfilled placeholder [..] remains in its body
    # and its verified-at carries a real ISO date. Template slots are NOT progress.
    $slotBodies = [regex]::Split($content, '<!-- entity-record-v1 id=[^ ]+ -->')
    $filled = 0
    for ($i = 1; $i -lt $slotBodies.Count; $i++) {
        $body = $slotBodies[$i]
        $cut = $body.IndexOf('### ')
        if ($cut -ge 0) { $body = $body.Substring(0, $cut) }
        $hasPlaceholder = [regex]::IsMatch($body, '\[[^\]]+\]')
        $hasRealDate = [regex]::IsMatch($body, 'verified-at`\):\*\* \d{4}-\d{2}-\d{2}')
        if ((-not $hasPlaceholder) -and $hasRealDate) { $filled++ }
    }

    $tMatch = [regex]::Match($content, '<!-- entity-records-collection[^>]*target=(\d+)')
    $target = if ($tMatch.Success) { [int]$tMatch.Groups[1].Value } else { $records.Count }
    $structureValid = ($target -gt 0 -and $records.Count -eq $target)
    $gatePassed = ($target -gt 0 -and $filled -ge $target)

    if ($Json) {
        $data = [PSCustomObject]@{
            File         = $EntityFile
            SlotsCount   = $records.Count
            FilledCount  = $filled
            TargetCount  = $target
            StructureValid = $structureValid
            GatePassed   = $gatePassed
            PrivacyCheck = [PSCustomObject]@{
                NoContactDataDetected = $isPiiClean
                PhoneHits            = $phoneHits.Count
                EmailHits            = $emailHits.Count
            }
        }
        $data | ConvertTo-Json -Depth 4
        if (-not $structureValid -or -not $isPiiClean) { exit 1 }
        return
    }

    Show-Header "Entity Records Validation & Privacy (PDPL) Check"

    Write-Host "  Checking target file: $EntityFile" -ForegroundColor Cyan
    Write-Host "  Machine-readable slots found: $($records.Count)" -ForegroundColor White
    if (-not $structureValid) {
        Write-Host "  [FAIL] Entity collection must declare a positive target and contain exactly that many slots." -ForegroundColor Red
    }

    if ($isPiiClean) {
        Write-Host "  [PASS] No personal phone/email pattern detected. This is not a legal compliance judgment." -ForegroundColor Green
    } else {
        Write-Host "  [FAIL] Privacy Breach Warning! Personal data detected in file:" -ForegroundColor Red
        if ($phoneHits.Count -gt 0) { Write-Host "    - Found $($phoneHits.Count) phone numbers!" -ForegroundColor Red }
        if ($emailHits.Count -gt 0) { Write-Host "    - Found $($emailHits.Count) email addresses!" -ForegroundColor Red }
    }

    Write-Host "  Slots FILLED with a real entity: $filled of $target" -ForegroundColor White
    if ($gatePassed) {
        Write-Host "  [PASS] $target entity-record-v1 records are filled and dated." -ForegroundColor Green
    } else {
        Write-Host "  [OPEN] Preliminary gate NOT met: $filled/$target filled ($($target - $filled) remaining)." -ForegroundColor Yellow
        Write-Host "         Empty template slots are craft scaffolding, not market progress." -ForegroundColor Yellow
    }
    Write-Host ''
    if (-not $structureValid -or -not $isPiiClean) { exit 1 }
}

function Calculate-CVI {
    if ($Revenue -le 0) {
        Write-Error "Revenue must be greater than 0!"
        return
    }
    if ($Days -le 0) {
        Write-Error "Days must be greater than 0!"
        return
    }
    if ($Margin -lt 0 -or $Margin -gt 1) {
        Write-Error "Margin must be between 0 and 1!"
        return
    }

    $cvi = ($Revenue / $Days) * $Margin

    $scenarios = @(
        [PSCustomObject]@{ Scenario = "Conservative (Slow)"; Revenue = $Revenue; Days = [Math]::Max(1, $Days * 2); Margin = [Math]::Max(0.0, $Margin - 0.15); CVI = 0.0 },
        [PSCustomObject]@{ Scenario = "Base Hypothesis     "; Revenue = $Revenue; Days = $Days; Margin = $Margin; CVI = 0.0 },
        [PSCustomObject]@{ Scenario = "Optimistic (Fast)   "; Revenue = $Revenue; Days = [Math]::Max(1, [int]($Days / 2)); Margin = [Math]::Min(1.0, $Margin + 0.1); CVI = 0.0 }
    )

    foreach ($sc in $scenarios) {
        $sc.CVI = [Math]::Round((($sc.Revenue / $sc.Days) * $sc.Margin), 2)
    }

    # 4x4 Sensitivity Grid across Price and Days to Cash
    $priceLevels = @(450, 600, 900, 1200)
    $dayLevels   = @(7, 14, 30, 60)
    $sensitivityGrid = @()
    foreach ($d in $dayLevels) {
        $rowObj = [ordered]@{ "DaysToCash" = "${d}d" }
        foreach ($p in $priceLevels) {
            $val = [Math]::Round((($p / $d) * $Margin), 1)
            $rowObj["Price_${p}SAR"] = $val
        }
        $sensitivityGrid += [PSCustomObject]$rowObj
    }

    if ($Json) {
        $data = [PSCustomObject]@{
            Revenue             = $Revenue
            DaysToCash          = $Days
            GrossMargin         = $Margin
            CashVelocityIndex   = [Math]::Round($cvi, 2)
            DailyGrossCashFlow  = [Math]::Round(($Revenue / $Days), 2)
            Scenarios           = $scenarios
            SensitivityMatrix   = $sensitivityGrid
        }
        $data | ConvertTo-Json -Depth 4
        return
    }

    Show-Header "Cash Velocity Index (CVI) Simulator"

    Write-Host ("  Expected Deal Revenue   : {0:N0} SAR" -f $Revenue) -ForegroundColor White
    Write-Host ("  Days to Cash Collection : {0} days" -f $Days) -ForegroundColor White
    Write-Host ("  Gross Profit Margin     : {0:P0}" -f $Margin) -ForegroundColor White
    Write-Host ("  Cash Velocity Index CVI : {0:F2}" -f $cvi) -ForegroundColor Green
    Write-Host ''

    Write-Host "  Sensitivity & Scenario Analysis:" -ForegroundColor White
    Write-Host "  +--------------------+---------+--------+--------+--------+" -ForegroundColor DarkGray
    Write-Host "  | Scenario           | Revenue | Days   | Margin | CVI    |" -ForegroundColor Cyan
    Write-Host "  +--------------------+---------+--------+--------+--------+" -ForegroundColor DarkGray

    foreach ($sc in $scenarios) {
        Write-Host ("  | {0} | {1,7:N0} | {2,6} | {3,6:P0} | {4,6:F2} |" -f $sc.Scenario, $sc.Revenue, $sc.Days, $sc.Margin, $sc.CVI) -ForegroundColor White
    }
    Write-Host "  +--------------------+---------+--------+--------+--------+" -ForegroundColor DarkGray
    Write-Host ''
    Write-Host "  CVI Sensitivity Matrix (Price vs DaysToCash @ Margin):" -ForegroundColor White
    Write-Host "  +------------+----------+----------+----------+----------+" -ForegroundColor DarkGray
    Write-Host "  | Days \ SAR |  450 SAR |  600 SAR |  900 SAR | 1200 SAR |" -ForegroundColor Cyan
    Write-Host "  +------------+----------+----------+----------+----------+" -ForegroundColor DarkGray
    foreach ($sg in $sensitivityGrid) {
        Write-Host ("  | {0,-10} | {1,8:F1} | {2,8:F1} | {3,8:F1} | {4,8:F1} |" -f $sg.DaysToCash, $sg.Price_450SAR, $sg.Price_600SAR, $sg.Price_900SAR, $sg.Price_1200SAR) -ForegroundColor White
    }
    Write-Host "  +------------+----------+----------+----------+----------+" -ForegroundColor DarkGray
    Write-Host "  Note: Pre-revenue CVI is a scenario comparison tool, not deterministic accounting." -ForegroundColor Gray
    Write-Host ''
}

function Invoke-Audit {
    if ($Json) {
        & (Join-Path $PSScriptRoot 'audit-project.ps1') -Json
    }
    else {
        & (Join-Path $PSScriptRoot 'audit-project.ps1')
    }
}

# The suite and the audit both shell out, so they must agree on which PowerShell
# runs them. 'pwsh' is not installed everywhere this repo lives; fall back rather
# than fail with CommandNotFoundException.
function Get-PowerShellHostPath {
    foreach ($candidate in @('pwsh', 'powershell')) {
        $resolved = Get-Command -Name $candidate -CommandType Application -ErrorAction SilentlyContinue |
            Select-Object -First 1
        if ($resolved) { return $resolved.Source }
    }
    throw 'No PowerShell host found on PATH (looked for pwsh, then powershell).'
}

function Invoke-ContractTests {
    $testPath = Join-Path $projectRoot 'tests\cli-contracts.ps1'
    if (-not (Test-Path -LiteralPath $testPath)) {
        if ($Json) {
            [PSCustomObject]@{
                Suite    = 'cli-contracts'
                Passed   = $false
                ExitCode = 1
                Output   = 'tests\cli-contracts.ps1 is missing'
            } | ConvertTo-Json -Depth 3
        }
        else {
            Write-Host 'FAIL  contract suite is missing: tests\cli-contracts.ps1' -ForegroundColor Red
        }
        exit 1
    }

    $hostPath = Get-PowerShellHostPath

    # The suite runs negative cases that exit non-zero and write to stderr; under
    # 'Stop' that would terminate this process instead of being measured.
    $previousPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        if ($Json) {
            $output = & $hostPath -NoProfile -File $testPath 2>&1 | Out-String
            $code = $LASTEXITCODE
        }
        else {
            Show-Header 'CLI Contract Suite'
            & $hostPath -NoProfile -File $testPath
            $code = $LASTEXITCODE
            $output = ''
        }
    }
    finally {
        $ErrorActionPreference = $previousPreference
    }

    if ($Json) {
        [PSCustomObject]@{
            Suite      = 'cli-contracts'
            HostBinary = $hostPath
            Passed     = ($code -eq 0)
            ExitCode   = $code
            Output     = $output.Trim()
        } | ConvertTo-Json -Depth 3
    }

    if ($code -ne 0) { exit $code }
}

function Invoke-Verify {
    # One command that proves both halves. The audit reads the documents; the
    # contract suite exercises this tool. A green audit alone never proved the CLI
    # still worked -- the suite existed for eleven days without ever being run.
    $auditScript = Join-Path $PSScriptRoot 'audit-project.ps1'
    $testPath    = Join-Path $projectRoot 'tests\cli-contracts.ps1'
    $hostPath    = Get-PowerShellHostPath

    $previousPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        if ($Json) {
            $auditOutput = & $hostPath -NoProfile -File $auditScript -Json 2>&1 | Out-String
            $auditCode = $LASTEXITCODE
            $testOutput = & $hostPath -NoProfile -File $testPath 2>&1 | Out-String
            $testCode = $LASTEXITCODE
        }
        else {
            & $hostPath -NoProfile -File $auditScript
            $auditCode = $LASTEXITCODE
            Show-Header 'CLI Contract Suite'
            & $hostPath -NoProfile -File $testPath
            $testCode = $LASTEXITCODE
            $auditOutput = ''
            $testOutput = ''
        }
    }
    finally {
        $ErrorActionPreference = $previousPreference
    }

    if ($Json) {
        $auditResult = $null
        try { $auditResult = $auditOutput | ConvertFrom-Json -ErrorAction Stop } catch { $auditResult = $null }

        [PSCustomObject]@{
            Passed    = (($auditCode -eq 0) -and ($testCode -eq 0))
            Audit     = [PSCustomObject]@{
                Passed   = ($auditCode -eq 0)
                ExitCode = $auditCode
                Result   = $auditResult
                Raw      = $(if ($null -eq $auditResult) { $auditOutput.Trim() } else { $null })
            }
            Contracts = [PSCustomObject]@{
                Passed   = ($testCode -eq 0)
                ExitCode = $testCode
                Output   = $testOutput.Trim()
            }
        } | ConvertTo-Json -Depth 6
    }
    else {
        $auditLabel = if ($auditCode -eq 0) { 'PASS' } else { 'FAIL' }
        $testLabel  = if ($testCode -eq 0) { 'PASS' } else { 'FAIL' }
        Write-Host ''
        Write-Host ("VERIFY      : audit {0} | cli-contracts {1}" -f $auditLabel, $testLabel) -ForegroundColor Cyan
    }

    if (($auditCode -ne 0) -or ($testCode -ne 0)) { exit 1 }
}

switch ($Command) {
    'status'        { Show-Status }
    'triage'        { Show-Triage }
    'verify-entity' { Verify-EntityRecords }
    'calc-cvi'      { Calculate-CVI }
    'audit'         { Invoke-Audit }
    'test'          { Invoke-ContractTests }
    'verify'        { Invoke-Verify }
    'help'          {
        $commands = @(
            [PSCustomObject]@{ Name = 'status'; Description = 'Show deadlines and the active constraint' },
            [PSCustomObject]@{ Name = 'triage'; Description = 'Recalculate the portfolio scorecard from evidence rows' },
            [PSCustomObject]@{ Name = 'verify-entity'; Description = 'Validate entity draft structure and privacy' },
            [PSCustomObject]@{ Name = 'calc-cvi'; Description = 'Calculate a pre-revenue cash-velocity scenario' },
            [PSCustomObject]@{ Name = 'audit'; Description = 'Run the deterministic project audit' },
            [PSCustomObject]@{ Name = 'test'; Description = 'Run the CLI contract suite against this tool' },
            [PSCustomObject]@{ Name = 'verify'; Description = 'Run audit + contract suite; fail if either fails' }
        )

        if ($Json) {
            [PSCustomObject]@{
                Commands = $commands
                Parameters = @('Json', 'Revenue', 'Days', 'Margin', 'EntityFile')
            } | ConvertTo-Json -Depth 3
            return
        }

        Show-Header 'Usage Guide'
        Write-Host '  Available Commands:' -ForegroundColor White
        foreach ($item in $commands) {
            Write-Host ("    {0,-14} : {1}" -f $item.Name, $item.Description)
        }
        Write-Host ''
        Write-Host '  Use -Json for machine-readable output.' -ForegroundColor Gray
        Write-Host ''
    }
}
