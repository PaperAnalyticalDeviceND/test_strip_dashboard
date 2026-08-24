#!/usr/bin/env python3
"""Build the (unlinked) usage-stats page from a GoatCounter snapshot.

Usage:
    python3 build_stats.py <snapshot.json> <templates/stats_template.html> <output.html>

Network-free, like the other build_*.py scripts -- the snapshot is pulled
separately by analytics/goatcounter/pull_stats.py. Reuses common.py's
embed_json_in_script() for the same HTML/script-injection safety the
dashboard builds already rely on, even though this payload is our own
GoatCounter data, not attacker-controlled sheet data.
"""
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from common import embed_json_in_script


def main():
    if len(sys.argv) != 4:
        print(__doc__)
        sys.exit(1)
    snapshot_path, template_path, out_path = sys.argv[1:4]

    with open(snapshot_path, encoding='utf-8') as f:
        snapshot = json.load(f)

    template_html = open(template_path, encoding='utf-8').read()
    payload = embed_json_in_script(snapshot)
    html = template_html.replace('__STATS_DATA__', payload, 1)

    with open(out_path, 'w', encoding='utf-8') as f:
        f.write(html)
    print(f'wrote {out_path} ({len(html)} bytes)')


if __name__ == '__main__':
    main()
