#!/usr/bin/env python3
"""Build the hub landing page from already-built FTS/XTS dashboards.

Usage:
    python3 build_hub.py <fts.html> <xts.html> <hub_template.html> <output.html>

Reads each dashboard's embedded `const DATA = {...}` blob (the same JSON
build_fts.py/build_xts.py inject into their own templates) to pull live
overall stats, so the hub's target cards never drift from what the
dashboards themselves say. Everything else on the hub is static content
from the template.
"""
import json
import re
import sys


def extract_overall(dashboard_html_path):
    html = open(dashboard_html_path, encoding='utf-8').read()
    m = re.search(r'const DATA = (.*?);\n', html)
    if not m:
        raise RuntimeError(f'could not find `const DATA = ...;` in {dashboard_html_path}')
    return json.loads(m.group(1))['overall']


def main():
    if len(sys.argv) != 5:
        print(__doc__)
        sys.exit(1)
    fts_path, xts_path, template_path, out_path = sys.argv[1:5]

    fts = extract_overall(fts_path)
    xts = extract_overall(xts_path)

    html = open(template_path, encoding='utf-8').read()
    replacements = {
        '__FTS_LOTS__': str(fts['n_lots']),
        '__FTS_SUBS__': str(fts['n_submissions']),
        '__FTS_RATE__': f"{fts['pooled_fen_rate']:.1f}",
        '__XTS_LOTS__': str(xts['n_lots']),
        '__XTS_SUBS__': str(xts['n_submissions']),
        '__XTS_DI_RATE__': f"{xts['pooled_2500_di_rate']:.1f}",
        '__XTS_TAP_RATE__': f"{xts['pooled_2500_tap_rate']:.1f}",
    }
    missing = [k for k in replacements if k not in html]
    if missing:
        raise RuntimeError(f'template is missing placeholder(s): {missing}')

    for placeholder, value in replacements.items():
        html = html.replace(placeholder, value)

    with open(out_path, 'w', encoding='utf-8') as f:
        f.write(html)
    print(f'wrote {out_path} ({len(html)} bytes)')
    print(f"FTS: {fts['n_lots']} lots, {fts['n_submissions']} submissions, {fts['pooled_fen_rate']:.1f}% pooled")
    print(f"XTS: {xts['n_lots']} lots, {xts['n_submissions']} submissions, DI {xts['pooled_2500_di_rate']:.1f}% / tap {xts['pooled_2500_tap_rate']:.1f}%")


if __name__ == '__main__':
    main()
