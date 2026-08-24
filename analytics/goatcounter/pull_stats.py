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
import time
import urllib.error
import urllib.request
from datetime import datetime, timezone

SITE = "https://liebermandashboards.goatcounter.com"

# GoatCounter tracking on this site started 2026-08-12. The API defaults to
# a 1-week window if no `start` is given, so an explicit start date well
# before tracking began is required to pull the full history every run.
TRACKING_STARTED = "2026-08-01T00:00:00Z"


# Empirically flaky, not a code bug: the exact same request (same token, same
# params) has failed with a bare 404 {"error":"not found"} from GoatCounter's
# own API and then succeeded on an unmodified retry minutes later, more than
# once (see wiki Automation/log for the run history that established this --
# 4 of 6 real attempts between 2026-08-12 and 2026-08-24 failed this way).
# Retry a few times with backoff before giving up, rather than failing the
# whole weekly snapshot on what's usually a transient upstream hiccup.
RETRY_ATTEMPTS = 4
RETRY_BACKOFF_SECONDS = 3


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
    last_error = None
    for attempt in range(1, RETRY_ATTEMPTS + 1):
        try:
            with urllib.request.urlopen(req, timeout=30) as resp:
                return json.loads(resp.read())
        except urllib.error.HTTPError as e:
            body = e.read().decode('utf-8', errors='replace')
            print(f"HTTPError {e.code} for {url} (attempt {attempt}/{RETRY_ATTEMPTS})\n"
                  f"Response headers: {dict(e.headers)}\nBody: {body[:2000]}", file=sys.stderr)
            last_error = e
            if attempt < RETRY_ATTEMPTS:
                time.sleep(RETRY_BACKOFF_SECONDS * attempt)
    raise last_error


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
