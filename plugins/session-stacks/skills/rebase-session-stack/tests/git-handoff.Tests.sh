#!/usr/bin/env bash
set -euo pipefail

die() {
    printf 'fixture: %s\n' "$*" >&2
    exit 1
}
[[ $# -eq 1 ]] || die 'Supply an existing scratch directory.'
parent=$(CDPATH='' cd -P -- "$1" && pwd -P)
helper_dir=$(CDPATH='' cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")/../scripts" && pwd -P)
helper="$helper_dir/git-handoff.sh"
python=''
for candidate in python3 python; do
    if type -P "$candidate" >/dev/null &&
            "$candidate" -c 'import sys; assert sys.version_info.major == 3' >/dev/null 2>&1; then
        python=$candidate
        break
    fi
done
[[ -n "$python" ]] || die 'Python 3 is required for JSON assertions.'
printf 'Using %s for JSON assertions.\n' "$python"
fixture=$(mktemp -d "$parent/git-handoff-sh-fixture.XXXXXXXX")
trap 'rm -rf -- "$fixture"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
passed=0
skipped=0

pass() {
    passed=$((passed + 1))
    printf 'PASS %s\n' "$1"
}
assert_equal() {
    [[ "$1" == "$2" ]] || die "$3."
}
git_fixture() {
    local repo=$1
    shift
    git -c core.longpaths=true -c core.autocrlf=false -c "core.hooksPath=$fixture/no-hooks" -C "$repo" "$@"
}
check_json() {
    "$python" - "$1" "$2" "$3" <<'PY'
import json, sys
with open(sys.argv[1], encoding="utf-8") as f:
    value = json.load(f)
for key in sys.argv[2].split("."):
    value = len(value) if key == "length" else value[key]
actual = value if isinstance(value, str) else json.dumps(value, separators=(",", ":"))
if actual != sys.argv[3]:
    raise AssertionError(f"{sys.argv[2]}: expected {sys.argv[3]!r}, found {actual!r}")
PY
}
reject() {
    local pattern=$1
    shift
    if bash "$helper" "$@" > "$fixture/rejected.json" 2> "$fixture/rejected.err"; then
        die "Expected rejection: $pattern."
    fi
    if ! grep -F -- "$pattern" "$fixture/rejected.err" >/dev/null; then
        cat "$fixture/rejected.err" >&2
        die "Wrong rejection; expected $pattern."
    fi
    [[ ! -s "$fixture/rejected.json" ]] || die 'Failure emitted a success payload.'
}
new_repo() {
    local repo=$1 format=${2:-sha1}
    mkdir -- "$repo"
    git_fixture "$repo" init --quiet --initial-branch=fixture-base "--object-format=$format"
    git_fixture "$repo" config user.name Fixture
    git_fixture "$repo" config user.email fixture@example.invalid
    git_fixture "$repo" config commit.gpgsign false
    git_fixture "$repo" config core.autocrlf false
    printf 'base\n' > "$repo/sample.txt"
    git_fixture "$repo" add -- sample.txt
    git_fixture "$repo" commit --quiet -m 'Fixture base'
    new_old=$(git_fixture "$repo" rev-parse HEAD)
    git_fixture "$repo" branch owned "$new_old"
    printf 'candidate\n' > "$repo/sample.txt"
    git_fixture "$repo" add -- sample.txt
    git_fixture "$repo" commit --quiet -m 'Fixture candidate'
    new_target=$(git_fixture "$repo" rev-parse HEAD)
    git_fixture "$repo" branch target "$new_target"
}

source="$fixture/source repo"
receiver="$fixture/receiver repo"
new_repo "$source"
old=$new_old
target=$new_target
git_fixture "$fixture" clone --quiet --no-hardlinks -- "$source" "$receiver"
git_fixture "$receiver" branch owned refs/remotes/origin/owned >/dev/null
git_fixture "$receiver" branch unrelated "$target"
git_fixture "$receiver" switch --quiet --detach "$old"
git_fixture "$receiver" update-ref refs/remotes/origin/target "$old" "$target"
git_fixture "$receiver" config fetch.prune true
git_fixture "$receiver" config fetch.pruneTags true
git_fixture "$receiver" config fetch.writeCommitGraph true
git_fixture "$receiver" tag local-only "$old"
git_fixture "$source" tag remote-only "$target"
printf 'fixture sentinel\n' > "$receiver/.git/FETCH_HEAD"
cp -- "$receiver/.git/FETCH_HEAD" "$fixture/fetch-before"
attach_args=(--mode attach --worktree "$receiver" --branch refs/heads/owned
    --expected-head "$old" --expected-old "$old" --target "$target"
    --operation fixture --generation 1 --source origin --source-ref refs/heads/target)
authorized_args=("${attach_args[@]}" --mutation-authorized --quiesced)

bash "$helper" --worktree "$receiver" --branch refs/heads/owned > "$fixture/inspect.json"
bash "$helper" --worktree "$source" --branch refs/heads/owned > "$fixture/source.json"
check_json "$fixture/inspect.json" clean true
check_json "$fixture/inspect.json" symbolicHead null
check_json "$fixture/inspect.json" branchEqualsHead true
check_json "$fixture/inspect.json" branchOccupants '[]'
"$python" - "$fixture/inspect.json" "$fixture/source.json" <<'PY'
import json, sys
with open(sys.argv[1], encoding="utf-8") as a, open(sys.argv[2], encoding="utf-8") as b:
    assert json.load(a)["commonDir"] != json.load(b)["commonDir"]
PY
pass 'read-only detached snapshot and distinct clone identities'

reject attestations "${attach_args[@]}" --quiesced
pass 'missing authorization rejected'
reject attestations "${attach_args[@]}" --mutation-authorized
pass 'missing quiescence rejected'
reject 'full lowercase' "${authorized_args[@]}" --target "${target:0:12}"
pass 'abbreviated object ID rejected'
reject 'safe operation ID' "${authorized_args[@]}" --operation ../other
pass 'unsafe operation ID rejected'
reject 'safe operation ID' "${authorized_args[@]}" --generation 2147483648
pass 'out-of-range generation rejected'
reject 'Git failed' --worktree "$receiver" --branch refs/heads/../bad
pass 'invalid branch rejected'

git_fixture "$receiver" symbolic-ref refs/heads/alias refs/heads/unrelated
reject 'direct ref' --worktree "$receiver" --branch refs/heads/alias
assert_equal "$(git_fixture "$receiver" rev-parse refs/heads/unrelated)" "$target" 'Alias changed its sibling'
git_fixture "$receiver" symbolic-ref --delete refs/heads/alias
pass 'symbolic branch alias rejected without touching its sibling'

mkdir -- "$receiver/empty-child"
reject 'exact repository/worktree root' --worktree "$receiver/empty-child" --branch refs/heads/owned
rmdir -- "$receiver/empty-child"
pass 'wrong worktree root rejected'
reject 'HEAD drifted' "${authorized_args[@]}" --expected-head "$target"
pass 'detached HEAD drift rejected'

printf 'preserve\n' > "$receiver/untracked.txt"
reject 'Worktree is dirty' "${authorized_args[@]}"
assert_equal "$(cat "$receiver/untracked.txt")" preserve 'Untracked work was lost'
rm -- "$receiver/untracked.txt"
pass 'untracked user work preserved'
printf 'staged\n' > "$receiver/sample.txt"
git_fixture "$receiver" add -- sample.txt
reject 'Worktree is dirty' "${authorized_args[@]}"
git_fixture "$receiver" restore "--source=$old" --staged --worktree -- sample.txt
pass 'staged changes rejected'

for (( i=0; i<13; i++ )); do printf 'dirty\n' > "$receiver/entry-$i"; done
bash "$helper" --worktree "$receiver" --branch refs/heads/owned > "$fixture/dirty.json"
check_json "$fixture/dirty.json" clean false
check_json "$fixture/dirty.json" dirtyEntryCount 13
check_json "$fixture/dirty.json" dirtyPreview.length 10
for (( i=0; i<13; i++ )); do rm -- "$receiver/entry-$i"; done
pass 'dirty preview bounded without hiding full cleanliness count'

printf '%s\n' "$old" > "$receiver/.git/MERGE_HEAD"
reject 'Active Git operation' "${authorized_args[@]}"
rm -- "$receiver/.git/MERGE_HEAD"
pass 'active Git operation rejected'
occupied="$fixture/occupied worktree"
git_fixture "$receiver" worktree add --quiet "$occupied" owned
reject 'Branch is occupied' "${authorized_args[@]}"
git_fixture "$receiver" worktree remove "$occupied"
pass 'occupied sibling worktree rejected'
reject 'Unexpected branch SHA' "${authorized_args[@]}" --expected-old "$target"
assert_equal "$(git_fixture "$receiver" rev-parse refs/heads/owned)" "$old" 'Stale expectation changed branch'
pass 'stale expected branch SHA rejected'

reject 'Transferred commit differs from target' "${authorized_args[@]}" --source-ref refs/heads/owned
assert_equal "$(git_fixture "$receiver" rev-parse refs/heads/owned)" "$old" 'Wrong fetched SHA was installed'
git_fixture "$receiver" for-each-ref '--format=%(refname)' refs/copilot/fixture/g1 > "$fixture/recovery-refs"
grep -F /backup- "$fixture/recovery-refs" >/dev/null || die 'Recovery backup missing.'
pass 'wrong fetched SHA rejected with recovery refs retained'

bash "$helper" "${authorized_args[@]}" > "$fixture/attached.json"
check_json "$fixture/attached.json" disposition transferred
check_json "$fixture/attached.json" snapshot.clean true
check_json "$fixture/attached.json" snapshot.head "$target"
check_json "$fixture/attached.json" snapshot.symbolicHead refs/heads/owned
"$python" - "$fixture/attached.json" "$receiver" "$old" "$target" <<'PY'
import json, subprocess, sys
with open(sys.argv[1], encoding="utf-8") as f:
    result = json.load(f)
for key, expected in (("backupRef", sys.argv[3]), ("transferRef", sys.argv[4])):
    actual = subprocess.check_output(["git", "-C", sys.argv[2], "rev-parse", result[key]], text=True).strip()
    assert actual == expected
PY
pass 'cross-clone guarded transfer and exact attachment'

cmp -- "$receiver/.git/FETCH_HEAD" "$fixture/fetch-before" || die 'FETCH_HEAD changed.'
assert_equal "$(git_fixture "$receiver" rev-parse refs/remotes/origin/target)" "$old" 'Configured refmap changed tracking'
assert_equal "$(git_fixture "$receiver" rev-parse refs/remotes/origin/owned)" "$old" 'Owned tracking changed prematurely'
assert_equal "$(git_fixture "$receiver" rev-parse refs/heads/unrelated)" "$target" 'Sibling branch changed'
pass 'FETCH_HEAD, tracking and unrelated branch untouched'
assert_equal "$(git_fixture "$receiver" rev-parse refs/tags/local-only)" "$old" 'Local tag was pruned'
assert_equal "$(git_fixture "$receiver" tag --list remote-only)" '' 'Unrequested tag was fetched'
[[ ! -e "$receiver/.git/objects/info/commit-graph" ]] || die 'Commit graph was written.'
pass 'configured pruning, tag fetch and commit-graph writes suppressed'
reject 'detached handoff' "${authorized_args[@]}" --expected-head "$target"
assert_equal "$(git_fixture "$receiver" symbolic-ref HEAD)" refs/heads/owned 'Owner was detached'
pass 'attached owner rejected rather than silently detached'

git_fixture "$receiver" switch --quiet --detach "$target"
git_fixture "$receiver" for-each-ref '--format=%(refname) %(objectname)' refs/copilot > "$fixture/refs-before"
bash "$helper" --mode attach --worktree "$receiver" --branch refs/heads/owned \
    --expected-head "$target" --expected-old "$old" --target "$target" \
    --operation fixture --generation 1 --mutation-authorized --quiesced > "$fixture/idempotent.json"
check_json "$fixture/idempotent.json" disposition verified-already-at-target
check_json "$fixture/idempotent.json" backupRef null
git_fixture "$receiver" for-each-ref '--format=%(refname) %(objectname)' refs/copilot > "$fixture/refs-after"
cmp -- "$fixture/refs-before" "$fixture/refs-after" || die 'Idempotent attachment changed refs.'
pass 'already-at-target attachment avoids transfer and stale CAS'

shared="$fixture/shared owner"
git_fixture "$source" branch shared-owned "$target"
git_fixture "$source" worktree add --quiet --detach "$shared" "$old"
bash "$helper" --mode attach --worktree "$shared" --branch refs/heads/shared-owned \
    --expected-head "$old" --expected-old "$old" --target "$target" \
    --operation fixture --generation 2 --mutation-authorized --quiesced > "$fixture/shared.json"
check_json "$fixture/shared.json" disposition verified-already-at-target
"$python" - "$fixture/shared.json" "$fixture/source.json" <<'PY'
import json, sys
with open(sys.argv[1], encoding="utf-8") as a, open(sys.argv[2], encoding="utf-8") as b:
    assert json.load(a)["snapshot"]["commonDir"] == json.load(b)["commonDir"]
PY
pass 'shared clone uses verified already-shared target'

sha_repo="$fixture/sha256 repo"
new_repo "$sha_repo" sha256
git_fixture "$sha_repo" switch --quiet --detach "$new_old"
bash "$helper" --mode attach --worktree "$sha_repo" --branch refs/heads/owned \
    --expected-head "$new_old" --expected-old "$new_old" --target "$new_target" \
    --operation fixture --generation 3 --source "$sha_repo" --source-ref refs/heads/target \
    --mutation-authorized --quiesced > "$fixture/sha256.json"
check_json "$fixture/sha256.json" snapshot.head "$new_target"
[[ ${#new_target} -eq 64 ]] || die 'SHA-256 fixture had wrong object format.'
pass 'SHA-256 full OIDs and create-only backup'

case "$(uname -s)" in
    Linux|Darwin|FreeBSD|OpenBSD|NetBSD)
        odd_repo="$fixture/"$'quoted"backslash\\newline\nutf8-\303\251'
        new_repo "$odd_repo"
        git_fixture "$odd_repo" switch --quiet --detach "$new_old"
        reject 'verified source repository/remote' --mode attach \
            --worktree "$odd_repo" --branch refs/heads/owned \
            --expected-head "$new_old" --expected-old "$new_old" --target "$new_target" \
            --operation fixture --generation 4 --source "$odd_repo" --source-ref refs/heads/target \
            --mutation-authorized --quiesced
        git_fixture "$odd_repo" update-ref --no-deref refs/heads/owned "$new_target" "$new_old"
        bash "$helper" --mode attach --worktree "$odd_repo" --branch refs/heads/owned \
            --expected-head "$new_old" --expected-old "$new_old" --target "$new_target" \
            --operation fixture --generation 4 \
            --mutation-authorized --quiesced > "$fixture/odd.json"
        check_json "$fixture/odd.json" snapshot.worktree "$odd_repo"
        check_json "$fixture/odd.json" snapshot.clean true
        check_json "$fixture/odd.json" snapshot.head "$new_target"
        pass 'Unix newline, quote, backslash and UTF-8 paths preserve valid JSON' ;;
    *)
        skipped=$((skipped + 1))
        printf 'SKIP Unix filename controls are not supported on this platform.\n' ;;
esac
printf '%s tests passed; %s skipped.\n' "$passed" "$skipped"
