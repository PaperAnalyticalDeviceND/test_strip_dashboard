#!/usr/bin/env python3
"""Build the lot checking progress tracker page.

Usage:
    python3 build_progress.py <intake.xlsx> <fts.html> <xts.html> <output.html>

<intake.xlsx> is an export of the "lot intake" Google Form's response sheet
(NOT the FTS/XTS test-result sheets). Each response is either a "New lot
received" row (adds/updates a lot's in-lab status) or a "Request a
brand/lot to purchase" row (adds to the be-on-the-lookout list) -- see
BRANCH_INTAKE/BRANCH_BOLO below, which must match the live Form's exact
radio-button option text.

<fts.html> and <xts.html> must already be built (by build_fts.py/
build_xts.py) -- this script reads their embedded `const DATA = {...}`
blob via common.extract_dashboard_data() rather than re-parsing the raw
FTS/XTS sheets a second time, so a lot's testing counts are read once,
from the one place they're actually computed.

Network-free, stdlib only, like every other build script here. The
COL positions below are a DRAFT, written before the live Form exists --
verify them against the real header row the first time this runs against
a real export, exactly like every other hardcoded COL map in this repo
(see build_fts.py's/build_xts.py's own "re-verify against a fresh header
row" comment).
"""
import os
import sys
from collections import defaultdict

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from common import (
    parse_xlsx_sheet, excel_serial_to_dt, fix_numeric_id,
    extract_dashboard_data, embed_json_in_script, DASHBOARD_VERSION,
)
from completion_rules import STRIP_TYPES

# Must match the live Form's "What are you submitting to the progress
# tracker?" radio option text exactly. Verified 2026-08-24 against the real
# "Lot checking intake form (Responses)" sheet -- Marya's actual wording for
# the BOLO branch differs from the original draft ("Be on the lookout..."
# vs. "Request a brand/lot to purchase").
BRANCH_INTAKE = 'New lot received'
BRANCH_BOLO = 'Be on the lookout for this brand/lot to purchase'

# Column positions verified 2026-08-24 against the real sheet's header row
# (previously a pre-Form draft -- the real form has one field the draft
# didn't, intake_expiration, which shifted every field after it by one).
# Re-verify again if the form's question order ever changes.
COL = dict(
    ts=0, email=1, name=2, branch=3,
    intake_strip_type=4, intake_brand=5, intake_lot=6, intake_expiration=7,
    intake_date_received=8, intake_qty=9, intake_notes=10,
    bolo_product=11, bolo_strip_type=12, bolo_reason=13,
)


def lotkey(brand, lot):
    """Same normalization build_fts.py/build_xts.py use internally, so a
    lot logged here matches the same lot's dashboard entry."""
    lot = fix_numeric_id(lot.strip())
    return f"{brand.strip()}||{lot.upper().replace(' ', '')}"


def parse_intake_rows(rows):
    """Split raw sheet rows into (intake_events, bolo_requests) by the
    branch-selector column. Rows with an unrecognized/blank branch, or
    missing required fields for their branch, are skipped rather than
    guessed at."""
    intake, bolo = [], []
    for r in rows:
        dt = excel_serial_to_dt(r[COL['ts']])
        if dt is None:
            continue
        branch = r[COL['branch']].strip()
        name = r[COL['name']].strip() if len(r) > COL['name'] else ''

        if branch == BRANCH_INTAKE:
            brand = r[COL['intake_brand']].strip()
            lot = r[COL['intake_lot']].strip()
            strip_type = r[COL['intake_strip_type']].strip().upper()
            if not brand or not lot or not strip_type:
                continue
            qty_raw = r[COL['intake_qty']].strip()
            try:
                qty = int(float(qty_raw)) if qty_raw else None
            except ValueError:
                qty = None
            intake.append({
                'dt': dt, 'name': name, 'strip_type': strip_type,
                'brand': brand, 'lot': fix_numeric_id(lot),
                'expiration': excel_serial_to_dt(r[COL['intake_expiration']]),
                'date_received': excel_serial_to_dt(r[COL['intake_date_received']]),
                'qty': qty,
                'notes': r[COL['intake_notes']].strip() if len(r) > COL['intake_notes'] else '',
            })
        elif branch == BRANCH_BOLO:
            product = r[COL['bolo_product']].strip()
            if not product:
                continue
            bolo.append({
                'dt': dt, 'name': name, 'product': product,
                'strip_type': r[COL['bolo_strip_type']].strip() if len(r) > COL['bolo_strip_type'] else '',
                'reason': r[COL['bolo_reason']].strip() if len(r) > COL['bolo_reason'] else '',
            })
        # else: blank/unrecognized branch -- skipped, not guessed at.
    return intake, bolo


def group_intake_by_lot(intake_events):
    """One entry per (strip_type, lot), aggregating every intake event
    logged for it -- a lot can legitimately be received more than once."""
    grouped = defaultdict(list)
    for e in intake_events:
        key = (e['strip_type'], lotkey(e['brand'], e['lot']))
        grouped[key].append(e)
    out = {}
    for key, events in grouped.items():
        events.sort(key=lambda e: e['dt'])
        received_dates = [e['date_received'] for e in events if e['date_received']]
        out[key] = {
            'brand': events[0]['brand'], 'lot': events[0]['lot'],
            'n_events': len(events),
            'first_received': min(received_dates).strftime('%Y-%m-%d') if received_dates else None,
            'total_qty': sum(e['qty'] for e in events if e['qty'] is not None) or None,
            'notes': next((e['notes'] for e in reversed(events) if e['notes']), ''),
            # Most recently-logged expiration wins if it's ever entered more
            # than once for the same lot (e.g. a correction) -- same
            # "trust the latest entry" convention as `notes` above.
            'expiration': next((e['expiration'].strftime('%Y-%m-%d') for e in reversed(events) if e['expiration']), None),
        }
    return out


def evaluate_completion(strip_type, dash_lot):
    """Returns a completion breakdown for one lot, or None if strip_type
    has no entry in completion_rules.STRIP_TYPES yet (a lot logged with a
    strip type whose build script/config doesn't exist -- e.g. a
    benzo/nitazene panel before build_bts.py exists -- shows as "not yet
    supported" rather than crashing or silently marking it complete).

    dash_lot is the matched lot dict from fts.html's/xts.html's own
    DATA.lots (or None if this lot has never been submitted for testing
    at all -- every run/photo count is then treated as zero)."""
    rules = STRIP_TYPES.get(strip_type)
    if rules is None:
        return None

    d = dash_lot or {}

    target_results = []
    for t in rules['targets']:
        run = d.get(t['run_field'], 0)
        target_results.append({
            'label': t['label'], 'run': run, 'min_run': t['min_run'],
            'complete': run >= t['min_run'],
        })
    targets_complete = all(t['complete'] for t in target_results)

    tn_rule = rules['true_negative']
    tn_run = d.get(tn_rule['run_field'], 0)
    tn_complete = tn_run >= tn_rule['min_run']

    matrix = d.get('matrix') or {}
    empty_level = {'run': 0, 'hits': 0}
    interference_results = []
    for sub in rules['interferences']:
        st = matrix.get(sub) or {}
        by_level = st.get('by_level') or {}
        hi = by_level.get('HI', empty_level)
        med = by_level.get('MED', empty_level)
        lo = by_level.get('LO', empty_level)
        hi_run, hi_hits = hi.get('run', 0), hi.get('hits', 0)
        has_follow_up = med.get('run', 0) > 0 or lo.get('run', 0) > 0
        # Complete when HI has been run at all, and it's either clean
        # (never positive) or, if positive, also characterized at a
        # lower concentration -- Marya's rule is about testing coverage,
        # not about the lot being "clean": a lot with a confirmed,
        # fully-characterized interference still counts as complete here.
        complete = hi_run > 0 and (hi_hits == 0 or has_follow_up)
        interference_results.append({
            'substance': sub, 'hi_run': hi_run, 'hi_hits': hi_hits,
            'needs_follow_up': hi_run > 0 and hi_hits > 0,
            'has_follow_up': has_follow_up, 'complete': complete,
        })
    interferences_complete = all(i['complete'] for i in interference_results)

    n_pack = d.get('n_photos_packaging', 0)
    n_strip = d.get('n_photos_strip', 0)
    photos_complete = n_pack >= 1 and n_strip >= 1

    return {
        'complete': targets_complete and tn_complete and interferences_complete and photos_complete,
        'targets': target_results, 'targets_complete': targets_complete,
        'true_negative': {'run': tn_run, 'min_run': tn_rule['min_run'], 'complete': tn_complete},
        'interferences': interference_results, 'interferences_complete': interferences_complete,
        'n_photos_packaging': n_pack, 'n_photos_strip': n_strip, 'photos_complete': photos_complete,
    }


def merge_lots(intake_by_lot, dashboards):
    """dashboards: {'FTS': fts_DATA['lots'], 'XTS': xts_DATA['lots'], ...}.
    A lot is included if it has an intake row OR at least one real
    submission in a dashboard -- otherwise every already-tested lot would
    wrongly show as "not in lab" on day one, since nobody will
    retroactively fill out the brand-new intake form for old lots."""
    records = {}
    for strip_type, lots in dashboards.items():
        for l in lots:
            key = (strip_type, lotkey(l['brand'], l['lot']))
            records[key] = {'strip_type': strip_type, 'brand': l['brand'], 'lot': l['lot'], 'dash': l, 'intake': None}
    for key, intake in intake_by_lot.items():
        strip_type = key[0]
        if key in records:
            records[key]['intake'] = intake
        else:
            records[key] = {'strip_type': strip_type, 'brand': intake['brand'], 'lot': intake['lot'], 'dash': None, 'intake': intake}

    out = []
    for (strip_type, _), rec in records.items():
        rules = STRIP_TYPES.get(strip_type)
        completion = evaluate_completion(strip_type, rec['dash'])
        d = rec['dash'] or {}
        intake = rec['intake']
        out.append({
            'strip_type': strip_type,
            'strip_type_label': rules['label'] if rules else f'{strip_type} (not yet supported)',
            'dashboard_href': rules['dashboard_href'] if rules else None,
            'brand': rec['brand'], 'lot': rec['lot'],
            'first_received': intake['first_received'] if intake else None,
            'total_qty': intake['total_qty'] if intake else None,
            'intake_notes': intake['notes'] if intake else '',
            'expiration': intake['expiration'] if intake else None,
            'n_submissions': d.get('n_submissions', 0),
            'first_submitted': d.get('first_submitted'), 'last_submitted': d.get('last_submitted'),
            'complete': completion['complete'] if completion else None,
            'completion': completion,
        })
    out.sort(key=lambda l: (l['brand'].lower(), l['lot'].lower()))
    return out


def main():
    if len(sys.argv) != 5:
        print(__doc__)
        sys.exit(1)
    intake_xlsx, fts_path, xts_path, out_path = sys.argv[1:5]
    template_path = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'templates', 'progress_template.html')

    header, rows = parse_xlsx_sheet(intake_xlsx)
    intake_events, bolo_requests = parse_intake_rows(rows)
    print(f'parsed {len(intake_events)} intake event(s), {len(bolo_requests)} BOLO request(s)')

    intake_by_lot = group_intake_by_lot(intake_events)

    fts_data = extract_dashboard_data(fts_path)
    xts_data = extract_dashboard_data(xts_path)
    lots = merge_lots(intake_by_lot, {'FTS': fts_data['lots'], 'XTS': xts_data['lots']})

    bolo_requests.sort(key=lambda b: b['dt'], reverse=True)
    bolo_out = [{
        'timestamp': b['dt'].strftime('%-m/%-d/%Y'), 'requester': b['name'],
        'product': b['product'], 'strip_type': b['strip_type'], 'reason': b['reason'],
    } for b in bolo_requests]

    n_complete = sum(1 for l in lots if l['complete'] is True)
    n_incomplete = sum(1 for l in lots if l['complete'] is False)
    n_unsupported = sum(1 for l in lots if l['complete'] is None)

    dashboard_data = {
        'dashboard_version': DASHBOARD_VERSION,
        'overall': {
            'n_lots': len(lots), 'n_complete': n_complete, 'n_incomplete': n_incomplete,
            'n_unsupported': n_unsupported, 'n_bolo': len(bolo_out),
        },
        'lots': lots, 'bolo': bolo_out,
    }

    template_html = open(template_path, encoding='utf-8').read()
    html = template_html.replace('__PROGRESS_DATA__', embed_json_in_script(dashboard_data), 1)
    with open(out_path, 'w', encoding='utf-8') as f:
        f.write(html)
    print(f'lots: {len(lots)} ({n_complete} complete, {n_incomplete} incomplete, {n_unsupported} unsupported strip type)')
    print(f'BOLO requests: {len(bolo_out)}')
    print(f'wrote {out_path} ({len(html)} bytes)')


if __name__ == '__main__':
    main()
