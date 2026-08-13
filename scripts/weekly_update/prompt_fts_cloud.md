You are rebuilding and republishing the FTS (fentanyl test strip) lot-testing
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

Google Sheet file ID: `1Rlj5yWXoaa18aLsdI3L0Hri6RAq6MRvl6Rmxjycuo2Y`

Use `mcp__Google_Drive__download_file_content` with
`exportMimeType: application/vnd.openxmlformats-officedocument.spreadsheetml.sheet`.

**Important gotcha:** if this file is small, the tool may return the base64
content *inline* in the tool result instead of auto-saving it to a file. If
that happens, write it to disk yourself with the Write tool in a single
clean call — do not split it across multiple edits, and do not retype or
reformat it. After writing, decode it and verify the result is a valid zip
(`python3 -c "import zipfile; zipfile.ZipFile('the_file.xlsx').testzip()"`
should raise nothing / print `None`). If it's corrupted, redownload and
rewrite once before giving up — a bad transcription on a long base64 string
is a known failure mode here.

If the tool instead errors with "exceeds maximum allowed tokens" and saves
to a file automatically, just read the JSON from that saved path, base64-decode
the `content` field, and write the bytes to `responses_fts.xlsx`. This path is
safer (no manual retyping) — prefer it if you have a choice.

## 2. Find and download the referenced photos

Run this repo's `common.py` to parse the sheet and find every Drive photo ID
referenced in the "Photos of product & packaging" column (column M, 0-indexed
12) and the "Photos of the strips" column (column AZ, 0-indexed 51) using
`parse_xlsx_sheet()`. For each unique file ID found, download the
raw file with `mcp__Google_Drive__download_file_content` (no exportMimeType
needed — these are ordinary uploaded images/HEIC files, not Google-native
documents). Save each one to a `photos_fts/` directory as `<file_id>.<ext>`,
using whatever extension matches the returned `mimeType`/`title`.

If a particular photo fails to download, log a warning and continue — a
missing photo should not block the whole rebuild.

## 3. Build the dashboard

```
python3 build_fts.py responses_fts.xlsx photos_fts/ fts_dashboard_output.html
```

Check the script's stdout: it prints the record/lot count it parsed. Sanity
check that the lot count is in a plausible range (currently ~30-40 lots,
~90-110 submissions) — if it's wildly different (e.g. 0, or 3), something
upstream broke silently; stop and report rather than publishing.

Photo processing (`common.py`'s `process_photo()`) now auto-detects an
available image tool (macOS `sips`, ImageMagick, or Python Pillow) so it
should work in this Linux cloud sandbox without special handling — but if
the script exits non-zero with an error about "all N photo(s) ... failed to
process", that's a real environment problem (no working image tool found),
not a transient one. Stop and report the exact error rather than retrying
blindly or publishing without photos.

## 4. Publish

Publish `fts_dashboard_output.html` as an Artifact, updating the **existing**
FTS dashboard in place (pass its current URL as `url`, don't mint a new one):

`https://claude.ai/code/artifact/bc2b2073-c08d-45c2-93c5-732cc96ec8b8`

Title: "FTS Lot Characteristics". Favicon: 🧪. Keep the same description as
before (a QC dashboard for fentanyl test strip lot testing).

## 5. Report

End with a one-paragraph summary: lots/submissions counts, any photos that
failed to download or process, and confirmation the Artifact publish
succeeded (include the URL). If anything in steps 0-4 failed in a way you
couldn't recover from, say so plainly and do NOT claim success.
