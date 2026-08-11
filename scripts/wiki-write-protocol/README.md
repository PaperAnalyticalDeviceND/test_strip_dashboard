# Wiki Write Protocol — Reference Implementation

A bash reference implementation of the wiki write protocol specified in
the template wiki page `Multi-Agent-Write-Protocol`. Exercises the
git-merge layer against a sandboxed remote with two (or more) simulated
agents. No LLM in the loop; the semantic resolver step is replaced with
deterministic policies so the mechanics can be tested.

**Design: push-time-only / transparent wrapper.** Agents work directly
on local `main` (standard git workflow). The `wiki_push` wrapper attempts
an optimistic push; on rejection it fetches, merges, classifies
conflicts (union for `index_*`/`log_*`, semantic for everything else),
commits the merge, and retries.

**Status (2026-06-13).** CI-validated reference implementation. Nine
scenarios PASS on `ubuntu-latest` + `macos-latest` as part of the
template's standard test harness. The production wiring into the agent
overlay (sourcing `protocol.sh` from the verification gate / ingest
skills, installing a pre-push hook in derived projects' wiki sub-repos)
is the remaining gap; see the wiki page `Analysis-of-Wiki-Push-Race-Pattern`
for the empirical motivation. PR6 (this rename) is the housekeeping
half; PR7 will land the wiring.

## Layout

```
scripts/wiki-write-protocol/
├── README.md            this file
├── protocol.sh          agent_session_start + wiki_push (+ helpers)
├── sandbox.sh           bare-repo origin + per-agent local clones
├── run-all.sh           discovers and runs every scenario; exit = fails
└── scenarios/
    ├── 01-different-pages          (two agents add unrelated pages)
    ├── 02-different-sections       (different sections of same page)
    ├── 03-same-section             (semantic resolution: append below)
    ├── 04-index-union              (.gitattributes merge=union)
    ├── 05-log-append               (.gitattributes merge=union)
    ├── 06-push-race                (pre-receive rejects first push; retry succeeds)
    ├── 07-livelock-retry           (always reject; cap halts at exit 2)
    ├── 08-session-start-auto-pull  (B's session_start fast-forwards to A's commit)
    └── 09-session-start-divergent  (divergent local; session_start defers, no auto-rebase)
```

## API

`protocol.sh` exposes two entry points:

- **`agent_session_start <wiki_dir>`** — read-side freshness. Fetches
  `origin`, fast-forwards local `main` if behind, reports incoming
  commits to stdout. Defers (no auto-rebase) on divergence. Returns 0
  on success, 4 on divergence, 5 on fetch failure.
- **`wiki_push <wiki_dir> <handle> <resolve_fn>`** — write-side
  collision-free push. Optimistic push, on rejection: fetch, merge,
  classify, resolve, retry up to `AGENT_MAX_RETRIES + 1` total attempts.
  Returns 0 on success, 2 at retry cap, 3 on internal bug.

The `resolve_fn` argument is the name of a shell function called once
per semantically-conflicting file with `(wiki_dir, file_path)`. The
function must produce a resolved file with no conflict markers. In
production this is an LLM call; in the scenarios here it is a
deterministic policy per scenario (e.g. scenario 03's resolver appends
agent B's content beneath agent A's under an "Update by agent-B" header).

The union-merge driver for `index_*` and `log_*` files is installed
into the wiki sub-repo at sandbox-creation time (via `.gitattributes`),
so concurrent edits to those files merge mechanically without invoking
the resolver. In production the template's `init-wiki.sh` would write
the same `.gitattributes` during scaffolding.

## Usage

```bash
# Run every scenario.
./run-all.sh

# Run a single scenario.
./scenarios/03-same-section/run.sh

# Keep the sandbox dir after a run (for inspection).
KEEP_SANDBOX=1 ./scenarios/03-same-section/run.sh
```

Exit code = number of failed scenarios. 0 = all green.

## Test-harness integration

The existing template test harness at `scripts/test/` includes an
integration test that drives all nine scenarios:

```
scripts/test/tests/integration/wiki-write-protocol/
├── patch.sh        (no-op; the implementation manages its own sandbox)
└── assertions.sh   (iterates scenarios; one harness assertion each)
```

The harness CI workflow at `.github/workflows/test-harness.yml` runs on
every push to every branch, on both `ubuntu-latest` and `macos-latest`,
so the protocol is structurally validated on both platforms as part of
normal harness CI.

Run the integration category alone:

```bash
MVP_TEMPLATE_LOCAL=$(pwd) ./scripts/test/run.sh --category=integration
```

## What this implementation tests

The mechanics, not the LLM judgement:

- The git-merge layer behaves as the spec assumes.
- Conflicts on `index_<repo>.md` and `log_<repo>.md` union-merge cleanly
  via `.gitattributes` (no resolver invocation).
- Push races are detected and retried (scenario 06 via a pre-receive
  hook simulating concurrent push rejection).
- The retry cap halts cleanly on persistent rejection (scenario 07).
- SessionStart fast-forwards on incoming commits and reports them
  (scenario 08).
- SessionStart defers cleanly on divergence rather than auto-rebasing
  (scenario 09).

## What this implementation does NOT test

- LLM-driven semantic reasoning over a real conflict. Behavioural
  validation requires real LLM agents in the loop, which is part of
  PR7's wiring work (or a follow-up).
- The template's existing scripts and hooks. Those are exercised by the
  rest of the test harness.

## Compatibility

- macOS bash 3.2 and Linux bash 5+ both work (existing harness discipline
  followed: no `mapfile`, careful with empty arrays and `set -u`).
- Requires `git`. Nothing else.
