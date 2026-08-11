#!/usr/bin/env bash
#
# install-feature.sh — Shared feature install/uninstall logic for the
# llm-wiki-memory-template feature-flag architecture (RFC #13, Etapa 1).
#
# This file is sourced by:
#   scripts/instantiate.sh      (the declarative entry point: --features=)
#   scripts/enable-feature.sh   (the retroactive entry point)
#   scripts/disable-feature.sh  (the symmetric removal)
#
# Do not invoke this file directly. It defines two functions:
#
#   install_feature <name>     install the named feature into the current
#                              project root (idempotent)
#   uninstall_feature <name>   symmetric removal (idempotent)
#
# Both functions expect the current working directory to be a derived
# project root (containing scripts/ and either an existing features/
# directory or a path provided via the FEATURES_DIR env var).
#
# The FEATURES_DIR override exists for tests, where the fixture lives
# outside the conventional features/ tree. In production install_feature
# defaults to ./features/ relative to the caller's cwd.
#
# A feature's agent context ships as a rule FILE, not a CLAUDE.md patch:
# rule.source (conventionally rule.md) is copied to
# .claude/rules/feature-<name>.md, and uninstall deletes that file. The
# host's CLAUDE.md is never touched -- it is host-owned, like everywhere
# else in the template. The feature- filename prefix marks provenance and
# keeps feature rules from colliding with the template's own rules.
# The rule step is gated on a .claude/ directory existing: a project
# instantiated with --agent=none (or one whose agent does not read
# .claude/rules/) opted out of Claude Code config, so the step skips
# loudly instead of creating .claude/ behind the user's back.
#
# Requires: bash 3.2+, jq.
# Bash 3.2 compatibility means no mapfile and no associative arrays;
# arrays are explicitly initialised before any expansion under `set -u`.

# --- Internal helpers ------------------------------------------------------

_feature_require_cmd() {
    if ! command -v "$1" >/dev/null 2>&1; then
        echo "Error: '$1' is required but not on PATH (used by install_feature)." >&2
        return 1
    fi
}

_feature_features_dir() {
    if [[ -n "${FEATURES_DIR:-}" ]]; then
        echo "$FEATURES_DIR"
    else
        echo "./features"
    fi
}

_feature_list_available() {
    local features_dir; features_dir=$(_feature_features_dir)
    local d
    if [[ ! -d "$features_dir" ]]; then
        return 0
    fi
    for d in "$features_dir"/*/; do
        [[ -d "$d" ]] || continue
        [[ -f "$d/feature.json" ]] || continue
        echo "  $(basename "$d")"
    done
}

_feature_is_enabled() {
    local name="$1"
    [[ -f ".features-enabled" ]] && grep -qFx "$name" .features-enabled 2>/dev/null
}

# --- Public: install_feature -----------------------------------------------

install_feature() {
    local name="${1:-}"
    if [[ -z "$name" ]]; then
        echo "Error: install_feature requires a feature name." >&2
        return 1
    fi

    local features_dir feature_dir feature_json
    features_dir=$(_feature_features_dir)
    feature_dir="$features_dir/$name"
    feature_json="$feature_dir/feature.json"

    # Validate the feature exists
    if [[ ! -d "$feature_dir" ]]; then
        echo "Error: feature '$name' not found in $features_dir/." >&2
        echo "Available features:" >&2
        _feature_list_available >&2
        return 1
    fi
    if [[ ! -f "$feature_json" ]]; then
        echo "Error: feature '$name' is missing feature.json at $feature_json." >&2
        return 1
    fi

    _feature_require_cmd jq || return 1

    # Idempotency: if already in .features-enabled, no-op success
    if _feature_is_enabled "$name"; then
        echo "Feature '$name' already enabled; skipping."
        return 0
    fi

    echo "Installing feature '$name' from $feature_dir/ ..."

    # Step 1: copy code files (files.source -> files.destination)
    local files_src files_dst
    files_src=$(jq -r '.files.source // empty' "$feature_json")
    files_dst=$(jq -r '.files.destination // empty' "$feature_json")
    if [[ -n "$files_src" && -n "$files_dst" ]]; then
        local src_path="$feature_dir/$files_src"
        if [[ ! -d "$src_path" ]]; then
            echo "Error: files.source '$files_src' does not exist in $feature_dir." >&2
            return 1
        fi
        if [[ -e "$files_dst" ]]; then
            echo "Error: destination '$files_dst' already exists." >&2
            echo "       Refusing to overwrite. Resolve the conflict and re-run." >&2
            return 1
        fi
        mkdir -p "$(dirname "$files_dst")"
        cp -R "$src_path" "$files_dst"
        echo "  + copied $files_src/* -> $files_dst/"
    fi

    # Step 2: copy tests (tests.source -> tests.destination), if declared
    local tests_src tests_dst
    tests_src=$(jq -r '.tests.source // empty' "$feature_json")
    tests_dst=$(jq -r '.tests.destination // empty' "$feature_json")
    if [[ -n "$tests_src" && -n "$tests_dst" ]]; then
        local tests_src_path="$feature_dir/$tests_src"
        if [[ -d "$tests_src_path" ]]; then
            if [[ -e "$tests_dst" ]]; then
                echo "Error: tests destination '$tests_dst' already exists." >&2
                return 1
            fi
            mkdir -p "$(dirname "$tests_dst")"
            cp -R "$tests_src_path" "$tests_dst"
            echo "  + copied tests -> $tests_dst/"
        fi
    fi

    # Step 3: copy CI workflow file, if declared
    local ci_wf
    ci_wf=$(jq -r '.ci.workflow_file // empty' "$feature_json")
    if [[ -n "$ci_wf" ]]; then
        local ci_src="$feature_dir/$ci_wf"
        if [[ -f "$ci_src" ]]; then
            local ci_dst=".github/workflows/$(basename "$ci_wf")"
            if [[ -e "$ci_dst" ]]; then
                echo "Error: CI workflow destination '$ci_dst' already exists." >&2
                echo "       Refusing to overwrite. Resolve the conflict and re-run." >&2
                return 1
            fi
            mkdir -p .github/workflows
            cp "$ci_src" "$ci_dst"
            echo "  + copied CI workflow -> $ci_dst"
        fi
    fi

    # Step 4: install the feature's rule file at .claude/rules/feature-<name>.md
    local rule_src
    rule_src=$(jq -r '.rule.source // empty' "$feature_json")
    if [[ -n "$rule_src" ]]; then
        local rule_src_path="$feature_dir/$rule_src"
        local rule_dst=".claude/rules/feature-$name.md"
        if [[ ! -f "$rule_src_path" ]]; then
            echo "Error: rule.source '$rule_src' does not exist in $feature_dir." >&2
            return 1
        fi
        if [[ ! -d ".claude" ]]; then
            # No .claude/ means the project opted out of Claude Code config
            # (e.g. --agent=none). Skip loudly instead of silently: the
            # feature's usage notes are otherwise lost.
            echo "  = no .claude/ directory; skipped installing the rule file."
            echo "    (Usage notes live at $rule_src_path; add them to your own"
            echo "     agent configuration if you want them in context.)"
        elif [[ -e "$rule_dst" ]]; then
            echo "  = $rule_dst already present; leaving it in place."
        else
            mkdir -p .claude/rules
            cp "$rule_src_path" "$rule_dst"
            echo "  + installed $rule_dst"
        fi
    fi

    # Step 5: record in .features-enabled (plain text, one name per line)
    echo "$name" >> .features-enabled
    echo "  + recorded '$name' in .features-enabled"

    # Step 6: print system_deps install instructions (declarative, never auto-run)
    local n_deps
    n_deps=$(jq -r '.system_deps | length' "$feature_json" 2>/dev/null || echo 0)
    if [[ "$n_deps" -gt 0 ]]; then
        echo ""
        echo "System dependencies required for feature '$name':"
        local i=0
        while [[ "$i" -lt "$n_deps" ]]; do
            local dep_name dep_ver dep_inst_ubuntu dep_inst_macos dep_inst_manual
            dep_name=$(jq -r ".system_deps[$i].name // \"\"" "$feature_json")
            dep_ver=$(jq -r ".system_deps[$i].version // \"\"" "$feature_json")
            dep_inst_ubuntu=$(jq -r ".system_deps[$i].install.ubuntu // \"\"" "$feature_json")
            dep_inst_macos=$(jq -r ".system_deps[$i].install.macos // \"\"" "$feature_json")
            dep_inst_manual=$(jq -r ".system_deps[$i].install.manual // \"\"" "$feature_json")
            echo "  - $dep_name${dep_ver:+ ($dep_ver)}"
            [[ -n "$dep_inst_ubuntu" ]] && echo "      Ubuntu/Debian: $dep_inst_ubuntu"
            [[ -n "$dep_inst_macos" ]]  && echo "      macOS:         $dep_inst_macos"
            [[ -n "$dep_inst_manual" ]] && echo "      Manual:        $dep_inst_manual"
            i=$((i + 1))
        done
        echo ""
        echo "Note: install_feature does NOT run these commands."
        echo "      Install dependencies yourself before using the feature."
    fi

    echo ""
    echo "Feature '$name' installed."
    return 0
}

# --- Public: uninstall_feature ---------------------------------------------

uninstall_feature() {
    local name="${1:-}"
    if [[ -z "$name" ]]; then
        echo "Error: uninstall_feature requires a feature name." >&2
        return 1
    fi

    if ! _feature_is_enabled "$name"; then
        echo "Feature '$name' is not enabled; nothing to remove."
        return 0
    fi

    local features_dir feature_dir feature_json
    features_dir=$(_feature_features_dir)
    feature_dir="$features_dir/$name"
    feature_json="$feature_dir/feature.json"

    echo "Uninstalling feature '$name' ..."

    # If feature.json is missing, do minimal cleanup: the rule file and the
    # .features-enabled entry are both derivable from the name alone. The
    # user's deployment may have lost the feature definition; we still
    # honour the request to remove what we can identify.
    if [[ ! -f "$feature_json" ]]; then
        echo "Warning: feature.json missing at $feature_json." >&2
        echo "         Removing the rule file and the .features-enabled entry only;" >&2
        echo "         manual cleanup of other installed files may be needed." >&2
    else
        _feature_require_cmd jq || return 1

        # Step 1: remove files destination
        local files_dst
        files_dst=$(jq -r '.files.destination // empty' "$feature_json")
        if [[ -n "$files_dst" && -e "$files_dst" ]]; then
            rm -rf "$files_dst"
            echo "  - removed $files_dst"
        fi

        # Step 2: remove tests destination
        local tests_dst
        tests_dst=$(jq -r '.tests.destination // empty' "$feature_json")
        if [[ -n "$tests_dst" && -e "$tests_dst" ]]; then
            rm -rf "$tests_dst"
            echo "  - removed $tests_dst"
        fi

        # Step 3: remove CI workflow file
        local ci_wf
        ci_wf=$(jq -r '.ci.workflow_file // empty' "$feature_json")
        if [[ -n "$ci_wf" ]]; then
            local ci_dst=".github/workflows/$(basename "$ci_wf")"
            if [[ -f "$ci_dst" ]]; then
                rm -f "$ci_dst"
                echo "  - removed $ci_dst"
            fi
        fi

    fi

    # Step 4: remove the feature's rule file. Runs even when feature.json is
    # missing: the destination derives from the name alone.
    local rule_dst=".claude/rules/feature-$name.md"
    if [[ -f "$rule_dst" ]]; then
        rm -f "$rule_dst"
        echo "  - removed $rule_dst"
        # Drop the rules directory again if this feature's rule was the
        # only thing in it (rmdir refuses non-empty; .claude/ itself
        # predates the install, so it stays).
        rmdir .claude/rules 2>/dev/null || true
    fi

    # Step 5: remove from .features-enabled
    if [[ -f ".features-enabled" ]]; then
        local tmp
        tmp=$(mktemp)
        grep -vFx "$name" .features-enabled > "$tmp" 2>/dev/null || true
        if [[ -s "$tmp" ]]; then
            mv "$tmp" .features-enabled
        else
            rm -f "$tmp" .features-enabled
        fi
        echo "  - removed '$name' from .features-enabled"
    fi

    echo ""
    echo "Feature '$name' uninstalled."
    return 0
}
