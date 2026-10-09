#requires -Version 7.0
[CmdletBinding()]
param([Parameter(Mandatory)][string] $ScratchRoot)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false
$helper = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\scripts\git-handoff.ps1'))
$parent = (Resolve-Path -LiteralPath $ScratchRoot -ErrorAction Stop).ProviderPath
$fixture = Join-Path $parent "git-handoff-fixture-$([guid]::NewGuid().ToString('N'))"
$null = New-Item -ItemType Directory -Path $fixture
$passed = 0

function Invoke-FixtureGit {
    param([string] $Repo, [string[]] $Arguments)

    $output = @(& git -c core.longpaths=true -C $Repo @Arguments 2>&1)
    $code = $LASTEXITCODE
    if ($code -ne 0) {
        throw "Fixture Git failed (exit $code): $($output -join "`n")"
    }
    return ($output -join "`n")
}

function Assert {
    param([bool] $Condition, [string] $Message)
    if (-not $Condition) {
        throw $Message
    }
}

function Reject {
    param([scriptblock] $Action, [string] $MessagePattern)

    $rejected = $false
    try {
        $null = & $Action
    }
    catch {
        if ($_.Exception.Message -notmatch $MessagePattern) {
            throw
        }
        $rejected = $true
    }
    Assert $rejected "Expected rejection matching $MessagePattern."
}

function Run-Test {
    param([string] $Name, [scriptblock] $Action)
    & $Action
    $script:passed++
    Write-Output "PASS $Name"
}

function New-Repo {
    param([string] $Path, [string] $Format = 'sha1')

    $null = New-Item -ItemType Directory -Path $Path
    $null = Invoke-FixtureGit $Path @('init', '--quiet', '--initial-branch=fixture-base', "--object-format=$Format")
    $null = Invoke-FixtureGit $Path @('config', 'user.name', 'Fixture')
    $null = Invoke-FixtureGit $Path @('config', 'user.email', 'fixture@example.invalid')
    $null = Invoke-FixtureGit $Path @('config', 'commit.gpgsign', 'false')
    $null = Invoke-FixtureGit $Path @('config', 'core.autocrlf', 'false')
    Set-Content -LiteralPath (Join-Path $Path 'sample.txt') -Value 'base' -Encoding utf8NoBOM
    $null = Invoke-FixtureGit $Path @('add', '--', 'sample.txt')
    $null = Invoke-FixtureGit $Path @('commit', '--quiet', '-m', 'Fixture base')
    $old = Invoke-FixtureGit $Path @('rev-parse', 'HEAD')
    $null = Invoke-FixtureGit $Path @('branch', 'owned', $old)
    Set-Content -LiteralPath (Join-Path $Path 'sample.txt') -Value 'candidate' -Encoding utf8NoBOM
    $null = Invoke-FixtureGit $Path @('add', '--', 'sample.txt')
    $null = Invoke-FixtureGit $Path @('commit', '--quiet', '-m', 'Fixture candidate')
    $target = Invoke-FixtureGit $Path @('rev-parse', 'HEAD')
    $null = Invoke-FixtureGit $Path @('branch', 'target', $target)
    return @{ old = $old; target = $target }
}

try {
    $source = Join-Path $fixture 'source repo'
    $receiver = Join-Path $fixture 'receiver repo'
    $tips = New-Repo $source
    $old = $tips.old
    $target = $tips.target
    $null = Invoke-FixtureGit $fixture @('clone', '--quiet', '--no-hardlinks', '--', $source, $receiver)
    $null = Invoke-FixtureGit $receiver @('branch', 'owned', 'refs/remotes/origin/owned')
    $null = Invoke-FixtureGit $receiver @('branch', 'unrelated', $target)
    $null = Invoke-FixtureGit $receiver @('switch', '--quiet', '--detach', $old)
    $null = Invoke-FixtureGit $receiver @('update-ref', 'refs/remotes/origin/target', $old, $target)
    $null = Invoke-FixtureGit $receiver @('config', 'fetch.prune', 'true')
    $null = Invoke-FixtureGit $receiver @('config', 'fetch.pruneTags', 'true')
    $null = Invoke-FixtureGit $receiver @('config', 'fetch.writeCommitGraph', 'true')
    $null = Invoke-FixtureGit $receiver @('tag', 'local-only', $old)
    $null = Invoke-FixtureGit $source @('tag', 'remote-only', $target)
    $fetchHead = Join-Path $receiver '.git\FETCH_HEAD'
    Set-Content -LiteralPath $fetchHead -Value 'fixture sentinel' -Encoding utf8NoBOM
    $fetchBefore = Get-Content -LiteralPath $fetchHead -Raw
    $attachArgs = @{
        Mode = 'Attach'; Worktree = $receiver; Branch = 'refs/heads/owned'
        ExpectedHead = $old; ExpectedOld = $old; Target = $target
        Operation = 'fixture'; Generation = 1
        Source = 'origin'; SourceRef = 'refs/heads/target'
        MutationAuthorized = $true; Quiesced = $true
    }

    Run-Test 'read-only detached snapshot and distinct clone identities' {
        $a = & $helper -Worktree $receiver -Branch 'refs/heads/owned' | ConvertFrom-Json
        $b = & $helper -Worktree $source -Branch 'refs/heads/owned' | ConvertFrom-Json
        Assert ($a.clean -and $null -eq $a.symbolicHead -and $a.branchEqualsHead) 'Wrong detached snapshot.'
        Assert ($a.commonDir -ne $b.commonDir) 'Separate clones were conflated.'
        Assert ($a.branchOccupants.Count -eq 0) 'Detached branch reported occupied.'
    }
    Run-Test 'missing authorization rejected' {
        $bad = $attachArgs.Clone(); $bad.MutationAuthorized = $false
        Reject { & $helper @bad } 'attestations'
    }
    Run-Test 'missing quiescence rejected' {
        $bad = $attachArgs.Clone(); $bad.Quiesced = $false
        Reject { & $helper @bad } 'attestations'
    }
    Run-Test 'abbreviated object ID rejected' {
        $bad = $attachArgs.Clone(); $bad.Target = $target.Substring(0, 12)
        Reject { & $helper @bad } 'full lowercase'
    }
    Run-Test 'unsafe operation ID rejected' {
        $bad = $attachArgs.Clone(); $bad.Operation = '../other'
        Reject { & $helper @bad } 'safe operation ID'
    }
    Run-Test 'invalid branch rejected' {
        Reject { & $helper -Worktree $receiver -Branch 'refs/heads/../bad' } 'failed'
    }
    Run-Test 'symbolic branch alias rejected without touching its sibling' {
        $null = Invoke-FixtureGit $receiver @('symbolic-ref', 'refs/heads/alias', 'refs/heads/unrelated')
        Reject { & $helper -Worktree $receiver -Branch 'refs/heads/alias' } 'direct ref'
        Assert ((Invoke-FixtureGit $receiver @('rev-parse', 'refs/heads/unrelated')) -ceq $target) 'Alias check changed its sibling.'
        $null = Invoke-FixtureGit $receiver @('symbolic-ref', '--delete', 'refs/heads/alias')
    }
    Run-Test 'wrong worktree root rejected' {
        $child = Join-Path $receiver 'empty-child'
        $null = New-Item -ItemType Directory -Path $child
        Reject { & $helper -Worktree $child -Branch 'refs/heads/owned' } 'exact repository/worktree root'
        Remove-Item -LiteralPath $child
    }
    Run-Test 'detached HEAD drift rejected' {
        $bad = $attachArgs.Clone(); $bad.ExpectedHead = $target
        Reject { & $helper @bad } 'HEAD drifted'
    }
    Run-Test 'untracked user work preserved' {
        $file = Join-Path $receiver 'untracked.txt'
        Set-Content -LiteralPath $file -Value 'preserve' -Encoding utf8NoBOM
        Reject { & $helper @attachArgs } 'Worktree is dirty'
        Assert ((Get-Content -LiteralPath $file -Raw).Trim() -eq 'preserve') 'User work was lost.'
        Remove-Item -LiteralPath $file
    }
    Run-Test 'staged changes rejected' {
        Set-Content -LiteralPath (Join-Path $receiver 'sample.txt') -Value 'staged' -Encoding utf8NoBOM
        $null = Invoke-FixtureGit $receiver @('add', '--', 'sample.txt')
        Reject { & $helper @attachArgs } 'Worktree is dirty'
        $null = Invoke-FixtureGit $receiver @('restore', "--source=$old", '--staged', '--worktree', '--', 'sample.txt')
    }
    Run-Test 'active Git operation rejected' {
        $marker = Join-Path $receiver '.git\MERGE_HEAD'
        Set-Content -LiteralPath $marker -Value $old -Encoding utf8NoBOM
        Reject { & $helper @attachArgs } 'Active Git operation'
        Remove-Item -LiteralPath $marker
    }
    Run-Test 'occupied sibling worktree rejected' {
        $occupied = Join-Path $fixture 'occupied worktree'
        $null = Invoke-FixtureGit $receiver @('worktree', 'add', '--quiet', $occupied, 'owned')
        Reject { & $helper @attachArgs } 'Branch is occupied'
        $null = Invoke-FixtureGit $receiver @('worktree', 'remove', $occupied)
    }
    Run-Test 'stale expected branch SHA rejected' {
        $bad = $attachArgs.Clone(); $bad.ExpectedOld = $target; $bad.Target = $target
        Reject { & $helper @bad } 'Unexpected branch SHA'
        Assert ((Invoke-FixtureGit $receiver @('rev-parse', 'refs/heads/owned')) -ceq $old) 'Branch changed on rejection.'
    }
    Run-Test 'wrong fetched SHA rejected with recovery refs retained' {
        $bad = $attachArgs.Clone(); $bad.SourceRef = 'refs/heads/owned'
        Reject { & $helper @bad } 'Transferred commit differs from target'
        Assert ((Invoke-FixtureGit $receiver @('rev-parse', 'refs/heads/owned')) -ceq $old) 'Wrong fetched SHA was installed.'
        $refs = Invoke-FixtureGit $receiver @('for-each-ref', '--format=%(refname)', 'refs/copilot/fixture/g1')
        Assert ($refs -match '/backup-') 'Recovery backup missing.'
    }
    Run-Test 'cross-clone guarded transfer and exact attachment' {
        $script:attached = & $helper @attachArgs | ConvertFrom-Json
        Assert ($attached.disposition -eq 'transferred') 'Transfer did not run.'
        Assert ($attached.snapshot.clean -and $attached.snapshot.head -ceq $target) 'Wrong final checkout.'
        Assert ($attached.snapshot.symbolicHead -ceq 'refs/heads/owned') 'Wrong symbolic HEAD.'
        Assert ((Invoke-FixtureGit $receiver @('rev-parse', $attached.backupRef)) -ceq $old) 'Backup was not the old tip.'
        Assert ((Invoke-FixtureGit $receiver @('rev-parse', $attached.transferRef)) -ceq $target) 'Transfer was not exact.'
    }
    Run-Test 'FETCH_HEAD, tracking and unrelated branch untouched' {
        Assert ((Get-Content -LiteralPath $fetchHead -Raw) -ceq $fetchBefore) 'FETCH_HEAD changed.'
        Assert ((Invoke-FixtureGit $receiver @('rev-parse', 'refs/remotes/origin/target')) -ceq $old) 'Configured refmap updated tracking.'
        Assert ((Invoke-FixtureGit $receiver @('rev-parse', 'refs/remotes/origin/owned')) -ceq $old) 'Owned tracking changed prematurely.'
        Assert ((Invoke-FixtureGit $receiver @('rev-parse', 'refs/heads/unrelated')) -ceq $target) 'Sibling branch changed.'
    }
    Run-Test 'configured pruning, tag fetch and commit-graph writes suppressed' {
        Assert ((Invoke-FixtureGit $receiver @('rev-parse', 'refs/tags/local-only')) -ceq $old) 'Local tag was pruned.'
        $tags = Invoke-FixtureGit $receiver @('tag', '--list', 'remote-only')
        Assert ($tags.Length -eq 0) 'Unrequested remote tag was fetched.'
        Assert (-not (Test-Path -LiteralPath (Join-Path $receiver '.git\objects\info\commit-graph'))) 'Commit graph was written.'
    }
    Run-Test 'attached owner rejected rather than silently detached' {
        $bad = $attachArgs.Clone(); $bad.ExpectedHead = $target
        Reject { & $helper @bad } 'detached handoff'
        Assert ((Invoke-FixtureGit $receiver @('symbolic-ref', 'HEAD')) -ceq 'refs/heads/owned') 'Owner was detached.'
    }
    Run-Test 'already-at-target attachment avoids transfer and stale CAS' {
        $null = Invoke-FixtureGit $receiver @('switch', '--quiet', '--detach', $target)
        $before = Invoke-FixtureGit $receiver @('for-each-ref', '--format=%(refname) %(objectname)', 'refs/copilot')
        $same = $attachArgs.Clone(); $same.ExpectedHead = $target
        $same.Remove('Source'); $same.Remove('SourceRef')
        $result = & $helper @same | ConvertFrom-Json
        Assert ($result.disposition -eq 'verified-already-at-target' -and $null -eq $result.backupRef) 'Idempotent path made a transfer.'
        Assert ((Invoke-FixtureGit $receiver @('for-each-ref', '--format=%(refname) %(objectname)', 'refs/copilot')) -ceq $before) 'Idempotent path changed refs.'
    }
    Run-Test 'shared clone uses verified already-shared target' {
        $shared = Join-Path $fixture 'shared owner'
        $null = Invoke-FixtureGit $source @('branch', 'shared-owned', $target)
        $null = Invoke-FixtureGit $source @('worktree', 'add', '--quiet', '--detach', $shared, $old)
        $result = & $helper -Mode Attach -Worktree $shared -Branch 'refs/heads/shared-owned' `
            -ExpectedHead $old -ExpectedOld $old -Target $target -Operation fixture `
            -Generation 2 -MutationAuthorized -Quiesced | ConvertFrom-Json
        $original = & $helper -Worktree $source -Branch 'refs/heads/shared-owned' | ConvertFrom-Json
        Assert ($result.snapshot.commonDir -eq $original.commonDir) 'Shared clone identity did not match.'
        Assert ($result.disposition -eq 'verified-already-at-target') 'Shared clone fetched unnecessarily.'
    }
    Run-Test 'SHA-256 full OIDs and create-only backup' {
        $shaRepo = Join-Path $fixture 'sha256 repo'
        $shaTips = New-Repo $shaRepo 'sha256'
        $null = Invoke-FixtureGit $shaRepo @('switch', '--quiet', '--detach', $shaTips.old)
        $result = & $helper -Mode Attach -Worktree $shaRepo -Branch 'refs/heads/owned' `
            -ExpectedHead $shaTips.old -ExpectedOld $shaTips.old -Target $shaTips.target `
            -Operation fixture -Generation 3 -Source $shaRepo -SourceRef 'refs/heads/target' `
            -MutationAuthorized -Quiesced | ConvertFrom-Json
        Assert ($result.snapshot.head.Length -eq 64 -and $result.snapshot.head -ceq $shaTips.target) 'SHA-256 target failed.'
        Assert ((Invoke-FixtureGit $shaRepo @('rev-parse', $result.backupRef)) -ceq $shaTips.old) 'SHA-256 backup failed.'
    }
    Run-Test 'long-path tracked file is actually checked out' {
        $longRepo = Join-Path $fixture 'long path repo'
        $longTips = New-Repo $longRepo
        $deep = Join-Path (Join-Path $longRepo ('a' * 90)) ('b' * 90)
        $null = New-Item -ItemType Directory -Path $deep
        $file = Join-Path $deep 'long.txt'
        Assert ($file.Length -gt 260) 'Fixture did not exercise a long path.'
        Set-Content -LiteralPath $file -Value 'long path fixture' -Encoding utf8NoBOM
        $null = Invoke-FixtureGit $longRepo @('add', '--', '.')
        $null = Invoke-FixtureGit $longRepo @('commit', '--quiet', '-m', 'Fixture long path')
        $longTarget = Invoke-FixtureGit $longRepo @('rev-parse', 'HEAD')
        $null = Invoke-FixtureGit $longRepo @('switch', '--quiet', '--detach', $longTips.old)
        Assert (-not (Test-Path -LiteralPath $file)) 'Fixture remained checked out before attachment.'
        $result = & $helper -Mode Attach -Worktree $longRepo -Branch 'refs/heads/owned' `
            -ExpectedHead $longTips.old -ExpectedOld $longTips.old -Target $longTarget `
            -Operation fixture -Generation 4 -Source $longRepo -SourceRef 'refs/heads/fixture-base' `
            -MutationAuthorized -Quiesced | ConvertFrom-Json
        Assert ($result.snapshot.clean -and $result.snapshot.head -ceq $longTarget) 'Long-path attachment was not clean.'
        Assert ((Get-Content -LiteralPath $file -Raw).Trim() -eq 'long path fixture') 'Long-path file was not restored exactly.'
    }
    Write-Output "$passed tests passed."
}
finally {
    # Delete only the uniquely named fixture directory created by this invocation.
    Remove-Item -LiteralPath $fixture -Recurse -Force
}
