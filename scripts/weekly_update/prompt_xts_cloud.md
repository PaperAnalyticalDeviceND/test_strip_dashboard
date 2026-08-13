You are rebuilding and republishing the XTS (xylazine test strip) lot-testing
QC dashboard from fresh spreadsheet data. This is a scheduled cloud run (no
human watching) — don't skip verification steps, since a silent bad publish
would go unnoticed for a week. The `test_strip_dashboard` repo is already
checked out at your current working directory.

## 0. Load your Google Drive tools

Your Google Drive connector's tools are deferred at session start. Load them
first:

`ToolSearch({query: "select:mcp__Google_Drive__download_file_content,mcp__Google_Drive__get_file_metadata", max_results: 5})`

If that doesn't return them, try a keyword search (`"google drive"`) instead —
the exact tool-name prefix in this environment is `mcp__Google_Drive__*`, not
the UUID-prefixed form you might see documented elsewhere for local/chat use.
No `mcp_connections` attachment is needed — this account's Drive access is
ambient in this cloud sandbox (confirmed by an earlier diagnostic run); if the
tools genuinely aren't there at all, stop and report that plainly rather than
guessing around it.

## 1. Download the response sheet

Google Sheet file ID: `1qYtKDqcohHx9rJ3bx4wJ6injxoIY592twVzGwKtEzg4`

Use `mcp__Google_Drive__download_file_content` with
`exportMimeType: application/vnd.openxmlformats-officedocument.spreadsheetml.sheet`.

**Important gotcha:** this particular sheet is small enough that the xlsx
export usually returns *inline* in the tool result rather than auto-saving
to a file. Writing a long inline base64 string by hand is a known failure
mode (a past manual attempt at this exact file got silently corrupted). If it
comes back inline:
- Prefer requesting `exportMimeType: text/csv` instead — this sheet's CSV
  export is large enough to exceed the tool's inline-return threshold and
  gets auto-saved to a file, which you can then read and decode without ever
  retyping it yourself. That avoids the corruption risk entirely.
- CSV only exports the first/active sheet, but that's the one with the raw
  response data, which is all this build needs.
- If you use the CSV path, use this repo's `build_xts_from_csv.py` directly
  instead of `build_xts.py` (see step 3) — it already handles the CSV-vs-xlsx
  differences (timestamp format, header row) for you.
- If you'd rather get a real `.xlsx`, only trust it if you can verify the
  written file is a valid zip (`python3 -c "import zipfile;
  zipfile.ZipFile('f.xlsx').testzip()"` should raise nothing) — if not,
  don't retry retyping it by hand, fall back to the CSV approach above.

## 2. Find and download the referenced photos

Parse the sheet (however you obtained it above) to find every Drive photo ID
referenced in the product/packaging photo column (column K, 0-indexed 10) and
the strip-photo column (column BT, 0-indexed 71).
For each unique file ID found, download the raw file with
`mcp__Google_Drive__download_file_content` (no exportMimeType — these are
ordinary uploaded images). Save each to a `photos_xts/` directory as
`<file_id>.<ext>`, matching the returned `mimeType`/`title`. There are
normally only ~15-20 unique photos for this sheet.

If a photo fails to download, log a warning and continue — a missing photo
should not block the whole rebuild.

## 3. Build the dashboard

If you went the xlsx route:
```
python3 build_xts.py responses_xts.xlsx photos_xts/ xts_dashboard_output.html
```

If you went the CSV route:
```
python3 build_xts_from_csv.py responses_xts.csv photos_xts/ xts_dashboard_output.html
```

Sanity check the printed lot/record counts before publishing: currently
~20-25 lots, ~70-100 submissions. If wildly different (0, or single digits),
stop and report rather than publishing.

Photo processing (`common.py`'s `process_photo()`) now auto-detects an
available image tool (macOS `sips`, ImageMagick, or Python Pillow) so it
should work in this Linux cloud sandbox without special handling — but if
the script exits non-zero with an error about "all N photo(s) ... failed to
process", that's a real environment problem (no working image tool found),
not a transient one. Stop and report the exact error rather than retrying
blindly or publishing without photos.

## 4. Publish

Publish the built HTML as an Artifact, updating the **existing** XTS
dashboard in place (pass its current URL as `url`):

`https://claude.ai/code/artifact/901a2781-90ba-452e-8b26-ff5a7636283f`

Title: "XTS Lot Characteristics". Favicon: 🐎. Keep the same description as
before (xylazine test strip QC dashboard — DI vs. tap water comparison,
interference matrix, per-lot photo galleries).

## 5. Report

End with a one-paragraph summary: lot/submission counts, which data-fetch
path you used (xlsx or CSV), any photos that failed, and confirmation the
Artifact publish succeeded (include the URL). If anything failed in a way
you couldn't recover from, say so plainly and do NOT claim success.
