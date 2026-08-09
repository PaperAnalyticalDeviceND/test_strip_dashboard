# Proposal: pivot the weekly update to GitHub Actions + GitHub Pages

**Author:** Chris Sweet (via Claude), 2026-08-09
**Branch:** `proposal/github-actions-weekly`
**Status:** proposal — not merged, not enabled

## Why change

The current weekly update runs on **Marya's Mac** via `launchd` +
`claude -p` headless, using an OAuth'd Google Drive MCP connector local
to that machine. Two real problems with that:

1. **Reliability:** the update fires only when Marya's laptop is awake,
   plugged in, and connected. If she travels, closes the lid at 8 PM
   Friday, or her Mac is asleep, the week's rebuild is silently skipped.
2. **Coupling:** the pipeline depends on a specific tool namespace
   (`mcp__<uuid>__*`) that lives only in her Claude Code config. When we
   explored moving it to a Claude cloud RemoteTrigger routine, we hit
   layered problems — connector visibility, code-delivery mechanism,
   GitHub auth for private-repo checkout — none individually fatal but
   collectively enough that no cloud path has actually run end-to-end.

The rebuild logic itself doesn't need Claude at all. It's a plain
Python pipeline: parse an .xlsx, resize some photos, fill an HTML
template. Claude was in the loop only because Drive access needed
OAuth'd credentials and Anthropic's Artifact tool needed an agent to
publish. Both of those can go.

## Proposed architecture

```
GitHub Actions (schedule: Fri 20:00 America/Indianapolis)
        │
        ├── auth to Google Drive via service account
        │     (JSON key stored as repo secret GDRIVE_SA_JSON)
        │
        ├── run scripts/gha/fetch_drive.py
        │     → responses_fts.xlsx + photos_fts/*.jpg
        │
        ├── run build_fts.py responses_fts.xlsx photos_fts docs/fts.html
        │     (unchanged; already cross-platform via ImageMagick / Pillow fallback in common.py)
        │
        └── git commit docs/ + push to main
                │
                └── GitHub Pages auto-deploys docs/ to padproject.info/test_strip_dashboard/
```

Everything above happens on GitHub's infrastructure. Marya's laptop is
irrelevant. Claude is not involved. No MCP connectors, no RemoteTrigger,
no `mcp-registry` empty-result mystery, no code-delivery gap.

## What's in this branch

- `.github/workflows/weekly-update.yml` — the scheduled Actions workflow
  (FTS scheduled; XTS block written but commented out until the sheet ID
  and photo column index for XTS get pasted in — trivially copy-paste).
- `scripts/gha/fetch_drive.py` — narrow helper that authenticates as the
  service account, exports the Google Sheet as .xlsx, and downloads
  every photo referenced in a specified column. Reuses `common.py`'s
  parser + Drive-ID extractor rather than duplicating them.
- `scripts/gha/requirements.txt` — the three pip deps
  (`google-api-python-client`, `google-auth`, `Pillow`).
- `docs/` — GitHub Pages source. Empty at branch creation; populated by
  the workflow on first run. Site will serve at
  `padproject.info/test_strip_dashboard/` once Pages is enabled on
  `main` → `/docs`.

## What still needs a human

Two one-time setup steps before the workflow will do anything useful:

### 1. Create a Google Cloud service account and share the sheet

- In Google Cloud Console (`console.cloud.google.com`), pick or create
  a project the lab controls.
- APIs & Services → Enable the **Google Drive API** for that project.
- IAM & Admin → Service Accounts → **Create Service Account**. Any name;
  no role needed (Drive access happens via file-level sharing, not IAM).
- Once created, click the service account → **Keys** → Add key → JSON.
  Download the .json file. Copy the `client_email` field somewhere handy
  (looks like `<something>@<project>.iam.gserviceaccount.com`).
- In Google Drive, open the responses sheet (FTS: file ID
  `1Rlj5yWXoaa18aLsdI3L0Hri6RAq6MRvl6Rmxjycuo2Y`, plus its XTS sibling)
  and share it with the service account's email address as **Viewer**.
- Do the same with the parent folder containing the photos (or with
  each photo individually if they're not in a folder Marya can share
  wholesale).

### 2. Add the JSON key as a repo secret

- Repo → Settings → Secrets and variables → Actions → **New repository
  secret**.
- Name: `GDRIVE_SA_JSON`.
- Value: the entire contents of the .json key file downloaded above,
  pasted in as-is.

### 3. Enable GitHub Pages

- Repo → Settings → Pages.
- Source: **Deploy from a branch**.
- Branch: `main`, folder: `/docs`.
- Once the workflow has committed something to `docs/`, Pages will
  serve it at whatever URL is configured for the org's Pages (probably
  `padproject.info/test_strip_dashboard/`).

## First run

Once the secret is set and Pages is enabled, hit **Actions → weekly-update
→ Run workflow** to fire it manually and confirm end-to-end. On success,
`docs/fts.html` gets committed and served at the Pages URL. On failure,
the Actions log shows exactly which step broke.

## Migration and shutdown

Once the GitHub Pages URL is up and serving the same content as the
existing Claude Artifact, either:

- **Redirect the Artifact** by editing its HTML to a minimal
  `<meta http-equiv="refresh" content="0; url=<gh-pages-url>">` that
  points at the new location. Existing links keep working.
- **Or leave both running in parallel** for a week, compare, then
  disable the launchd LaunchAgent:
  ```
  launchctl unload ~/Library/LaunchAgents/edu.nd.lieberman.test-strip-weekly-update.plist
  ```

Nothing else in the repo needs to change. `build_fts.py`, `build_xts.py`,
`common.py`, `templates/` all continue to work exactly as they do today —
they were already cross-platform and network-free.

## What this does NOT change

- The build logic (`build_fts.py`, `build_xts.py`, `common.py`, templates)
  is untouched. Any dashboard UI / metric change lives in the same
  places it does now.
- The local `claude -p` + launchd path (`scripts/weekly_update/`) is
  left in place until the new path is verified — no reason to burn a
  working fallback while shaking out the replacement.
- The Google Sheet form + submission process on Marya's end doesn't
  change at all. The dashboard consumes the same data, just fetches
  it via a different mechanism.
