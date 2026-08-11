#!/usr/bin/env bash
# Patch: fixture for the stale-manifest self-heal in update-from-template.sh.
#
# Field case: hosts instantiated between the manifest consolidation (#60,
# 2026-06-28) and the manifest-ships-itself fix (#76, 2026-07-10) carry a
# manifest that is PRESENT but does not list itself. Their update runs
# assemble the file list from that stale manifest, which can never deliver
# its own replacement — the host is stuck on the old list forever (first
# observed on ND-DAC-DOME/naval-sensor-fusion, instantiated 2026-06-30).
#
# Effects: creates $SANDBOX/stale-manifest-self-heal/ with:
#   template-src/  stand-in template repo (branch main) holding the CURRENT
#                  manifest plus three files only the current manifest lists
#                  (wiki/Edge-Types.md.template, .claude/commands/ask.md,
#                  scripts/wiki-reciprocity.py) and one old-list file with a
#                  {{REPO_NAME}} token (control: normal sync still works)
#   host/          project with the CURRENT sync tooling under scripts/ but a
#                  STALE manifest: derived from the current one by deleting
#                  the self-listing and the three post-#76 entries — the
#                  exact shape of the stuck vintage (functional, sources
#                  cleanly, omits itself)
#
# Hermetic: the "remote" is a local path.

set -uo pipefail

HERE_PATCH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE_ROOT="$(cd "$HERE_PATCH/../../../../.." && pwd)"

STAGE="$SANDBOX/stale-manifest-self-heal"
mkdir -p "$STAGE"

g() { git "$@"; }

# --- template-src: minimal current-shape template repo ---
T="$STAGE/template-src"
g init -q "$T"
g -C "$T" symbolic-ref HEAD refs/heads/main
mkdir -p "$T/scripts/lib" "$T/.claude/commands" "$T/.claude/skills/wiki-experiment" "$T/wiki"
cp "$TEMPLATE_ROOT/scripts/lib/template-manifest.sh" "$T/scripts/lib/"
printf '# Edge-Types for {{REPO_NAME}} (rendered by init-wiki)\n' > "$T/wiki/Edge-Types.md.template"
printf 'ask command body\n'            > "$T/.claude/commands/ask.md"
printf '#!/usr/bin/env python3\n'      > "$T/scripts/wiki-reciprocity.py"
printf 'skill for {{REPO_NAME}}\n'     > "$T/.claude/skills/wiki-experiment/SKILL.md"
g -C "$T" add -A
g -C "$T" commit -q -m "template content"

# --- host: current tooling + genuinely stale manifest ---
H="$STAGE/host"
g init -q "$H"
mkdir -p "$H/wiki/stalehost.wiki" "$H/.claude/skills/wiki-experiment" "$H/scripts/lib"
: > "$H/wiki/stalehost.wiki/SCHEMA_stalehost.md"
printf 'stale local content\n' > "$H/.claude/skills/wiki-experiment/SKILL.md"
cp "$TEMPLATE_ROOT/scripts/update-from-template.sh" "$H/scripts/"
cp "$TEMPLATE_ROOT/scripts/check-template-version.sh" "$H/scripts/"
cp "$TEMPLATE_ROOT"/scripts/lib/*.sh "$H/scripts/lib/"

# Stale manifest: current one minus the self-listing and the post-#76
# entries. Still valid bash, still assembles — just the stuck-vintage list.
sed -e '/"scripts\/lib\/template-manifest.sh"/d' \
    -e '/"wiki\/Edge-Types.md.template"/d' \
    -e '/".claude\/commands\/ask.md"/d' \
    -e '/"scripts\/wiki-reciprocity.py"/d' \
    "$TEMPLATE_ROOT/scripts/lib/template-manifest.sh" \
    > "$H/scripts/lib/template-manifest.sh"

# Sanity: the stale manifest must source cleanly and must NOT list itself —
# otherwise the fixture is not exercising the stuck vintage at all.
bash -n "$H/scripts/lib/template-manifest.sh"
if grep -qF '"scripts/lib/template-manifest.sh"' "$H/scripts/lib/template-manifest.sh"; then
    echo "  ERROR: fixture failed to produce a stale (non-self-listing) manifest" >&2
    exit 1
fi

echo "  stale-manifest-self-heal patch applied: fixtures at $STAGE"
