---
name: wiki-lint
description: Run a health check on the wiki. Surfaces orphan pages, dead links, stale claims, missing frontmatter, untyped pages, and concepts that lack their own page. Reports findings and offers fixes.
---

The wiki is a compounding artifact. Over time it accretes orphans, broken links, and stale claims that contradict newer pages. A periodic lint pass keeps it healthy.

## What to check

Walk `wiki/{{REPO_NAME}}.wiki/` and report on each of the following. For each issue, list the affected page(s) and propose a fix.

1. **Orphan pages.** Pages with no inbound links from other wiki pages or from `index_{{REPO_NAME}}.md`. Either link them in from a parent page, or flag them for archival.
2. **Dead links.** `[Display](Page-Name)` or `[[Page-Name]]` references pointing to files that do not exist. Either fix the target name or remove the broken link.
3. **Stale claims.** Pages whose claims are superseded by newer pages or by current code/results. Update the page or add a note pointing to the superseding page.
4. **Missing frontmatter.** Pages without a frontmatter block at the top, or with frontmatter missing required fields (`type:`, `up:`). Infer the fields from page content and add them.
5. **`type: untyped` pages.** Review each and assign a proper type if now obvious (`concept`, `entity`, `source-summary`, `synthesis`, `index`, `comparison`).
6. **Missing concept pages.** Concepts mentioned in multiple body texts that do not have their own page. Promote to standalone pages with proper frontmatter.
7. **Missing cross-references (bidirectional).** If A links to B, B should link back to A unless one is hub-and-spoke by design. Enumerate these mechanically rather than by eye: run `python3 scripts/wiki-reciprocity.py wiki/{{REPO_NAME}}.wiki/` — it lists every one-way link (`A -> B` where B does not reference A back by any means), exempting special files and pages marked `hub: true` in frontmatter. Fix each by adding the missing back-reference on the target, or mark a genuine hub `hub: true`.
8. **Index gaps.** Pages that exist in the wiki but are not listed in `index_{{REPO_NAME}}.md`.
9. **Naming convention.** Page filenames should be `Title-Case-Hyphenated.md`. Flag deviations.
10. **Special-file integrity.** `Home_…md`, `index_…md`, `log_…md`, `SCHEMA_…md`, `Home.md` (redirect) all present and well-formed.

## Reference

Defer to `wiki/{{REPO_NAME}}.wiki/SCHEMA_{{REPO_NAME}}.md` for the precise conventions. This skill is a checklist, not a redefinition.

## Procedure

1. Read `index_{{REPO_NAME}}.md` to get the canonical list of pages.
2. List all `.md` files in the wiki directory.
3. For each check above, scan systematically and collect findings.
4. Report findings to the user grouped by check type, with one or two example pages per finding.
5. Ask which findings to fix in this pass. Lint is incremental; not every issue needs to be addressed at once.
6. For accepted fixes, apply them with cross-reference repair in both directions, update `index_{{REPO_NAME}}.md` as needed, and append a `## [YYYY-MM-DD] lint | Subject` entry to `log_{{REPO_NAME}}.md` describing what was cleaned up. The first bullet of that entry is the attribution line `- by: <name> via claude-code`, where `<name>` is the output of `git config user.name` in the wiki repo (read it, do not invent it). See "Log Entry Attribution" in `SCHEMA_{{REPO_NAME}}.md`.
7. Optionally rebuild the knowledge graph: `./scripts/kg/build-graph.sh`.
8. Commit in the wiki's own git repo in two steps: first stage and commit the lint fixes and index changes by name, then stage and commit the `log_{{REPO_NAME}}.md` entry on its own. One commit per log entry keeps `git blame` on the log a faithful per-entry record (see "Log Entry Attribution" in SCHEMA). Do not push unless asked. **When pushing, follow the procedure at `wiki/agents/wiki-write-protocol.md`** rather than plain `git push`.

## When to run

- Every several sessions, when the wiki has grown by ~10 or more pages since the last lint.
- After a major ingest (a new source or a large experiment write-up) that touched many pages.
- When the user asks, or notices a broken link or a contradiction.

## Honest reporting

Do not paper over contradictions or stale claims to make the wiki look cleaner. If two pages disagree and current code/results decide between them, update the loser to reflect that and link to the winner. The wiki is durable memory only when it remains honest.
