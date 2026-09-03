[CmdletBinding()]
param(
    [Parameter()]
    [switch]$Json
)

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

    $normalized = $RelativePath -replace '[\\/]', [System.IO.Path]::DirectorySeparatorChar
    Get-Content -LiteralPath (Join-Path $projectRoot $normalized) -Raw -Encoding UTF8
}

$requiredFiles = @(
    'CLAUDE.md',
    'portfolio.md',
    'docs\unit-economics-book.example.md',
    'docs\decision-log.md',
    'docs\evidence-standard.md',
    'docs\privacy-data-handling.md',
    'docs\source-register.md',
    'docs\weekly-constraint-loop.md',
    'docs\scoring-model.md',
    'tests\cli-contracts.ps1',
    '.claude\skills\consultation\SKILL.md',
    '.claude\skills\portfolio-triage\SKILL.md'
)

foreach ($relativePath in $requiredFiles) {
    Add-AuditResult `
        -Condition (Test-Path -LiteralPath (Join-Path $projectRoot $relativePath)) `
        -PassMessage "required file exists: $relativePath" `
        -FailMessage "missing required file: $relativePath"
}

# AGENTS.md must stay absent. Codex resolves AGENTS.md BEFORE the CLAUDE.md
# fallback, so its mere presence shadows the real instruction file -- and the
# copy that appeared on 2026-08-27 carried dead ~/.Codex/... paths, exactly the
# defect deleted on 2026-08-21. An audit that tolerates a reverted decision is
# not an audit; this fails on return instead of adapting to it.
foreach ($banned in @('AGENTS.md', '.agents')) {
    Add-AuditResult `
        -Condition (-not (Test-Path -LiteralPath (Join-Path $projectRoot $banned))) `
        -PassMessage "banned path is absent: $banned (CLAUDE.md is the single instruction file)" `
        -FailMessage "$banned exists again; it shadows CLAUDE.md for Codex and was deleted by decision on 2026-08-21"
}

$instructionFiles = @('CLAUDE.md')

foreach ($instFile in $instructionFiles) {
    $instContent = Get-ProjectText $instFile

    # Measured in CHARACTERS, not bytes. Arabic costs two bytes per character in
    # UTF-8, so a byte ceiling silently halves an Arabic instruction file's
    # budget for no reason. The governing rule is 10,000 characters.
    $instSize = $instContent.Length
    Add-AuditResult `
        -Condition ($instSize -le 10000) `
        -PassMessage "$instFile is within the 10,000-character ceiling ($instSize chars)" `
        -FailMessage "$instFile exceeds the 10,000-character ceiling ($instSize chars)"
    Add-AuditResult `
        -Condition ($instContent -match '<!-- market-stage-contract -->') `
        -PassMessage "$instFile declares machine-readable market-stage contract" `
        -FailMessage "$instFile must declare a machine-readable market-stage contract"

    $hasFiveLaws = ($instContent -match 'القوانين الخمسة') -and `
                   ($instContent -match '1\.\s+\*\*واحد فقط') -and `
                   ($instContent -match '2\.\s+\*\*لا مشترٍ مسمّى') -and `
                   ($instContent -match '3\.\s+\*\*كل مرحلة سوقية') -and `
                   ($instContent -match '4\.\s+\*\*لا تقمّص') -and `
                   ($instContent -match '5\.\s+\*\*كل توصية تُقيَّد')
    Add-AuditResult `
        -Condition $hasFiveLaws `
        -PassMessage "$instFile declares all five governing laws intact" `
        -FailMessage "$instFile must declare all five governing laws"
}

$markdownFiles = Get-ChildItem -LiteralPath $projectRoot -Recurse -File -Filter '*.md' |
    Where-Object {
        $_.FullName -notmatch '[\\/]\.git[\\/]' -and
        $_.FullName -notmatch '[\\/]\.review-quarantine-[^\\/]+[\\/]'
    }

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

$skillSearchDirs = @('.claude\skills', 'vendor\wondelai')
$skillFiles = [System.Collections.Generic.List[System.IO.FileInfo]]::new()
foreach ($sDir in $skillSearchDirs) {
    $dirPath = Join-Path $projectRoot $sDir
    if (Test-Path -LiteralPath $dirPath) {
        $found = Get-ChildItem -LiteralPath $dirPath -Recurse -File -Filter 'SKILL.md'
        foreach ($f in $found) { $skillFiles.Add($f) }
    }
}
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
    $tableRows = [regex]::Matches($portfolioText, '(?m)^\|\s*`([a-z0-9-]+)`.*?\|(.*?)\|\r?$')
    Add-AuditResult `
        -Condition ($tableRows.Count -ge 1) `
        -PassMessage "portfolio table catalogs $($tableRows.Count) project(s)" `
        -FailMessage 'portfolio table has no project rows; fill portfolio.md from portfolio.example.md'

    $malformedRows = @($tableRows | Where-Object { ($_.Value -split '\|').Count -ne 8 })
    Add-AuditResult `
        -Condition ($malformedRows.Count -eq 0) `
        -PassMessage "all $($tableRows.Count) portfolio table rows have consistent 6-column structure" `
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

    # This is the one check allowed to fail on doing nothing. Every other check
    # in this file measures craft, and craft went 96 -> 108 -> 138 green while
    # the filled-slot count stayed at zero. A gate that cannot expire is not a
    # gate; past its date with an empty list, the audit is red and stays red.
    $gateMatch = [regex]::Match($draftContent, '<!-- entity-records-collection[^>]*gate=(\d{4}-\d{2}-\d{2})')
    Add-AuditResult `
        -Condition $gateMatch.Success `
        -PassMessage "entity records declare a machine-readable gate date of $($gateMatch.Groups[1].Value)" `
        -FailMessage 'entity records draft must declare gate=YYYY-MM-DD in its entity-records-collection marker'

    if ($gateMatch.Success) {
        $gateDate = [datetime]::ParseExact($gateMatch.Groups[1].Value, 'yyyy-MM-dd', $null)
        $daysToGate = ($gateDate - [datetime]::Today).Days
        $marketState = "$filledRecords of $slotTarget slot(s) filled with a real entity"
        Add-AuditResult `
            -Condition (($daysToGate -ge 0) -or ($filledRecords -ge $slotTarget)) `
            -PassMessage $(if ($filledRecords -ge $slotTarget) { "market gate met: $marketState" } else { "market gate open: $marketState, $daysToGate day(s) to $($gateMatch.Groups[1].Value)" }) `
            -FailMessage "MARKET GATE MISSED: $marketState, $([Math]::Abs($daysToGate)) day(s) past $($gateMatch.Groups[1].Value). Craft fixes do not clear this; only a filled slot does."

        $script:MarketLine = if ($filledRecords -ge $slotTarget) {
            "$marketState -- gate met."
        } elseif ($daysToGate -ge 0) {
            "$marketState -- $daysToGate day(s) left to $($gateMatch.Groups[1].Value). Green below means the craft is intact, NOT that the market moved."
        } else {
            "$marketState -- $([Math]::Abs($daysToGate)) day(s) OVERDUE past $($gateMatch.Groups[1].Value)."
        }
    }
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

    # Every private ledger needs an explicit exclusion. The unit-economics book
    # earned its line the hard way: its figures -- a lease and a monthly burn --
    # sat inline in majlis-cli.ps1 and would have been published on next push.
    foreach ($ledger in @('portfolio.md', 'docs/decision-log.md', 'docs/entity-records-draft.md', 'docs/unit-economics-book.md')) {
        Add-AuditResult `
            -Condition ($gitIgnoreText -match ('(?m)^' + [regex]::Escape($ledger) + '\s*$')) `
            -PassMessage "private ledger is excluded from git: $ledger" `
            -FailMessage "'.gitignore' must exclude the private ledger $ledger"
    }
}

# A financial position is data, not logic. Figures naming a lease, a monthly
# burn or a personal reserve belong in the gitignored ledger, never inline in a
# tracked script where the next push publishes them.
$cliSource = Get-ProjectText 'scripts\majlis-cli.ps1'
# Only literals are flagged. Assigning from $Margin or from a ledger field is
# exactly the fix; a bare number on the right-hand side is the leak.
$inlineFinance = [regex]::Matches($cliSource, '(?m)^\s*(?:BurnRateSAR|PriceSAR|GrossMargin|DaysToCash)\s*=\s*[\d.]+\s*(?:[,;]|#.*)?\s*$')
Add-AuditResult `
    -Condition ($inlineFinance.Count -eq 0) `
    -PassMessage 'no private financial figures are hard-coded in majlis-cli.ps1' `
    -FailMessage "majlis-cli.ps1 hard-codes $($inlineFinance.Count) financial field(s); move them to docs/unit-economics-book.md"

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
    $scoredProjects = @($scoreEvidence | ForEach-Object { $_.Groups[1].Value } | Select-Object -Unique)
    Add-AuditResult `
        -Condition ($scoreEvidence.Count -gt 0 -and $scoreEvidence.Count -eq ($scoredProjects.Count * 5)) `
        -PassMessage "current scorecard has $($scoreEvidence.Count) evidence records across $($scoredProjects.Count) project(s), five axes each" `
        -FailMessage "scorecard must hold exactly five axis records per project; found $($scoreEvidence.Count) across $($scoredProjects.Count) project(s)"

    # The audit used to pin the three project names and their totals (23/20/10)
    # literally, which froze the ranking: scoring a fourth project failed the
    # audit. What must be guaranteed is not WHICH projects are scored but that
    # the total printed in the scorecard equals the sum of its own evidence.
    $weights = @{ a = 3; b = 3; c = 2; d = 2; e = 1 }
    foreach ($project in $scoredProjects) {
        $records = @($scoreEvidence | Where-Object { $_.Groups[1].Value -eq $project })
        $axes = @($records | ForEach-Object { $_.Groups[2].Value } | Sort-Object -Unique)
        $total = 0
        foreach ($record in $records) {
            $total += [int]$record.Groups[3].Value * $weights[$record.Groups[2].Value]
        }

        $declared = [regex]::Match($scoring, '(?m)^\|\s*`' + [regex]::Escape($project) + '`\s*\|.*?\*\*(\d+)/33\*\*')
        Add-AuditResult `
            -Condition ($records.Count -eq 5 -and $axes.Count -eq 5 -and $declared.Success -and [int]$declared.Groups[1].Value -eq $total) `
            -PassMessage "scorecard row for $project recalculates to $total/33 from its own evidence" `
            -FailMessage $(if (-not $declared.Success) { "$project has evidence records but no **N/33** total in the scorecard table" } else { "$project declares $($declared.Groups[1].Value)/33 but its evidence sums to $total" })
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
    $constraintHeaders = [regex]::Matches($decisionLog, '(?m)^## قيد #(\d+)')
    Add-AuditResult `
        -Condition ($constraintHeaders.Count -ge 1) `
        -PassMessage "decision log records $($constraintHeaders.Count) constraint(s)" `
        -FailMessage 'decision log holds no constraint; an unrecorded consultation did not happen'

    # Every constraint record must carry a full measurement contract. The ids,
    # baselines and metric names belong to whoever runs the gate -- only the
    # shape is enforced here, so a fork keeps its own history.
    $records = [regex]::Matches($decisionLog, '<!-- constraint-record ([^>]*?)-->')

    # ...and every constraint HEADER must have one. Validating only the records
    # that happen to exist let constraints #001-#003 -- the governing market
    # constraint among them -- sit in the log with no measurement contract at
    # all, and the audit stayed green. A heading without a record is a story.
    $recordIds = @($records | ForEach-Object {
        $m = [regex]::Match($_.Groups[1].Value, '(?:^|\s)id=(\S+)')
        if ($m.Success) { $m.Groups[1].Value.TrimStart('#') }
    })
    $unrecorded = @($constraintHeaders | ForEach-Object { $_.Groups[1].Value } |
        Where-Object { $recordIds -notcontains $_ })
    Add-AuditResult `
        -Condition ($unrecorded.Count -eq 0) `
        -PassMessage "every constraint heading has a machine-readable record ($($constraintHeaders.Count) heading(s), $($records.Count) record(s))" `
        -FailMessage ("constraint heading(s) with no constraint-record marker: " + ($unrecorded -join ', '))
    $incomplete = [System.Collections.Generic.List[string]]::new()
    foreach ($rec in $records) {
        $body = $rec.Groups[1].Value
        # A constraint may refuse an independent number and read with its parent
        # -- constraints #002 and #003 say exactly that in prose. That shape is
        # a contract, not an exemption: it still names a parent and a read date,
        # and inventing a baseline for it after the fact is what the log forbids.
        $required = if ($body -match '(?:^|\s)defers-to=\S') {
            @('id', 'defers-to', 'read-at')
        } else {
            @('id', 'baseline', 'metric', 'target', 'read-at', 'evidence')
        }
        foreach ($field in $required) {
            if ($body -notmatch ("(?:^|\s)" + [regex]::Escape($field) + "=\S")) {
                $incomplete.Add("$($rec.Value.Trim()) is missing '$field'")
            }
        }
    }

    # A deferring constraint must point at a constraint that actually exists.
    $deferBroken = [System.Collections.Generic.List[string]]::new()
    foreach ($rec in $records) {
        $d = [regex]::Match($rec.Groups[1].Value, '(?:^|\s)defers-to=(\S+)')
        if ($d.Success -and ($recordIds -notcontains $d.Groups[1].Value)) {
            $deferBroken.Add("$($rec.Value.Trim()) defers to a constraint with no record")
        }
    }
    Add-AuditResult `
        -Condition ($deferBroken.Count -eq 0) `
        -PassMessage 'every deferring constraint points at a recorded parent' `
        -FailMessage ("dangling defers-to: " + ($deferBroken -join '; '))
    Add-AuditResult `
        -Condition ($incomplete.Count -eq 0) `
        -PassMessage "all $($records.Count) constraint record(s) declare baseline, metric, target, read date, and evidence" `
        -FailMessage ("incomplete constraint records: " + ($incomplete -join '; '))

    # A craft metric must never absorb the market constraint into itself.
    $singleMetrics = [regex]::Matches($decisionLog, '<!-- single-metric=([a-z0-9-]+) -->')
    Add-AuditResult `
        -Condition ($singleMetrics.Count -eq 0 -or ($singleMetrics | ForEach-Object { $_.Groups[1].Value } | Select-Object -Unique).Count -eq $singleMetrics.Count) `
        -PassMessage 'each constraint declares its own single metric without reusing another' `
        -FailMessage 'two constraints declare the same single-metric; one is absorbing the other'
}


$firstPartyFiles = $markdownFiles | Where-Object {
    $_.FullName -notmatch '[\\/]vendor[\\/]' -and
    $_.FullName -notmatch '[\\/]tasks[\\/]'
}
$claimFiles = @($firstPartyFiles | Where-Object { $_.FullName -notmatch '[\\/]docs[\\/]decision-log\.md$' })
$claimFiles += @(Get-Item -LiteralPath (Join-Path $projectRoot 'scripts\majlis-cli.ps1'))

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
    'truncated buyer evidence typo' = '\buyer-evidence-v1\b'
    'truncated vendor path typo' = '\bendor/wondelai\b'
    'truncated behavioral alchemy typo' = '\behavioral-alchemy\b'
    'invented expert consensus or persona verdict' = 'UNANIMOUS CONSENSUS|GREEN_LIT|STRONG_OFFER|READY_FOR_SPEARING|Council Gate Ruling'
    'legal compliance self-certification' = 'IsPDPLCompliant|PDPL Compliant|Compliant Outbound Pitch|compliant outreach messages'
    'unsupported delivery promise' = 'الربط المعتمد في 48 ساعة|دون توقف مبيعات|شهادتك جاهزة|تقرير اعتماد رسمي'
    'misattributed local behavioral-alchemy vendor skill' = '\bbehavioral-alchemy\b'
}

foreach ($entry in $forbiddenPatterns.GetEnumerator()) {
    $hits = [System.Collections.Generic.List[string]]::new()
    foreach ($claimFile in $claimFiles) {
        $text = Get-Content -LiteralPath $claimFile.FullName -Raw -Encoding UTF8
        if ($text -match $entry.Value) {
            $hits.Add($claimFile.FullName.Substring($projectRoot.Length + 1))
        }
    }
    Add-AuditResult `
        -Condition ($hits.Count -eq 0) `
        -PassMessage "forbidden pattern absent: $($entry.Key)" `
        -FailMessage ("forbidden pattern '$($entry.Key)' found in: " + ($hits -join ', '))
}

# --- Operational and Strategic Playbooks Integrity ---
$playbookFiles = @(
    'docs\playbook-weekly-sprint.md',
    'docs\playbook-b2b-outbound.md',
    'docs\playbook-offer-engineering.md',
    'docs\playbook-objection-destruction.md',
    'docs\playbook-pre-mortem.md',
    'docs\playbook-unit-economics.md'
)
foreach ($pbFile in $playbookFiles) {
    $pbPath = Join-Path $projectRoot $pbFile
    Add-AuditResult `
        -Condition (Test-Path -LiteralPath $pbPath) `
        -PassMessage "required playbook exists: $pbFile" `
        -FailMessage "missing playbook file: $pbFile"
}

# The .claude/.agents synchronization block was removed on 2026-08-30 together
# with .agents itself. One instruction tree cannot drift from itself.

# --- CLI Command Coverage Check ---
if (Test-Path -LiteralPath $cliPath) {
    $cliText = Get-ProjectText 'scripts\majlis-cli.ps1'

    # Grepping for "'status'" anywhere in the file proved nothing: every command
    # name is already in the ValidateSet, so the check passed by construction
    # even for a command that dispatched to nothing. Follow the dispatch instead.
    $switchBlock = [regex]::Match($cliText, '(?ms)^switch \(\$Command\) \{(.*?)^\}')
    Add-AuditResult `
        -Condition $switchBlock.Success `
        -PassMessage 'majlis-cli exposes a parseable command dispatcher' `
        -FailMessage 'majlis-cli must expose a switch ($Command) dispatcher'

    foreach ($cmd in @('status', 'triage', 'verify-entity', 'calc-cvi', 'audit', 'test', 'verify')) {
        $dispatch = if ($switchBlock.Success) {
            [regex]::Match($switchBlock.Groups[1].Value, "(?m)^\s*'" + [regex]::Escape($cmd) + "'\s*\{\s*(.+?)\s*\}")
        } else { $null }

        $wired = $false
        $detail = 'not dispatched'
        if ($dispatch -and $dispatch.Success) {
            $body = $dispatch.Groups[1].Value
            $fn = [regex]::Match($body, '^([A-Z][A-Za-z]+-[A-Za-z]+)')
            if ($fn.Success) {
                $wired = $cliText -match ('(?m)^function\s+' + [regex]::Escape($fn.Groups[1].Value) + '\s*\{')
                $detail = if ($wired) { "-> $($fn.Groups[1].Value)" } else { "-> $($fn.Groups[1].Value) which is not defined" }
            }
            else {
                # 'audit' shells out to the audit script rather than a function.
                $wired = $body -match '\S'
                $detail = 'inline dispatch'
            }
        }

        Add-AuditResult `
            -Condition $wired `
            -PassMessage "majlis-cli dispatches command '$cmd' ($detail)" `
            -FailMessage "majlis-cli command '$cmd' is $detail"
    }
}

# The contract suite passed the 'required file exists' check for eleven days while
# being unrunnable: it hard-coded 'pwsh', which is absent on the machine this repo
# lives on, so every case died with CommandNotFoundException. Existence is not
# execution -- assert the suite resolves a host and is reachable from the dispatcher.
$contractSuiteRelative = 'tests\cli-contracts.ps1'
if (Test-Path -LiteralPath (Join-Path $projectRoot $contractSuiteRelative)) {
    $contractText = Get-ProjectText $contractSuiteRelative

    Add-AuditResult `
        -Condition ($contractText -match 'Resolve-PowerShellHost') `
        -PassMessage 'contract suite resolves its PowerShell host instead of hard-coding one' `
        -FailMessage 'contract suite must resolve a PowerShell host (a hard-coded pwsh made it unrunnable)'

    Add-AuditResult `
        -Condition ($contractText -notmatch '&\s+pwsh') `
        -PassMessage 'contract suite invokes no hard-coded pwsh binary' `
        -FailMessage 'contract suite still invokes a hard-coded pwsh binary'

    Add-AuditResult `
        -Condition ($contractText -match '(?m)^exit 0\s*$') `
        -PassMessage 'contract suite exits 0 on success instead of leaking $LASTEXITCODE' `
        -FailMessage 'contract suite must exit 0 on success; otherwise a green run reports failure'

    if (Test-Path -LiteralPath $cliPath) {
        $cliTextForSuite = Get-ProjectText 'scripts\majlis-cli.ps1'
        Add-AuditResult `
            -Condition ($cliTextForSuite -match [regex]::Escape($contractSuiteRelative)) `
            -PassMessage 'contract suite is reachable from majlis-cli (test / verify)' `
            -FailMessage 'contract suite exists but no majlis-cli command runs it'
    }
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

$consultationPaths = @(
    '.claude\skills\consultation\SKILL.md'
)
foreach ($cPath in $consultationPaths) {
    if (Test-Path -LiteralPath (Join-Path $projectRoot $cPath)) {
        $consultation = Get-ProjectText $cPath
        foreach ($contractReference in @('docs/evidence-standard.md', 'docs/weekly-constraint-loop.md')) {
            Add-AuditResult `
                -Condition ($consultation -match [regex]::Escape($contractReference)) `
                -PassMessage "consultation ($cPath) routes through $contractReference" `
                -FailMessage "consultation ($cPath) must route through $contractReference"
        }
    }
}

if (-not $script:MarketLine) { $script:MarketLine = 'market state unknown: docs/entity-records-draft.md not readable' }

if ($Json) {
    [PSCustomObject]@{
        Summary   = "$($passes.Count) passed, $($failures.Count) failed."
        PassCount = $passes.Count
        FailCount = $failures.Count
        Market    = $script:MarketLine
        Passes    = $passes
        Failures  = $failures
    } | ConvertTo-Json -Depth 4
}
else {
    foreach ($message in $passes) {
        Write-Host "PASS  $message" -ForegroundColor Green
    }
    foreach ($message in $failures) {
        Write-Host "FAIL  $message" -ForegroundColor Red
    }

    Write-Host ''
    Write-Host "Audit summary: $($passes.Count) passed, $($failures.Count) failed."
    # The craft count is printed above; the market number is printed last so it
    # is the line the reader leaves with. A green audit is not a sold service.
    Write-Host "MARKET      : $script:MarketLine" -ForegroundColor Magenta
}

if ($failures.Count -gt 0) {
    exit 1
}
