from pathlib import Path
import sys
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'backend'))
from app.ingestion_service import read_upload, deterministic_mapping, normalize_row

for path in [Path(__file__).resolve().parents[1] / 'data/samples/messy_transactions.csv', Path(__file__).resolve().parents[1] / 'data/samples/messy_transactions.xlsx']:
    sheets=read_upload(path.name, path.read_bytes())
    print(f'== {path.name} ==')
    for sheet, frame in sheets.items():
        mapping=deterministic_mapping([str(c) for c in frame.columns])
        print('mapping:', mapping)
        ok=0; bad=0
        for row_no, (_, row) in enumerate(frame.iterrows(), start=2):
            try: normalize_row(row.to_dict(), mapping, row_no, sheet); ok += 1
            except Exception as exc: bad += 1; print('row', row_no, 'ERROR', exc)
        print('rows:', len(frame), 'normalizable:', ok, 'errors:', bad)
