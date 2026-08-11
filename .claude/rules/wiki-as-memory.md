# Wiki as project memory

This project maintains a persistent wiki at `wiki/<repo>.wiki/` (a separate git repository with its own remote) following the [llm-wiki pattern](https://github.com/tobi/llm-wiki).
The wiki is the project's durable memory across sessions and collaborators: findings, decisions, and intermediate insights belong in the wiki.
Read it to recall context; write to it to remember.
Apply this rule in both directions, proactively, without waiting to be asked.

Defer to the wiki's own `SCHEMA_<repo>.md` for page format, frontmatter (required `type:` and `up:`, optional typed edges like `extends:` / `supports:` / `criticizes:`), naming, cross-reference styles, and the full operation procedures.
Do not duplicate SCHEMA's rules into project files.
For background on why the wiki exists as a compounding artifact rather than as RAG over raw sources, see `llm-wiki.md` at the repo root.

## Read to recall

When context about the project would help an answer, read the wiki first: start at `index_<repo>.md`, then drill into named pages.
Cite page names when synthesizing answers.
If a wiki claim conflicts with current code or results, trust what is observed now and flag the stale page rather than repeating it.

## Write to remember

Write to the wiki whenever significant work produces something a future session would benefit from knowing: experiment results (configuration, headline metrics, what changed, what was surprising), decisions with stated reasons, reusable syntheses, contradictions of prior claims.
Follow the Ingest procedure in the wiki's SCHEMA file: create or update pages with frontmatter, fix cross-references on every affected page in both directions, update `index_<repo>.md`, and append an entry to `log_<repo>.md`.
After each experiment run, file at least a short summary page that links to the experiment's `results/` directory.

## Lint

Periodically health-check the wiki for orphan pages, dead links, stale claims, concepts mentioned without their own page, missing cross-references, pages missing frontmatter, and pages still marked `type: untyped`.

## Finish the cycle: every wiki edit ends with a commit

The wiki is a separate git repo; wiki edits are committed there, not in the containing project.
Before committing, run the Verification Gate at `wiki/agents/verification-gate.md` over every page created or edited.
It catches projection-as-fact, missing corpus tags on numerical claims, missing back-references, and missing log/index entries.
Then:

```bash
git -C wiki/<repo>.wiki add <files-by-name>
git -C wiki/<repo>.wiki commit -m "<descriptive message>"
```

Execute these without asking; local commits in the wiki repo are trivially reversible.
Push only when explicitly asked.
When pushing, follow the procedure at `wiki/agents/wiki-write-protocol.md` rather than plain `git push`: its `wiki_push` wrapper handles multi-writer collisions safely.

Honest reporting: bad results and contradicted claims get filed truthfully, not polished.
Never report metrics from projections, only from real script outputs.
See `wiki/agents/discipline-gates.md` for the canonical "Universal Rationalizations (Always Wrong)" table that names the failure modes the Verification Gate catches.

Skills `/wiki-experiment`, `/wiki-source`, and `/wiki-lint` (`.claude/skills/<name>/SKILL.md`) invoke each operation explicitly.
They are a safety net: the proactive behavior described above is the default.
