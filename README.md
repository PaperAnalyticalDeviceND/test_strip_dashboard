# test_strip_dashboard

Build pipeline for the Lieberman Lab's drug-checking test strip lot-testing
QC dashboards (FTS/fentanyl, XTS/xylazine, and future targets), published as
claude.ai Artifacts. Separate from `annotated_chemopad` (ChemoPAD ML/PLS
work) — different subject, different audience, kept in its own repo on
purpose.

## How it fits together

Each dashboard is a single self-contained HTML file (no server, no external
requests — all data and photos are embedded inline as base64). Building one
means:

1. Download the response sheet as `.xlsx` from Google Drive (needs a live
   Drive/Sheets connector — a plain script can't do this step, only an agent
   with MCP tool access can).
2. Download every photo referenced in the sheet's product/packaging photo
   column (same connector, one call per file).
3. Run `build_fts.py` / `build_xts.py`, which do **not** touch the network —
   they parse the local `.xlsx`, resize the local photos with `sips`, and
   fill in `templates/{fts,xts}_template.html` to produce the final HTML.
4. Publish the resulting HTML file as the dashboard's Artifact (same URL each
   time, so links don't break).

This split exists because MCP tool calls can only be made by the agent
orchestrating the run, not by a plain Python script — steps 1, 2, and 4 are
"agent does this"; step 3 is "script does this."

## Files

- `common.py` — shared, network-free utilities: xlsx parsing (stdlib only,
  no openpyxl/pandas needed), photo resize via macOS `sips`, and safe JSON
  embedding into a `<script>` tag (escapes `</script` so a malicious note
  field can't break out of it).
- `build_fts.py`, `build_xts.py` — per-target column mapping, result
  classification, and lot aggregation. Run standalone:
  `python3 build_fts.py <responses.xlsx> <photos_dir> <output.html>`
- `templates/fts_template.html`, `templates/xts_template.html` — the dashboard
  UI (HTML/CSS/JS) with `__DASHBOARD_DATA__` / `__PHOTOS_DATA__` placeholders.
  Edit these for UI/copy changes; edit `build_*.py` for data/metric changes.

## Security note

Every free-text field in the sheet (brand, lot, tester name, notes, ...) is
attacker-controllable — anyone who can submit the form controls that text.
The templates escape all of it (`esc()` in the template JS) before writing it
into the page, and `common.embed_json_in_script()` neutralizes `</script`
sequences in the embedded JSON. If you add a new field to a template's
rendering, escape it. If you add a new report format that's ever embedded raw
into HTML, run it through `embed_json_in_script()` or the JS `esc()`.

## Column positions are hardcoded, not inferred

`build_fts.py` and `build_xts.py` hardcode which spreadsheet column is which
(see `COL = dict(...)` near the top of each). This is deliberate — inferring
structure from header text is fragile against typos and reordering. **If the
Google Form's question order ever changes, these column indices go stale
silently** (wrong data in the right shape, not a crash). Re-verify against a
fresh header row before trusting a rebuild after any form edit.

## Adding a new target

Copy `build_xts.py` (closer to a "general" template than `build_fts.py`,
which has fewer true-positive panels) and its template, adjust `COL`, the
substance list, and the result-classification rules for that target's sheet,
then add a routine (see the repo's automation setup / ask in chat).
