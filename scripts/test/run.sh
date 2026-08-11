#!/usr/bin/env bash
# Test harness for the llm-wiki-memory-template MVP.
# See ./README.md for what this is and how to use it.

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/assert.sh
source "$HERE/lib/assert.sh"
# shellcheck source=lib/sandbox.sh
source "$HERE/lib/sandbox.sh"
# shellcheck source=lib/template.sh
source "$HERE/lib/template.sh"

# Globals updated by assertion helpers
PASS=0
FAIL=0
SKIP=0
FAILED_TESTS=()

# Category order: faster / structural first, behavioral later.
# Any category directory under tests/ that's not in this list still runs,
# alphabetically, after the known ones.
KNOWN_CATEGORIES=(smoke unit integration e2e regression)

# Parse args (initialize arrays explicitly for bash 3.2 + set -u).
# Uses a while loop so `--category <name>` (space-separated) can consume
# the next positional argument; a for-loop over "$@" would freeze the
# iteration list and make `shift` a no-op for advancing past <name>.
EXPLICIT_TESTS=()
EXPLICIT_CATEGORIES=()
TEST_LIST=()
CLEANUP=1
while [[ $# -gt 0 ]]; do
    case "$1" in
        --no-cleanup) CLEANUP=0; shift ;;
        -h|--help)
            grep -E '^# ' "$0" | sed 's/^# \?//'
            echo ""
            echo "Usage: $0 [--no-cleanup] [--category <name>] [test-name ...]"
            echo ""
            echo "  --no-cleanup       Keep the sandbox dir after the run for inspection."
            echo "  --category <name>  Run only tests in this category (smoke/unit/integration/e2e/regression)."
            echo "                     Can be repeated. --category=<name> is also accepted."
            echo "  <test-name>        Run only this specific test (by directory name). Can be repeated."
            echo ""
            echo "With no args, runs all tests in known category order."
            exit 0
            ;;
        --category)
            shift
            if [[ $# -eq 0 ]]; then
                echo "Error: --category requires an argument" >&2
                exit 2
            fi
            EXPLICIT_CATEGORIES+=("$1")
            shift
            ;;
        --category=*)
            EXPLICIT_CATEGORIES+=("${1#--category=}")
            shift
            ;;
        --*)
            echo "Unknown flag: $1" >&2
            exit 2
            ;;
        *)
            # Treat anything else as a test name to filter on
            EXPLICIT_TESTS+=("$1")
            shift
            ;;
    esac
done

# Build the list of test directories to run.
# Each entry is "<category>/<name>".
build_test_list() {
    local categories=()
    # ${#ARRAY[@]} always returns 0 for empty (declared) arrays in any bash
    # version; no special handling needed. (Earlier ${#ARR[@]:-0} workaround
    # was wrong syntax: works in bash 3.2 by accident, rejected by bash 5+.)
    if [ "${#EXPLICIT_CATEGORIES[@]}" -gt 0 ]; then
        categories=("${EXPLICIT_CATEGORIES[@]}")
    else
        # Known categories first, then any others
        for c in "${KNOWN_CATEGORIES[@]}"; do
            [ -d "$HERE/tests/$c" ] && categories+=("$c")
        done
        # Catch any extra category dirs not in the known list
        for d in "$HERE/tests"/*; do
            [ -d "$d" ] || continue
            local cname; cname=$(basename "$d")
            local known=0
            for c in "${KNOWN_CATEGORIES[@]}"; do
                [ "$c" = "$cname" ] && known=1 && break
            done
            [ "$known" -eq 0 ] && categories+=("$cname")
        done
    fi

    local out=()
    for cat in "${categories[@]}"; do
        local cat_dir="$HERE/tests/$cat"
        [ -d "$cat_dir" ] || continue
        for t in "$cat_dir"/*/; do
            [ -d "$t" ] || continue
            local tname; tname=$(basename "$t")
            # If specific tests requested, filter
            if [ "${#EXPLICIT_TESTS[@]}" -gt 0 ]; then
                local match=0
                for et in "${EXPLICIT_TESTS[@]}"; do
                    [ "$et" = "$tname" ] && match=1 && break
                done
                [ "$match" -eq 0 ] && continue
            fi
            out+=("$cat/$tname")
        done
    done
    printf '%s\n' "${out[@]}"
}

# Portable equivalent of `mapfile -t TEST_LIST < <(build_test_list)`
# (mapfile is bash 4+; macOS ships bash 3.2)
TEST_LIST=()
while IFS= read -r _line; do
    [ -n "$_line" ] && TEST_LIST+=("$_line")
done < <(build_test_list)

if [ ${#TEST_LIST[@]} -eq 0 ]; then
    echo "No tests found." >&2
    if [ ${#EXPLICIT_TESTS[@]} -gt 0 ]; then
        echo "  Filters were: ${EXPLICIT_TESTS[*]}" >&2
    fi
    exit 2
fi

# Set up sandbox
SANDBOX=$(sandbox_setup)
echo "Sandbox: $SANDBOX"

# Pin one hermetic git identity for every test and script-under-test.
sandbox_git_env

# Cleanup on exit unless --no-cleanup
cleanup() {
    if [ "$CLEANUP" -eq 1 ]; then
        sandbox_teardown "$SANDBOX"
    else
        echo ""
        echo "Sandbox preserved at: $SANDBOX"
    fi
}
trap cleanup EXIT

# Default the template source to THIS working tree when the caller set
# neither MVP_TEMPLATE_LOCAL nor MVP_TEMPLATE_REPO. Without this, a bare
# local run network-cloned the PUBLISHED template: the sandbox then tested
# upstream main instead of the tree being edited (a green that says nothing
# about your change), and the clone-dir naming broke every wiki/<name>.wiki
# assertion (30 spurious fails).
#
# The export copies git-visible files only (tracked + untracked-unignored,
# via ls-files --exclude-standard) instead of cp -R'ing the working tree,
# so gitignored contributor artifacts — the dev-self CLAUDE.md excluded via
# .git/info/exclude, wiki/<template>.wiki/, kg build caches — never leak
# into the sandbox and corrupt the bootstrap assertions.
#
# CI is unaffected: test-harness.yml sets MVP_TEMPLATE_LOCAL explicitly.
# In a DERIVED project (this harness ships via "Use this template"), the
# export lacks scripts/instantiate.sh (self-deleted at instantiation), so
# clone_template's derived-project guard (issue #15) still declines and
# smoke tests skip.
if [ -z "${MVP_TEMPLATE_LOCAL:-}" ] && [ -z "${MVP_TEMPLATE_REPO:-}" ]; then
    REPO_ROOT_DEFAULT="$(cd "$HERE/../.." && pwd)"
    if git -C "$REPO_ROOT_DEFAULT" rev-parse --show-toplevel >/dev/null 2>&1; then
        TEMPLATE_SRC="$SANDBOX/template-src"
        mkdir -p "$TEMPLATE_SRC"
        # The while loop drops tracked-but-deleted paths (ls-files --cached
        # still lists them) so tar never errors on a missing file. NUL
        # delimiters throughout; bsdtar and GNU tar both take --null -T -.
        if (
            cd "$REPO_ROOT_DEFAULT" \
            && git ls-files -z --cached --others --exclude-standard \
               | while IFS= read -r -d '' _f; do
                     if [ -e "$_f" ]; then printf '%s\0' "$_f"; fi
                 done \
               | tar --null -T - -cf -
        ) | tar -xf - -C "$TEMPLATE_SRC"; then
            export MVP_TEMPLATE_LOCAL="$TEMPLATE_SRC"
            echo "Template source: $REPO_ROOT_DEFAULT working tree (git-visible files)"
            echo "  (override with MVP_TEMPLATE_LOCAL=<path> or MVP_TEMPLATE_REPO=<url>)"
        else
            # Fail LOUD, do not fall back to the network clone: observed in a
            # derived project's CI, a transient tar failure here degraded into
            # cloning the PUBLISHED template — the run then tested the wrong
            # tree and drowned the real (one-line) error under 30 misleading
            # naming-assertion fails. An export failure means the environment
            # is broken; nothing this run could report would be trustworthy.
            echo "ERROR: could not export the working tree for smoke tests" >&2
            echo "       (git ls-files | tar pipeline failed; see tar errors above)." >&2
            echo "       Refusing to fall back to a network clone of the published" >&2
            echo "       template: that would test upstream main, not this tree." >&2
            echo "       To test a different source explicitly, set MVP_TEMPLATE_LOCAL" >&2
            echo "       or MVP_TEMPLATE_REPO." >&2
            exit 2
        fi
    fi
fi

# Run each test in order
LAST_CATEGORY=""
for entry in "${TEST_LIST[@]}"; do
    category="${entry%%/*}"
    test_name="${entry#*/}"
    test_dir="$HERE/tests/$category/$test_name"

    if [ "$category" != "$LAST_CATEGORY" ]; then
        echo ""
        echo "########## Category: $category ##########"
        LAST_CATEGORY="$category"
    fi

    echo ""
    echo "=== Test: $test_name ($category) ==="

    # Apply patch (test setup)
    if [ -f "$test_dir/patch.sh" ]; then
        if ! SANDBOX="$SANDBOX" bash "$test_dir/patch.sh"; then
            echo "  Patch script failed; skipping assertions for this test." >&2
            FAIL=$((FAIL+1))
            FAILED_TESTS+=("$entry: patch script failed")
            continue
        fi
    fi

    # Run assertions
    if [ -f "$test_dir/assertions.sh" ]; then
        # shellcheck source=/dev/null
        SANDBOX="$SANDBOX" source "$test_dir/assertions.sh"
    else
        echo "  No assertions.sh in $test_dir; skipping." >&2
    fi
done

# Report
echo ""
echo "=========================================="
echo "RESULTS: $PASS pass, $FAIL fail, $SKIP skip"
if [ "$FAIL" -gt 0 ]; then
    echo ""
    echo "Failed assertions:"
    for t in "${FAILED_TESTS[@]}"; do
        echo "  - $t"
    done
fi
echo "=========================================="
exit "$FAIL"
