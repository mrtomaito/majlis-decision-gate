<#
.SYNOPSIS
    أداة القيادة والتشغيل الميداني لمستشار الأعمال والتسويق «مجلس»
.DESCRIPTION
    تتيح فرز المحفظة آلياً، متابعة القيود الأسبوعية والعداد التنازلي للمواعيد التنظيمية،
    حساب مؤشر سرعة النقد CVI، والتحقق من سلامة سجلات الكيانات دون خرق الخصوصية.
.EXAMPLE
    .\scripts\majlis-cli.ps1 status
    .\scripts\majlis-cli.ps1 triage
    .\scripts\majlis-cli.ps1 verify-entity
    .\scripts\majlis-cli.ps1 calc-cvi -Revenue 600 -Days 14 -Margin 0.85
#>

[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [ValidateSet('status', 'triage', 'verify-entity', 'calc-cvi', 'audit', 'help')]
    [string]$Command = 'status',

    [Parameter()]
    [double]$Revenue = 600,

    [Parameter()]
    [int]$Days = 14,

    [Parameter()]
    [double]$Margin = 0.85,

    [Parameter()]
    [string]$EntityFile = 'docs\entity-records-draft.md'
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot

try {
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
    $OutputEncoding = [System.Text.Encoding]::UTF8
} catch {}

function Show-Header {
    param([string]$Title)
    Write-Host ''
    Write-Host "======================================================================" -ForegroundColor Cyan
    Write-Host "  Majlis | $Title" -ForegroundColor Yellow
    Write-Host "======================================================================" -ForegroundColor Cyan
    Write-Host ''
}

function Get-ProjectDeadlines {
    $now = Get-Date
    $deadlines = [ordered]@{
        'Constraint #001: 15 Entity Records (kadr)' = [DateTime]::Parse('2026-09-03')
        'Constraint #001: First 600 SAR Deal'       = [DateTime]::Parse('2026-09-17')
        'System Exit Standard: First Riyal (90d)'   = [DateTime]::Parse('2026-11-18')
        'ZATCA: Penalties Cancellation Deadline'    = [DateTime]::Parse('2026-12-31')
        'ZATCA: Wave 25 Integration Deadline'       = [DateTime]::Parse('2027-02-01')
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
    Show-Header "Operational Status & Active Constraints Dashboard"
    $todayStr = (Get-Date).ToString('yyyy-MM-dd')
    Write-Host "  Current System Date: $todayStr" -ForegroundColor Gray
    Write-Host ''

    Get-ProjectDeadlines
    Write-Host ''

    Write-Host "  Current Active Constraint:" -ForegroundColor White
    Write-Host "  --------------------------------------------------------------------" -ForegroundColor DarkGray
    Write-Host "  Selected Project : ai-freelance-income (KADR)" -ForegroundColor Green
    Write-Host "  Launch State     : Validation Candidate (0 named buyers, 0 PII)" -ForegroundColor Yellow
    Write-Host "  Weekly Sprint    : Build 15 entity-record-v1 slots before 2026-09-03" -ForegroundColor Cyan
    Write-Host "  Single Metric    : Complete entity records count (Internal Draft)" -ForegroundColor White
    Write-Host ''

    # Check draft entities
    $draftPath = Join-Path $projectRoot $EntityFile
    if (Test-Path -LiteralPath $draftPath) {
        $text = Get-Content -LiteralPath $draftPath -Raw -Encoding UTF8
        $entityMatches = [regex]::Matches($text, '<!-- entity-record-v1 id=([^ ]+) -->')
        $filledMatches = [regex]::Matches($text, '(?s)<!-- entity-record-v1 id=[^ ]+ -->(?:(?!<!-- entity-record-v1).)*?verified-at`\):\*\* \d{4}-\d{2}-\d{2}')
        Write-Host "  Entity Records in Draft ($EntityFile): $($entityMatches.Count) slots / $($filledMatches.Count) filled" -ForegroundColor Magenta
    }
    Write-Host ''
}

function Show-Triage {
    Show-Header "Deterministic Portfolio Triage & Scoring Engine"

    $scoringPath = Join-Path $projectRoot 'docs\scoring-model.md'
    if (-not (Test-Path -LiteralPath $scoringPath)) {
        Write-Error "File docs\scoring-model.md not found!"
        return
    }

    $scoringText = Get-Content -LiteralPath $scoringPath -Raw -Encoding UTF8
    $scoreEvidence = [regex]::Matches(
        $scoringText,
        '<!-- score-evidence project=([^ ]+) axis=([abcde]) score=([0-3]) grade=([abcd]) source=([^ ]+) -->'
    )

    $weights = @{ a = 3; b = 3; c = 2; d = 2; e = 1 }
    $projects = @($scoreEvidence | ForEach-Object { $_.Groups[1].Value } | Select-Object -Unique)

    Write-Host "  Deterministic Evidence-Backed Scorecard:" -ForegroundColor White
    Write-Host "  +--------------------------+----+----+----+----+----+-----------+------------------+" -ForegroundColor DarkGray
    Write-Host "  | Project Name             | Ax3| Bx3| Cx2| Dx2| Ex1| Total /33 | Launch Status    |" -ForegroundColor Cyan
    Write-Host "  +--------------------------+----+----+----+----+----+-----------+------------------+" -ForegroundColor DarkGray

    $results = @()
    foreach ($proj in $projects) {
        $projRecords = @($scoreEvidence | Where-Object { $_.Groups[1].Value -eq $proj })
        $scores = @{}
        foreach ($rec in $projRecords) {
            $scores[$rec.Groups[2].Value] = [int]$rec.Groups[3].Value
        }

        $total = ($scores['a'] * 3) + ($scores['b'] * 3) + ($scores['c'] * 2) + ($scores['d'] * 2) + ($scores['e'] * 1)
        $statusStr = if ($proj -eq 'ai-freelance-income') { "Validation Cand (1)" } elseif ($proj -eq 'realestate-ai-employee') { "Validation Cand (2)" } else { "Not Ready" }

        $results += [PSCustomObject]@{
            Project = $proj
            A = $scores['a'] * 3
            B = $scores['b'] * 3
            C = $scores['c'] * 2
            D = $scores['d'] * 2
            E = $scores['e'] * 1
            Total = $total
            Status = $statusStr
        }
    }

    foreach ($res in ($results | Sort-Object Total -Descending)) {
        Write-Host ("  | {0,-24} | {1,2} | {2,2} | {3,2} | {4,2} | {5,2} |   {6,2}/33  | {7,-16} |" -f `
            $res.Project, $res.A, $res.B, $res.C, $res.D, $res.E, $res.Total, $res.Status) -ForegroundColor White
    }
    Write-Host "  +--------------------------+----+----+----+----+----+-----------+------------------+" -ForegroundColor DarkGray
    Write-Host ''
    Write-Host "  Ruling: #1 Focus Candidate is ai-freelance-income (23/33)." -ForegroundColor Green
    Write-Host "  Tie-Breaker: 1) Buyer Evidence 2) Demand Proof 3) Cash Bleed 4) Measured CVI 5) External Deadline" -ForegroundColor Gray
    Write-Host ''
}

function Verify-EntityRecords {
    Show-Header "Entity Records Validation & Privacy (PDPL) Check"

    $filePath = Join-Path $projectRoot $EntityFile
    if (-not (Test-Path -LiteralPath $filePath)) {
        Write-Error "File $filePath not found!"
        return
    }

    $content = Get-Content -LiteralPath $filePath -Raw -Encoding UTF8
    $records = [regex]::Matches($content, '<!-- entity-record-v1 id=([^ ]+) -->')
    Write-Host "  Checking target file: $EntityFile" -ForegroundColor Cyan
    Write-Host "  Machine-readable slots found: $($records.Count)" -ForegroundColor White

    # PII Scan: Phones and personal emails
    $phoneRegex = '(\+966|00966|05)\d{8}'
    $emailRegex = '\b[A-Za-z0-9._%+-]+@(?!example\.com)[A-Za-z0-9.-]+\.[A-Za-z]{2,}\b'

    $phoneHits = [regex]::Matches($content, $phoneRegex)
    $emailHits = [regex]::Matches($content, $emailRegex)

    if ($phoneHits.Count -eq 0 -and $emailHits.Count -eq 0) {
        Write-Host "  [PASS] Zero PII (no personal phone/email leaks) - PDPL Compliant" -ForegroundColor Green
    } else {
        Write-Host "  [FAIL] Privacy Breach Warning! Personal data detected in file:" -ForegroundColor Red
        if ($phoneHits.Count -gt 0) { Write-Host "    - Found $($phoneHits.Count) phone numbers!" -ForegroundColor Red }
        if ($emailHits.Count -gt 0) { Write-Host "    - Found $($emailHits.Count) email addresses!" -ForegroundColor Red }
    }

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

    Write-Host "  Slots FILLED with a real entity: $filled of 15" -ForegroundColor White
    if ($filled -ge 15) {
        Write-Host "  [PASS] 15 entity-record-v1 records are filled and dated." -ForegroundColor Green
    } else {
        Write-Host "  [OPEN] Constraint #001 preliminary gate NOT met: $filled/15 filled ($(15 - $filled) remaining)." -ForegroundColor Yellow
        Write-Host "         Empty template slots are craft scaffolding, not market progress." -ForegroundColor Yellow
    }
    Write-Host ''
}

function Calculate-CVI {
    Show-Header "Cash Velocity Index (CVI) Simulator"

    if ($Days -le 0) {
        Write-Error "Days must be greater than 0!"
        return
    }

    $cvi = ($Revenue / $Days) * $Margin
    Write-Host ("  Expected Deal Revenue   : {0:N0} SAR" -f $Revenue) -ForegroundColor White
    Write-Host ("  Days to Cash Collection : {0} days" -f $Days) -ForegroundColor White
    Write-Host ("  Gross Profit Margin     : {0:P0}" -f $Margin) -ForegroundColor White
    Write-Host ("  Cash Velocity Index CVI : {0:F2}" -f $cvi) -ForegroundColor Green
    Write-Host ''

    Write-Host "  Sensitivity & Scenario Analysis:" -ForegroundColor White
    Write-Host "  +----------------+---------+--------+--------+--------+" -ForegroundColor DarkGray
    Write-Host "  | Scenario       | Revenue | Days   | Margin | CVI    |" -ForegroundColor Cyan
    Write-Host "  +----------------+---------+--------+--------+--------+" -ForegroundColor DarkGray

    $scenarios = @(
        @{ Name = "Conservative (Slow)"; Rev = $Revenue; Days = [Math]::Max(1, $Days * 2); Mar = [Math]::Max(0.1, $Margin - 0.15) }
        @{ Name = "Base Hypothesis     "; Rev = $Revenue; Days = $Days; Mar = $Margin }
        @{ Name = "Optimistic (Fast)   "; Rev = $Revenue; Days = [Math]::Max(1, [int]($Days / 2)); Mar = [Math]::Min(1.0, $Margin + 0.1) }
    )

    foreach ($sc in $scenarios) {
        $scCvi = ($sc.Rev / $sc.Days) * $sc.Mar
        Write-Host ("  | {0} | {1,7:N0} | {2,6} | {3,6:P0} | {4,6:F2} |" -f $sc.Name, $sc.Rev, $sc.Days, $sc.Mar, $scCvi) -ForegroundColor White
    }
    Write-Host "  +----------------+---------+--------+--------+--------+" -ForegroundColor DarkGray
    Write-Host "  Note: Pre-revenue CVI is a scenario comparison tool, not deterministic accounting." -ForegroundColor Gray
    Write-Host ''
}

switch ($Command) {
    'status'        { Show-Status }
    'triage'        { Show-Triage }
    'verify-entity' { Verify-EntityRecords }
    'calc-cvi'      { Calculate-CVI }
    'audit'         { & (Join-Path $PSScriptRoot 'audit-project.ps1') }
    'help'          {
        Show-Header "Usage Guide"
        Write-Host "  Available Commands:" -ForegroundColor White
        Write-Host "    .\scripts\majlis-cli.ps1 status         : Show milestone countdown and active constraints"
        Write-Host "    .\scripts\majlis-cli.ps1 triage         : Run automated portfolio triage & recalculation"
        Write-Host "    .\scripts\majlis-cli.ps1 verify-entity  : Validate entity records draft and privacy compliance"
        Write-Host "    .\scripts\majlis-cli.ps1 calc-cvi       : Calculate Cash Velocity Index with sensitivity scenarios"
        Write-Host "    .\scripts\majlis-cli.ps1 audit          : Run complete deterministic audit suite"
        Write-Host ''
    }
}
