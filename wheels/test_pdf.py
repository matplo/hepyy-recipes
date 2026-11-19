"""Fetch a small, pinned PDF set for tests only (not included in any wheel)."""
import hashlib
from pathlib import Path
import sys
import tarfile
import urllib.request

root=Path(sys.argv[1]).resolve();root.mkdir(parents=True,exist_ok=True)
archive=root/'CT14lo.tar.gz'
if not archive.exists():
    with urllib.request.urlopen('https://lhapdfsets.web.cern.ch/current/CT14lo.tar.gz',timeout=120) as response:
        archive.write_bytes(response.read())
if hashlib.sha256(archive.read_bytes()).hexdigest()!='5554b2f66027accc3fe38b55b846d5c7c6d771283868187870bf9c86e5c46678':
    raise RuntimeError('CT14lo test data checksum mismatch')
with tarfile.open(archive) as tar:
    tar.extractall(root,filter='data')
print(root)
