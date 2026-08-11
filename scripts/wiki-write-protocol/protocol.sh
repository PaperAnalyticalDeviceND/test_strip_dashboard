#!/usr/bin/env bash
# Multi-agent wiki write protocol: deterministic shell implementation.
#
# Push-time-only design (the "transparent wrapper" approach): agents work
# directly on the current branch of the wiki sub-repo (typically `main`
# or `master`; auto-detected via git symbolic-ref). The wiki_push wrapper
# attempts an optimistic push, and on rejection fetches, merges,
# classifies conflicts (union for index_*/log_*, semantic for everything
# else), commits the merge, and retries. No working branches.
#
# Two entry points:
#
#   agent_session_start <wiki_dir>            (read-side freshness)
#       Fetches origin and pulls --ff-only into the current local branch.
#       Reports any incoming commits to stdout (Claude Code would surface
#       these as a system reminder). On non-fast-forward (someone
#       force-pushed or there is unmerged local work), defers cleanly
#       without auto-rebasing; returns non-zero so the agent knows.
#
#   wiki_push <wiki_dir> <handle> <resolve_fn>   (write-side collision-free)
#       Tries `git push origin <branch>` optimistically. On rejection,
#       fetches, merges, resolves conflicts (mechanical for index/log;
#       via resolve_fn for everything else), and retries up to
#       AGENT_MAX_RETRIES+1 total attempts. Returns 0 on success, 2 on
#       retry cap, 3 on internal bug, 4 when a semantic resolve was
#       deferred/failed (merge left conflicted for the agent; #94).
#
# The "semantic resolution" step is parameterized: callers pass a function
# name that takes (wiki_dir, file_path) and produces a resolved file with
# no conflict markers. Production replaces this with an LLM call; tests
# replace it with deterministic policies.

# Default retry cap. AGENT_MAX_RETRIES is the number of *retries* allowed
# after the first attempt; total attempts = AGENT_MAX_RETRIES + 1.
AGENT_MAX_RETRIES="${AGENT_MAX_RETRIES:-3}"

# Set up the union-merge driver for index_* and log_* files. Call once
# per wiki clone. Without this, the agent will mis-classify index/log
# additions as semantic conflicts.
protocol_install_union_merge() {
    local wiki_dir="$1"
    local attrs="$wiki_dir/.gitattributes"
    if ! grep -qE '^(index|log)_.*merge=union' "$attrs" 2>/dev/null; then
        cat >> "$attrs" <<'EOF'
index_*.md  merge=union
log_*.md    merge=union
EOF
        git -C "$wiki_dir" add .gitattributes
        git -C "$wiki_dir" commit -m "Configure union merge for index/log files" --quiet
    fi
}

# Classify a conflict file. Echoes one of: union, semantic.
#  - union: index_*.md or log_*.md. The .gitattributes union driver
#    should have handled these during git merge already; if we hit one
#    here it means the driver wasn't installed before the conflict
#    happened. Apply a fall-back union merge.
#  - semantic: anything else. Delegated to the caller's resolve_fn.
protocol_classify_conflict() {
    local file="$1"
    case "$(basename "$file")" in
        index_*.md|log_*.md) echo "union" ;;
        *) echo "semantic" ;;
    esac
}

# List files with merge conflicts, one per line.
protocol_conflict_files() {
    local wiki_dir="$1"
    git -C "$wiki_dir" diff --name-only --diff-filter=U
}

# Fallback union merge: strip the conflict markers from a file, keeping
# both sides' content interleaved. Used when the .gitattributes union
# driver did not apply.
protocol_apply_union_merge() {
    local file="$1"
    sed -E -i.bak '/^(<<<<<<< |=======|>>>>>>> )/d' "$file"
    rm -f "$file.bak"
}

# SessionStart: fetch origin, pull --ff-only if behind, report incoming.
# Returns:
#   0  on success (fast-forwarded, or already up-to-date)
#   4  on non-fast-forward (deferred; local branch has un-pushed work or
#      origin force-pushed; the agent should look at it)
#   5  on network / fetch failure OR detached HEAD (no branch to track)
agent_session_start() {
    local wiki_dir="$1"
    local branch
    branch="$(git -C "$wiki_dir" symbolic-ref --short HEAD 2>/dev/null)"
    if [ -z "$branch" ]; then
        echo "  [session_start] HEAD is detached; cannot determine branch to track" >&2
        return 5
    fi
    if ! git -C "$wiki_dir" fetch origin --quiet 2>/dev/null; then
        echo "  [session_start] fetch failed; offline?" >&2
        return 5
    fi
    local local_sha origin_sha base
    local_sha="$(git -C "$wiki_dir" rev-parse HEAD)"
    origin_sha="$(git -C "$wiki_dir" rev-parse "origin/$branch")"
    if [ "$local_sha" = "$origin_sha" ]; then
        echo "  [session_start] up to date"
        return 0
    fi
    base="$(git -C "$wiki_dir" merge-base "$local_sha" "$origin_sha")"
    if [ "$base" = "$local_sha" ]; then
        # Local is behind origin (origin moved forward). Fast-forward.
        local count
        count="$(git -C "$wiki_dir" rev-list --count "$local_sha..$origin_sha")"
        git -C "$wiki_dir" merge --ff-only "origin/$branch" --quiet
        echo "  [session_start] pulled $count incoming commit(s) from origin/$branch"
        # Also surface what changed so the agent's read context is informed.
        git -C "$wiki_dir" log --format='    %h %an: %s' "$local_sha..$origin_sha"
        return 0
    fi
    if [ "$base" = "$origin_sha" ]; then
        echo "  [session_start] local $branch is ahead of origin (un-pushed work); no pull needed" >&2
        return 0
    fi
    # Diverged: both sides have commits the other doesn't have.
    echo "  [session_start] DIVERGED: local $branch and origin/$branch have diverged; not auto-rebasing" >&2
    echo "  [session_start] inspect with: git -C $wiki_dir log --oneline --graph --all" >&2
    return 4
}

# wiki_push: push-time-only protocol. Tries to push the local branch
# (auto-detected via git symbolic-ref --short HEAD); on rejection,
# integrates origin/<branch> and retries with a semantic-or-union
# resolver for any conflicts.
#
# Args: wiki_dir, handle, resolve_fn.
#  - resolve_fn is a shell function name called with (wiki_dir, file)
#    for each semantically-conflicting file. Must produce a resolved
#    file with no conflict markers. The caller is responsible for the
#    function's policy (LLM-based in production; deterministic in tests).
#
# Returns: 0 on success, 2 on retry cap, 3 on internal bug, 4 when a
# semantic resolve was deferred/failed (merge left conflicted; see #94).
wiki_push() {
    local wiki_dir="$1"
    local handle="$2"
    local resolve_fn="$3"

    local branch
    branch="$(git -C "$wiki_dir" symbolic-ref --short HEAD 2>/dev/null)"
    if [ -z "$branch" ]; then
        echo "  [$handle] HEAD is detached; cannot determine branch to push" >&2
        return 3
    fi

    protocol_install_union_merge "$wiki_dir"

    local attempt=0
    local max_attempts=$((AGENT_MAX_RETRIES + 1))
    while true; do
        attempt=$((attempt + 1))
        if [ "$attempt" -gt "$max_attempts" ]; then
            echo "  [$handle] hit retry cap (max attempts $max_attempts); halting" >&2
            return 2
        fi

        # Try the optimistic push first. If accepted, done.
        if git -C "$wiki_dir" push origin "$branch" --quiet 2>/dev/null; then
            echo "  [$handle] pushed on attempt $attempt"
            return 0
        fi

        # Push was rejected. Fetch and integrate origin/<branch>.
        if ! git -C "$wiki_dir" fetch origin --quiet 2>/dev/null; then
            echo "  [$handle] fetch failed after push rejection; aborting" >&2
            return 3
        fi

        # Attempt to merge origin/<branch> into local <branch>.
        if git -C "$wiki_dir" merge --no-commit --no-ff "origin/$branch" --quiet 2>/dev/null; then
            # Merge applied cleanly (no conflicts). Commit and loop to retry push.
            git -C "$wiki_dir" commit -m "Merge origin/$branch" --quiet
            echo "  [$handle] clean merge on attempt $attempt; retrying push" >&2
            continue
        fi

        # Conflict. Classify and resolve.
        local conflicted
        conflicted="$(protocol_conflict_files "$wiki_dir")"
        if [ -z "$conflicted" ]; then
            echo "  [$handle] merge of origin/$branch into $branch failed without producing conflicts." >&2
            echo "  [$handle] This usually means origin/$branch does not exist (was the branch renamed or deleted?). Aborting." >&2
            git -C "$wiki_dir" merge --abort 2>/dev/null
            return 3
        fi

        local unresolved=""
        while IFS= read -r file; do
            [ -z "$file" ] && continue
            local class
            class="$(protocol_classify_conflict "$file")"
            case "$class" in
                union)
                    protocol_apply_union_merge "$wiki_dir/$file"
                    git -C "$wiki_dir" add "$file"
                    echo "  [$handle]   union-merged $file"
                    ;;
                semantic)
                    # A resolver that returns non-zero is DEFERRING (the
                    # documented production llm_resolve does exactly this);
                    # and a resolver that returns 0 but leaves markers has
                    # failed whether it knows it or not. Either way this
                    # file must never be staged — publishing conflict
                    # markers to the shared wiki is the #94 field bug.
                    if ! "$resolve_fn" "$wiki_dir" "$file"; then
                        echo "  [$handle]   semantic resolve deferred/failed: $file" >&2
                        unresolved="${unresolved}${file}"$'\n'
                        continue
                    fi
                    if [ -f "$wiki_dir/$file" ] \
                       && grep -qE '^(<<<<<<< |=======$|>>>>>>> )' "$wiki_dir/$file"; then
                        echo "  [$handle]   resolver left conflict markers in $file; treating as failed" >&2
                        unresolved="${unresolved}${file}"$'\n'
                        continue
                    fi
                    if [ ! -f "$wiki_dir/$file" ]; then
                        git -C "$wiki_dir" rm -f "$file" --quiet
                    else
                        git -C "$wiki_dir" add "$file"
                    fi
                    echo "  [$handle]   semantic-resolved $file"
                    ;;
            esac
        done <<< "$conflicted"

        if [ -n "$unresolved" ]; then
            # Honor the documented contract (wiki-write-protocol.md): the
            # merge stays in its conflicted state, the listed files keep
            # their markers on disk, and the agent's next turn resolves
            # them in context, commits, and re-runs wiki_push. Do NOT
            # commit, do NOT push.
            echo "  [$handle] semantic resolution incomplete; leaving the merge conflicted for the agent:" >&2
            printf '%s' "$unresolved" | while IFS= read -r _f; do
                [ -n "$_f" ] && echo "  [$handle]     $_f" >&2
            done
            echo "  [$handle] resolve the file(s) in place, 'git add' them, 'git commit', then re-run wiki_push." >&2
            return 4
        fi

        git -C "$wiki_dir" commit -m "Resolve merge with origin/$branch" --quiet
        echo "  [$handle] resolved merge on attempt $attempt; retrying push" >&2
        # Loop to retry push.
    done
}
