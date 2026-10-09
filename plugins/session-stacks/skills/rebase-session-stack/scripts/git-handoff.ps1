#requires -Version 7.0
[CmdletBinding()]
param(
    [ValidateSet('Inspect', 'Attach')]
    [string] $Mode = 'Inspect',
    [Parameter(Mandatory)]
    [string] $Worktree,
    [Parameter(Mandatory)]
    [string] $Branch,
    [string] $ExpectedHead,
    [string] $ExpectedOld,
    [string] $Target,
    [string] $Operation,
    [int] $Generation,
    [string] $Source,
    [string] $SourceRef,
    [switch] $MutationAuthorized,
    [switch] $Quiesced
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$git = (Get-Command git -CommandType Application -ErrorAction Stop | Select-Object -First 1).Source
$Worktree = (Resolve-Path -LiteralPath $Worktree -ErrorAction Stop).ProviderPath

function Invoke-Git {
    param([string[]] $Arguments, [int[]] $AllowedExitCodes = @(0))

    $info = [System.Diagnostics.ProcessStartInfo]::new()
    $info.FileName = $git
    $info.UseShellExecute = $false
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    foreach ($argument in @('--no-optional-locks', '-C', $Worktree, '-c', 'core.longpaths=true') + $Arguments) {
        $info.ArgumentList.Add($argument)
    }
    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo = $info
    try {
        if (-not $process.Start()) {
            throw 'Could not start Git.'
        }
        $stdoutTask = $process.StandardOutput.ReadToEndAsync()
        $stderrTask = $process.StandardError.ReadToEndAsync()
        $process.WaitForExit()
        $stdout = $stdoutTask.GetAwaiter().GetResult()
        $stderr = $stderrTask.GetAwaiter().GetResult()
        $exitCode = $process.ExitCode
        if ($exitCode -notin $AllowedExitCodes) {
            throw "Git $($Arguments -join ' ') failed (exit $exitCode): $stderr$stdout"
        }
        if ($stderr.Length -gt 0) {
            Write-Warning $stderr.TrimEnd([char[]] "`r`n")
        }
        return [pscustomobject] @{
            ExitCode = $exitCode
            Text = $stdout.TrimEnd([char[]] "`r`n")
        }
    }
    finally {
        $process.Dispose()
    }
}

function Test-SamePath {
    param([string] $Left, [string] $Right)

    $comparison = if ([OperatingSystem]::IsWindows()) {
        [StringComparison]::OrdinalIgnoreCase
    }
    else {
        [StringComparison]::Ordinal
    }
    $separators = [char[]] @([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
    return [string]::Equals(
        [IO.Path]::GetFullPath($Left).TrimEnd($separators),
        [IO.Path]::GetFullPath($Right).TrimEnd($separators),
        $comparison)
}

function Get-Snapshot {
    $root = (Invoke-Git @('rev-parse', '--show-toplevel')).Text
    if (-not (Test-SamePath $root $Worktree)) {
        throw 'Worktree must be the exact repository/worktree root, not a subdirectory.'
    }
    $status = (Invoke-Git @('status', '--porcelain=v1', '--untracked-files=all')).Text
    $symbolic = Invoke-Git @('symbolic-ref', '--quiet', 'HEAD') @(0, 1)
    $head = (Invoke-Git @('rev-parse', '--verify', 'HEAD^{commit}')).Text
    $branchHead = (Invoke-Git @('rev-parse', '--verify', "$Branch^{commit}")).Text
    $common = (Invoke-Git @('rev-parse', '--path-format=absolute', '--git-common-dir')).Text
    $occupants = @()
    $currentPath = $null
    $records = (Invoke-Git @('worktree', 'list', '--porcelain', '-z')).Text
    foreach ($field in $records.Split([char] 0)) {
        if ($field.StartsWith('worktree ', [StringComparison]::Ordinal)) {
            $currentPath = $field.Substring(9)
        }
        elseif ($field -ceq "branch $Branch") {
            if ($null -eq $currentPath) {
                throw 'Malformed Git worktree record.'
            }
            $occupants += [IO.Path]::GetFullPath($currentPath)
        }
    }
    $operations = @()
    foreach ($marker in @('rebase-merge', 'rebase-apply', 'MERGE_HEAD', 'CHERRY_PICK_HEAD',
            'REVERT_HEAD', 'BISECT_START', 'sequencer')) {
        $path = (Invoke-Git @('rev-parse', '--path-format=absolute', '--git-path', $marker)).Text
        if (Test-Path -LiteralPath $path) {
            $operations += $marker
        }
    }
    $dirtyLines = @()
    if ($status.Length -gt 0) {
        $dirtyLines = @($status -split "`n")
    }
    return [pscustomobject] @{
        worktree = [IO.Path]::GetFullPath($root)
        commonDir = [IO.Path]::GetFullPath($common)
        branch = $Branch
        head = $head
        branchHead = $branchHead
        branchEqualsHead = $branchHead -ceq $head
        symbolicHead = if ($symbolic.ExitCode -eq 0) { $symbolic.Text } else { $null }
        clean = $status.Length -eq 0
        dirtyEntryCount = $dirtyLines.Count
        dirtyPreview = @($dirtyLines | Select-Object -First 10)
        gitOperations = @($operations)
        branchOccupants = @($occupants)
    }
}

function Assert-DetachedReady {
    param($Snapshot)

    if (-not $Snapshot.clean) {
        throw 'Worktree is dirty; preserve its tracked/staged/untracked files.'
    }
    if ($Snapshot.gitOperations.Count -ne 0) {
        throw "Active Git operation: $($Snapshot.gitOperations -join ', ')."
    }
    if ($null -ne $Snapshot.symbolicHead) {
        throw 'Owner must provide a detached handoff before Attach.'
    }
    if ($Snapshot.head -cne $ExpectedHead) {
        throw "Detached HEAD drifted: expected $ExpectedHead, found $($Snapshot.head)."
    }
    if ($Snapshot.branchOccupants.Count -ne 0) {
        throw "Branch is occupied: $($Snapshot.branchOccupants -join ', ')."
    }
    if ($Snapshot.branchHead -cne $ExpectedOld -and $Snapshot.branchHead -cne $Target) {
        throw "Unexpected branch SHA: $($Snapshot.branchHead)."
    }
}

if (-not $Branch.StartsWith('refs/heads/', [StringComparison]::Ordinal)) {
    throw 'Branch must be a full refs/heads/ ref.'
}
$null = Invoke-Git @('check-ref-format', $Branch)
$branchSymbolic = Invoke-Git @('symbolic-ref', '--quiet', $Branch) @(0, 1)
if ($branchSymbolic.ExitCode -eq 0) {
    throw 'Owned branch must be a direct ref, not a symbolic alias to another ref.'
}
$snapshot = Get-Snapshot
if ($Mode -eq 'Inspect') {
    $snapshot | ConvertTo-Json -Depth 5 -Compress
    return
}

$leasePath = Join-Path $snapshot.commonDir 'copilot-owner-light\lease.json'
if (Test-Path -LiteralPath $leasePath) {
    $lease = Get-Content -LiteralPath $leasePath -Raw | ConvertFrom-Json -ErrorAction Stop
    if ($lease.schema -ne 1 -or $lease.status -ne 'released' -or $null -ne $lease.pending) {
        throw 'Active or invalid owner-light lease; use its executor commands, not the owner-driven Attach helper.'
    }
}

if (-not $MutationAuthorized -or -not $Quiesced) {
    throw 'Attach requires MutationAuthorized and Quiesced attestations, including the exclusive writer lease.'
}
if ($Operation -cnotmatch '^[A-Za-z0-9][A-Za-z0-9._-]{0,79}$' -or $Generation -lt 1) {
    throw 'Attach requires a safe operation ID and positive generation.'
}
$format = (Invoke-Git @('rev-parse', '--show-object-format')).Text
$oidLength = switch ($format) {
    'sha1' { 40 }
    'sha256' { 64 }
    default { throw "Unsupported Git object format: $format." }
}
foreach ($oid in @($ExpectedHead, $ExpectedOld, $Target)) {
    if ($oid -cnotmatch "^[0-9a-f]{$oidLength}$") {
        throw "Attach requires full lowercase $format object IDs."
    }
}
Assert-DetachedReady $snapshot

$backupRef = $null
$transferRef = $null
$disposition = 'verified-already-at-target'
if ($snapshot.branchHead -cne $Target) {
    if ([string]::IsNullOrWhiteSpace($Source) -or $Source.StartsWith('-') -or
            $Source -match '[\x00-\x1f]' -or
            [string]::IsNullOrWhiteSpace($SourceRef) -or
            -not $SourceRef.StartsWith('refs/', [StringComparison]::Ordinal)) {
        throw 'A changed branch requires a verified source repository/remote and full source ref.'
    }
    $null = Invoke-Git @('check-ref-format', $SourceRef)
    $namespace = "refs/copilot/$Operation/g$Generation"
    $backupRef = "$namespace/backup-$([guid]::NewGuid().ToString('N'))"
    $transferRef = "$namespace/transfer-$([guid]::NewGuid().ToString('N'))"
    $null = Invoke-Git @('check-ref-format', $backupRef)
    $null = Invoke-Git @('check-ref-format', $transferRef)
    $existing = Invoke-Git @('show-ref', '--verify', '--quiet', $transferRef) @(0, 1)
    if ($existing.ExitCode -ne 1) {
        throw "Transfer ref collision: $transferRef."
    }

    # Recheck live safety after argument validation; keep the exclusive lease throughout.
    Assert-DetachedReady (Get-Snapshot)
    $null = Invoke-Git @('update-ref', '--no-deref', $backupRef, $ExpectedOld, ('0' * $oidLength))
    if ((Invoke-Git @('rev-parse', '--verify', $backupRef)).Text -cne $ExpectedOld) {
        throw "Backup verification failed: $backupRef."
    }
    $null = Invoke-Git @('fetch', '--quiet', '--no-tags', '--no-write-fetch-head',
        '--no-recurse-submodules', '--no-prune', '--no-prune-tags',
        '--no-auto-maintenance', '--no-write-commit-graph', '--refmap=',
        '--', $Source, "${SourceRef}:$transferRef")
    $imported = (Invoke-Git @('rev-parse', '--verify', "$transferRef^{commit}")).Text
    if ($imported -cne $Target) {
        throw "Transferred commit differs from target: $imported. Recovery refs: $backupRef, $transferRef."
    }
    $live = Get-Snapshot
    Assert-DetachedReady $live
    if ($live.branchHead -cne $Target) {
        $null = Invoke-Git @('update-ref', '--no-deref', $Branch, $Target, $ExpectedOld)
    }
    $disposition = 'transferred'
}

$live = Get-Snapshot
Assert-DetachedReady $live
if ($live.branchHead -cne $Target) {
    throw 'Branch does not match the verified target before checkout.'
}
$null = Invoke-Git @('switch', '--quiet', '--', $Branch.Substring('refs/heads/'.Length))
$final = Get-Snapshot
if (-not $final.clean -or $final.gitOperations.Count -ne 0 -or
        $final.symbolicHead -cne $Branch -or $final.head -cne $Target -or
        $final.branchHead -cne $Target -or $final.branchOccupants.Count -ne 1 -or
        -not (Test-SamePath $final.branchOccupants[0] $Worktree)) {
    throw 'Final attachment verification failed; preserve state and recovery refs.'
}
[pscustomobject] @{
    operation = $Operation
    generation = $Generation
    disposition = $disposition
    backupRef = $backupRef
    transferRef = $transferRef
    snapshot = $final
} | ConvertTo-Json -Depth 6 -Compress
