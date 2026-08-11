#!/usr/bin/env bash
# Sandbox lifecycle for the MVP test harness.

sandbox_setup() {
    local d
    d=$(mktemp -d -t llm-wiki-mvp-test.XXXXXX)
    echo "$d"
}

# Pin the one hermetic git identity for the whole harness, exported so it is
# inherited both by the patch.sh subprocesses run.sh spawns and by the
# scripts-under-test the sourced assertions.sh invokes. This is the single place
# fixtures get their git identity; they must not pin it themselves.
#
# Uses GIT_AUTHOR_*/GIT_COMMITTER_* rather than a config file:
#   - GIT_CONFIG_GLOBAL/GIT_CONFIG_SYSTEM only took effect in git 2.32, so on
#     older git (2.25.1 on Ubuntu 20.04) they are silently ignored, leaving
#     commits with no author.
#   - Overriding HOME works on every git version, but it also moves Python's
#     user site-packages and discards git's safe.directory allowlist, breaking
#     unrelated CI setup (missing rdflib, dubious-ownership errors).
# These vars give commit identity on every git version and touch nothing else.
# Branches an assertion checks are set via symbolic-ref, since init.defaultBranch
# is honoured only on git >=2.28.
sandbox_git_env() {
    export GIT_AUTHOR_NAME="llm-wiki test"    GIT_AUTHOR_EMAIL="llm-wiki-test@example.test"
    export GIT_COMMITTER_NAME="llm-wiki test" GIT_COMMITTER_EMAIL="llm-wiki-test@example.test"
}

sandbox_teardown() {
    local d="$1"
    if [ -n "$d" ] && [ -d "$d" ]; then
        # Safety: only delete if path looks like a mktemp dir
        case "$d" in
            /tmp/llm-wiki-mvp-test.*|/var/folders/*/llm-wiki-mvp-test.*)
                rm -rf "$d"
                ;;
            *)
                echo "Refusing to delete unexpected sandbox path: $d" >&2
                return 1
                ;;
        esac
    fi
}
