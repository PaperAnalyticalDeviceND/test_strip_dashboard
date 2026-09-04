#!/usr/bin/env python3
"""Build the lot checking progress tracker page.

Usage:
    python3 build_progress.py <intake.xlsx> <feedback.xlsx> <fts.html> <xts.html> <output.html>

<intake.xlsx> is an export of the "lot intake" Google Form's response
sheet. Each response is either a "New lot received" row (adds/updates a
lot's in-lab status) or a "Request a brand/lot to purchase" row (adds to
the be-on-the-lookout list) -- see BRANCH_INTAKE/BRANCH_BOLO below, which
must match the live Form's exact radio-button option text.

<feedback.xlsx> is an export of the separate "report an interference, or
suggest a product" Google Form's response sheet -- a second BOLO-list
source, merged in alongside the intake form's requests. See COL_FEEDBACK
and parse_feedback_rows() below.

<fts.html> and <xts.html> must already be built (by build_fts.py/
build_xts.py) -- this script reads their embedded `const DATA = {...}`
blob via common.extract_dashboard_data() rather than re-parsing the raw
FTS/XTS sheets a second time, so a lot's testing counts are read once,
from the one place they're actually computed. That same merged lot
registry is also used to answer whether a BOLO entry has actually been
acquired/tested yet -- see match_registry()/bolo_status().

Network-free, stdlib only, like every other build script here. Every
hardcoded COL/COL_FEEDBACK map here should be re-verified against a fresh
header row if either live Form's question order ever changes, exactly
like every other hardcoded COL map in this repo (see build_fts.py's/
build_xts.py's own "re-verify against a fresh header row" comment).
"""
import os
import sys
from collections import defaultdict
from datetime import datetime

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from common import (
    parse_xlsx_sheet, excel_serial_to_dt, fix_numeric_id, sanitize_text,
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

# Column positions for the separate "report an interference, or suggest a
# product" form's response sheet (id 15wZHFE13Q77jpNlcT_8OOcwOkIridAiVprVV3Hqd6s4,
# "Lot checking feedback form (Responses)") -- a different sheet from the
# lot-intake form above. Verified 2026-09-04 against the real header row
# plus two real test submissions covering both branches. Branch is *not*
# matched by the "What are you reporting?" text (cols[COL_FEEDBACK['what']]
# is parsed but only used for a debug print) -- see parse_feedback_rows().
COL_FEEDBACK = dict(
    ts=0, email=1, name=2, org=3, what=4,
    strip_type=5, brand=6, lot=7, suspected=8, why_wrong=9, photo=10, can_send_strip=11,
    sugg_brand=12, sugg_lot=13, sugg_substance=14, why_test=15, can_send_bulk=16, notes=17,
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
            # A free-text cell anyone with form access can type into --
            # tolerate "inf"/"nan"/absurd numbers (float() parses all of
            # these without error) rather than crash the whole build, or
            # let a joke/garbage entry silently poison total_qty sums.
            try:
                qty = int(float(qty_raw)) if qty_raw else None
                if qty is not None and not (0 <= qty <= 100_000):
                    qty = None
            except (ValueError, OverflowError):
                qty = None
            intake.append({
                'dt': dt, 'name': name, 'strip_type': strip_type,
                'brand': brand, 'lot': fix_numeric_id(lot),
                'expiration': excel_serial_to_dt(r[COL['intake_expiration']]),
                'date_received': excel_serial_to_dt(r[COL['intake_date_received']]),
                'qty': qty,
                'notes': sanitize_text(r[COL['intake_notes']]) if len(r) > COL['intake_notes'] else '',
            })
        elif branch == BRANCH_BOLO:
            product = r[COL['bolo_product']].strip()
            if not product:
                continue
            bolo.append({
                'dt': dt, 'name': name, 'product': sanitize_text(product, max_len=200),
                'strip_type': r[COL['bolo_strip_type']].strip().upper() if len(r) > COL['bolo_strip_type'] else '',
                'reason': sanitize_text(r[COL['bolo_reason']]) if len(r) > COL['bolo_reason'] else '',
            })
        # else: blank/unrecognized branch -- skipped, not guessed at.
    return intake, bolo


def _cell(r, idx):
    return r[idx].strip() if len(r) > idx else ''


def parse_feedback_rows(rows):
    """Split the "report an interference, or suggest a product" form's raw
    rows into BOLO-shaped dicts. Branch is detected by which column-group
    is actually populated (cols 5-11 for an interference report, 12-17 for
    a product suggestion) rather than by matching the "What are you
    reporting?" option text -- verified 2026-09-04 against two real
    submissions ("a suspected false negative/false positive/interference"
    and "a product or lot you'd like tested"), but the column-group
    occupancy is what's load-bearing so a future Form wording tweak can't
    silently drop rows the way BRANCH_BOLO's text mismatch nearly did for
    the intake form."""
    out = []
    for r in rows:
        dt = excel_serial_to_dt(_cell(r, COL_FEEDBACK['ts']))
        if dt is None:
            continue
        name = sanitize_text(_cell(r, COL_FEEDBACK['name']), max_len=200)
        org = sanitize_text(_cell(r, COL_FEEDBACK['org']), max_len=200)

        strip_type = sanitize_text(_cell(r, COL_FEEDBACK['strip_type']), max_len=40).upper()
        brand = sanitize_text(_cell(r, COL_FEEDBACK['brand']), max_len=200)
        lot = fix_numeric_id(sanitize_text(_cell(r, COL_FEEDBACK['lot']), max_len=100))
        suspected = sanitize_text(_cell(r, COL_FEEDBACK['suspected']))
        why_wrong = sanitize_text(_cell(r, COL_FEEDBACK['why_wrong']))
        has_photo = bool(_cell(r, COL_FEEDBACK['photo']))
        can_send_strip = sanitize_text(_cell(r, COL_FEEDBACK['can_send_strip']), max_len=200)

        sugg_brand = sanitize_text(_cell(r, COL_FEEDBACK['sugg_brand']), max_len=200)
        sugg_lot = fix_numeric_id(sanitize_text(_cell(r, COL_FEEDBACK['sugg_lot']), max_len=100))
        sugg_substance = sanitize_text(_cell(r, COL_FEEDBACK['sugg_substance']), max_len=200)
        why_test = sanitize_text(_cell(r, COL_FEEDBACK['why_test']))
        can_send_bulk = sanitize_text(_cell(r, COL_FEEDBACK['can_send_bulk']), max_len=200)
        notes = sanitize_text(_cell(r, COL_FEEDBACK['notes']))

        if strip_type or brand or lot or suspected or why_wrong:
            out.append({
                'dt': dt, 'name': name, 'org': org, 'kind': 'interference_report',
                'strip_type': strip_type, 'brand': brand, 'lot': lot,
                'suspected': suspected, 'why_wrong': why_wrong,
                'has_photo': has_photo, 'can_send_strip': can_send_strip,
            })
        elif sugg_brand or sugg_lot or sugg_substance or why_test:
            out.append({
                'dt': dt, 'name': name, 'org': org, 'kind': 'product_suggestion',
                'strip_type': '', 'brand': sugg_brand, 'lot': sugg_lot,
                'marketed_substance': sugg_substance, 'why_test': why_test,
                'can_send_bulk': can_send_bulk, 'notes': notes,
            })
        # else: blank/unrecognized row (neither column-group populated) --
        # skipped, not guessed at.
    return out


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


def _parse_iso_date(s):
    if not s:
        return None
    try:
        return datetime.strptime(s, '%Y-%m-%d')
    except (TypeError, ValueError):
        return None


def match_registry(brand, lot, lots):
    """Look a BOLO entry's brand/lot up against `lots` (merge_lots()'s
    output -- the same intake+dashboard-merged registry the Lots view
    itself uses), to answer "has the lab actually acquired this yet, and
    has it been tested." Returns (matched_lot_dict_or_None, confidence),
    confidence in {'exact', 'brand_only', None}.

    An exact brand+lot match (normalized via lotkey(), same as
    merge_lots()) is authoritative. A brand-only match (no lot given, or
    given lot didn't match anything -- common for `purchase_request` and
    for `product_suggestion` when "lot number if known" was left blank) is
    only accepted if it resolves to exactly one distinct lot; 0 or >1
    candidates means no match rather than a guess."""
    if brand and lot:
        key = lotkey(brand, lot)
        candidates = [l for l in lots if lotkey(l['brand'], l['lot']) == key]
        confidence = 'exact'
    elif brand:
        candidates = [l for l in lots if l['brand'].strip().lower() == brand.strip().lower()]
        confidence = 'brand_only' if len(candidates) == 1 else None
        if confidence is None:
            candidates = []
    else:
        candidates, confidence = [], None

    if not candidates:
        return None, None
    best = min(candidates, key=lambda l: l['first_received'] or '9999-99-99')
    return best, confidence


def bolo_status(kind, match):
    """'not_yet_acquired' (a true BOLO -- nothing on hand yet) vs.
    'received' (on hand, not yet tested) vs. 'tested' (on hand and at
    least one test result exists), all three read straight off the
    matched dashboard/intake lot record.

    'in_lab_reported' is the one special case: an interference_report is
    by construction about a physical strip someone already ran, so
    'not_yet_acquired' would be actively wrong even when the lot isn't one
    of our own dashboard entries (e.g. a partner org reporting on strips
    we've never logged ourselves)."""
    if match and match.get('n_submissions', 0) > 0:
        return 'tested'
    if match and match.get('first_received'):
        return 'received'
    if kind == 'interference_report':
        return 'in_lab_reported'
    return 'not_yet_acquired'


SOURCE_LABEL = {
    'intake': 'Lot intake form',
    'feedback': 'Report an interference / suggest a product form',
}
KIND_LABEL = {
    'purchase_request': 'Purchase request',
    'interference_report': 'Interference report',
    'product_suggestion': 'Product suggestion',
}


def build_bolo_entries(intake_bolo, feedback_rows, lots):
    """Unify BOLO-list entries from both sources into one flat, sortable
    list, each tagged with where it came from (source/kind) and whether
    the lab has actually acquired/tested the item yet (status, plus
    latency in days -- see match_registry()/bolo_status() above)."""
    raw = []
    for b in intake_bolo:
        raw.append({
            'dt': b['dt'], 'source': 'intake', 'kind': 'purchase_request',
            'name': b['name'], 'org': '',
            'strip_type': b['strip_type'], 'brand': b['product'], 'lot': '',
            'reason': b['reason'],
            'suspected': '', 'why_wrong': '', 'has_photo': False, 'can_send_strip': '',
            'marketed_substance': '', 'why_test': '', 'can_send_bulk': '', 'notes': '',
        })
    for f in feedback_rows:
        raw.append({
            'dt': f['dt'], 'source': 'feedback', 'kind': f['kind'],
            'name': f['name'], 'org': f['org'],
            'strip_type': f.get('strip_type', ''), 'brand': f['brand'], 'lot': f['lot'],
            'reason': '',
            'suspected': f.get('suspected', ''), 'why_wrong': f.get('why_wrong', ''),
            'has_photo': f.get('has_photo', False), 'can_send_strip': f.get('can_send_strip', ''),
            'marketed_substance': f.get('marketed_substance', ''), 'why_test': f.get('why_test', ''),
            'can_send_bulk': f.get('can_send_bulk', ''), 'notes': f.get('notes', ''),
        })

    out = []
    for e in raw:
        match, confidence = match_registry(e['brand'], e['lot'], lots)
        status = bolo_status(e['kind'], match)
        acquired = _parse_iso_date(match['first_received']) if match else None
        tested = _parse_iso_date(match['first_submitted']) if (match and match.get('n_submissions', 0) > 0) else None

        days_to_acquire = (acquired - e['dt']).days if acquired else None
        days_to_test = (tested - acquired).days if (tested and acquired) else None
        days_report_to_test = (tested - e['dt']).days if tested else None

        out.append({
            'dt_display': e['dt'].strftime('%-m/%-d/%Y'), 'dt_sort': e['dt'].strftime('%Y-%m-%dT%H:%M'),
            'source': e['source'], 'source_label': SOURCE_LABEL[e['source']],
            'kind': e['kind'], 'kind_label': KIND_LABEL[e['kind']],
            'submitter': e['name'], 'org': e['org'],
            'strip_type': e['strip_type'], 'brand': e['brand'], 'lot': e['lot'],
            'reason': e['reason'],
            'suspected': e['suspected'], 'why_wrong': e['why_wrong'],
            'has_photo': e['has_photo'], 'can_send_strip': e['can_send_strip'],
            'marketed_substance': e['marketed_substance'], 'why_test': e['why_test'],
            'can_send_bulk': e['can_send_bulk'], 'notes': e['notes'],
            'status': status, 'match_confidence': confidence,
            'acquired_date': acquired.strftime('%Y-%m-%d') if acquired else None,
            'first_tested_date': tested.strftime('%Y-%m-%d') if tested else None,
            'days_to_acquire': days_to_acquire, 'days_to_test': days_to_test,
            'days_report_to_test': days_report_to_test,
        })
    out.sort(key=lambda e: e['dt_sort'], reverse=True)
    return out


def main():
    if len(sys.argv) != 6:
        print(__doc__)
        sys.exit(1)
    intake_xlsx, feedback_xlsx, fts_path, xts_path, out_path = sys.argv[1:6]
    template_path = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'templates', 'progress_template.html')

    header, rows = parse_xlsx_sheet(intake_xlsx)
    intake_events, bolo_requests = parse_intake_rows(rows)
    print(f'parsed {len(intake_events)} intake event(s), {len(bolo_requests)} BOLO request(s)')

    fb_header, fb_rows = parse_xlsx_sheet(feedback_xlsx)
    feedback_rows = parse_feedback_rows(fb_rows)
    print(f'parsed {len(feedback_rows)} feedback-form row(s)')

    intake_by_lot = group_intake_by_lot(intake_events)

    fts_data = extract_dashboard_data(fts_path)
    xts_data = extract_dashboard_data(xts_path)
    lots = merge_lots(intake_by_lot, {'FTS': fts_data['lots'], 'XTS': xts_data['lots']})

    bolo_out = build_bolo_entries(bolo_requests, feedback_rows, lots)

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
