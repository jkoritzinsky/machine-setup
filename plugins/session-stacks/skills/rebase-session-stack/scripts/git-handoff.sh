#!/usr/bin/env bash
set -euo pipefail

die() {
    printf 'git-handoff: %s\n' "$*" >&2
    exit 1
}

usage() {
    cat <<'EOF'
Usage: bash git-handoff.sh --worktree PATH --branch refs/heads/NAME [--mode inspect]
       bash git-handoff.sh --mode attach --worktree PATH --branch refs/heads/NAME
         --expected-head OID --expected-old OID --target OID
         --operation ID --generation N --mutation-authorized --quiesced
         [--source REPOSITORY_OR_REMOTE --source-ref FULL_REF]

Requires Bash 3.2+, Git, and standard Unix utilities. Outputs compact JSON.
Attach requires an authorized detached owner and an exclusive writer lease.
It does not detach, rebase, push, or refresh tracking refs.
EOF
}

mode=inspect
worktree=''
branch=''
expected_head=''
expected_old=''
target=''
operation=''
generation=''
source=''
source_ref=''
mutation_authorized=false
quiesced=false
while (( $# > 0 )); do
    case "$1" in
        --help|-h) usage; exit 0 ;;
        --mutation-authorized) mutation_authorized=true; shift; continue ;;
        --quiesced) quiesced=true; shift; continue ;;
        --mode|--worktree|--branch|--expected-head|--expected-old|--target|--operation|--generation|--source|--source-ref)
            (( $# >= 2 )) || die "Missing value for $1."
            case "$1" in
                --mode) mode=$2 ;;
                --worktree) worktree=$2 ;;
                --branch) branch=$2 ;;
                --expected-head) expected_head=$2 ;;
                --expected-old) expected_old=$2 ;;
                --target) target=$2 ;;
                --operation) operation=$2 ;;
                --generation) generation=$2 ;;
                --source) source=$2 ;;
                --source-ref) source_ref=$2 ;;
            esac
            shift 2 ;;
        *) die "Unknown argument: $1." ;;
    esac
done
[[ "$mode" == inspect || "$mode" == attach ]] || die 'Mode must be inspect or attach.'
[[ -n "$worktree" && "$branch" == refs/heads/* ]] || die 'Supply a worktree and full refs/heads/ ref.'
git_path=$(type -P git) || die 'Git is not installed.'

canonical_dir() {
    if canonical=$(CDPATH='' cd -P -- "$1" && printf '%s.' "$PWD"); then
        canonical=${canonical%.}
    else
        die "Cannot resolve directory: $1."
    fi
}
canonical_dir "$worktree"
worktree=$canonical
temp_dir=$(mktemp -d "${TMPDIR:-/tmp}/git-handoff.XXXXXXXX") || die 'Cannot create private scratch directory.'
trap 'rm -rf -- "$temp_dir"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

git_run() {
    local allowed=$1
    shift
    if "$git_path" --no-optional-locks -C "$worktree" -c core.longpaths=true "$@" \
            > "$temp_dir/output" 2> "$temp_dir/error"; then
        git_code=0
    else
        git_code=$?
    fi
    case " $allowed " in
        *" $git_code "*) ;;
        *)
            printf 'git-handoff: Git failed (exit %s): ' "$git_code" >&2
            printf '%q ' "$@" >&2
            printf '\n' >&2
            cat "$temp_dir/error" "$temp_dir/output" >&2
            exit 1 ;;
    esac
    if [[ -s "$temp_dir/error" ]]; then
        cat "$temp_dir/error" >&2
    fi
}

capture_git() {
    git_run "$@"
    # Preserve newlines belonging to paths; remove only Git's final record newline.
    git_text=$(cat "$temp_dir/output" && printf '.')
    git_text=${git_text%.}
    git_text=${git_text%$'\n'}
}

json_string() {
    local value=$1 character code i
    printf '"'
    for (( i=0; i<${#value}; i++ )); do
        character=${value:i:1}
        case "$character" in
            '"') printf '\\"' ;;
            '\') printf '\\\\' ;;
            $'\b') printf '\\b' ;;
            $'\f') printf '\\f' ;;
            $'\n') printf '\\n' ;;
            $'\r') printf '\\r' ;;
            $'\t') printf '\\t' ;;
            [[:cntrl:]])
                printf -v code '%d' "'$character"
                printf '\\u%04x' "$code" ;;
            *) printf '%s' "$character" ;;
        esac
    done
    printf '"'
}

json_nullable_string() {
    if [[ -n "$1" ]]; then json_string "$1"; else printf 'null'; fi
}

json_array() {
    local separator='' value
    printf '['
    for value in "$@"; do
        printf '%s' "$separator"
        json_string "$value"
        separator=,
    done
    printf ']'
}

get_snapshot() {
    local root field current_path='' marker path line=''
    git_run 0 check-ref-format "$branch"
    git_run '0 1' symbolic-ref --quiet "$branch"
    (( git_code == 1 )) || die 'Owned branch must be a direct ref, not a symbolic alias to another ref.'
    capture_git 0 rev-parse --show-toplevel
    canonical_dir "$git_text"
    root=$canonical
    [[ "$root" == "$worktree" ]] || die 'Worktree must be the exact repository/worktree root, not a subdirectory.'
    git_run 0 status --porcelain=v1 --untracked-files=all
    clean=true
    dirty_count=0
    dirty_preview=()
    while IFS= read -r line || [[ -n "$line" ]]; do
        clean=false
        dirty_count=$((dirty_count + 1))
        if (( dirty_count <= 10 )); then dirty_preview+=("$line"); fi
    done < "$temp_dir/output"
    capture_git '0 1' symbolic-ref --quiet HEAD
    symbolic_head=''
    if (( git_code == 0 )); then symbolic_head=$git_text; fi
    capture_git 0 rev-parse --verify 'HEAD^{commit}'
    head=$git_text
    capture_git 0 rev-parse --verify "${branch}^{commit}"
    branch_head=$git_text
    capture_git 0 rev-parse --path-format=absolute --git-common-dir
    canonical_dir "$git_text"
    common_dir=$canonical
    git_run 0 worktree list --porcelain -z
    occupants=()
    occupant_count=0
    while IFS= read -r -d '' field; do
        case "$field" in
            'worktree '*) current_path=${field#worktree } ;;
            "branch $branch")
                [[ -n "$current_path" ]] || die 'Malformed Git worktree record.'
                occupants+=("$current_path")
                occupant_count=$((occupant_count + 1)) ;;
        esac
    done < "$temp_dir/output"
    git_operations=()
    operation_count=0
    for marker in rebase-merge rebase-apply MERGE_HEAD CHERRY_PICK_HEAD REVERT_HEAD BISECT_START sequencer; do
        capture_git 0 rev-parse --path-format=absolute --git-path "$marker"
        path=$git_text
        if [[ -e "$path" || -L "$path" ]]; then
            git_operations+=("$marker")
            operation_count=$((operation_count + 1))
        fi
    done
}

emit_snapshot() {
    printf '{"worktree":'; json_string "$worktree"
    printf ',"commonDir":'; json_string "$common_dir"
    printf ',"branch":'; json_string "$branch"
    printf ',"head":'; json_string "$head"
    printf ',"branchHead":'; json_string "$branch_head"
    printf ',"branchEqualsHead":'
    if [[ "$branch_head" == "$head" ]]; then printf 'true'; else printf 'false'; fi
    printf ',"symbolicHead":'; json_nullable_string "$symbolic_head"
    printf ',"clean":%s,"dirtyEntryCount":%s,"dirtyPreview":' "$clean" "$dirty_count"
    json_array ${dirty_preview[@]+"${dirty_preview[@]}"}
    printf ',"gitOperations":'; json_array ${git_operations[@]+"${git_operations[@]}"}
    printf ',"branchOccupants":'; json_array ${occupants[@]+"${occupants[@]}"}
    printf '}'
}

assert_detached_ready() {
    [[ "$clean" == true ]] || die 'Worktree is dirty; preserve its tracked/staged/untracked files.'
    (( operation_count == 0 )) || die "Active Git operation: ${git_operations[*]}."
    [[ -z "$symbolic_head" ]] || die 'Owner must provide a detached handoff before attach.'
    [[ "$head" == "$expected_head" ]] || die "Detached HEAD drifted: expected $expected_head, found $head."
    (( occupant_count == 0 )) || die "Branch is occupied: ${occupants[*]}."
    [[ "$branch_head" == "$expected_old" || "$branch_head" == "$target" ]] ||
        die "Unexpected branch SHA: $branch_head."
}

get_snapshot
if [[ "$mode" == inspect ]]; then
    emit_snapshot
    printf '\n'
    exit 0
fi
if [[ -e "$common_dir/copilot-owner-light/lease.json" ]]; then
    python=''
    for candidate in python3 python; do
        if type -P "$candidate" >/dev/null &&
                "$candidate" -c 'import sys; assert sys.version_info >= (3, 9)' >/dev/null 2>&1; then
            python=$candidate
            break
        fi
    done
    [[ -n "$python" ]] || die 'Owner-light metadata requires Python 3.9+; do not bypass the lease.'
    script_dir=$(CDPATH='' cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
    "$python" "$script_dir/owner-light.py" guard-helper --worktree "$worktree" >/dev/null
fi
[[ "$mutation_authorized" == true && "$quiesced" == true ]] ||
    die 'Attach requires mutation-authorized and quiesced attestations, including the exclusive writer lease.'
[[ "$operation" =~ ^[A-Za-z0-9][A-Za-z0-9._-]{0,79}$ ]] ||
    die 'Attach requires a safe operation ID and positive generation.'
[[ "$generation" =~ ^[0-9]+$ && ${#generation} -le 10 ]] ||
    die 'Attach requires a safe operation ID and positive generation.'
(( 10#$generation > 0 && 10#$generation <= 2147483647 )) ||
    die 'Attach requires a safe operation ID and positive generation.'
generation=$((10#$generation))
capture_git 0 rev-parse --show-object-format
case "$git_text" in
    sha1) oid_length=40 ;;
    sha256) oid_length=64 ;;
    *) die "Unsupported Git object format: $git_text." ;;
esac
for oid in "$expected_head" "$expected_old" "$target"; do
    [[ ${#oid} -eq "$oid_length" && "$oid" =~ ^[0-9a-f]+$ ]] ||
        die 'Attach requires full lowercase object IDs for the repository format.'
done
assert_detached_ready

backup_ref=''
transfer_ref=''
disposition=verified-already-at-target
if [[ "$branch_head" != "$target" ]]; then
    [[ -n "$source" && "$source" != -* && ! "$source" =~ [[:cntrl:]] && "$source_ref" == refs/* ]] ||
        die 'A changed branch requires a verified source repository/remote and full source ref.'
    git_run 0 check-ref-format "$source_ref"
    nonce=$(od -An -N16 -tx1 /dev/urandom | tr -d ' \n')
    [[ "$nonce" =~ ^[0-9a-f]{32}$ ]] || die 'Could not generate fresh recovery ref names.'
    namespace="refs/copilot/$operation/g$generation"
    backup_ref="$namespace/backup-$nonce"
    transfer_ref="$namespace/transfer-$nonce"
    git_run 0 check-ref-format "$backup_ref"
    git_run 0 check-ref-format "$transfer_ref"
    git_run '0 1' show-ref --verify --quiet "$transfer_ref"
    (( git_code == 1 )) || die "Transfer ref collision: $transfer_ref."
    get_snapshot
    assert_detached_ready
    printf -v zero_oid '%0*d' "$oid_length" 0
    git_run 0 update-ref --no-deref "$backup_ref" "$expected_old" "$zero_oid"
    capture_git 0 rev-parse --verify "$backup_ref"
    [[ "$git_text" == "$expected_old" ]] || die "Backup verification failed: $backup_ref."
    git_run 0 fetch --quiet --no-tags --no-write-fetch-head --no-recurse-submodules \
        --no-prune --no-prune-tags --no-auto-maintenance --no-write-commit-graph \
        --refmap= -- "$source" "$source_ref:$transfer_ref"
    capture_git 0 rev-parse --verify "${transfer_ref}^{commit}"
    [[ "$git_text" == "$target" ]] ||
        die "Transferred commit differs from target: $git_text. Recovery refs: $backup_ref, $transfer_ref."
    get_snapshot
    assert_detached_ready
    if [[ "$branch_head" != "$target" ]]; then
        git_run 0 update-ref --no-deref "$branch" "$target" "$expected_old"
    fi
    disposition=transferred
fi
get_snapshot
assert_detached_ready
[[ "$branch_head" == "$target" ]] || die 'Branch does not match the verified target before checkout.'
git_run 0 switch --quiet -- "${branch#refs/heads/}"
get_snapshot
[[ "$clean" == true && "$symbolic_head" == "$branch" && "$head" == "$target" &&
    "$branch_head" == "$target" && "$operation_count" == 0 && "$occupant_count" == 1 ]] ||
    die 'Final attachment verification failed; preserve state and recovery refs.'
canonical_dir "${occupants[0]}"
[[ "$canonical" == "$worktree" ]] || die 'Final attachment occupies an unexpected worktree.'
printf '{"operation":'; json_string "$operation"
printf ',"generation":%s,"disposition":' "$generation"; json_string "$disposition"
printf ',"backupRef":'; json_nullable_string "$backup_ref"
printf ',"transferRef":'; json_nullable_string "$transfer_ref"
printf ',"snapshot":'; emit_snapshot
printf '}\n'
