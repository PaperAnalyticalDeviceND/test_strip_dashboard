You are rebuilding and republishing the XTS (xylazine test strip) lot-testing
QC dashboard from fresh spreadsheet data. This repo (test_strip_dashboard,
already checked out at your current working directory) has everything you
need except the live data, which you must fetch yourself. Work in this exact
order and don't skip verification steps — this runs unattended on a schedule,
so a silent bad publish would go unnoticed for a week.

## 1. Download the response sheet

Google Sheet file ID: `1qYtKDqcohHx9rJ3bx4wJ6injxoIY592twVzGwKtEzg4`

Use your Google Drive connector's download tool
(`mcp__59170adc-5242-42d9-a35c-f748cfef1da1__download_file_content`) with
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
- If you use the CSV path, adapt: `common.py`'s `parse_xlsx_sheet()` expects
  xlsx; for CSV, parse with Python's stdlib `csv` module instead — header is
  row 0, data is every following row with a non-empty first cell — and pass
  the resulting `(header, rows)` tuple into `build_xts.parse_records()`
  exactly as `parse_xlsx_sheet()` would have. Confirm this still works before
  proceeding: it should parse to roughly 70-100 records.
- If you'd rather get a real `.xlsx`, only trust it if you can verify the
  written file is a valid zip (`python3 -c "import zipfile;
  zipfile.ZipFile('f.xlsx').testzip()"` should raise nothing) — if not,
  don't retry retyping it by hand, fall back to the CSV approach above.

## 2. Find and download the referenced photos

Parse the sheet (however you obtained it above) to find every Drive photo ID
referenced in the product/packaging photo column (column K, 0-indexed 10).
For each unique file ID found, download the raw file with the connector's
download tool (no exportMimeType — these are ordinary uploaded images).
Save each to a `photos_xts/` directory as `<file_id>.<ext>`, matching the
returned `mimeType`/`title`. There are normally only ~15-20 unique photos for
this sheet, much fewer than the FTS dashboard.

If a photo fails to download, log a warning and continue — a missing photo
should not block the whole rebuild (`build_xts.py` tolerates missing photos).

## 3. Build the dashboard

If you went the xlsx route:
```
python3 build_xts.py responses_xts.xlsx photos_xts/ xts_dashboard_output.html
```

If you went the CSV route, you'll need a short adapter script (a few lines)
that does the CSV parse, calls `build_xts.parse_records()` /
`build_xts.build_dashboard_data()` / `build_xts.build_photos_by_lot()`
directly, and writes the result via `common.inject_into_template()` against
`templates/xts_template.html` — mirror what `build_xts.py`'s own `main()`
does, just with a CSV-sourced `(header, rows)` instead of the xlsx-sourced
one.

Sanity check the printed lot/record counts before publishing: currently
~20-25 lots, ~70-100 submissions. If wildly different (0, or single digits),
stop and report rather than publishing.

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
