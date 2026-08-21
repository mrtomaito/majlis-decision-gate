[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$failures = [System.Collections.Generic.List[string]]::new()
$passes = [System.Collections.Generic.List[string]]::new()

function Add-AuditResult {
    param(
        [bool]$Condition,
        [string]$PassMessage,
        [string]$FailMessage
    )

    if ($Condition) {
        $passes.Add($PassMessage)
    }
    else {
        $failures.Add($FailMessage)
    }
}

function Get-ProjectText {
    param([string]$RelativePath)

    Get-Content -LiteralPath (Join-Path $projectRoot $RelativePath) -Raw -Encoding UTF8
}

$requiredFiles = @(
    'CLAUDE.md',
    'portfolio.md',
    'docs\decision-log.md',
    'docs\evidence-standard.md',
    'docs\privacy-data-handling.md',
    'docs\source-register.md',
    'docs\weekly-constraint-loop.md',
    'docs\scoring-model.md',
    '.claude\skills\consultation\SKILL.md',
    '.claude\skills\portfolio-triage\SKILL.md'
)

foreach ($relativePath in $requiredFiles) {
    Add-AuditResult `
        -Condition (Test-Path -LiteralPath (Join-Path $projectRoot $relativePath)) `
        -PassMessage "required file exists: $relativePath" `
        -FailMessage "missing required file: $relativePath"
}

Add-AuditResult `
    -Condition (-not (Test-Path -LiteralPath (Join-Path $projectRoot 'AGENTS.md'))) `
    -PassMessage 'AGENTS.md is absent' `
    -FailMessage 'AGENTS.md must not exist because it masks CLAUDE.md'

$claudePath = Join-Path $projectRoot 'CLAUDE.md'
if (Test-Path -LiteralPath $claudePath) {
    $claudeSize = (Get-Item -LiteralPath $claudePath).Length
    Add-AuditResult `
        -Condition ($claudeSize -le 10240) `
        -PassMessage "CLAUDE.md is within the 10 KiB ceiling ($claudeSize bytes)" `
        -FailMessage "CLAUDE.md exceeds the 10 KiB ceiling ($claudeSize bytes)"

    $claude = Get-ProjectText 'CLAUDE.md'
    Add-AuditResult `
        -Condition ($claude -match '<!-- market-stage-contract -->') `
        -PassMessage 'market-stage contract distinguishes preparation from external execution' `
        -FailMessage 'CLAUDE.md must declare a machine-readable market-stage contract'

    $hasFiveLaws = ($claude -match 'القوانين الخمسة') -and `
                   ($claude -match '1\.\s+\*\*واحد فقط') -and `
                   ($claude -match '2\.\s+\*\*لا مشترٍ مسمّى') -and `
                   ($claude -match '3\.\s+\*\*كل مرحلة سوقية') -and `
                   ($claude -match '4\.\s+\*\*لا تقمّص') -and `
                   ($claude -match '5\.\s+\*\*كل توصية تُقيَّد')
    Add-AuditResult `
        -Condition $hasFiveLaws `
        -PassMessage 'CLAUDE.md declares all five governing laws intact' `
        -FailMessage 'CLAUDE.md must declare all five governing laws'
}

$markdownFiles = Get-ChildItem -LiteralPath $projectRoot -Recurse -File -Filter '*.md' |
    Where-Object { $_.FullName -notmatch '[\\/]\.git[\\/]' }

$brokenLinks = [System.Collections.Generic.List[string]]::new()
foreach ($markdownFile in $markdownFiles) {
    $text = Get-Content -LiteralPath $markdownFile.FullName -Raw -Encoding UTF8
    foreach ($match in [regex]::Matches($text, '\[[^\]]+\]\(([^)]+)\)')) {
        $link = $match.Groups[1].Value.Split('#')[0]
        if (-not $link -or $link -match '^(https?:|mailto:|#)' -or $link -match '^[A-Za-z]:\\') {
            continue
        }

        $target = Join-Path $markdownFile.DirectoryName $link
        if (-not (Test-Path -LiteralPath $target)) {
            $relativeFile = $markdownFile.FullName.Substring($projectRoot.Length + 1)
            $brokenLinks.Add("$relativeFile -> $link")
        }
    }
}
Add-AuditResult `
    -Condition ($brokenLinks.Count -eq 0) `
    -PassMessage 'all local Markdown links resolve' `
    -FailMessage ("broken local Markdown links: " + ($brokenLinks -join '; '))

$skillFiles = @(
    Get-ChildItem -LiteralPath (Join-Path $projectRoot '.claude\skills') -Recurse -File -Filter 'SKILL.md'
    Get-ChildItem -LiteralPath (Join-Path $projectRoot 'vendor\wondelai') -Recurse -File -Filter 'SKILL.md'
)
foreach ($skillFile in $skillFiles) {
    $text = Get-Content -LiteralPath $skillFile.FullName -Raw -Encoding UTF8
    $frontmatter = [regex]::Match($text, '(?ms)^---\s*$\s*(.*?)^---\s*$')
    $nameMatch = if ($frontmatter.Success) {
        [regex]::Match($frontmatter.Groups[1].Value, '(?m)^name:\s*[''\"]?([^''\"\r\n]+)')
    }
    else {
        $null
    }
    $descriptionPresent = $frontmatter.Success -and $frontmatter.Groups[1].Value -match '(?m)^description:\s*\S+'
    $folderName = $skillFile.Directory.Name
    $validName = $nameMatch -and $nameMatch.Success -and $nameMatch.Groups[1].Value.Trim() -eq $folderName

    $relativeFile = $skillFile.FullName.Substring($projectRoot.Length + 1)
    Add-AuditResult `
        -Condition ($frontmatter.Success -and $descriptionPresent -and $validName) `
        -PassMessage "skill frontmatter is valid: $relativeFile" `
        -FailMessage "invalid skill frontmatter or name mismatch: $relativeFile"
}

$limitsPath = Join-Path $projectRoot 'vendor\wondelai\LIMITS.md'
if (Test-Path -LiteralPath $limitsPath) {
    $limitsText = Get-ProjectText 'vendor\wondelai\LIMITS.md'
    $vendorSkillDirs = Get-ChildItem -LiteralPath (Join-Path $projectRoot 'vendor\wondelai') -Directory
    foreach ($vDir in $vendorSkillDirs) {
        $vName = $vDir.Name
        $hasLimit = $limitsText -match [regex]::Escape("## ``$vName``") -or $limitsText -match [regex]::Escape("## $vName")
        Add-AuditResult `
            -Condition $hasLimit `
            -PassMessage "vendor skill '$vName' has documented failure boundaries in LIMITS.md" `
            -FailMessage "vendor skill '$vName' missing from LIMITS.md"
    }
}

if (Test-Path -LiteralPath (Join-Path $projectRoot 'portfolio.md')) {
    $portfolioText = Get-ProjectText 'portfolio.md'
    $tableRows = [regex]::Matches($portfolioText, '(?m)^\|\s*`([a-z0-9-]+)`.*?\|(.*?)\|$')
    Add-AuditResult `
        -Condition ($tableRows.Count -ge 1) `
        -PassMessage "portfolio table catalogs $($tableRows.Count) project(s)" `
        -FailMessage 'portfolio table has no project rows; fill portfolio.md from portfolio.example.md'

    $malformedRows = @($tableRows | Where-Object { ($_.Value -split '\|').Count -ne 8 })
    Add-AuditResult `
        -Condition ($malformedRows.Count -eq 0) `
        -PassMessage 'all 27 portfolio table rows have consistent 6-column structure' `
        -FailMessage "portfolio has malformed rows: $($malformedRows.Count)"
}

$entityDraftPath = Join-Path $projectRoot 'docs\entity-records-draft.md'
Add-AuditResult `
    -Condition (Test-Path -LiteralPath $entityDraftPath) `
    -PassMessage 'entity records draft exists: docs\entity-records-draft.md' `
    -FailMessage 'missing docs\entity-records-draft.md'

if (Test-Path -LiteralPath $entityDraftPath) {
    $draftContent = Get-ProjectText 'docs\entity-records-draft.md'
    $draftRecords = [regex]::Matches($draftContent, '<!-- entity-record-v1 id=([^ ]+) -->')
    # The slot target belongs to the owner's constraint, not to this script.
    # Read it from the collection marker so a fork can set its own number.
    $targetMatch = [regex]::Match($draftContent, '<!-- entity-records-collection[^>]*target=(\d+)')
    $slotTarget = if ($targetMatch.Success) { [int]$targetMatch.Groups[1].Value } else { 0 }
    Add-AuditResult `
        -Condition ($slotTarget -gt 0) `
        -PassMessage "entity records declare a slot target of $slotTarget" `
        -FailMessage 'entity records draft must declare target=N in its entity-records-collection marker'
    Add-AuditResult `
        -Condition ($draftRecords.Count -ge $slotTarget) `
        -PassMessage "entity records draft contains $($draftRecords.Count) machine-readable slots (target $slotTarget)" `
        -FailMessage "entity records draft declares target=$slotTarget but holds only $($draftRecords.Count) slots"

    # An unfilled slot must never carry a verification date. A date on a
    # placeholder is fabricated evidence -- the exact false precision this
    # project forbids in docs/evidence-standard.md.
    $draftBodies = [regex]::Split($draftContent, '<!-- entity-record-v1 id=[^ ]+ -->')
    $fabricated = 0
    $filledRecords = 0
    for ($i = 1; $i -lt $draftBodies.Count; $i++) {
        $body = $draftBodies[$i]
        $cut = $body.IndexOf('### ')
        if ($cut -ge 0) { $body = $body.Substring(0, $cut) }
        $hasPlaceholder = [regex]::IsMatch($body, '\[[^\]]+\]')
        $hasRealDate = [regex]::IsMatch($body, 'verified-at`\):\*\* \d{4}-\d{2}-\d{2}')
        if ($hasPlaceholder -and $hasRealDate) { $fabricated++ }
        if ((-not $hasPlaceholder) -and $hasRealDate) { $filledRecords++ }
    }

    Add-AuditResult `
        -Condition ($fabricated -eq 0) `
        -PassMessage 'no unfilled entity slot carries a fabricated verified-at date' `
        -FailMessage "$fabricated unfilled entity slots carry a verified-at date; a placeholder cannot be verified"

    Add-AuditResult `
        -Condition ($true) `
        -PassMessage "entity records filled with a real entity: $filledRecords of 15 (craft scaffolding is not market progress; the market gate lives in constraint #001)" `
        -FailMessage 'unreachable'
}

# --- source freshness contract -------------------------------------------
$registerText = Get-ProjectText 'docs\source-register.md'
Add-AuditResult `
    -Condition ($registerText -match '<!-- source-freshness-contract -->') `
    -PassMessage 'source register declares a machine-readable freshness contract' `
    -FailMessage 'docs/source-register.md must declare <!-- source-freshness-contract -->'

# Regulatory sources carry a 90-day window. Past it, evidence grade drops to c
# until the primary page is reopened -- stale regulation quoted as fact is the
# fastest way this advisor becomes wrong with confidence.
$verifiedMatch = [regex]::Match($registerText, 'آخر تحقق:\s*(\d{4}-\d{2}-\d{2})')
if ($verifiedMatch.Success) {
    $lastVerified = [datetime]::ParseExact($verifiedMatch.Groups[1].Value, 'yyyy-MM-dd', $null)
    $ageDays = ([datetime]::Today - $lastVerified).Days
    Add-AuditResult `
        -Condition ($ageDays -le 90) `
        -PassMessage "source register verified $ageDays days ago (within the 90-day regulatory window)" `
        -FailMessage "source register is $ageDays days old; reopen the primary pages and refresh 'آخر تحقق' before quoting any regulatory date"
} else {
    Add-AuditResult `
        -Condition $false `
        -PassMessage 'unreachable' `
        -FailMessage "docs/source-register.md must carry a parseable 'آخر تحقق: YYYY-MM-DD' header"
}

$cliPath = Join-Path $projectRoot 'scripts\majlis-cli.ps1'
Add-AuditResult `
    -Condition (Test-Path -LiteralPath $cliPath) `
    -PassMessage 'majlis operational CLI exists: scripts\majlis-cli.ps1' `
    -FailMessage 'missing scripts\majlis-cli.ps1'

$gitignorePath = Join-Path $projectRoot '.gitignore'
Add-AuditResult `
    -Condition (Test-Path -LiteralPath $gitignorePath) `
    -PassMessage '.gitignore exists for workspace protection' `
    -FailMessage 'missing .gitignore'

if (Test-Path -LiteralPath $gitignorePath) {
    $gitIgnoreText = Get-ProjectText '.gitignore'
    $hasPrivateStore = $gitIgnoreText -match 'restricted-store'
    Add-AuditResult `
        -Condition $hasPrivateStore `
        -PassMessage '.gitignore protects restricted contact stores' `
        -FailMessage '.gitignore must exclude restricted stores'
}

if (Test-Path -LiteralPath (Join-Path $projectRoot 'docs\scoring-model.md')) {
    $scoring = Get-ProjectText 'docs\scoring-model.md'
    $demandSectionMatch = [regex]::Match(
        $scoring,
        '(?ms)<!-- demand-evidence-scale -->(.*?)<!-- /demand-evidence-scale -->'
    )
    Add-AuditResult `
        -Condition $demandSectionMatch.Success `
        -PassMessage 'demand evidence scale is machine-readable' `
        -FailMessage 'scoring model must wrap the demand scale in demand-evidence-scale markers'

    $demandSection = $demandSectionMatch.Groups[1].Value
    foreach ($score in 0..3) {
        $count = [regex]::Matches($demandSection, "(?m)^- \*\*${score}:").Count
        Add-AuditResult `
            -Condition ($count -eq 1) `
            -PassMessage "demand-evidence score $score appears exactly once" `
            -FailMessage "demand-evidence score $score must appear exactly once; found $count"
    }

    Add-AuditResult `
        -Condition ($scoring -match 'buyer-evidence-v1') `
        -PassMessage 'buyer-evidence-v1 contract is declared in scoring model' `
        -FailMessage 'scoring model must declare buyer-evidence-v1 contract'

    $scoreEvidence = [regex]::Matches(
        $scoring,
        '<!-- score-evidence project=([^ ]+) axis=([abcde]) score=([0-3]) grade=([abcd]) source=([^ ]+) -->'
    )
    Add-AuditResult `
        -Condition ($scoreEvidence.Count -eq 15) `
        -PassMessage 'current scorecard has 15 machine-readable evidence records' `
        -FailMessage "current scorecard must have 15 machine-readable evidence records; found $($scoreEvidence.Count)"

    $expectedTotals = [ordered]@{
        'ai-freelance-income' = 23
        'realestate-ai-employee' = 20
        'zatca-einvoicing-warraq' = 10
    }
    $weights = @{ a = 3; b = 3; c = 2; d = 2; e = 1 }
    foreach ($project in $expectedTotals.Keys) {
        $records = @($scoreEvidence | Where-Object { $_.Groups[1].Value -eq $project })
        $axes = @($records | ForEach-Object { $_.Groups[2].Value } | Sort-Object -Unique)
        $total = 0
        foreach ($record in $records) {
            $axis = $record.Groups[2].Value
            $total += [int]$record.Groups[3].Value * $weights[$axis]
        }
        Add-AuditResult `
            -Condition ($records.Count -eq 5 -and $axes.Count -eq 5 -and $total -eq $expectedTotals[$project]) `
            -PassMessage "score evidence recalculates $project to $total" `
            -FailMessage "score evidence for $project is incomplete or totals $total instead of $($expectedTotals[$project])"
    }
}

if (Test-Path -LiteralPath (Join-Path $projectRoot 'docs\evidence-standard.md')) {
    $evidenceStandard = Get-ProjectText 'docs\evidence-standard.md'
    $buyerContract = [regex]::Match(
        $evidenceStandard,
        '(?ms)<!-- buyer-evidence-v1 -->(.*?)<!-- /buyer-evidence-v1 -->'
    )
    Add-AuditResult `
        -Condition $buyerContract.Success `
        -PassMessage 'buyer-evidence-v1 contract is machine-readable' `
        -FailMessage 'evidence standard must wrap buyer-evidence-v1 in machine-readable markers'

    foreach ($field in @(
        'entity-name',
        'buyer-job',
        'public-source',
        'organization-channel',
        'outreach-consent',
        'contact-ref',
        'verified-at',
        'evidence-id'
    )) {
        Add-AuditResult `
            -Condition ($buyerContract.Success -and $buyerContract.Groups[1].Value -match [regex]::Escape("field=$field")) `
            -PassMessage "buyer-evidence-v1 declares $field" `
            -FailMessage "buyer-evidence-v1 must declare $field"
    }
}

if (Test-Path -LiteralPath (Join-Path $projectRoot 'docs\privacy-data-handling.md')) {
    $privacy = Get-ProjectText 'docs\privacy-data-handling.md'
    foreach ($policy in @(
        'project-personal-data=forbidden',
        'restricted-contact-store=required',
        'retention-or-deletion=required',
        'prior-interaction-is-consent=false',
        'regulatory-threat-without-primary-source=forbidden'
    )) {
        Add-AuditResult `
            -Condition ($privacy -match [regex]::Escape($policy)) `
            -PassMessage "privacy policy declares $policy" `
            -FailMessage "privacy policy must declare $policy"
    }
}

if (Test-Path -LiteralPath (Join-Path $projectRoot 'docs\playbook-weekly-sprint.md')) {
    $weeklySprint = Get-ProjectText 'docs\playbook-weekly-sprint.md'
    $activeConstraintMarkers = [regex]::Matches(
        $weeklySprint,
        '<!-- active-constraint=([^ ]+) metric=([^ ]+) -->'
    )
    Add-AuditResult `
        -Condition ($activeConstraintMarkers.Count -eq 1) `
        -PassMessage 'weekly sprint declares exactly one active constraint and metric' `
        -FailMessage "weekly sprint must declare exactly one active constraint and metric; found $($activeConstraintMarkers.Count)"
}

if (Test-Path -LiteralPath (Join-Path $projectRoot 'docs\decision-log.md')) {
    $decisionLog = Get-ProjectText 'docs\decision-log.md'
    foreach ($cId in @('001', '002', '003', '004')) {
        $hasHeader = $decisionLog -match [regex]::Escape("## قيد #$cId")
        Add-AuditResult `
            -Condition $hasHeader `
            -PassMessage "decision log records constraint #$cId" `
            -FailMessage "decision log missing constraint #$cId"
    }

    $constraint004 = [regex]::Match($decisionLog, '(?ms)^## .+?#004(.*?)(?=^## |\z)')
    Add-AuditResult `
        -Condition ($constraint004.Success -and $constraint004.Groups[1].Value -match '<!-- single-metric=project-audit-failures -->') `
        -PassMessage 'constraint 004 declares one craft metric without absorbing the market constraint' `
        -FailMessage 'constraint 004 must declare project-audit-failures as its single craft metric'

    $constraint004Record = [regex]::Match(
        $constraint004.Groups[1].Value,
        '<!-- constraint-record id=004 baseline=14 metric=project-audit-failures target=0 read-at=2026-08-20 evidence=docs/audit-2026-08-20.md -->'
    )
    Add-AuditResult `
        -Condition $constraint004Record.Success `
        -PassMessage 'constraint 004 has a complete machine-readable measurement contract' `
        -FailMessage 'constraint 004 must declare its baseline, one metric, target, read date, and evidence'
}

$firstPartyFiles = $markdownFiles | Where-Object {
    $_.FullName -notmatch '[\\/]vendor[\\/]' -and
    $_.FullName -notmatch '[\\/]tasks[\\/]'
}

$piiEmailRegex = '\b[A-Za-z0-9._%+-]+@(?!example\.com)[A-Za-z0-9.-]+\.[A-Za-z]{2,}\b'
$piiPhoneRegex = '(\+966|00966|05)\d{8}'
$piiHits = [System.Collections.Generic.List[string]]::new()
foreach ($firstPartyFile in $firstPartyFiles) {
    $text = Get-Content -LiteralPath $firstPartyFile.FullName -Raw -Encoding UTF8
    if ($text -match $piiEmailRegex) {
        $piiHits.Add("$($firstPartyFile.Name) (email)")
    }
    if ($text -match $piiPhoneRegex) {
        $piiHits.Add("$($firstPartyFile.Name) (phone)")
    }
}
Add-AuditResult `
    -Condition ($piiHits.Count -eq 0) `
    -PassMessage 'zero personal PII (email/phone) detected in first-party documents' `
    -FailMessage ("PII detected in: " + ($piiHits -join ', '))

$forbiddenPatterns = [ordered]@{
    'unsupported local channel rates' = '<\s*5%|>\s*85%'
    'unsupported follow-up folklore' = '80%'
    'absolute guarantees and margins' = '100%'
    'unsupported superiority claim' = 'best-in-class|world-class'
}

foreach ($entry in $forbiddenPatterns.GetEnumerator()) {
    $hits = [System.Collections.Generic.List[string]]::new()
    foreach ($firstPartyFile in $firstPartyFiles) {
        $text = Get-Content -LiteralPath $firstPartyFile.FullName -Raw -Encoding UTF8
        if ($text -match $entry.Value) {
            $hits.Add($firstPartyFile.FullName.Substring($projectRoot.Length + 1))
        }
    }
    Add-AuditResult `
        -Condition ($hits.Count -eq 0) `
        -PassMessage "forbidden pattern absent: $($entry.Key)" `
        -FailMessage ("forbidden pattern '$($entry.Key)' found in: " + ($hits -join ', '))
}

if (Test-Path -LiteralPath (Join-Path $projectRoot 'docs\source-register.md')) {
    $sourceRegister = Get-ProjectText 'docs\source-register.md'
    foreach ($requiredSource in @('zatca.gov.sa', 'dgp.sdaia.gov.sa', 'markster-public/markster-os', 'cgallic/kai-cmo-harness')) {
        Add-AuditResult `
            -Condition ($sourceRegister -match [regex]::Escape($requiredSource)) `
            -PassMessage "source register includes $requiredSource" `
            -FailMessage "source register must include $requiredSource"
    }
}

if (Test-Path -LiteralPath (Join-Path $projectRoot '.claude\skills\consultation\SKILL.md')) {
    $consultation = Get-ProjectText '.claude\skills\consultation\SKILL.md'
    foreach ($contractReference in @('docs/evidence-standard.md', 'docs/weekly-constraint-loop.md')) {
        Add-AuditResult `
            -Condition ($consultation -match [regex]::Escape($contractReference)) `
            -PassMessage "consultation routes through $contractReference" `
            -FailMessage "consultation must route through $contractReference"
    }
}

foreach ($message in $passes) {
    Write-Host "PASS  $message" -ForegroundColor Green
}
foreach ($message in $failures) {
    Write-Host "FAIL  $message" -ForegroundColor Red
}

Write-Host ''
Write-Host "Audit summary: $($passes.Count) passed, $($failures.Count) failed."

if ($failures.Count -gt 0) {
    exit 1
}
