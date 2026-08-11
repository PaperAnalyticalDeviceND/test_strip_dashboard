# Test Harness for llm-wiki-memory-template

Structural CI for the template. Clones the template, runs `instantiate.sh`,
and asserts the bootstrap produces the right files. Runs on every push and
PR via `.github/workflows/test-harness.yml`, matrixed across `ubuntu-latest`
and `macos-latest`. Addresses template issue #5.

## What it tests

Currently one category. The harness auto-discovers any new categories under
`tests/<category>/`; the canonical order is `smoke`, `unit`, `integration`,
`e2e`, `regression`, then anything else alphabetically.

### Smoke (real template, fast structural checks)

| Test | Assertions | What it checks |
|---|---|---|
| `template-bootstrap` | 14 | Clones the real template, runs `instantiate.sh`, asserts: bash syntax of all shipping scripts, no CLAUDE.md is created (host-owned), wiki sub-repo created, namespaced nav files present, `init-wiki.sh` is idempotent |
| `instantiate-agent-none` | 8 | Regression for issue #9: runs `instantiate.sh --agent=none`, asserts bootstrap completes, no CLAUDE.md is created, `init-wiki.sh` runs, and no `.claude/` or `.cursor/` overlay is copied |

## Usage

```bash
# Run all categories
./scripts/test/run.sh

# Filter by category
./scripts/test/run.sh --category=smoke
./scripts/test/run.sh --category smoke

# Filter by test name
./scripts/test/run.sh template-bootstrap

# Keep the sandbox dir after the run (for inspection)
./scripts/test/run.sh --no-cleanup
```

Exit code = number of failed assertions. 0 = all green.

### Python dependencies

The `kg-frontmatter-graph` unit test asserts that `python3` can import `yaml`, `rdflib`, and `pyshacl`; missing modules are failures, not skips.
CI installs them into a venv (see `.github/workflows/test-harness.yml`).
Locally, either install them the same way or supply them ephemerally with uv:

```bash
uv run --no-project --with pyyaml --with rdflib --with pyshacl -- ./scripts/test/run.sh
```

## Template source

Smoke tests need a real template clone. Resolution order:

```bash
# Default: no env vars needed. run.sh exports THIS working tree's
# git-visible files (tracked + untracked-unignored) into the sandbox and
# tests those — your edits, not the published template. Gitignored
# artifacts (dev-self settings.json and hooks, wiki/<template>.wiki/, kg caches) are
# excluded from the export.
./scripts/test/run.sh

# Explicit local clone (overrides the default; what CI uses)
export MVP_TEMPLATE_LOCAL=/path/to/llm-wiki-memory-template
./scripts/test/run.sh

# Network mode with a specific fork / URL (overrides the default)
export MVP_TEMPLATE_REPO=https://github.com/your-fork/llm-wiki-memory-template.git
./scripts/test/run.sh
```

The default only applies when neither variable is set AND run.sh sits
inside a git repository; otherwise it falls back to network-cloning the
canonical template, and if that is unreachable too, smoke tests `skip`
gracefully.

Note the network fallback tests the *published* template, not your local
changes — fine for a derived project's CI, wrong for template development.

Do not point `MVP_TEMPLATE_LOCAL` at a working tree that contains gitignored artifacts (a dogfooded `wiki/<template>.wiki/`, kg build caches, a dev-self CLAUDE.md).
That path copies the directory verbatim with `cp -R`, so those artifacts land in the sandbox and break the bootstrap assertions, most visibly as an `init-wiki.sh` "multiple wikis ... name is ambiguous" error.
For template development, prefer the no-env-var default, which exports git-visible files only.
`MVP_TEMPLATE_LOCAL` is intended for clean checkouts, which is how CI uses it.

## Running the CI workflow locally with act

[act](https://github.com/nektos/act) can run the `test` job from `.github/workflows/test-harness.yml` in a container:

```bash
act -j test --matrix os:ubuntu-latest --rm
```

- Keep act's default copy mode; never pass `-b`/`--bind`.
  Bind mode mounts your real working tree, which breaks twice over: workflow writes land on your host (root-owned `scripts/kg/build/` and `scripts/kg/.cache/` under rootful Docker, since the kg pipeline writes into the repo rather than the sandbox), and the workflow's `MVP_TEMPLATE_LOCAL=$GITHUB_WORKSPACE` picks up your gitignored artifacts (see the warning above).
  Copy mode respects `.gitignore` (`--use-gitignore` defaults to true), so the container sees the equivalent of a clean checkout and all writes stay inside it.
- `--matrix os:ubuntu-latest` skips the `macos-latest` leg, which act cannot run.
- `--rm` removes the container even when the job fails, so failed runs do not accumulate containers.

## Structure

```
scripts/test/
├── README.md           # this file
├── run.sh              # main entry point (categories, filtering, reporting)
├── lib/
│   ├── assert.sh       # assertion helpers (assert, assert_contains, assert_eq, assert_ne, skip)
│   ├── sandbox.sh      # sandbox lifecycle (mktemp + cleanup)
│   └── template.sh     # clone_template (offline or network)
└── tests/
    └── smoke/
        └── template-bootstrap/
            ├── patch.sh       # clones template, runs instantiate.sh
            └── assertions.sh  # syntax + bootstrap-output assertions
```

## Adding a test

1. Pick a category: `smoke` (fast/structural), `unit` (single-script), `integration` (multi-script), `e2e` (full sandbox), `regression` (test for a fixed bug).
2. `mkdir -p tests/<category>/<test-name>`
3. Write `patch.sh`: applies setup to the sandbox. Should be idempotent. Source `lib/template.sh` etc. if you need helpers (run.sh runs each `patch.sh` in a subshell).
4. Write `assertions.sh`: uses `assert` / `assert_contains` / `assert_eq` / `assert_ne` / `skip` helpers. Sourced by run.sh (so shares PASS/FAIL/FAILED_TESTS globals).
5. The harness auto-discovers by directory.

## CI

`.github/workflows/test-harness.yml` runs the harness on every push and pull
request, matrixed across `ubuntu-latest` and `macos-latest`. macOS in the
matrix is important: bash 3.2 (the macOS default) accepts and rejects
syntax differently from bash 5+, and macOS-specific path-canonicalization
behavior surfaces here.

## Design notes

- **Bash 3.2 compatible**: macOS default bash. No `mapfile`, careful with `set -u` and empty arrays.
- **Sandboxed**: each run uses a `mktemp -d` sandbox; cleaned up on exit unless `--no-cleanup` is passed.
- **Adding a test is one directory**: no harness changes needed.
- **What can't be tested here**: live Claude Code session behavior (whether an agent actually invokes hooks at the right moment). That requires an LLM in the loop, out of scope for structural CI.
