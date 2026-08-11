# features/

This directory holds **opt-in feature definitions** for the llm-wiki-memory
template. Each subdirectory `features/<name>/` is a self-contained feature
that derived projects can choose to enable, independently of the base
template.

## Status

Etapa 1 of the feature-flag architecture (RFC #13, PR #17) shipped the
install/uninstall infrastructure and this `features/` directory.

**First real feature**: `agent-comms` (cross-agent `ask` primitive +
federation enrollment). v0.1.0 scope is intentionally narrow — see
[`features/agent-comms/rule.md`](agent-comms/rule.md)
for the user-facing contract and [`features/agent-comms/feature.json`](agent-comms/feature.json)
for the system-deps manifest.

## Structure of a feature

```
features/<name>/
├── feature.json          # metadata (name, files, tests, ci, rule, system_deps, depends_on)
├── rule.md               # agent context, installed as .claude/rules/feature-<name>.md
├── code/                 # files copied into scripts/<name>/ at install time
├── tests/                # files copied into scripts/test/tests/<category>/<name>/
├── fixtures/             # test data referenced by the feature's own tests
└── ci/
    └── test-<name>.yml   # GitHub Actions workflow copied into .github/workflows/
```

## The two entry points

A derived project enables a feature in one of two ways:

```bash
# At instantiation (declarative)
./scripts/instantiate.sh "Project Name" --agent=claude-code --features=<name>

# Retroactively (procedural)
./scripts/enable-feature.sh <name>
```

Both call `install_feature` in `scripts/lib/install-feature.sh`.

Symmetric removal:

```bash
./scripts/disable-feature.sh <name>
```

## Tracking which features are enabled

A derived project records its enabled features in a `.features-enabled`
file at the project root, one feature name per line. The format is plain
text for now; future metadata (install date, version pinning) can be added
without breaking compatibility.

## Adding a new feature

Drop a new directory under `features/`, write a `feature.json`, and the
existing `install_feature` machinery handles the rest. No changes to
`instantiate.sh` or the install logic are needed per feature.

The canonical guide is [`../docs/adding-a-feature.md`](../docs/adding-a-feature.md):
schema reference, lifecycle, hello-world walkthrough, pitfalls.

## Still out of scope (post-Etapa 1)

- `update-from-template.sh` feature-awareness (Etapa 3)
- `migrate-to-feature-flags.sh` for legacy derived projects (Etapa 4)
- `depends_on` enforcement (declared in `feature.json` but ignored by
  the install logic)
