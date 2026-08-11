#!/usr/bin/env bash
# Unit test: mechanical reciprocity check (scripts/wiki-reciprocity.py).
#
# Runs the checker against a fixture wiki that contains, by construction:
#   - a reciprocal pair          Alpha <-> Beta      (must NOT be flagged)
#   - a one-way link             Alpha  -> Gamma     (MUST be flagged)
#   - a hub page                 Hub (hub: true)     (must be exempt)
#   - special files              index_/SCHEMA_      (must be excluded)
#
# The fixture is red by construction (one known violation), and the test also
# builds a patched copy that adds the missing back-reference to prove the check
# goes green — so both directions of the contrast are exercised here.

REPO_ROOT="$(cd "$HERE/../.." && pwd)"
SCRIPT="$REPO_ROOT/scripts/wiki-reciprocity.py"
FIX="$REPO_ROOT/scripts/test/tests/unit/wiki-reciprocity/fixtures/wiki"

assert "python3 on PATH"                 "command -v python3"
assert "wiki-reciprocity.py present"     "[ -f '$SCRIPT' ]"
assert "wiki-reciprocity.py compiles" \
    "python3 -c \"import py_compile; py_compile.compile('$SCRIPT', doraise=True)\""
assert "fixture wiki present"            "[ -d '$FIX' ]"

# --- Red: shipped fixture has exactly one one-way link (Alpha -> Gamma) ---
OUT="$SANDBOX/recip.out"; ERR="$SANDBOX/recip.err"
if python3 "$SCRIPT" "$FIX" >"$OUT" 2>"$ERR"; then RC=0; else RC=$?; fi

assert "exits non-zero when a violation exists"        "[ '$RC' -eq 1 ]"
assert_contains "reports the Alpha -> Gamma one-way link" "$OUT" "Alpha -> Gamma"
assert_not_contains "hub page is exempt (no Hub-> flagged)" "$OUT" "Hub ->"
assert_not_contains "reciprocal pair Alpha/Beta not flagged (A->B)" "$OUT" "Alpha -> Beta"
assert_not_contains "reciprocal pair Alpha/Beta not flagged (B->A)" "$OUT" "Beta -> Alpha"
assert_not_contains "special file index_ not flagged as source" "$OUT" "index_fixture ->"
assert_contains "summary counts exactly one violation" "$ERR" "1 reciprocity violation"

# --- JSON mode carries the same finding ---
JOUT="$SANDBOX/recip.json"
python3 "$SCRIPT" "$FIX" --json >"$JOUT" 2>/dev/null || true
assert_contains "json mode emits the Alpha->Gamma pair" "$JOUT" '"from": "Alpha"'
assert_contains "json mode emits the Gamma target"      "$JOUT" '"to": "Gamma"'

# --- Green: add the missing back-reference -> the check clears ---
CLEAN="$SANDBOX/wiki-clean"; rm -rf "$CLEAN"; cp -r "$FIX" "$CLEAN"
printf '\nGamma now references [Alpha](Alpha) back.\n' >> "$CLEAN/Gamma.md"
COUT="$SANDBOX/clean.out"; CERR="$SANDBOX/clean.err"
if python3 "$SCRIPT" "$CLEAN" >"$COUT" 2>"$CERR"; then RC2=0; else RC2=$?; fi

assert "exits 0 when every link is reciprocal"  "[ '$RC2' -eq 0 ]"
assert_contains "summary counts zero violations" "$CERR" "0 reciprocity violation"

# --- Bad path is a usage error, not a silent pass ---
if python3 "$SCRIPT" "$SANDBOX/does-not-exist" >/dev/null 2>&1; then RC3=0; else RC3=$?; fi
assert "missing wiki dir exits 2 (usage/IO error, not 0)" "[ '$RC3' -eq 2 ]"
