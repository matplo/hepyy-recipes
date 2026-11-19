"""Check that a release contains exactly three platforms for every locked package."""
import sys
import json
from collections import Counter
from pathlib import Path
from verify import verify

root = Path(sys.argv[1])
wheels = sorted(root.glob('*.whl'))
lock = json.loads(Path(__file__).with_name('packages.lock.json').read_text())['packages']
expected = {'hepyy_' + name: record['wheel_version'] for name,record in lock.items()}
counts = Counter()
for wheel in wheels:
    package, version, python, abi, platform = wheel.stem.split('-', 4)
    assert package in expected and version == expected[package], wheel
    assert (python,abi)==(('cp310','abi3') if package=='hepyy_lhapdf' else ('py3','none')), wheel
    family = ('linux-x86_64' if 'manylinux' in platform and platform.endswith('x86_64') else
              'macos-arm64' if platform.startswith('macosx_') and platform.endswith('arm64') else
              'macos-x86_64' if platform.startswith('macosx_') and platform.endswith('x86_64') else None)
    assert family is not None, wheel
    counts[package, family] += 1
    verify(wheel)
assert counts == Counter({(p, f): 1 for p in expected for f in ('linux-x86_64', 'macos-arm64', 'macos-x86_64')}), counts
print('PASS: complete locked release matrix, source archives, license files and metadata')
