#!/usr/bin/env python3
"""Mechanically enumerate reciprocity (bidirectional-link) violations in a wiki.

Backs check #7 of /wiki-lint ("if A links to B, B should link back to A unless
one is hub-and-spoke by design") with a deterministic scan, so a lint pass finds
every violation instead of relying on the agent to spot them by eye.

A *link* A -> B is either a frontmatter wikilink `[[B]]` or a body link
`[Display](B)` whose target is an existing content page. A -> B is a *violation*
when B does not reference A back by ANY means (frontmatter or body) — the
"any-means" reciprocity criterion.

Exemptions:
  - Special files (Home, Home_*, index_*, log_*, SCHEMA_*, Edge-Types*) are
    excluded as both source and target — they are navigation/scaffolding, not
    content nodes.
  - Hub-and-spoke: a page with `hub: true` in frontmatter is exempt; a pair is
    skipped when EITHER endpoint is a hub (a hub legitimately lists many children
    without each child linking back, and vice versa).

Stdlib only (no YAML dependency): frontmatter is parsed by regex, matching the
rest of the wiki tooling.

Usage:
    wiki-reciprocity.py <wiki-dir> [--json]

Exit status: 0 if no violations, 1 if any violations, 2 on usage/IO error.
"""
import argparse
import json
import os
import re
import sys

SPECIAL = re.compile(r'^(Home|Home_|index_|log_|SCHEMA_|Edge-Types)')
FM = re.compile(r'^---\n(.*?)\n---\n(.*)$', re.S)
WIKILINK = re.compile(r'\[\[([A-Za-z0-9_ -]+)\]\]')
BODYLINK = re.compile(r'\]\(([A-Za-z0-9_-]+)\)')
HUB = re.compile(r'^\s*hub\s*:\s*true\s*$', re.M | re.I)


def load(wiki_dir):
    pages = {}
    for fn in sorted(os.listdir(wiki_dir)):
        if fn.endswith('.md'):
            with open(os.path.join(wiki_dir, fn), encoding='utf-8') as fh:
                pages[fn[:-3]] = fh.read()
    return pages


def split_frontmatter(text):
    m = FM.match(text)
    return (m.group(1), m.group(2)) if m else ('', text)


def analyze(pages):
    """Return (refs, hubs). refs[A] = set of pages A references by any means."""
    refs = {name: set() for name in pages}
    hubs = set()
    for name, text in pages.items():
        fm, body = split_frontmatter(text)
        if HUB.search(fm):
            hubs.add(name)
        for target in WIKILINK.findall(fm):
            if target in pages:
                refs[name].add(target)
        for target in BODYLINK.findall(body):
            if target in pages:
                refs[name].add(target)
    return refs, hubs


def violations(pages):
    refs, hubs = analyze(pages)
    out = []
    for a in pages:
        if SPECIAL.match(a):
            continue
        for b in sorted(refs[a]):
            if b == a or SPECIAL.match(b):
                continue
            if a in hubs or b in hubs:
                continue
            if a not in refs[b]:
                out.append((a, b))
    return out


def main(argv=None):
    ap = argparse.ArgumentParser(description="Enumerate wiki reciprocity violations.")
    ap.add_argument("wiki_dir", help="path to the wiki sub-repo (wiki/<repo>.wiki/)")
    ap.add_argument("--json", action="store_true", help="emit findings as JSON")
    args = ap.parse_args(argv)

    if not os.path.isdir(args.wiki_dir):
        print(f"error: not a directory: {args.wiki_dir}", file=sys.stderr)
        return 2

    pages = load(args.wiki_dir)
    viols = violations(pages)

    if args.json:
        print(json.dumps({"violations": [{"from": a, "to": b} for a, b in viols],
                          "count": len(viols)}))
    else:
        for a, b in viols:
            print(f"{a} -> {b}   ({b} does not reference {a} back)")
        print(f"\n{len(viols)} reciprocity violation(s) "
              f"across {sum(1 for p in pages if not SPECIAL.match(p))} content pages.",
              file=sys.stderr)
    return 1 if viols else 0


if __name__ == "__main__":
    sys.exit(main())
