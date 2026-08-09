# One-time setup: GitHub Actions weekly update

This branch (`setup/github-actions`) adds a scheduled workflow that
rebuilds and publishes the FTS + XTS dashboards from GitHub's
infrastructure — no laptop needed, no Claude routine, no MCP connector.

The workflow itself is inert until three things are done. Marya's Claude
should walk her through them:

1. Create a Google Cloud service account and download its JSON key.
2. Share the response sheet + photo folder with the service account.
3. Add the JSON key to this repo as a secret named `GDRIVE_SA_JSON`.

Once those are done, merge this branch to `main` and run the workflow
manually once from Actions → weekly-update → Run workflow to confirm.

See the message from Chris's Claude for a step-by-step walk-through of
each of the three items above.

## Files added on this branch

- `.github/workflows/weekly-update.yml` — the scheduled workflow. FTS
  wired live; XTS block commented out (needs its sheet ID + photo
  column pasted in before enabling).
- `scripts/gha/fetch_drive.py` — narrow Drive-download helper. Uses the
  service account credentials, reuses `common.parse_xlsx_sheet` and
  `common.extract_drive_file_id`.
- `scripts/gha/requirements.txt` — three pip deps (google-api-python-client,
  google-auth, Pillow).

## What this does NOT change

- `build_fts.py`, `build_xts.py`, `common.py`, `templates/` — untouched.
- The local `scripts/weekly_update/` launchd path — left in place as a
  fallback until the new path is verified live.
- The Google Form / sheet Marya uses — no change on her side beyond the
  two "Share" clicks in step 2.

## Output location

Built dashboards land on the `gh-pages` branch (already created) as
`fts.html` and `xts.html`. GitHub Pages serves them at:

- https://padproject.info/test_strip_dashboard/fts.html
- https://padproject.info/test_strip_dashboard/xts.html
