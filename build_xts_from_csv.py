#!/usr/bin/env python3
"""Adapter: build the XTS dashboard from a CSV export instead of xlsx.

Usage:
    python3 build_xts_from_csv.py <responses.csv> <photos_dir> <output.html>
"""
import csv
import os
import sys
from datetime import datetime

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from common import inject_into_template
from build_xts import parse_records, build_dashboard_data, build_photos_by_lot

EPOCH = datetime(1899, 12, 30)


def to_excel_serial(ts_str):
    """CSV export renders the timestamp column as 'M/D/YYYY H:MM:SS' text,
    not the Excel serial number parse_records()/excel_serial_to_dt() expect
    from an xlsx export. Convert back to a serial so parse_records() (shared
    with the xlsx build path) needs no changes."""
    dt = datetime.strptime(ts_str.strip(), '%m/%d/%Y %H:%M:%S')
    return str((dt - EPOCH).total_seconds() / 86400)


def parse_csv_sheet(csv_path):
    with open(csv_path, newline='', encoding='utf-8') as f:
        reader = list(csv.reader(f))
    header = reader[0]
    rows = [r for r in reader[1:] if r and r[0].strip()]
    for r in rows:
        r[0] = to_excel_serial(r[0])
    return header, rows


def main():
    if len(sys.argv) != 4:
        print(__doc__)
        sys.exit(1)
    csv_path, photos_dir, out_path = sys.argv[1:4]
    template_path = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'templates', 'xts_template.html')

    header, rows = parse_csv_sheet(csv_path)
    records = parse_records(header, rows)
    print(f'parsed {len(records)} records')

    dashboard_data = build_dashboard_data(records)
    photos_by_lot = build_photos_by_lot(records, photos_dir)
    print(f'lots: {len(dashboard_data["lots"])}  photos matched to {len(photos_by_lot)} lots')

    template_html = open(template_path).read()
    html = inject_into_template(template_html, dashboard_data, photos_by_lot)
    with open(out_path, 'w') as f:
        f.write(html)
    print(f'wrote {out_path} ({len(html)} bytes)')


if __name__ == '__main__':
    main()
