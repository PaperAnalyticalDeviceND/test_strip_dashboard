#!/usr/bin/env bash
# Integration test assertions: SessionStart hook content injection.
#
# Runs the rendered hook against both fake projects staged by patch.sh
# (with-wiki and without-wiki) and asserts on stdout.

STAGE_DIR="$SANDBOX/session-start-hook"
FAKE_DIR="$STAGE_DIR/fakerepo"
NOWIKI_DIR="$STAGE_DIR/fakerepo-nowiki"

if [ ! -d "$FAKE_DIR" ] || [ ! -f "$FAKE_DIR/hook.sh" ]; then
    skip "session-start-hook integration assertions" "fakerepo staging missing"
    return 0 2>/dev/null || true
fi

# --- with-wiki: capture hook stdout once for the full assertion set ---
WITH_WIKI_OUT=$(cd "$FAKE_DIR" && bash hook.sh 2>&1)
WITH_WIKI_OUT_FILE=$(mktemp)
printf '%s\n' "$WITH_WIKI_OUT" > "$WITH_WIKI_OUT_FILE"

# Block 1: orientation reminder is always present.
assert_contains "hook emits orientation system-reminder" \
    "$WITH_WIKI_OUT_FILE" "durable memory"
assert_contains "hook orientation mentions wiki/<repo>.wiki/" \
    "$WITH_WIKI_OUT_FILE" "wiki/fakerepo.wiki/"

# Sed substitution actually fired: no literal \${REPO_NAME} survives.
assert "hook output does NOT leak \${REPO_NAME} placeholder" \
    "! grep -qF '\${REPO_NAME}' '$WITH_WIKI_OUT_FILE'"

# Block 2: the index was injected. Sentinel phrases come from the stub
# index that patch.sh wrote.
assert_contains "hook emits the index injection header" \
    "$WITH_WIKI_OUT_FILE" "## Wiki current state — index"
assert_contains "hook emits the index's H1" \
    "$WITH_WIKI_OUT_FILE" "Index — fakerepo"
assert_contains "hook emits the index's sentinel page entry" \
    "$WITH_WIKI_OUT_FILE" "Test-Concept-Alpha"

# Block 3: the LAST 5 of 7 log entries are emitted. Sentinel phrases:
# - "Entry 1" and "Entry 2" must NOT appear (they are too old).
# - "Entry 3" through "Entry 7" must all appear.
assert_contains "hook emits last-log-entries injection header" \
    "$WITH_WIKI_OUT_FILE" "## Wiki current state — last 5 log entries"
assert "hook does NOT include log Entry 1 (oldest, beyond last-5 window)" \
    "! grep -qF 'Entry 1 — oldest' '$WITH_WIKI_OUT_FILE'"
assert "hook does NOT include log Entry 2 (also beyond window)" \
    "! grep -qF 'Entry 2 — also too old' '$WITH_WIKI_OUT_FILE'"
assert_contains "hook includes log Entry 3 (first of last-5)" \
    "$WITH_WIKI_OUT_FILE" "Entry 3 — first of the last 5"
assert_contains "hook includes log Entry 4" \
    "$WITH_WIKI_OUT_FILE" "Entry 4"
assert_contains "hook includes log Entry 5" \
    "$WITH_WIKI_OUT_FILE" "Entry 5"
assert_contains "hook includes log Entry 6" \
    "$WITH_WIKI_OUT_FILE" "Entry 6"
assert_contains "hook includes log Entry 7 (most recent)" \
    "$WITH_WIKI_OUT_FILE" "Entry 7 — most recent"

rm -f "$WITH_WIKI_OUT_FILE"

# --- without-wiki: orientation only, no injection blocks ---
if [ -f "$NOWIKI_DIR/hook.sh" ]; then
    NOWIKI_OUT=$(cd "$NOWIKI_DIR" && bash hook.sh 2>&1)
    NOWIKI_OUT_FILE=$(mktemp)
    printf '%s\n' "$NOWIKI_OUT" > "$NOWIKI_OUT_FILE"

    # Orientation still emitted.
    assert_contains "no-wiki: hook still emits orientation" \
        "$NOWIKI_OUT_FILE" "durable memory"

    # Index and log injection blocks must be silently skipped.
    assert "no-wiki: hook does NOT emit index injection header" \
        "! grep -qF 'Wiki current state — index' '$NOWIKI_OUT_FILE'"
    assert "no-wiki: hook does NOT emit log injection header" \
        "! grep -qF 'Wiki current state — last 5' '$NOWIKI_OUT_FILE'"

    # The hook should also exit 0 (advisory; never blocks). assertions.sh
    # runs after patch.sh succeeds, so we verify by checking the hook
    # script exits cleanly when re-invoked with errexit-style strictness.
    NOWIKI_RC=$(cd "$NOWIKI_DIR" && bash hook.sh >/dev/null 2>&1; echo $?)
    assert_eq "no-wiki: hook exits 0 (advisory; never blocks)" "0" "$NOWIKI_RC"

    rm -f "$NOWIKI_OUT_FILE"
fi
