# Test Feature (fixture)

This rule file is installed to `.claude/rules/feature-test-feature.md`
by install_feature and removed by uninstall_feature. It exists only to
exercise the rule-file install logic.

- Install entry point: `./scripts/enable-feature.sh test-feature`
- Removal: `./scripts/disable-feature.sh test-feature`
