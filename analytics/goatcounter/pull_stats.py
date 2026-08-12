#!/usr/bin/env python3
"""Pull current GoatCounter stats for the Lieberman Lab test-strip dashboards
and write a snapshot to analytics/goatcounter/snapshot.json.

Usage:
    GOATCOUNTER_API_TOKEN=... python3 pull_stats.py [out_path]

No third-party dependencies (stdlib urllib only), matching the rest of this
project's build tooling. The snapshot file is overwritten each run; git
history on that one file is the historical record, not a hand-maintained
running log, matching the "recompute from source, never trust a cache"
convention the dashboard builds already follow.
"""
import json
import os
import sys
import urllib.error
import urllib.request
from datetime import datetime, timezone

SITE = "https://liebermandashboards.goatcounter.com"

# GoatCounter tracking on this site started 2026-08-12. The API defaults to
# a 1-week window if no `start` is given, so an explicit start date well
# before tracking began is required to pull the full history every run.
TRACKING_STARTED = "2026-08-01T00:00:00Z"


def api_get(token, path, params=None):
    url = f"{SITE}/api/v0{path}"
    if params:
        query = "&".join(f"{k}={v}" for k, v in params.items())
        url = f"{url}?{query}"
    req = urllib.request.Request(url, headers={
        "Authorization": f"Bearer {token}",
        "Content-Type": "application/json",
        "User-Agent": "test_strip_dashboard-goatcounter-snapshot/1.0",
    })
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            return json.loads(resp.read())
    except urllib.error.HTTPError as e:
        body = e.read().decode('utf-8', errors='replace')
        print(f"HTTPError {e.code} for {url}\nResponse headers: {dict(e.headers)}\nBody: {body[:2000]}",
              file=sys.stderr)
        raise


def main():
    token = os.environ.get("GOATCOUNTER_API_TOKEN")
    if not token:
        print("GOATCOUNTER_API_TOKEN not set", file=sys.stderr)
        sys.exit(1)

    out_path = sys.argv[1] if len(sys.argv) > 1 else "analytics/goatcounter/snapshot.json"

    start = TRACKING_STARTED
    end = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

    total = api_get(token, "/stats/total", {"start": start, "end": end})
    hits = api_get(token, "/stats/hits", {"start": start, "end": end, "limit": 100})

    snapshot = {
        "pulled_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "period_start": start,
        "period_end": end,
        "total_pageviews": total.get("total"),
        "total_events": total.get("total_events"),
        "pages": [
            {
                "path": h["path"],
                "title": h.get("title"),
                "is_event": h.get("event", False),
                "count": h["count"],
            }
            for h in hits.get("hits", [])
        ],
        "more_pages_not_shown": hits.get("more", False),
    }

    os.makedirs(os.path.dirname(out_path) or ".", exist_ok=True)
    with open(out_path, "w") as f:
        json.dump(snapshot, f, indent=2)
        f.write("\n")

    print(f"wrote {out_path}: {snapshot['total_pageviews']} total pageviews, "
          f"{len(snapshot['pages'])} paths/events")


if __name__ == "__main__":
    main()
