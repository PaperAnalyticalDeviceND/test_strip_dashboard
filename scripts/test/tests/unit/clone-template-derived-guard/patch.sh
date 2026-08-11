#!/usr/bin/env bash
# Patch: build two fake project roots so assertions.sh can exercise
# clone_template's derived-project guard (issue #15).
#
# Inputs:  SANDBOX env var.
# Effects: $SANDBOX/clone-template-guard/ contains
#            fake-template/   (has scripts/instantiate.sh)
#            fake-derived/    (lacks scripts/instantiate.sh)
#
# Idempotent.

set -uo pipefail

ROOT="$SANDBOX/clone-template-guard"
TEMPL="$ROOT/fake-template"
DERIVED="$ROOT/fake-derived"

mkdir -p "$TEMPL/scripts" "$DERIVED"

# A fake template: the discriminator is scripts/instantiate.sh present
# (the one-shot bootstrap only the canonical template carries). We do not
# need real template contents; clone_template's guard only looks at this
# one filename.
echo "#!/usr/bin/env bash" > "$TEMPL/scripts/instantiate.sh"

# A fake derived project: scripts/instantiate.sh absent. This is what
# instantiate.sh leaves behind after self-deleting. A derived project may
# or may not have its own CLAUDE.md; include one to prove the guard does
# not key on it.
echo "# CLAUDE.md (derived project state)" > "$DERIVED/CLAUDE.md"

# A fake derived project WITHOUT a CLAUDE.md: instantiate no longer
# creates one, so this is the normal shape of a new-style derived
# project. The old CLAUDE.md-based discriminator failed to refuse this
# case (no CLAUDE.md meant "not derived"); the instantiate.sh-based one
# must refuse it.
DERIVED_BARE="$ROOT/fake-derived-no-claude"
mkdir -p "$DERIVED_BARE"
echo "# host readme" > "$DERIVED_BARE/README.md"

echo "  clone-template-guard: fake roots ready at $ROOT"
