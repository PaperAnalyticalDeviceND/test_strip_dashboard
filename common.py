"""Shared utilities for building the FTS/XTS lot-testing dashboards.

This module does no network I/O and calls no MCP tools — it only transforms
files already sitting on disk (a downloaded .xlsx, downloaded photo bytes)
into the JSON blobs and final HTML a dashboard template needs. The calling
routine (a Claude agent, human or scheduled) is responsible for fetching the
spreadsheet and photos via the Drive/Sheets connector first.
"""
import base64
import json
import re
import shutil
import subprocess
import zipfile
from datetime import datetime, timedelta
from xml.etree import ElementTree as ET

NS = '{http://schemas.openxmlformats.org/spreadsheetml/2006/main}'

# Shown in each page's footer. Bump by hand: increment the part before the
# dot for a major change (new view, new data model, a redesign), the part
# after for a minor one (new filter/sort, copy edits, a bugfix). One shared
# version for both FTS and XTS -- they're the same "lot checking dashboard"
# project, built from this same module, and versioned separately from the
# unrelated drug_trash_dashboard project's own counter.
DASHBOARD_VERSION = '1.1'


# ---------------------------------------------------------------------------
# xlsx parsing (stdlib only — no openpyxl/pandas dependency)
# ---------------------------------------------------------------------------

def col_num(letters):
    n = 0
    for c in letters:
        n = n * 26 + (ord(c) - ord('A') + 1)
    return n


def excel_serial_to_dt(s):
    try:
        serial = float(s)
    except (TypeError, ValueError):
        return None
    return datetime(1899, 12, 30) + timedelta(days=serial)


def parse_xlsx_sheet(xlsx_path, sheet_file='xl/worksheets/sheet1.xml'):
    """Return (header_row, data_rows) as lists of cell strings, 0-indexed.

    header_row is row 1 of the sheet (assumed single header row — verify
    against a fresh export if a source sheet's layout changes). data_rows is
    every subsequent row that has a non-empty first cell.
    """
    z = zipfile.ZipFile(xlsx_path)
    shared = []
    if 'xl/sharedStrings.xml' in z.namelist():
        # Every real Google Sheets xlsx export has this part. Some writers
        # (e.g. openpyxl, used only for local test fixtures) skip it
        # entirely and inline every string with t="inlineStr" instead --
        # tolerate that rather than crash, since inline strings are already
        # handled below regardless of whether this table exists.
        sst_root = ET.fromstring(z.read('xl/sharedStrings.xml'))
        for si in sst_root.findall(f'{NS}si'):
            texts = si.findall(f'.//{NS}t')
            shared.append(''.join(t.text or '' for t in texts))

    root = ET.fromstring(z.read(sheet_file))
    sheetdata = root.find(f'{NS}sheetData')
    rows = {}
    max_col = 0
    for row in sheetdata.findall(f'{NS}row'):
        r_idx = int(row.get('r'))
        cells = {}
        for c in row.findall(f'{NS}c'):
            ref = c.get('r')
            m = re.match(r'([A-Z]+)(\d+)', ref)
            col_idx = col_num(m.group(1))
            max_col = max(max_col, col_idx)
            t = c.get('t')
            v_el = c.find(f'{NS}v')
            is_el = c.find(f'{NS}is')
            if t == 's' and v_el is not None:
                val = shared[int(v_el.text)]
            elif t == 'str' and v_el is not None:
                val = v_el.text
            elif t == 'inlineStr' and is_el is not None:
                texts = is_el.findall(f'.//{NS}t')
                val = ''.join(tt.text or '' for tt in texts)
            elif v_el is not None:
                val = v_el.text
            else:
                val = None
            cells[col_idx] = val
        rows[r_idx] = cells

    def clean(v):
        return '' if v is None else str(v).strip()

    header = [clean(rows.get(1, {}).get(i)) for i in range(1, max_col + 1)]
    data_rows = []
    r = 2
    while r in rows or any(k > r for k in rows):
        if r not in rows:
            r += 1
            if r > max(rows) + 1:
                break
            continue
        if rows[r].get(1) in (None, ''):
            r += 1
            continue
        data_rows.append([clean(rows[r].get(i)) for i in range(1, max_col + 1)])
        r += 1
    return header, data_rows


def fix_numeric_id(s):
    """Sheets sometimes stores a lot number as a plain number (e.g. 2404191.0).
    Strip the trailing .0 so it displays like the text everyone actually typed."""
    return re.sub(r'\.0$', '', s) if re.match(r'^\d+\.0$', s.strip()) else s


# ---------------------------------------------------------------------------
# Photo processing — macOS `sips` locally, ImageMagick/Pillow elsewhere (e.g.
# a Linux cloud sandbox where `sips` doesn't exist)
# ---------------------------------------------------------------------------

def process_photo(raw_path, out_jpg_path, max_dim=480, quality=45):
    """Convert/resize a downloaded photo (HEIC/JPEG/PNG/...) to a small JPEG
    and return its base64 string. Raises on failure — the caller should
    decide whether a single bad photo should abort the whole build."""
    if shutil.which('sips'):
        return _process_photo_sips(raw_path, out_jpg_path, max_dim, quality)
    if shutil.which('magick') or shutil.which('convert'):
        return _process_photo_imagemagick(raw_path, out_jpg_path, max_dim, quality)
    return _process_photo_pillow(raw_path, out_jpg_path, max_dim, quality)


def _process_photo_sips(raw_path, out_jpg_path, max_dim, quality):
    r = subprocess.run(
        ['sips', '-s', 'format', 'jpeg', '-Z', str(max_dim), raw_path, '--out', out_jpg_path],
        capture_output=True, text=True,
    )
    if r.returncode != 0:
        raise RuntimeError(f'sips failed on {raw_path}: {r.stderr[:300]}')
    subprocess.run(['sips', '-s', 'formatOptions', str(quality), out_jpg_path], capture_output=True, text=True)
    with open(out_jpg_path, 'rb') as f:
        return base64.b64encode(f.read()).decode('ascii')


def _process_photo_imagemagick(raw_path, out_jpg_path, max_dim, quality):
    exe = 'magick' if shutil.which('magick') else 'convert'
    cmd = [exe, raw_path, '-auto-orient', '-resize', f'{max_dim}x{max_dim}>', '-quality', str(quality), out_jpg_path]
    r = subprocess.run(cmd, capture_output=True, text=True)
    if r.returncode != 0:
        raise RuntimeError(f'{exe} failed on {raw_path}: {r.stderr[:300]}')
    with open(out_jpg_path, 'rb') as f:
        return base64.b64encode(f.read()).decode('ascii')


def _process_photo_pillow(raw_path, out_jpg_path, max_dim, quality):
    try:
        from PIL import Image
    except ImportError as e:
        raise RuntimeError(
            f'no photo-processing tool available (no sips, no ImageMagick, no Pillow) for {raw_path}'
        ) from e
    img = Image.open(raw_path).convert('RGB')
    img.thumbnail((max_dim, max_dim))
    img.save(out_jpg_path, 'JPEG', quality=quality)
    with open(out_jpg_path, 'rb') as f:
        return base64.b64encode(f.read()).decode('ascii')


def extract_drive_file_id(url):
    m = re.search(r'id=([a-zA-Z0-9_-]+)', url)
    return m.group(1) if m else None


def reconcile_photo_counts(dashboard_data, photos_by_lot, lotkey_fn):
    """Overwrite each lot's n_photos with the actual number of photos that
    will appear in its gallery. build_dashboard_data() counts raw photo
    references from the sheet; build_photos_by_lot() then drops references
    whose file isn't on disk and collapses duplicate-content uploads. Without
    this reconciliation the "N photos" badge can promise more than the
    gallery delivers when it's clicked.

    Also reconciles n_photos_packaging/n_photos_strip the same way, from
    each photo dict's 'kind' tag (set in build_photos_by_lot()) -- the
    lot-checking progress tracker needs to know packaging and strip photos
    were counted separately, not just that some photo exists."""
    for lot in dashboard_data['lots']:
        key = lotkey_fn(lot['brand'], lot['lot'])
        photos = photos_by_lot.get(key, [])
        lot['n_photos'] = len(photos)
        lot['n_photos_packaging'] = sum(1 for p in photos if p.get('kind') == 'packaging')
        lot['n_photos_strip'] = sum(1 for p in photos if p.get('kind') == 'strip')


# ---------------------------------------------------------------------------
# Safe embedding into an HTML <script> tag
# ---------------------------------------------------------------------------

def extract_dashboard_data(dashboard_html_path):
    """Pull the whole embedded `const DATA = {...};` blob back out of an
    already-built dashboard HTML file (build_fts.py's/build_xts.py's own
    output). Used by build_hub.py (which only wants ['overall']) and
    build_progress.py (which wants the full ['lots'] list) so a lot's
    testing status is read once, from the one place it's actually
    computed, instead of being re-derived from the raw sheet a second
    time by a parallel parser that could drift from the real one."""
    html = open(dashboard_html_path, encoding='utf-8').read()
    m = re.search(r'const DATA = (.*?);\n', html)
    if not m:
        raise RuntimeError(f'could not find `const DATA = ...;` in {dashboard_html_path}')
    return json.loads(m.group(1))


def embed_json_in_script(json_obj):
    """json.dumps() a value for direct embedding inside a <script> tag.

    Two things a naive json.dumps + string-replace would get wrong:
    1. A literal "</script" inside a string value (e.g. someone's notes field)
       would prematurely close the surrounding <script> tag when the browser
       parses the HTML, regardless of it being "inside a JS string" — HTML
       tokenization doesn't know about JS string boundaries.
    2. Backslashes in the payload need doubling if this string is later used
       as a *replacement* string in re.sub (re.sub treats \\1 etc. specially)
       — callers using re.sub for injection should still do that themselves;
       this function only handles the HTML/script safety, not the regex one.
    """
    payload = json.dumps(json_obj)
    payload = re.sub(r'</(script)', r'<\\/\1', payload, flags=re.IGNORECASE)
    return payload


def inject_into_template(template_html, dashboard_data, photos_by_lot):
    """Fill a template's __DASHBOARD_DATA__ / __PHOTOS_DATA__ placeholders."""
    data_payload = embed_json_in_script(dashboard_data)
    photos_payload = embed_json_in_script(photos_by_lot)
    html = template_html.replace('__PHOTOS_DATA__', photos_payload, 1)
    html = html.replace('__DASHBOARD_DATA__', data_payload, 1)
    return html
