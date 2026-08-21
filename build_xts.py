#!/usr/bin/env python3
"""Build the XTS (xylazine test strip) lot-testing dashboard.

Usage:
    python3 build_xts.py <responses.xlsx> <photos_dir> <output.html>

<photos_dir> must contain the raw downloaded bytes of every photo referenced
in the sheet's product/packaging photo column (column K) and its strip-photo
column (column BT), named <drive_file_id>.<ext>. Missing photos are skipped
with a warning, not a hard failure.
"""
import hashlib
import os
import re
import sys
from collections import defaultdict

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from common import (
    parse_xlsx_sheet, excel_serial_to_dt, fix_numeric_id,
    process_photo, extract_drive_file_id, inject_into_template,
    reconcile_photo_counts, DASHBOARD_VERSION,
)

SUBSTANCES = ['DIPHEN', 'KETA', 'LIDO', 'PREMETH', 'CETIRI', 'METH', 'MDMA', 'ROMI', 'TIZA', 'CLONI', 'APRACLONI']
SUB_LABEL = {
    'DIPHEN': 'Diphenhydramine', 'KETA': 'Ketamine', 'LIDO': 'Lidocaine', 'PREMETH': 'Promethazine',
    'CETIRI': 'Cetirizine', 'METH': 'Methamphetamine', 'MDMA': 'MDMA', 'ROMI': 'Romifidine',
    'TIZA': 'Tizanidine', 'CLONI': 'Clonidine', 'APRACLONI': 'Apraclonidine',
}
LEVEL_MG = {'HI': 2.0, 'MED': 0.7, 'LO': 0.2}
HI = list(range(38, 49))
MED = list(range(49, 60))
LO = list(range(60, 71))
TP_2500_DI = list(range(22, 27))
TP_2500_TAP = list(range(27, 32))
TP_1000_DI = list(range(32, 37))
TN_WATER = 37

# 0-indexed column positions, verified against the live sheet 2026-08.
# If the form's question order ever changes, re-verify against a fresh header row.
COL = dict(
    ts=0, name=2, affiliation=3, brand=6, lot=7, expiration=8,
    source=9, photos=10, strip_photos=71, notes=72,
)


def lotkey(brand, lot):
    lot = fix_numeric_id(lot.strip())
    return f"{brand.strip()}||{lot.upper().replace(' ', '')}"


def parse_result(cell):
    """Classify one result cell. Xylazine strips report either a flat
    "Positive"/"Did not run"/"invalid", or a 1-10 line-intensity score
    (sometimes a range like "5-10" or a comma list like "2, 3"). Per lab
    guidance, intensities of 1-3 are effectively unreadable in practice and
    get treated the same as a flat "Positive" for both detection and
    interference purposes. A cell with a range or list uses the *lowest*
    number present — the most conservative reading."""
    v = (cell or '').strip()
    if v == '' or v.lower() == 'did not run':
        return None
    if v.lower() == 'invalid':
        return {'kind': 'invalid', 'min_intensity': None, 'reads_positive': None}
    nums = [int(n) for n in re.findall(r'\d+', v)]
    has_positive_word = 'positive' in v.lower()
    if has_positive_word and not nums:
        return {'kind': 'positive', 'min_intensity': None, 'reads_positive': True}
    if nums:
        min_i = min(nums)
        return {'kind': 'intensity', 'min_intensity': min_i, 'reads_positive': (min_i <= 3 or has_positive_word)}
    return {'kind': 'unrecognized', 'min_intensity': None, 'reads_positive': None}


def panel_stats(row, cols):
    """Returns (run, pos, clean_pos). clean_pos counts positives with no
    visible test line at all (kind='positive') as distinct from positives
    read via a faint 1-3 intensity line (kind='intensity') — the latter is
    a real detection by the lab's scoring convention, but a line a reader
    could plausibly miss in practice, so it's tracked separately for the
    "how clear was the read" signal (see lotFitForUse() in the template)."""
    run = pos = clean_pos = 0
    for c in cols:
        r = parse_result(row[c])
        if r is None or r['kind'] in ('invalid', 'unrecognized'):
            continue
        run += 1
        if r['reads_positive']:
            pos += 1
            if r['kind'] == 'positive':
                clean_pos += 1
    return run, pos, clean_pos


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
            'tp_2500_di': panel_stats(r, TP_2500_DI),
            'tp_2500_tap': panel_stats(r, TP_2500_TAP),
            'tp_1000_di': panel_stats(r, TP_1000_DI),
            'tn_water': parse_result(r[TN_WATER]),
            'interference': interference,
            'notes': r[COL['notes']] if len(r) > COL['notes'] else '',
        })
    return records


def build_dashboard_data(records):
    lots = defaultdict(lambda: {
        'brand': '', 'lot': '', 'expirations': set(), 'submissions': [], 'testers': set(), 'photos': [],
        'tp': {'2500_di': [0, 0, 0], '2500_tap': [0, 0, 0], '1000_di': [0, 0, 0]},
        'tn_run': 0, 'tn_pos': 0,
        'sub_stats': defaultdict(lambda: {'run': 0, 'hits': 0, 'min_mg': None, 'min_intensity': None}),
    })
    sub_rows = []
    for idx, r in enumerate(records):
        k = lotkey(r['brand'], r['lot'])
        L = lots[k]
        L['brand'] = r['brand'].strip()
        L['lot'] = fix_numeric_id(r['lot'].strip())
        if r['expiration_dt']:
            L['expirations'].add(r['expiration_dt'].date())
        L['submissions'].append(r['dt'])
        L['testers'].add(r['name'])
        if r['photos']:
            L['photos'].extend(r['photos'])

        for key, panel in (('2500_di', 'tp_2500_di'), ('2500_tap', 'tp_2500_tap'), ('1000_di', 'tp_1000_di')):
            run, pos, clean_pos = r[panel]
            L['tp'][key][0] += run
            L['tp'][key][1] += pos
            L['tp'][key][2] += clean_pos

        tn = r['tn_water']
        if tn and tn['kind'] not in ('invalid', 'unrecognized'):
            L['tn_run'] += 1
            if tn['reads_positive']:
                L['tn_pos'] += 1

        row_flags = []
        for sub in SUBSTANCES:
            for level in ('HI', 'MED', 'LO'):
                res = parse_result(r['interference'][sub][level])
                if res is None or res['kind'] in ('invalid', 'unrecognized'):
                    continue
                st = L['sub_stats'][sub]
                st['run'] += 1
                if res['reads_positive']:
                    st['hits'] += 1
                    mg = LEVEL_MG[level]
                    if st['min_mg'] is None or mg < st['min_mg']:
                        st['min_mg'] = mg
                    if res['min_intensity'] is not None and (st['min_intensity'] is None or res['min_intensity'] < st['min_intensity']):
                        st['min_intensity'] = res['min_intensity']
                    row_flags.append(f"{sub}@{mg}")

        post_exp = bool(r['expiration_dt'] and r['dt'].date() > r['expiration_dt'].date())
        sub_rows.append({
            'id': idx, 'timestamp': r['dt'].strftime('%-m/%-d/%Y %H:%M:%S'), 'ts_sort': r['dt'].isoformat(),
            'tester': r['name'], 'affiliation': r['affiliation'],
            'brand': r['brand'], 'lot': fix_numeric_id(r['lot']),
            'expiration': r['expiration_dt'].strftime('%-m/%-d/%Y') if r['expiration_dt'] else None,
            'post_exp': post_exp,
            'tp_2500_di': r['tp_2500_di'], 'tp_2500_tap': r['tp_2500_tap'], 'tp_1000_di': r['tp_1000_di'],
            'tn_water': tn, 'interferents_flagged': row_flags,
            'n_photos': len(r['photos']), 'first_photo': r['photos'][0] if r['photos'] else None,
            'notes': r['notes'], 'source': r['source'],
        })

    lot_out = []
    for k, L in lots.items():
        dates = L['submissions']
        interferents = []
        for sub, st in L['sub_stats'].items():
            if st['hits'] > 0:
                interferents.append({'substance': sub, 'label': SUB_LABEL[sub], 'min_mg_ml': st['min_mg'], 'min_intensity': st['min_intensity'], 'hits': st['hits'], 'run': st['run']})
        interferents.sort(key=lambda x: x['min_mg_ml'])
        matrix = {sub: {'run': L['sub_stats'][sub]['run'], 'hits': L['sub_stats'][sub]['hits'], 'min_mg': L['sub_stats'][sub]['min_mg'], 'min_intensity': L['sub_stats'][sub]['min_intensity']} for sub in SUBSTANCES}

        def rate(pair):
            run, pos = pair[0], pair[1]
            return round(100 * pos / run, 1) if run else None

        clarity_run = sum(L['tp'][k][0] for k in L['tp'])
        clarity_clean = sum(L['tp'][k][2] for k in L['tp'])

        run_tn = L['tn_run']
        lot_out.append({
            'brand': L['brand'], 'lot': L['lot'],
            'expirations': [d.strftime('%-m/%-d/%Y') for d in sorted(L['expirations'])],
            'n_submissions': len(L['submissions']), 'testers': sorted(L['testers']),
            'first_submitted': min(dates).strftime('%Y-%m-%d'), 'last_submitted': max(dates).strftime('%Y-%m-%d'),
            'tp_2500_di_run': L['tp']['2500_di'][0], 'tp_2500_di_pos': L['tp']['2500_di'][1], 'tp_2500_di_rate': rate(L['tp']['2500_di']),
            'tp_2500_tap_run': L['tp']['2500_tap'][0], 'tp_2500_tap_pos': L['tp']['2500_tap'][1], 'tp_2500_tap_rate': rate(L['tp']['2500_tap']),
            'tp_1000_di_run': L['tp']['1000_di'][0], 'tp_1000_di_pos': L['tp']['1000_di'][1], 'tp_1000_di_rate': rate(L['tp']['1000_di']),
            'clarity_run': clarity_run, 'clarity_clean': clarity_clean,
            'clarity_rate': round(100 * clarity_clean / clarity_run, 1) if clarity_run else None,
            'tn_run': run_tn, 'tn_pos': L['tn_pos'],
            'tn_specificity_rate': round(100 * (run_tn - L['tn_pos']) / run_tn, 1) if run_tn else None,
            'interferents': interferents, 'matrix': matrix,
            'n_photos': len(L['photos']), 'first_photo': L['photos'][0] if L['photos'] else None,
        })
    lot_out.sort(key=lambda x: (x['tp_2500_di_rate'] if x['tp_2500_di_rate'] is not None else 999))
    sub_rows.sort(key=lambda s: s['ts_sort'], reverse=True)
    for i, s in enumerate(sub_rows):
        s['id'] = i

    def pooled(key_run, key_pos):
        run = sum(l[key_run] for l in lot_out)
        pos = sum(l[key_pos] for l in lot_out)
        return (round(100 * pos / run, 1) if run else None), run, pos

    di_rate, di_run, di_pos = pooled('tp_2500_di_run', 'tp_2500_di_pos')
    tap_rate, tap_run, tap_pos = pooled('tp_2500_tap_run', 'tp_2500_tap_pos')
    low_rate, low_run, low_pos = pooled('tp_1000_di_run', 'tp_1000_di_pos')
    tn_run_total = sum(l['tn_run'] for l in lot_out)
    tn_pos_total = sum(l['tn_pos'] for l in lot_out)
    dts = [r['dt'] for r in records]

    overall = {
        'n_lots': len(lot_out), 'n_submissions': len(records), 'n_testers': len(set(r['name'] for r in records)),
        'pooled_2500_di_rate': di_rate, 'pooled_2500_tap_rate': tap_rate, 'pooled_1000_di_rate': low_rate,
        'pooled_2500_di_n': [di_pos, di_run], 'pooled_2500_tap_n': [tap_pos, tap_run], 'pooled_1000_di_n': [low_pos, low_run],
        'pooled_water_specificity': round(100 * (tn_run_total - tn_pos_total) / tn_run_total, 1) if tn_run_total else None,
        'tn_run': tn_run_total, 'tn_pos': tn_pos_total,
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
    template_path = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'templates', 'xts_template.html')

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
