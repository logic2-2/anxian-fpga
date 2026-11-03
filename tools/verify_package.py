"""Verify package files and the exact V57 r7 release bitstream."""
from pathlib import Path
import hashlib
import json

root = Path(__file__).resolve().parents[1]
manifest = json.loads((root / 'SHA256SUMS.json').read_text(encoding='utf-8'))
failed = []
for relative, expected in manifest['files'].items():
    path = root / relative
    if not path.is_file() or hashlib.sha256(path.read_bytes()).hexdigest().upper() != expected:
        failed.append(relative)
if failed:
    raise SystemExit('Verification failed: ' + ', '.join(failed))
print('PASS: ' + str(len(manifest['files'])) + ' files match their SHA-256 hashes.')
