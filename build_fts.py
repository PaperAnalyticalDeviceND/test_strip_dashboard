#!/usr/bin/env python3
"""Build the FTS (fentanyl test strip) lot-testing dashboard.

Usage:
    python3 build_fts.py <responses.xlsx> <photos_dir> <output.html>

<photos_dir> must contain the raw downloaded bytes of every photo referenced
in the sheet's "Photos of product & packaging" column (column M) and its
"Photos of the strips" column (column AZ), named <drive_file_id>.<ext> (any
extension — sips will detect the real format).
Photos referenced in the sheet but missing from <photos_dir> are skipped
with a warning, not a hard failure, so a partial photo fetch still produces
a working dashboard.
"""
import hashlib
import json
import os
import re
import sys
from collections import defaultdict
from datetime import datetime

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from common import (
    parse_xlsx_sheet, excel_serial_to_dt, fix_numeric_id,
    process_photo, extract_drive_file_id, inject_into_template,
    reconcile_photo_counts, DASHBOARD_VERSION,
)

SUBSTANCES = ['DIPHEN', 'PROC', 'LIDO', 'LEVAM', 'MDONE', 'METH', 'MDMA']
SUB_LABEL = {
    'DIPHEN': 'Diphenhydramine', 'PROC': 'Procaine', 'LIDO': 'Lidocaine', 'LEVAM': 'Levamisole',
    'MDONE': 'Methadone', 'METH': 'Methamphetamine', 'MDMA': 'MDMA',
}
LEVEL_MG = {'HI': 2.0, 'MED': 0.7, 'LO': 0.2}
HI = [37, 39, 41, 43, 45, 47, 49]
LO = [53, 55, 57, 59, 61, 63, 65]
MED = [70, 71, 72, 73, 74, 75, 76]

# 0-indexed column positions, verified against the live sheet 2026-08.
# If the form's question order ever changes, re-verify these against a fresh
# header row before trusting a rebuild.
COL = dict(
    ts=0, email=1, name=2, affiliation=3, brand=6, lot=7, expiration=8,
    marketing=9, source=10, sample_selection=11, photos=12, strip_photos=51,
    packaging_issues=26, fen=(27, 32), wat=(32, 37), notes=67, other_notes=68,
)


def lotkey(brand, lot):
    lot = fix_numeric_id(lot.strip())
    return f"{brand.strip()}||{lot.upper().replace(' ', '')}"


def parse_records(header, rows):
    records = []
    for r in rows:
        dt = excel_serial_to_dt(r[COL['ts']])
        if not r[COL['brand']].strip() or not r[COL['lot']].strip() or dt is None:
            continue
        photos = [u.strip() for u in r[COL['photos']].split(',') if u.strip()] + \
            [u.strip() for u in r[COL['strip_photos']].split(',') if u.strip()]
        interference = {}
        for i, sub in enumerate(SUBSTANCES):
            interference[sub] = {'HI': r[HI[i]], 'MED': r[MED[i]], 'LO': r[LO[i]]}
        records.append({
            'dt': dt, 'name': r[COL['name']], 'affiliation': r[COL['affiliation']],
            'brand': r[COL['brand']], 'lot': fix_numeric_id(r[COL['lot']]),
            'expiration_dt': excel_serial_to_dt(r[COL['expiration']]),
            'source': r[COL['source']], 'photos': photos,
            'packaging_issues': r[COL['packaging_issues']],
            'fen': r[COL['fen'][0]:COL['fen'][1]], 'wat': r[COL['wat'][0]:COL['wat'][1]],
            'notes': r[COL['notes']] if len(r) > COL['notes'] else '',
            'other_notes': r[COL['other_notes']] if len(r) > COL['other_notes'] else '',
            'interference': interference,
        })
    return records


def build_dashboard_data(records):
    lots = defaultdict(lambda: {
        'brand': '', 'lot': '', 'expiration_dates': set(), 'submissions': [], 'testers': set(), 'photos': [],
        'fen_run': 0, 'fen_pos': 0, 'fen_unsure': 0, 'wat_run': 0, 'wat_true_neg': 0, 'wat_false_pos': 0,
        'sub_stats': defaultdict(lambda: {'run': 0, 'hits': 0, 'min_mg': None}),
    })
    sub_rows = []
    for idx, r in enumerate(records):
        k = lotkey(r['brand'], r['lot'])
        L = lots[k]
        L['brand'] = r['brand'].strip()
        L['lot'] = fix_numeric_id(r['lot'].strip())
        if r['expiration_dt']:
            L['expiration_dates'].add(r['expiration_dt'].date())
        L['submissions'].append(r['dt'])
        L['testers'].add(r['name'])
        if r['photos']:
            L['photos'].extend(r['photos'])

        fen_run = fen_pos = fen_unsure = 0
        for v in r['fen']:
            if v in ('', 'Did not run this'):
                continue
            fen_run += 1
            if v == 'Positive':
                fen_pos += 1
            if v == 'Not sure':
                fen_unsure += 1
        wat_run = wat_tn = wat_fp = 0
        for v in r['wat']:
            if v in ('', 'Did not run this'):
                continue
            wat_run += 1
            if v == 'Negative':
                wat_tn += 1
            if v == 'Positive':
                wat_fp += 1
        L['fen_run'] += fen_run
        L['fen_pos'] += fen_pos
        L['fen_unsure'] += fen_unsure
        L['wat_run'] += wat_run
        L['wat_true_neg'] += wat_tn
        L['wat_false_pos'] += wat_fp

        row_interferents = []
        for sub in SUBSTANCES:
            for level in ('HI', 'MED', 'LO'):
                v = r['interference'][sub][level]
                if v in ('', None, 'Did not run this'):
                    continue
                st = L['sub_stats'][sub]
                st['run'] += 1
                if v == 'Positive':
                    st['hits'] += 1
                    mg = LEVEL_MG[level]
                    if st['min_mg'] is None or mg < st['min_mg']:
                        st['min_mg'] = mg
                    row_interferents.append(f"{sub}@{mg}")

        post_exp = bool(r['expiration_dt'] and r['dt'].date() > r['expiration_dt'].date())
        sub_rows.append({
            'id': idx, 'timestamp': r['dt'].strftime('%-m/%-d/%Y %H:%M:%S'), 'ts_sort': r['dt'].isoformat(),
            'tester': r['name'], 'affiliation': r['affiliation'],
            'brand': r['brand'], 'lot': fix_numeric_id(r['lot']),
            'expiration': r['expiration_dt'].strftime('%-m/%-d/%Y') if r['expiration_dt'] else None,
            'post_exp': post_exp,
            'fen_summary': f"{fen_pos}/{fen_run}" + (f" (+{fen_unsure} unsure)" if fen_unsure else ""),
            'fen_pos': fen_pos, 'fen_run': fen_run,
            'wat_summary': f"{wat_tn}/{wat_run}", 'wat_tn': wat_tn, 'wat_run': wat_run,
            'interferents_flagged': row_interferents,
            'n_photos': len(r['photos']), 'first_photo': r['photos'][0] if r['photos'] else None,
            'notes': (r['notes'] or r['other_notes'] or '').strip(),
            'source': r['source'], 'packaging_issues': r['packaging_issues'],
        })

    lot_out = []
    for k, L in lots.items():
        dates = L['submissions']
        interferents = []
        for sub, st in L['sub_stats'].items():
            if st['hits'] > 0:
                interferents.append({'substance': sub, 'label': SUB_LABEL[sub], 'min_mg_ml': st['min_mg'], 'hits': st['hits'], 'run': st['run']})
        interferents.sort(key=lambda x: x['min_mg_ml'])
        matrix = {sub: {'run': L['sub_stats'][sub]['run'], 'hits': L['sub_stats'][sub]['hits'], 'min_mg': L['sub_stats'][sub]['min_mg']} for sub in SUBSTANCES}

        lot_out.append({
            'brand': L['brand'], 'lot': L['lot'],
            'expirations': [d.strftime('%-m/%-d/%Y') for d in sorted(L['expiration_dates'])],
            'n_submissions': len(L['submissions']), 'testers': sorted(L['testers']),
            'first_submitted': min(dates).strftime('%Y-%m-%d'), 'last_submitted': max(dates).strftime('%Y-%m-%d'),
            'fen_run': L['fen_run'], 'fen_pos': L['fen_pos'], 'fen_unsure': L['fen_unsure'],
            'fen_rate': round(100 * L['fen_pos'] / L['fen_run'], 1) if L['fen_run'] else None,
            'wat_run': L['wat_run'], 'wat_true_neg': L['wat_true_neg'], 'wat_false_pos': L['wat_false_pos'],
            'wat_rate': round(100 * L['wat_true_neg'] / L['wat_run'], 1) if L['wat_run'] else None,
            'interferents': interferents, 'matrix': matrix,
            'n_photos': len(L['photos']), 'first_photo': L['photos'][0] if L['photos'] else None,
        })
    lot_out.sort(key=lambda x: (x['fen_rate'] if x['fen_rate'] is not None else 999))
    sub_rows.sort(key=lambda s: s['ts_sort'], reverse=True)
    for i, s in enumerate(sub_rows):
        s['id'] = i

    total_fen_run = sum(l['fen_run'] for l in lot_out)
    total_fen_pos = sum(l['fen_pos'] for l in lot_out)
    total_wat_run = sum(l['wat_run'] for l in lot_out)
    total_wat_tn = sum(l['wat_true_neg'] for l in lot_out)
    dts = [r['dt'] for r in records]

    overall = {
        'n_lots': len(lot_out), 'n_submissions': len(records), 'n_testers': len(set(r['name'] for r in records)),
        'pooled_fen_rate': round(100 * total_fen_pos / total_fen_run, 1) if total_fen_run else None,
        'pooled_wat_rate': round(100 * total_wat_tn / total_wat_run, 1) if total_wat_run else None,
        'date_range': [min(dts).strftime('%b %-d, %Y'), max(dts).strftime('%b %-d, %Y')],
        'substances': [{'code': s, 'label': SUB_LABEL[s]} for s in SUBSTANCES],
    }
    return {'dashboard_version': DASHBOARD_VERSION, 'overall': overall, 'lots': lot_out, 'submissions': sub_rows}


def build_photos_by_lot(records, photos_dir):
    photos_by_lot = {}
    seen_hashes_by_lot = defaultdict(set)
    missing = []
    attempted = failed = skipped_dupes = 0
    for r in records:
        k = lotkey(r['brand'], r['lot'])
        for u in r['photos']:
            fid = extract_drive_file_id(u)
            if not fid:
                continue
            raw_candidates = [f for f in os.listdir(photos_dir) if f.startswith(fid + '.')] if os.path.isdir(photos_dir) else []
            if not raw_candidates:
                missing.append(fid)
                continue
            raw_path = os.path.join(photos_dir, raw_candidates[0])
            with open(raw_path, 'rb') as fh:
                content_hash = hashlib.sha256(fh.read()).hexdigest()
            if content_hash in seen_hashes_by_lot[k]:
                skipped_dupes += 1
                continue
            seen_hashes_by_lot[k].add(content_hash)
            out_jpg = os.path.join(photos_dir, f'{fid}.__out.jpg')
            attempted += 1
            try:
                b64 = process_photo(raw_path, out_jpg)
            except Exception as e:
                failed += 1
                print(f'WARN: photo {fid} failed to process: {e}', file=sys.stderr)
                continue
            finally:
                if os.path.exists(out_jpg):
                    os.remove(out_jpg)
            photos_by_lot.setdefault(k, []).append({
                'b64': b64, 'tester': r['name'], 'date': r['dt'].strftime('%Y-%m-%d'),
            })
    if missing:
        print(f'WARN: {len(missing)} photo(s) referenced in the sheet were not found in {photos_dir}: {missing}', file=sys.stderr)
    if skipped_dupes:
        print(f'INFO: skipped {skipped_dupes} duplicate photo upload(s) (identical content hash within the same lot)', file=sys.stderr)
    if attempted > 0 and failed == attempted:
        raise RuntimeError(
            f'all {attempted} photo(s) on disk failed to process (0 succeeded) - '
            'this looks like a missing/broken image tool, not per-photo corruption; '
            'aborting rather than publishing a dashboard with zero photos'
        )
    return photos_by_lot


def main():
    if len(sys.argv) != 4:
        print(__doc__)
        sys.exit(1)
    xlsx_path, photos_dir, out_path = sys.argv[1:4]
    template_path = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'templates', 'fts_template.html')

    header, rows = parse_xlsx_sheet(xlsx_path)
    records = parse_records(header, rows)
    print(f'parsed {len(records)} records')

    dashboard_data = build_dashboard_data(records)
    photos_by_lot = build_photos_by_lot(records, photos_dir)
    reconcile_photo_counts(dashboard_data, photos_by_lot, lotkey)
    print(f'lots: {len(dashboard_data["lots"])}  photos matched to {len(photos_by_lot)} lots')

    template_html = open(template_path).read()
    html = inject_into_template(template_html, dashboard_data, photos_by_lot)
    with open(out_path, 'w') as f:
        f.write(html)
    print(f'wrote {out_path} ({len(html)} bytes)')


if __name__ == '__main__':
    main()
