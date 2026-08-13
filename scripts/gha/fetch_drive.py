#!/usr/bin/env python3
"""Fetch a response Google Sheet + all referenced photos, via a Google Cloud
service account (no OAuth, no user in the loop).

The service account (whose JSON key is passed via --sa-json) must be granted
read access to the sheet and to every photo folder it references — by
Marya sharing the sheet and photos with the service account's email
(<something>@<project>.iam.gserviceaccount.com), the same way she'd share
with any collaborator.

Called by .github/workflows/weekly-update.yml. Not intended for local
interactive use — for that, use the Claude-driven flow via
scripts/weekly_update/prompt_fts.md and prompt_fts_cloud.md.

The script is deliberately narrow: it does the Drive fetch, and nothing
else. Parsing the sheet, resizing photos, filling templates — all of that
lives in build_fts.py / build_xts.py / common.py.
"""
from __future__ import annotations

import argparse
import io
import os
import sys
from pathlib import Path

# Make repo root importable so we can reuse common.parse_xlsx_sheet /
# extract_drive_file_id without duplicating them.
REPO_ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO_ROOT))

from common import parse_xlsx_sheet, extract_drive_file_id  # noqa: E402

from google.oauth2 import service_account  # type: ignore
from googleapiclient.discovery import build  # type: ignore
from googleapiclient.http import MediaIoBaseDownload  # type: ignore

DRIVE_SCOPES = ["https://www.googleapis.com/auth/drive.readonly"]

XLSX_MIME = (
    "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
)

# Common file-extension guesses for a Drive-hosted photo, given its
# reported MIME type. Anything not in this table falls back to '.bin' so
# common.process_photo (which sniffs actual bytes) can still handle it.
MIME_TO_EXT = {
    "image/jpeg": ".jpg",
    "image/png": ".png",
    "image/heic": ".heic",
    "image/heif": ".heif",
    "image/webp": ".webp",
    "image/gif": ".gif",
}


def _drive_service(sa_json_path: str):
    creds = service_account.Credentials.from_service_account_file(
        sa_json_path, scopes=DRIVE_SCOPES
    )
    return build("drive", "v3", credentials=creds, cache_discovery=False)


def download_sheet_as_xlsx(drive, file_id: str, out_path: Path) -> None:
    """Export a Google-Sheet-native file as an .xlsx blob."""
    request = drive.files().export_media(fileId=file_id, mimeType=XLSX_MIME)
    buf = io.BytesIO()
    downloader = MediaIoBaseDownload(buf, request)
    done = False
    while not done:
        _, done = downloader.next_chunk()
    out_path.write_bytes(buf.getvalue())
    print(f"  wrote {out_path} ({out_path.stat().st_size:,} bytes)")


def download_binary_file(drive, file_id: str, out_dir: Path) -> Path | None:
    """Download an uploaded (non-Google-native) file; return the local path."""
    try:
        meta = drive.files().get(fileId=file_id, fields="id,name,mimeType").execute()
    except Exception as exc:  # noqa: BLE001
        print(f"  warn: could not get metadata for {file_id}: {exc}")
        return None
    ext = MIME_TO_EXT.get(meta.get("mimeType", ""), "")
    if not ext:
        # If MIME didn't match, fall back to the extension in the original
        # filename (safer than guessing).
        name = meta.get("name", "")
        _, dot, tail = name.rpartition(".")
        ext = f".{tail.lower()}" if dot else ".bin"

    out_path = out_dir / f"{file_id}{ext}"
    request = drive.files().get_media(fileId=file_id)
    buf = io.BytesIO()
    downloader = MediaIoBaseDownload(buf, request)
    try:
        done = False
        while not done:
            _, done = downloader.next_chunk()
    except Exception as exc:  # noqa: BLE001
        print(f"  warn: download failed for {file_id} ({meta.get('name','?')}): {exc}")
        return None
    out_path.write_bytes(buf.getvalue())
    return out_path


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("--sheet-id", required=True, help="Google Sheet file ID (from the URL)")
    p.add_argument("--photo-column", type=int, action="append", required=True,
                   help="0-indexed column with comma-separated photo Drive URLs / IDs; "
                        "pass multiple times to pull photos from more than one column")
    p.add_argument("--out-xlsx", required=True, help="Path to write the exported .xlsx")
    p.add_argument("--out-photos-dir", required=True, help="Directory to write photos into")
    p.add_argument("--sa-json", required=True, help="Path to the service-account JSON key")
    args = p.parse_args()

    out_xlsx = Path(args.out_xlsx)
    out_photos_dir = Path(args.out_photos_dir)
    out_photos_dir.mkdir(parents=True, exist_ok=True)

    print(f"authenticating with service account: {args.sa_json}")
    drive = _drive_service(args.sa_json)

    print(f"exporting sheet {args.sheet_id} → {out_xlsx}")
    download_sheet_as_xlsx(drive, args.sheet_id, out_xlsx)

    print(f"parsing sheet for photo IDs in column(s) {args.photo_column}")
    header, rows = parse_xlsx_sheet(str(out_xlsx))
    for col in args.photo_column:
        if col >= len(header):
            print(
                f"ERROR: --photo-column {col} exceeds header width "
                f"{len(header)}; header={header}",
                file=sys.stderr,
            )
            return 2

    unique_ids: set[str] = set()
    for row in rows:
        for col in args.photo_column:
            if col >= len(row):
                continue
            for raw in row[col].split(","):
                raw = raw.strip()
                if not raw:
                    continue
                fid = extract_drive_file_id(raw)
                if fid:
                    unique_ids.add(fid)

    print(f"found {len(unique_ids)} unique photo IDs; downloading")
    n_ok = 0
    n_err = 0
    for i, fid in enumerate(sorted(unique_ids), start=1):
        # Skip if we already have any file starting with this id (rerun safety)
        if any(p.name.startswith(fid + ".") for p in out_photos_dir.iterdir()):
            n_ok += 1
            continue
        p = download_binary_file(drive, fid, out_photos_dir)
        if p:
            n_ok += 1
        else:
            n_err += 1
        if i % 25 == 0:
            print(f"  … {i} / {len(unique_ids)}")

    print(f"done: {n_ok} ok, {n_err} failed")
    return 0 if n_err == 0 else 0  # never fail the whole build for missing photos


if __name__ == "__main__":
    raise SystemExit(main())
